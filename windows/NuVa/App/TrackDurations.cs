using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;
using NuVa.Audio;
using NuVa.Core;
using NuVa.Core.Library;

namespace NuVa;

/// <summary>Track durations for the lists, read on demand (one file at a time) and cached in memory.</summary>
public sealed class TrackDurations
{
    private readonly Dictionary<string, double> values = new();
    private readonly HashSet<string> pending = [];
    private readonly ConcurrentQueue<(Entry Entry, string Url)> queue = new();
    private readonly SourceStore sources;
    private readonly Dispatcher ui;
    private readonly DispatcherTimer notify;
    private int working;

    public event Action? Changed;

    public TrackDurations(SourceStore sources, Dispatcher ui)
    {
        this.sources = sources;
        this.ui = ui;
        // Many durations arrive at once for an album: one redraw for them.
        notify = new DispatcherTimer(DispatcherPriority.Background, ui) { Interval = TimeSpan.FromMilliseconds(150) };
        notify.Tick += (_, _) =>
        {
            notify.Stop();
            Changed?.Invoke();
        };
    }

    public double? Get(Entry entry) => values.TryGetValue(entry.Id, out var d) ? d : null;

    public async void Load(Entry entry)
    {
        if (values.ContainsKey(entry.Id) || !pending.Add(entry.Id)) return;
        if (entry.Duration is { } known)
        {
            values[entry.Id] = known;
            pending.Remove(entry.Id);
            notify.Start();
            return;
        }
        string url;
        try
        {
            url = await sources.Resolve(entry);
        }
        catch (Exception)
        {
            return;
        }
        // Streams aren't opened just for a duration (Jellyfin sends it with the list).
        if (!Locations.IsFile(url) && !url.StartsWith("cdda://", StringComparison.Ordinal)) return;
        queue.Enqueue((entry, url));
        if (Interlocked.Exchange(ref working, 1) == 0) _ = Task.Run(Work);
    }

    private void Work()
    {
        var factory = new DecoderFactory();
        while (queue.TryDequeue(out var item))
        {
            double seconds = 0;
            try
            {
                using var decoder = factory.Open(item.Url);
                seconds = decoder.Duration;
            }
            catch (Exception e)
            {
                Log.Write($"durations: {item.Entry.Name}: {e.Message}");
            }
            ui.BeginInvoke(() =>
            {
                if (seconds > 0) values[item.Entry.Id] = seconds;
                pending.Remove(item.Entry.Id);
                notify.Start();
            });
        }
        Interlocked.Exchange(ref working, 0);
        if (!queue.IsEmpty && Interlocked.Exchange(ref working, 1) == 0) Work();
    }
}
