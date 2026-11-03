using System;
using System.IO;
using NuVa.Core.Library;

namespace NuVa.Core.Tests;

public static class ArtworkTests
{
    private static CoverArtArchive.ReleaseGroup Group(string artist, string title, int score = 100) =>
        new() { Id = "x", Score = score, Title = title, ArtistCredit = [new() { Name = artist }] };

    [Test]
    public static void OnlyConfidentMatches()
    {
        var query = new AlbumQuery("Fleetwood Mac", "Rumours");
        Assert.True(CoverArtArchive.Matches(Group("Fleetwood Mac", "Rumours"), query));
        Assert.True(CoverArtArchive.Matches(Group("Fleetwood Mac", "Rumours (Deluxe Edition)"), query));
        Assert.True(!CoverArtArchive.Matches(Group("Fleetwood Mac", "Tusk"), query));
        Assert.True(!CoverArtArchive.Matches(Group("Fleetwood Mac", "Rumours", 80), query));
        Assert.True(!CoverArtArchive.Matches(Group("Mac DeMarco", "Rumours"), query));
    }

    [Test]
    public static void CacheRemembersImagesAndMisses()
    {
        var root = Path.Combine(Path.GetTempPath(), "nuva-art-" + Guid.NewGuid());
        try
        {
            var cache = new ArtworkCache(root);
            var query = new AlbumQuery("A", "B");
            Assert.Equal(ArtworkCache.Kind.Unknown, cache.Online(query).Item1);
            cache.SaveOnline(null, query);
            Assert.Equal(ArtworkCache.Kind.None, cache.Online(query).Item1);
            cache.SaveOnline([1, 2, 3], query);
            Assert.Equal(ArtworkCache.Kind.Image, cache.Online(query).Item1);
            cache.SaveUser(null, "folder");
            Assert.Equal(ArtworkCache.Kind.None, cache.User("folder").Item1);
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    [Test]
    public static void DiscFoldersShareTheAlbumKey()
    {
        var id = Guid.NewGuid();
        var a = ArtworkResolver.FolderKey(new Entry(id, "Artist/Album/CD 1/01.flac", "01.flac", EntryKind.Track));
        var b = ArtworkResolver.FolderKey(new Entry(id, "Artist/Album/CD 2/01.flac", "01.flac", EntryKind.Track));
        Assert.Equal(a, b);
        Assert.True(a.EndsWith("/Artist/Album"), a);
    }
}
