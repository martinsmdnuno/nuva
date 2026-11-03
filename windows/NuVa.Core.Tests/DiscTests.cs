using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NuVa.Core.Library;

namespace NuVa.Core.Tests;

public static class DiscTests
{
    // MusicBrainz's own example (and Tests/DiscTests.swift).
    private static readonly DiscToc example = new(1, 6, new Dictionary<int, int> { [1] = 0, [2] = 15213, [3] = 32164, [4] = 46442, [5] = 63264, [6] = 80339 }, 95312);

    [Test]
    public static void MusicBrainzDiscId()
    {
        Assert.Equal("49HHV7Eb8UKF3aQiNmu1GR8vKTY-", example.MusicBrainzId);
        Assert.Equal("1 6 95462 150 15363 32314 46592 63414 80489", example.MusicBrainzToc);
        Assert.Near(15213 / 75.0, example.Duration(1)!.Value, 1e-9);
    }

    [Test]
    public static void TocFromTheDrive()
    {
        var toc = DiscToc.From([(1, 150, false), (2, 10150, false), (3, 20150, false)], 30150)!;
        Assert.Equal(30000, toc.Leadout);
        Assert.Equal(10000, toc.Starts[2]);
        // Enhanced CD: the data session ends the audio early.
        var enhanced = DiscToc.From([(1, 150, false), (2, 10150, false), (3, 31400 + 150, true)], 40000)!;
        Assert.Equal(2, enhanced.LastTrack);
        Assert.Equal(31400 - DiscToc.DataSessionGap, enhanced.Leadout);
    }

    [Test]
    public static void SourceNamesTracksFromMusicBrainz()
    {
        var info = new DiscInfo("AC/DC", "Back in Black", ["Hells Bells", "Shoot to Thrill", "What Do You Do for Money Honey", "Given the Dog a Bone", "Let Me Put My Love into You", "Back in Black"], "r");
        var disc = new DiscSource('e', example, info, new DiscLookup(Path.GetTempPath(), CoverArtArchive.Shared));
        Assert.Equal("AC∕DC – Back in Black", disc.Folder);
        var tracks = disc.List(disc.Folder).Result;
        Assert.Equal("Hells Bells", tracks[0].Title);
        Assert.Equal("cdda://E/6", disc.Url(tracks[5]).Result);
        Assert.Equal(disc.Id, new DiscSource('F', example, null, new DiscLookup(Path.GetTempPath(), CoverArtArchive.Shared)).Id);
    }

    [Test]
    public static void PickPrefersTheExactDisc()
    {
        var six = Enumerable.Range(1, 6).Select(i => new DiscLookup.Release.Medium.Track { Title = $"t{i}" }).ToList();
        var releases = new List<DiscLookup.Release>
        {
            new() { Id = "a", Title = "Other", Media = [new() { Tracks = six }] },
            new() { Id = "b", Title = "Right", Media = [new() { Discs = [new() { Id = example.MusicBrainzId }], Tracks = six }] },
        };
        Assert.Equal("b", DiscLookup.Pick(releases, example)!.ReleaseId);
    }
}
