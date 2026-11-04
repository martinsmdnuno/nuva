using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NuVa.Core.Library;

namespace NuVa.Core.Tests;

public static class LibraryTests
{
    [Test]
    public static void NaturalOrder()
    {
        string[] names = ["Track 10.flac", "track 2.flac", "Track 1.flac", "01 Intro.flac", "1 Intro.flac", "CD 2", "CD 10", "CD 1"];
        var sorted = names.OrderBy(n => n, NaturalComparer.Instance).ToArray();
        Assert.Sequence(["01 Intro.flac", "1 Intro.flac", "CD 1", "CD 2", "CD 10", "Track 1.flac", "track 2.flac", "Track 10.flac"], sorted);
    }

    [Test]
    public static void FolderLineNamesArtistAndAlbumFolders()
    {
        Entry At(string path) => new(Guid.NewGuid(), path, "01 - Dreams.flac", EntryKind.Track);
        var album = At("Fleetwood Mac/Rumours (1977)/01 - Dreams.flac");
        Assert.Equal("Fleetwood Mac", album.ArtistFolder);
        Assert.Equal("Fleetwood Mac · Rumours (1977)", album.FolderLine);
        // A disc folder belongs to the album above it.
        var disc = At("Música/Fleetwood Mac/Tusk/CD 2/01 - Dreams.flac");
        Assert.Equal("Música/Fleetwood Mac/Tusk", disc.AlbumPath);
        Assert.Equal("Fleetwood Mac · Tusk", disc.FolderLine);
        // A source added at the album: nothing above it.
        var root = At("Rumours/01 - Dreams.flac");
        Assert.Equal(null, root.ArtistFolder);
        Assert.Equal("Rumours", root.FolderLine);
    }

    [Test]
    public static void FoldersComeFirst()
    {
        var id = Guid.NewGuid();
        var entries = new[]
        {
            new Entry(id, "b.flac", "b.flac", EntryKind.Track),
            new Entry(id, "Z", "Z", EntryKind.Folder),
            new Entry(id, "a.flac", "a.flac", EntryKind.Track),
            new Entry(id, "A", "A", EntryKind.Folder),
        }.NaturallySorted();
        Assert.Sequence(["A", "Z", "a.flac", "b.flac"], entries.Select(e => e.Name));
    }

    [Test]
    public static void TitlesDropNumbersAndExtension()
    {
        var id = Guid.NewGuid();
        Assert.Equal("Dreams", new Entry(id, "x/02 - Dreams.flac", "02 - Dreams.flac", EntryKind.Track).Title);
        Assert.Equal("Dreams", new Entry(id, "x/2. Dreams.flac", "2. Dreams.flac", EntryKind.Track).Title);
        Assert.Equal("Dreams", new Entry(id, "x/02_Dreams.flac", "02_Dreams.flac", EntryKind.Track).Title);
        Assert.Equal("1999", new Entry(id, "x/1999.flac", "1999.flac", EntryKind.Track).Title);
        Assert.Equal("FLAC", new Entry(id, "x/1999.flac", "1999.flac", EntryKind.Track).Format);
        Assert.Equal("x", new Entry(id, "x/1999.flac", "1999.flac", EntryKind.Track).FolderName);
    }

    [Test]
    public static void ArtworkFilePreference()
    {
        Assert.Equal("Folder.JPG", ArtworkFiles.Pick(["a.flac", "back.jpg", "Folder.JPG", "front.png"]));
        Assert.Equal("cover.png", ArtworkFiles.Pick(["capa.jpg", "cover.png"]));
        Assert.Equal(null, ArtworkFiles.Pick(["scan.jpg", "cover.gif"]));
    }

    [Test]
    public static void AlbumGuesses()
    {
        Assert.Equal(new AlbumQuery("Fleetwood Mac", "Rumours"), AlbumGuess.From("Fleetwood Mac/1977 - Rumours (Remastered) [FLAC 24-96]/CD 01"));
        Assert.Equal(new AlbumQuery("Fleetwood Mac", "Rumours"), AlbumGuess.From("Music/Fleetwood Mac - Rumours"));
        Assert.Equal(new AlbumQuery("Fleetwood Mac", "Rumours"), AlbumGuess.From("Rumours (1977)", "Fleetwood Mac"));
        Assert.Equal(new AlbumQuery("Fleetwood Mac", "Rumours"), AlbumGuess.From("Fleetwood Mac/Fleetwood Mac - Rumours"));
        Assert.Equal(null, AlbumGuess.From("Rumours"));
        Assert.Equal("lauryn hill|miseducation", new AlbumQuery("Ms. Lauryn Hill", "The Miseducation").WithoutTitle!.Key);
        Assert.Equal("beyonce and jayz", AlbumGuess.Normalize("Beyoncé & Jay-Z"));
        Assert.True(AlbumGuess.IsDiscFolder("Disc 2"));
        Assert.True(!AlbumGuess.IsDiscFolder("Discovery"));
    }

    [Test]
    public static void LocalSourceListsPlayableFiles()
    {
        var root = Path.Combine(Path.GetTempPath(), "nuva-test-" + Guid.NewGuid());
        Directory.CreateDirectory(Path.Combine(root, "Album", "CD 2"));
        Directory.CreateDirectory(Path.Combine(root, "Album", "CD 10"));
        File.WriteAllText(Path.Combine(root, "Album", "10 b.flac"), "");
        File.WriteAllText(Path.Combine(root, "Album", "2 a.FLAC"), "");
        File.WriteAllText(Path.Combine(root, "Album", "notes.txt"), "");
        File.WriteAllText(Path.Combine(root, "Album", ".hidden.flac"), "");
        File.WriteAllText(Path.Combine(root, "Album", "cover.jpg"), "");
        try
        {
            var source = new LocalSource(Guid.NewGuid(), "Music", root);
            var entries = source.List("Album").Result;
            Assert.Sequence(["CD 2", "CD 10", "2 a.FLAC", "10 b.flac"], entries.Select(e => e.Name));
            Assert.Equal("Album/CD 2", entries[0].Path);
            Assert.Equal("cover.jpg", Path.GetFileName(source.Artwork("Album").Result!));

            var store = new SourceStore(new Settings(null), new MemoryCredentials());
            var added = store.AddLocal(root);
            Assert.Equal(added, store.AddLocal(root + Path.DirectorySeparatorChar));
            var art = store.Artwork(new Entry(added.Id, "Album/CD 2/01.flac", "01.flac", EntryKind.Track)).Result;
            Assert.Equal("cover.jpg", Path.GetFileName(art!));
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Test]
    public static void SourcesAreRemembered()
    {
        var root = Path.GetTempPath();
        var settings = new Settings(null);
        var first = new SourceStore(settings, new MemoryCredentials());
        first.Load();
        var added = first.AddLocal(root);
        var second = new SourceStore(settings, new MemoryCredentials());
        second.Load();
        Assert.Equal(added.Id, second.Sources.Single().Id);
        var third = new SourceStore(settings, new MemoryCredentials());
        settings.Set("sources", new[] { new SourceStore.Record(Guid.NewGuid(), "Gone", SourceKind.Local, Path: "/nonexistent/nuva") });
        third.Load();
        Assert.Equal(1, third.Failed.Count);
    }
}

public sealed class MemoryCredentials : ICredentialStore
{
    private readonly System.Collections.Generic.Dictionary<string, string> passwords = new();
    public string? Password(string account) => passwords.GetValueOrDefault(account);
    public void SetPassword(string password, string account) => passwords[account] = password;
    public void DeletePassword(string account) => passwords.Remove(account);
}

public static class LocationTests
{
    [Test]
    public static void FilePathsStayAsTheyAre()
    {
        var root = Path.Combine(Path.GetTempPath(), "nuva-loc-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        var name = "a#b 100% c%20d.flac";
        File.WriteAllText(Path.Combine(root, name), "");
        try
        {
            var source = new LocalSource(Guid.NewGuid(), "x", root);
            var location = source.Url(new Entry(source.Id, name, name, EntryKind.Track)).Result;
            Assert.Equal(Path.Combine(root, name), location);
            Assert.True(Locations.IsFile(location));
            Assert.True(!Locations.IsFile("https://jellyfin/Audio/1/stream.flac"));
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }
}
