using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NuVa.Core.Audio;
using NuVa.Core.Library;

namespace NuVa.Core.Player;

/// <summary>A queue entry. The same track can appear more than once.</summary>
public sealed record QueueItem(long Id, Entry Entry);

public enum RepeatMode { Off, All, One }

/// <summary>
/// Playback on top of the <see cref="Pipeline"/>: the queue, the playing order (shuffle), repeat, and
/// what to do when a track fails. A port of the Mac's PlayerController. Used on the UI thread; the
/// pipeline's events are posted back to it.
/// </summary>
public sealed class PlayerController
{
    private static long nextId;

    private readonly Pipeline pipeline;
    private readonly Func<Entry, CancellationToken, Task<Uri>> resolve;
    private readonly SynchronizationContext? ui;
    private readonly object gate = new();
    private List<QueueItem> queue = [];
    /// <summary>Playback order (queue ids). Same as the queue without shuffle.</summary>
    private List<long> order = [];
    private readonly HashSet<long> failedIds = [];
    private readonly HashSet<long> retriedIds = [];
    private RepeatMode repeat = RepeatMode.Off;
    private bool shuffle;
    private bool autoplay = true;
    private int playToken;
    private double heldTime;
    private float volume = 1;

    public IReadOnlyList<QueueItem> Queue => queue;
    public long? CurrentId { get; private set; }
    public QueueItem? Current => queue.FirstOrDefault(q => q.Id == CurrentId);
    public bool IsPlaying { get; private set; }
    public double Duration { get; private set; }
    /// <summary>"FLAC 24/96 · 4608 kbps".</summary>
    public string FormatLabel { get; private set; } = "";
    /// <summary>"Couldn't play …", shown on the display until a track plays.</summary>
    public string? ErrorMessage { get; private set; }
    public string? ErrorDetail { get; private set; }
    /// <summary>A track is being resolved or opened (a slow server).</summary>
    public bool IsLoading { get; private set; }

    /// <summary>Anything above changed (queue, current track, state).</summary>
    public event Action? Changed;
    /// <summary>After a seek (for the system media controls).</summary>
    public event Action? Seeked;
    /// <summary>Called once when a track fails, before trying it again: a server can sign in afresh.</summary>
    public Func<Entry, Task>? OnStreamFailure { get; set; }
    /// <summary>Volume changes go to the output.</summary>
    public Action<float>? ApplyVolume { get; set; }

    public PlayerController(Pipeline pipeline, Func<Entry, CancellationToken, Task<Uri>> resolve, SynchronizationContext? ui)
    {
        this.pipeline = pipeline;
        this.resolve = resolve;
        this.ui = ui;
        pipeline.Next = Upcoming;
        pipeline.Started += info => Post(() => Started(info));
        pipeline.Failed += (token, error) => Post(() => Failed(token, error.Message));
        pipeline.Ended += () => Post(Ended);
    }

    private void Post(Action action)
    {
        if (ui == null) action();
        else ui.Post(_ => action(), null);
    }

    /// <summary>The audible position. Held while loading or stopped.</summary>
    public double CurrentTime => pipeline.Audible?.Token == CurrentId && CurrentId != null && !IsLoading ? pipeline.Position : heldTime;

    public float Volume
    {
        get => volume;
        set
        {
            volume = Math.Clamp(value, 0, 1);
            ApplyVolume?.Invoke(volume);
            Changed?.Invoke();
        }
    }

    public RepeatMode RepeatMode
    {
        get => repeat;
        set
        {
            lock (gate) repeat = value;
            pipeline.RefreshUpcoming();
            Changed?.Invoke();
        }
    }

    public bool Shuffle
    {
        get => shuffle;
        set
        {
            if (shuffle == value) return;
            shuffle = value;
            RebuildOrder();
            pipeline.RefreshUpcoming();
            Changed?.Invoke();
        }
    }

    // MARK: Queue

    /// <summary>Replaces the queue (play folder) and starts at <paramref name="startAt"/>.</summary>
    public void SetQueue(IEnumerable<Entry> entries, int startAt = 0)
    {
        lock (gate)
        {
            queue = entries.Select(e => new QueueItem(Interlocked.Increment(ref nextId), e)).ToList();
            failedIds.Clear();
            retriedIds.Clear();
        }
        if (startAt < 0 || startAt >= queue.Count)
        {
            StopAll();
            Changed?.Invoke();
            return;
        }
        CurrentId = queue[startAt].Id;
        RebuildOrder();
        Play(queue[startAt].Id);
    }

    /// <summary>Appends to the end of the queue.</summary>
    public void Append(IEnumerable<Entry> entries)
    {
        var items = entries.Select(e => new QueueItem(Interlocked.Increment(ref nextId), e)).ToList();
        lock (gate)
        {
            queue = [.. queue, .. items];
            if (shuffle)
            {
                var start = order.IndexOf(CurrentId ?? -1) + 1;
                foreach (var item in items) order.Insert(Random.Shared.Next(start, order.Count + 1), item.Id);
            }
            else
            {
                order = queue.Select(q => q.Id).ToList();
            }
        }
        pipeline.RefreshUpcoming();
        Changed?.Invoke();
    }

    public void Remove(IEnumerable<int> indices)
    {
        var removed = indices.Where(i => i >= 0 && i < queue.Count).Select(i => queue[i].Id).ToHashSet();
        if (removed.Count == 0) return;
        var wasPlaying = IsPlaying;
        long? replacement = null;
        if (CurrentId is { } current && removed.Contains(current))
        {
            // The current track was removed: move on to the next remaining one.
            replacement = order.SkipWhile(id => id != current).Where(id => !removed.Contains(id)).Cast<long?>().FirstOrDefault();
        }
        lock (gate)
        {
            queue = queue.Where(q => !removed.Contains(q.Id)).ToList();
            order = order.Where(id => !removed.Contains(id)).ToList();
        }
        if (CurrentId is { } c && removed.Contains(c))
        {
            if (replacement is { } next && wasPlaying)
            {
                Play(next);
            }
            else
            {
                StopAll();
                CurrentId = replacement;
            }
        }
        else
        {
            pipeline.RefreshUpcoming();
        }
        Changed?.Invoke();
    }

    /// <summary>Removes every entry that matches (a CD that went away). If the current track goes too, playback stops.</summary>
    public void RemoveAll(Func<Entry, bool> shouldRemove)
    {
        var removed = queue.Where(q => shouldRemove(q.Entry)).Select(q => q.Id).ToHashSet();
        if (removed.Count == 0) return;
        var stopsCurrent = CurrentId is { } c && removed.Contains(c);
        if (stopsCurrent) StopAll();
        lock (gate)
        {
            queue = queue.Where(q => !removed.Contains(q.Id)).ToList();
            order = order.Where(id => !removed.Contains(id)).ToList();
        }
        if (!stopsCurrent) pipeline.RefreshUpcoming();
        Changed?.Invoke();
    }

    /// <summary>Moves the rows at <paramref name="indices"/> to before row <paramref name="destination"/> (as SwiftUI's move).</summary>
    public void Move(IEnumerable<int> indices, int destination)
    {
        var set = indices.Where(i => i >= 0 && i < queue.Count).OrderBy(i => i).ToList();
        if (set.Count == 0) return;
        var moving = set.Select(i => queue[i]).ToList();
        var before = set.Count(i => i < destination);
        var rest = queue.Where((_, i) => !set.Contains(i)).ToList();
        rest.InsertRange(Math.Clamp(destination - before, 0, rest.Count), moving);
        lock (gate)
        {
            queue = rest;
            if (!shuffle) order = queue.Select(q => q.Id).ToList();
        }
        pipeline.RefreshUpcoming();
        Changed?.Invoke();
    }

    public void Clear()
    {
        lock (gate)
        {
            queue = [];
            order = [];
            failedIds.Clear();
            retriedIds.Clear();
        }
        ErrorMessage = null;
        ErrorDetail = null;
        StopAll();
        Changed?.Invoke();
    }

    // MARK: Transport

    /// <summary>Plays a queue entry. One the user picks is tried again even if it failed before.</summary>
    public void Play(long id)
    {
        lock (gate) failedIds.Remove(id);
        Start(id);
    }

    private void Start(long id, double at = 0)
    {
        var item = queue.FirstOrDefault(q => q.Id == id);
        if (item == null) return;
        playToken++;
        CurrentId = id;
        heldTime = at;
        Duration = item.Entry.Duration ?? 0;
        FormatLabel = item.Entry.Format;
        autoplay = true;
        IsLoading = true;
        IsPlaying = true;
        pipeline.Play(Request(item), at);
        Changed?.Invoke();
    }

    private TrackRequest Request(QueueItem item) => new(item.Id, token => resolve(item.Entry, token), item.Entry.Name);

    public void TogglePlayPause()
    {
        if (IsPlaying)
        {
            Pause();
        }
        else if (CurrentId is { } current && pipeline.Audible?.Token == current)
        {
            autoplay = true;
            IsPlaying = true;
            pipeline.Resume();
            Changed?.Invoke();
        }
        else if (CurrentId is { } id)
        {
            Start(id, heldTime);
            lock (gate) failedIds.Remove(id);
        }
        else if (order.Count > 0)
        {
            var first = order.FirstOrDefault(id => !failedIds.Contains(id));
            Play(first != 0 ? first : order[0]);
        }
    }

    public void Pause()
    {
        autoplay = false;
        IsPlaying = false;
        heldTime = CurrentTime;
        pipeline.Pause();
        Changed?.Invoke();
    }

    public void Stop()
    {
        Pause();
        Seek(0);
    }

    public void Next()
    {
        if (CurrentId is not { } current || Step(current, 1, repeat != RepeatMode.Off) is not { } id) return;
        Play(id);
    }

    /// <summary>Back to the start of the track after 3 s; otherwise to the previous one.</summary>
    public void Previous()
    {
        if (CurrentId is not { } current) return;
        if (CurrentTime > 3) Seek(0);
        else if (Step(current, -1, repeat != RepeatMode.Off) is { } id) Play(id);
        else Seek(0);
    }

    public void Seek(double seconds)
    {
        var target = Math.Max(0, Duration > 0 ? Math.Min(seconds, Duration) : seconds);
        heldTime = target;
        if (pipeline.Audible?.Token == CurrentId) pipeline.Seek(target);
        Seeked?.Invoke();
        Changed?.Invoke();
    }

    public void Skip(double seconds) => Seek(CurrentTime + seconds);

    public void ChangeVolume(float delta) => Volume = volume + delta;

    // MARK: Internal

    private void StopAll()
    {
        playToken++;
        IsLoading = false;
        IsPlaying = false;
        pipeline.Stop();
        CurrentId = null;
        heldTime = 0;
        Duration = 0;
        FormatLabel = "";
    }

    private void RebuildOrder()
    {
        lock (gate)
        {
            var ids = queue.Select(q => q.Id).ToList();
            if (!shuffle)
            {
                order = ids;
                return;
            }
            // Shuffle: the current track stays first, the rest shuffled.
            var rest = ids.Where(id => id != CurrentId).OrderBy(_ => Random.Shared.Next()).ToList();
            order = CurrentId is { } c ? [c, .. rest] : rest;
        }
    }

    private long? Step(long id, int delta, bool wrap)
    {
        lock (gate)
        {
            var i = order.IndexOf(id);
            if (i < 0 || order.Count == 0) return null;
            var j = i + delta;
            if (j >= 0 && j < order.Count) return order[j];
            if (!wrap) return null;
            return order[((j % order.Count) + order.Count) % order.Count];
        }
    }

    /// <summary>What plays after <paramref name="token"/> without intervention, skipping tracks that failed (decoder thread).</summary>
    public TrackRequest? Upcoming(long token)
    {
        lock (gate)
        {
            long? id;
            if (repeat == RepeatMode.One) id = failedIds.Contains(token) ? null : token;
            else id = Playable(token, repeat == RepeatMode.All);
            var item = id == null ? null : queue.FirstOrDefault(q => q.Id == id);
            return item == null ? null : Request(item);
        }
    }

    /// <summary>The next track that hasn't failed, in playing order, or null.</summary>
    private long? Playable(long after, bool wrap)
    {
        var candidate = after;
        for (var n = 0; n < order.Count; n++)
        {
            var i = order.IndexOf(candidate);
            if (i < 0) return null;
            var j = i + 1;
            long next;
            if (j < order.Count) next = order[j];
            else if (wrap) next = order[0];
            else return null;
            if (next == after) return null;
            if (!failedIds.Contains(next)) return next;
            candidate = next;
        }
        return null;
    }

    private void Started(TrackInfo info)
    {
        var item = queue.FirstOrDefault(q => q.Id == info.Token);
        if (item == null) return;
        // The pipeline moved on by itself (gapless), or the track we asked for opened.
        CurrentId = item.Id;
        IsLoading = false;
        IsPlaying = pipeline.IsPlaying;
        Duration = info.Duration > 0 ? info.Duration : item.Entry.Duration ?? 0;
        FormatLabel = Label(item.Entry, info);
        heldTime = 0;
        if (ErrorMessage != null || retriedIds.Contains(item.Id))
        {
            // Music is coming out: an earlier failure's message has done its job.
            ErrorMessage = null;
            ErrorDetail = null;
            lock (gate) retriedIds.Remove(item.Id);
        }
        Changed?.Invoke();
    }

    private void Ended()
    {
        // End of the queue: stays on the last track, ready to play again.
        IsPlaying = false;
        IsLoading = false;
        heldTime = 0;
        pipeline.Stop();
        Changed?.Invoke();
    }

    /// <summary>
    /// A track failed to resolve or open. The first time it is tried again (after the source had its chance
    /// to sign in afresh); the second time it is skipped, with a message on the display. If nothing in the
    /// queue plays, playback stops on the failed track.
    /// </summary>
    private async void Failed(long id, string detail)
    {
        var item = queue.FirstOrDefault(q => q.Id == id);
        if (item == null || failedIds.Contains(id)) return;
        var isCurrent = id == CurrentId && pipeline.Audible?.Token != id;
        if (!retriedIds.Contains(id))
        {
            lock (gate) retriedIds.Add(id);
            var token = playToken;
            if (OnStreamFailure != null) await OnStreamFailure(item.Entry);
            if (isCurrent)
            {
                if (token != playToken || CurrentId != id) return;
                Start(id);
            }
            else
            {
                pipeline.RefreshUpcoming();
            }
            return;
        }
        lock (gate) failedIds.Add(id);
        if (!isCurrent)
        {
            pipeline.RefreshUpcoming();
            return;
        }
        ErrorMessage = L.F("Não foi possível tocar {0}", item.Entry.Title);
        ErrorDetail = detail;
        long? next;
        lock (gate) next = Playable(id, repeat != RepeatMode.Off);
        if (autoplay && next is { } n)
        {
            Start(n);
        }
        else
        {
            // Nothing else to try: stay on this track, stopped.
            playToken++;
            IsLoading = false;
            IsPlaying = false;
            heldTime = 0;
            pipeline.Stop();
        }
        Changed?.Invoke();
    }

    /// <summary>"FLAC 24/96 · 4608 kbps", "MP3 44.1 · 320 kbps", as the Mac's AudioFormat.label.</summary>
    public static string Label(Entry entry, TrackInfo info)
    {
        var ext = entry.Format;
        var rate = KHz(info.Format.SampleRate);
        var label = info.SourceBits > 0 ? $"{ext} {info.SourceBits}/{rate}" : $"{ext} {rate}";
        var kbps = 0L;
        try
        {
            if (info.Duration > 0 && System.IO.File.Exists(info.Location))
                kbps = (long)Math.Round(new System.IO.FileInfo(info.Location).Length * 8 / info.Duration / 1000);
        }
        catch (Exception)
        {
        }
        return kbps > 0 ? $"{label} · {kbps} kbps" : label;
    }

    /// <summary>44100 → "44.1", 48000 → "48".</summary>
    public static string KHz(int rate)
    {
        var k = rate / 1000.0;
        return Math.Round(k) == k ? ((int)k).ToString(CultureInfo.InvariantCulture) : k.ToString("0.0", CultureInfo.InvariantCulture);
    }
}
