using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NuVa.Core.Audio;
using NuVa.Core.Library;
using NuVa.Core.Player;

namespace NuVa.Core.Tests;

public static class PlayerTests
{
    private static (PlayerController, Pipeline, FakeOutput) Make(int tracks)
    {
        var factory = new RampFactory();
        for (var k = 1; k <= tracks; k++) factory.Frames[k] = 200;
        var output = new FakeOutput();
        var pipeline = new Pipeline(factory, output, null);
        var player = new PlayerController(pipeline, (entry, _) => Task.FromResult(new Uri($"test://track/{entry.Name}")), null);
        var id = Guid.NewGuid();
        player.SetQueue(Enumerable.Range(1, tracks).Select(k => new Entry(id, $"a/{k}", $"{k}", EntryKind.Track)));
        return (player, pipeline, output);
    }

    [Test]
    public static void UpcomingFollowsOrderAndRepeat()
    {
        var (player, pipeline, _) = Make(3);
        var ids = player.Queue.Select(q => q.Id).ToArray();
        Assert.Equal(ids[1], player.Upcoming(ids[0])!.Token);
        Assert.Equal(null, player.Upcoming(ids[2]));
        player.RepeatMode = RepeatMode.All;
        Assert.Equal(ids[0], player.Upcoming(ids[2])!.Token);
        player.RepeatMode = RepeatMode.One;
        Assert.Equal(ids[2], player.Upcoming(ids[2])!.Token);
        pipeline.Dispose();
    }

    [Test]
    public static void ShuffleKeepsCurrentFirst()
    {
        var (player, pipeline, _) = Make(20);
        var current = player.CurrentId;
        player.Shuffle = true;
        // Every track comes up once, starting after the current one.
        var seen = new System.Collections.Generic.List<long>();
        var at = current!.Value;
        while (player.Upcoming(at) is { } next) { seen.Add(next.Token); at = next.Token; }
        Assert.Equal(19, seen.Count);
        Assert.True(!seen.Contains(current.Value), "current not repeated");
        pipeline.Dispose();
    }

    [Test]
    public static void RemovingTheCurrentTrackMovesOn()
    {
        var (player, pipeline, _) = Make(3);
        var ids = player.Queue.Select(q => q.Id).ToArray();
        player.Remove([0]);
        Assert.Equal(ids[1], player.CurrentId);
        Assert.Equal(2, player.Queue.Count);
        pipeline.Dispose();
    }

    [Test]
    public static void MoveReorders()
    {
        var (player, pipeline, _) = Make(4);
        var ids = player.Queue.Select(q => q.Id).ToArray();
        player.Move([3], 1);
        Assert.Sequence([ids[0], ids[3], ids[1], ids[2]], player.Queue.Select(q => q.Id));
        player.Move([0], 4);
        Assert.Sequence([ids[3], ids[1], ids[2], ids[0]], player.Queue.Select(q => q.Id));
        pipeline.Dispose();
    }

    [Test]
    public static void FormatLabels()
    {
        var entry = new Entry(Guid.NewGuid(), "a.flac", "a.flac", EntryKind.Track);
        Assert.Equal("FLAC 24/96", PlayerController.Label(entry, new TrackInfo(1, 1, 0, new AudioFormat(96000, 2), 24, "")));
        Assert.Equal("FLAC 44.1", PlayerController.Label(entry, new TrackInfo(1, 1, 0, new AudioFormat(44100, 2), 0, "")));
    }
}
