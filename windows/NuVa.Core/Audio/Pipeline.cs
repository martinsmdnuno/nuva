using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace NuVa.Core.Audio;

public readonly record struct AudioFormat(int SampleRate, int Channels)
{
    public override string ToString() => $"{SampleRate} Hz × {Channels}";
}

/// <summary>A decoder of one track, from the platform (Media Foundation), or NuVa's own for AIFF and CDs.</summary>
public interface IDecoder : IDisposable
{
    AudioFormat Format { get; }
    /// <summary>Seconds; 0 when unknown.</summary>
    double Duration { get; }
    /// <summary>Bits per sample of the source (24 for a 24/96 FLAC); 0 when unknown or lossy.</summary>
    int SourceBits { get; }
    /// <summary>Reads up to <paramref name="maxFrames"/> interleaved float frames (−1…1). 0 at the end.</summary>
    int Read(float[] buffer, int maxFrames);
    void Seek(double seconds);
}

public interface IDecoderFactory
{
    /// <summary>Opens a track (blocking; the pipeline calls it on its own thread). Throws when it can't.</summary>
    IDecoder Open(Uri location);
}

/// <summary>Where the sound goes: the platform's output (AudioGraph), or a fake in tests.</summary>
public interface IAudioOutput : IDisposable
{
    /// <summary>Called by the output's thread for each block: fill <c>frames</c> interleaved frames in <c>format</c>.</summary>
    Action<float[], int, AudioFormat>? Render { get; set; }
    /// <summary>(Re)creates the output for a format. The pipeline calls it on its own thread.</summary>
    void Configure(AudioFormat format);
    void Start();
    void Stop();
    /// <summary>Seconds from Render to the speakers.</summary>
    double Latency { get; }
}

/// <summary>Sees every block on its way out, after the volume-independent processing (EQ, meters).</summary>
public interface IAudioTap
{
    /// <summary>In place. <paramref name="endTime"/>: the track time at the end of the block.</summary>
    void Process(float[] samples, int frames, AudioFormat format, double endTime);
    /// <summary>A seek or a new chain: forget the filters' state and old measurements.</summary>
    void Reset();
}

/// <summary>A track to play: its token (the queue item) and how to get its location.</summary>
public sealed record TrackRequest(long Token, Func<CancellationToken, Task<Uri>> Resolve, string Name);

/// <summary>What the display needs about the track that is heard now.</summary>
public sealed record TrackInfo(long Token, int Run, double Duration, AudioFormat Format, int SourceBits, string Location);

/// <summary>
/// The pipe between the platform's decoder and the platform's output, in the place of the Mac's
/// AVQueuePlayer: a decoder thread keeps about a second decoded ahead, opening the next track before the
/// current one ends (gapless), and the output pulls blocks from it, running the tap (EQ, meters) on the
/// way. Track changes are reported when the first block of a track goes out, not when it is decoded.
/// Events come on the pipeline's threads; the app marshals them to the UI.
/// </summary>
public sealed class Pipeline : IDisposable
{
    private sealed class Block
    {
        public required float[] Samples;
        public required int Frames;
        public int Offset;
        public required AudioFormat Format;
        public required TrackInfo Info;
        public required double Start;
        public bool End;
    }

    public const int BlockFrames = 4096;

    private readonly IDecoderFactory factory;
    private readonly IAudioOutput output;
    private readonly IAudioTap? tap;
    private readonly Thread thread;
    private readonly ConcurrentQueue<Action> commands = new();
    private readonly AutoResetEvent wake = new(false);
    private readonly object gate = new();
    private readonly LinkedList<Block> blocks = new();
    private double bufferedSeconds;
    private volatile bool running = true;

    // Decoder thread only.
    private IDecoder? decoder;
    private TrackRequest? decoding;
    private TrackInfo? decodingInfo;
    private double decodePosition;
    private AudioFormat? configured;
    private int runs;
    private readonly float[] scratch = new float[BlockFrames * 8];
    private CancellationTokenSource resolving = new();

    // Output thread (under gate).
    private TrackInfo? audible;
    private TrackRequest? audibleRequest;
    private readonly Dictionary<long, TrackRequest> requests = new();
    private double audibleTime;
    private bool endReported;
    private bool reconfiguring;
    private bool playing;
    private bool flushedTap;

    /// <summary>Seconds decoded ahead. More for streams, which can stall.</summary>
    public double Ahead { get; set; } = 1.0;

    /// <summary>What follows a track, for gapless playback (decoder thread; answer quickly). Null: nothing.</summary>
    public Func<long, TrackRequest?>? Next { get; set; }
    /// <summary>A track is heard now (output thread).</summary>
    public event Action<TrackInfo>? Started;
    /// <summary>A track couldn't be opened (decoder thread).</summary>
    public event Action<long, Exception>? Failed;
    /// <summary>The last track ended and nothing follows (output thread).</summary>
    public event Action? Ended;

    public Pipeline(IDecoderFactory factory, IAudioOutput output, IAudioTap? tap)
    {
        this.factory = factory;
        this.output = output;
        this.tap = tap;
        output.Render = Render;
        thread = new Thread(Run) { IsBackground = true, Name = "NuVa decoder", Priority = ThreadPriority.AboveNormal };
        thread.Start();
    }

    /// <summary>The audible track's position, in seconds.</summary>
    public double Position
    {
        get
        {
            lock (gate) return Math.Max(0, audibleTime - (playing ? output.Latency : 0));
        }
    }

    public TrackInfo? Audible
    {
        get { lock (gate) return audible; }
    }

    public bool IsPlaying
    {
        get { lock (gate) return playing; }
    }

    // MARK: Commands (any thread; run in order on the decoder thread)

    /// <summary>Starts a new chain at <paramref name="request"/>, dropping whatever was queued.</summary>
    public void Play(TrackRequest request, double startAt = 0, bool paused = false) => Post(() =>
    {
        Flush();
        CloseDecoder();
        lock (gate)
        {
            audible = null;
            audibleRequest = null;
            audibleTime = startAt;
            endReported = false;
            playing = !paused;
        }
        if (!Open(request, startAt, configure: true)) return;
        if (paused) output.Stop();
        else output.Start();
    });

    public void Pause() => Post(() =>
    {
        lock (gate) playing = false;
        output.Stop();
    });

    public void Resume() => Post(() =>
    {
        lock (gate)
        {
            if (audible == null && decoding == null && blocks.Count == 0) return;
            playing = true;
        }
        output.Start();
    });

    /// <summary>Stops and forgets everything.</summary>
    public void Stop() => Post(() =>
    {
        lock (gate)
        {
            playing = false;
            audible = null;
            audibleRequest = null;
            audibleTime = 0;
        }
        output.Stop();
        Flush();
        CloseDecoder();
    });

    /// <summary>Moves within the audible track.</summary>
    public void Seek(double seconds)
    {
        lock (gate) audibleTime = Math.Max(0, seconds);
        Post(() =>
        {
            TrackRequest? request;
            lock (gate) request = audibleRequest ?? decoding;
            if (request == null) return;
            Flush();
            if (decoding?.Token == request.Token && decoder != null && decodingInfo != null && decodingInfo == AudibleInfo())
            {
                // Still decoding the audible track: seek in place.
                decoder.Seek(seconds);
                decodePosition = seconds;
                tap?.Reset();
                lock (gate) audibleTime = seconds;
            }
            else
            {
                // The decoder has moved on to the next track (or ended): reopen this one.
                CloseDecoder();
                Open(request, seconds, keepRun: true, configure: true);
            }
        });
    }

    /// <summary>
    /// The queue changed (order, repeat, a track removed or failed): if the next track was already being
    /// decoded, drop it and ask again what follows the audible one.
    /// </summary>
    public void RefreshUpcoming() => Post(() =>
    {
        TrackInfo? heard;
        lock (gate) heard = audible;
        if (heard == null) return;
        if (decodingInfo != null && decodingInfo.Token == heard.Token && decodingInfo.Run == heard.Run) return; // not there yet
        lock (gate)
        {
            var node = blocks.First;
            while (node != null)
            {
                var following = node.Next;
                if (node.Value.End || node.Value.Info != heard)
                {
                    bufferedSeconds -= Remaining(node.Value);
                    blocks.Remove(node);
                }
                node = following;
            }
            endReported = false;
        }
        CloseDecoder();
        OpenNext(heard.Token);
    });

    private void Post(Action command)
    {
        commands.Enqueue(command);
        wake.Set();
    }

    // MARK: Decoder thread

    private void Run()
    {
        while (running)
        {
            while (commands.TryDequeue(out var command))
            {
                try
                {
                    command();
                }
                catch (Exception e)
                {
                    Log.Write($"pipeline: command failed: {e}");
                }
            }
            if (!running) break;
            bool room;
            lock (gate) room = bufferedSeconds < Ahead;
            if (decoder != null && room)
            {
                try
                {
                    DecodeOne();
                }
                catch (Exception e)
                {
                    Log.Write($"pipeline: decoding {decoding?.Name} failed: {e.Message}");
                    var failed = decoding;
                    CloseDecoder();
                    if (failed != null) Failed?.Invoke(failed.Token, e);
                }
                continue;
            }
            wake.WaitOne(decoder != null ? 20 : 250);
        }
        CloseDecoder();
    }

    private void DecodeOne()
    {
        var format = decoder!.Format;
        var frames = decoder.Read(scratch, Math.Min(BlockFrames, scratch.Length / Math.Max(1, format.Channels)));
        if (frames > 0)
        {
            var samples = new float[frames * format.Channels];
            Array.Copy(scratch, samples, samples.Length);
            var block = new Block { Samples = samples, Frames = frames, Format = format, Info = decodingInfo!, Start = decodePosition };
            decodePosition += (double)frames / format.SampleRate;
            lock (gate)
            {
                blocks.AddLast(block);
                bufferedSeconds += (double)frames / format.SampleRate;
            }
            return;
        }
        // End of this track: open what follows, without a gap.
        var finished = decoding!;
        CloseDecoder();
        OpenNext(finished.Token);
    }

    private void OpenNext(long after)
    {
        TrackRequest? next = null;
        try
        {
            next = Next?.Invoke(after);
        }
        catch (Exception e)
        {
            Log.Write($"pipeline: next failed: {e.Message}");
        }
        if (next == null)
        {
            lock (gate)
                blocks.AddLast(new Block { Samples = [], Frames = 0, Format = default, Info = AudibleInfo() ?? decodingInfo!, Start = 0, End = true });
            return;
        }
        Open(next, 0);
    }

    /// <summary>Opens a track and makes it the one being decoded. False (and reported) when it fails.</summary>
    private bool Open(TrackRequest request, double startAt, bool keepRun = false, bool configure = false)
    {
        resolving.Cancel();
        resolving = new CancellationTokenSource();
        try
        {
            var location = request.Resolve(resolving.Token).GetAwaiter().GetResult();
            var opened = factory.Open(location);
            if (startAt > 0) opened.Seek(startAt);
            decoder = opened;
            decoding = request;
            decodePosition = startAt;
            var run = keepRun && AudibleInfo() is { } heard && heard.Token == request.Token ? heard.Run : ++runs;
            decodingInfo = keepRun && AudibleInfo() is { } same && same.Token == request.Token
                ? same
                : new TrackInfo(request.Token, run, opened.Duration, opened.Format, opened.SourceBits, location.IsFile ? location.LocalPath : location.GetLeftPart(UriPartial.Path));
            lock (gate)
            {
                requests[request.Token] = request;
                flushedTap = true;
            }
            // A track that follows gaplessly is configured when its first block reaches the output.
            if (configure && configured != opened.Format) Configure(opened.Format);
            Log.Write($"pipeline: opened {request.Name}: {opened.Format}, {opened.Duration:F1} s, {opened.SourceBits} bits");
            return true;
        }
        catch (Exception e)
        {
            Log.Write($"pipeline: can't open {request.Name}: {e.Message}");
            Failed?.Invoke(request.Token, e);
            return false;
        }
    }

    private void Configure(AudioFormat format)
    {
        try
        {
            output.Configure(format);
            configured = format;
        }
        catch (Exception e)
        {
            Log.Write($"pipeline: output can't take {format}: {e.Message}");
        }
        lock (gate) reconfiguring = false;
    }

    private void CloseDecoder()
    {
        decoder?.Dispose();
        decoder = null;
        decoding = null;
        decodingInfo = null;
    }

    private void Flush()
    {
        lock (gate)
        {
            blocks.Clear();
            bufferedSeconds = 0;
            endReported = false;
            flushedTap = true;
        }
    }

    private TrackInfo? AudibleInfo()
    {
        lock (gate) return audible;
    }

    private static double Remaining(Block block) => block.End ? 0 : (double)(block.Frames - block.Offset) / block.Format.SampleRate;

    // MARK: Output thread

    private void Render(float[] destination, int frames, AudioFormat format)
    {
        var channels = format.Channels;
        var written = 0;
        TrackInfo? started = null;
        var ended = false;
        bool reset;
        double end;
        lock (gate)
        {
            reset = flushedTap;
            flushedTap = false;
            while (written < frames && blocks.First is { } node)
            {
                var block = node.Value;
                if (block.End)
                {
                    if (!endReported)
                    {
                        endReported = true;
                        ended = true;
                        playing = false;
                    }
                    break;
                }
                if (block.Format != format)
                {
                    // A track at another rate: the output is rebuilt for it, in silence meanwhile.
                    if (!reconfiguring)
                    {
                        reconfiguring = true;
                        var wanted = block.Format;
                        Post(() => Configure(wanted));
                    }
                    break;
                }
                if (block.Info != audible)
                {
                    audible = block.Info;
                    audibleRequest = requests.GetValueOrDefault(block.Info.Token);
                    started = block.Info;
                    reset = true;
                }
                var n = Math.Min(frames - written, block.Frames - block.Offset);
                Array.Copy(block.Samples, block.Offset * channels, destination, written * channels, n * channels);
                block.Offset += n;
                written += n;
                bufferedSeconds -= (double)n / format.SampleRate;
                audibleTime = block.Start + (double)block.Offset / format.SampleRate;
                if (block.Offset >= block.Frames) blocks.RemoveFirst();
            }
            end = audibleTime;
        }
        Array.Clear(destination, written * channels, (frames - written) * channels);
        wake.Set();
        if (tap != null)
        {
            if (reset) tap.Reset();
            if (written > 0) tap.Process(destination, written, format, end);
        }
        if (started != null) Started?.Invoke(started);
        if (ended) Ended?.Invoke();
    }

    public void Dispose()
    {
        running = false;
        wake.Set();
        thread.Join(1000);
        output.Dispose();
    }
}
