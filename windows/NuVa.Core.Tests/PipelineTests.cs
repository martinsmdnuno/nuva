using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NuVa.Core.Audio;

namespace NuVa.Core.Tests;

/// <summary>A decoder of a ramp: sample i of track k is k * 1000 + i, so gaps and repeats show.</summary>
public sealed class RampDecoder(int track, int frames, int rate = 1000) : IDecoder
{
    private int position;
    public AudioFormat Format { get; } = new(rate, 1);
    public double Duration => (double)frames / rate;
    public int SourceBits => 16;

    public int Read(float[] buffer, int maxFrames)
    {
        var n = Math.Min(maxFrames, frames - position);
        for (var i = 0; i < n; i++) buffer[i] = track * 1000 + position + i;
        position += n;
        return n;
    }

    public void Seek(double seconds) => position = (int)(seconds * Format.SampleRate);
    public void Dispose() { }
}

public sealed class RampFactory : IDecoderFactory
{
    public readonly Dictionary<int, int> Frames = new();
    public readonly Dictionary<int, int> Rates = new();
    public IDecoder Open(string location)
    {
        var track = int.Parse(location.Split('/').Last());
        if (!Frames.TryGetValue(track, out var frames)) throw new Exception("missing");
        return new RampDecoder(track, frames, Rates.GetValueOrDefault(track, 1000));
    }
}

/// <summary>Pulls blocks of 100 frames as fast as asked, recording what came out.</summary>
public sealed class FakeOutput : IAudioOutput
{
    public Action<float[], int, AudioFormat>? Render { get; set; }
    public AudioFormat Format;
    public readonly List<AudioFormat> Configured = new();
    public bool Running;
    public double Latency => 0;
    public readonly List<float> Heard = new();

    public void Configure(AudioFormat format) { Format = format; Configured.Add(format); }
    public void Start() => Running = true;
    public void Stop() => Running = false;

    /// <summary>Pulls <paramref name="blocks"/> blocks, waiting for the decoder when the queue is empty.</summary>
    public void Pull(int blocks, int frames = 100)
    {
        var buffer = new float[frames * 2];
        for (var b = 0; b < blocks; b++)
        {
            Thread.Sleep(2);
            Render!(buffer, frames, Format);
            for (var i = 0; i < frames * Format.Channels; i += Format.Channels) Heard.Add(buffer[i]);
        }
    }

    public void Dispose() { }
}

public static class PipelineTests
{
    private static TrackRequest Track(int k) => new(k, _ => Task.FromResult($"test://track/{k}"), $"track {k}");

    private static (Pipeline, FakeOutput, RampFactory, ConcurrentQueue<long>) Make(params int[] frames)
    {
        var factory = new RampFactory();
        for (var k = 0; k < frames.Length; k++) factory.Frames[k + 1] = frames[k];
        var output = new FakeOutput();
        var pipeline = new Pipeline(factory, output, null);
        var started = new ConcurrentQueue<long>();
        pipeline.Started += info => started.Enqueue(info.Token);
        pipeline.Next = token => token < frames.Length ? Track((int)token + 1) : null;
        return (pipeline, output, factory, started);
    }

    private static void Settle() => Thread.Sleep(150);

    [Test]
    public static void GaplessAcrossTracks()
    {
        var (pipeline, output, _, started) = Make(250, 300);
        var ended = false;
        pipeline.Ended += () => ended = true;
        pipeline.Play(Track(1));
        Settle();
        output.Pull(7);
        // 250 frames of track 1, then track 2 straight after, then silence.
        var heard = output.Heard.Take(550).ToList();
        Assert.Sequence(Enumerable.Range(0, 250).Select(i => (float)(1000 + i)).Concat(Enumerable.Range(0, 300).Select(i => (float)(2000 + i))), heard);
        Assert.Sequence([1L, 2L], started);
        Assert.True(ended, "ended");
        Assert.True(output.Heard.Skip(550).All(x => x == 0), "silence after the end");
        pipeline.Dispose();
    }

    [Test]
    public static void SeekWithinTrack()
    {
        var (pipeline, output, _, _) = Make(5000);
        pipeline.Play(Track(1));
        Settle();
        output.Pull(1);
        pipeline.Seek(3.0);
        Assert.Near(3.0, pipeline.Position, 0.001);
        Settle();
        output.Heard.Clear();
        output.Pull(1);
        Assert.Equal(1000f + 3000, output.Heard[0]);
        Assert.Near(3.1, pipeline.Position, 0.001);
        pipeline.Dispose();
    }

    [Test]
    public static void SeekAfterDecoderMovedOn()
    {
        // Track 1 is short: the decoder is already into track 2 while track 1 is heard.
        var (pipeline, output, _, started) = Make(300, 2000);
        pipeline.Play(Track(1));
        Settle();
        output.Pull(1);
        pipeline.Seek(0.05);
        Settle();
        output.Heard.Clear();
        output.Pull(3);
        Assert.Equal(1050f, output.Heard[0]);
        Assert.Equal(2000f, output.Heard[250]);
        Assert.Sequence([1L, 2L], started);
        pipeline.Dispose();
    }

    [Test]
    public static void RefreshUpcomingDropsPrefetchedTrack()
    {
        var (pipeline, output, factory, started) = Make(300, 300, 300);
        pipeline.Play(Track(1));
        Settle();
        output.Pull(1);
        // The queue changed: after track 1 comes track 3 now.
        pipeline.Next = token => token == 1 ? Track(3) : null;
        pipeline.RefreshUpcoming();
        Settle();
        output.Heard.Clear();
        output.Pull(3);
        Assert.Equal(1100f, output.Heard[0]);
        Assert.Equal(3000f, output.Heard[200]);
        Assert.Sequence([1L, 3L], started);
        pipeline.Dispose();
    }

    [Test]
    public static void FailedTrackIsReported()
    {
        var (pipeline, output, _, _) = Make(300);
        var failed = new ConcurrentQueue<long>();
        pipeline.Failed += (token, _) => failed.Enqueue(token);
        pipeline.Play(Track(7));
        Settle();
        Assert.Sequence([7L], failed);
        pipeline.Dispose();
    }

    [Test]
    public static void RepeatOneStartsAgain()
    {
        var (pipeline, output, _, started) = Make(150);
        var infos = new ConcurrentQueue<TrackInfo>();
        pipeline.Started += infos.Enqueue;
        pipeline.Next = token => Track(1);
        pipeline.Play(Track(1));
        Settle();
        output.Pull(4);
        Assert.Equal(1000f, output.Heard[150]);
        Assert.True(infos.Count >= 2 && infos.Select(i => i.Run).Distinct().Count() >= 2, "each run reported");
        pipeline.Dispose();
    }

    [Test]
    public static void NewRateReconfiguresOutput()
    {
        var (pipeline, output, factory, started) = Make(200, 400);
        factory.Rates[2] = 2000;
        pipeline.Play(Track(1));
        Settle();
        output.Pull(3); // the third block finds track 2 at another rate: silence while the output is rebuilt
        Settle();
        output.Pull(4);
        Assert.Sequence([new AudioFormat(1000, 1), new AudioFormat(2000, 1)], output.Configured);
        Assert.True(output.Heard.Contains(2000f) && output.Heard.Contains(2399f), "track 2 heard after the switch: " + string.Join(",", output.Heard.Where((x, i) => i % 50 == 0)));
        pipeline.Dispose();
    }
}
