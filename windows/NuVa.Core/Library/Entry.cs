using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace NuVa.Core.Library;

public enum EntryKind { Folder, Track }

/// <summary>A folder or a track inside a source. The path is relative to the source root, with '/' between folders.</summary>
public sealed record Entry(Guid SourceId, string Path, string Name, EntryKind Kind, double? Duration = null)
{
    public string Id => $"{SourceId}/{Path}";

    /// <summary>Uppercase extension, for the display ("FLAC").</summary>
    public string Format => Paths.Extension(Name).ToUpperInvariant();

    /// <summary>Name for lists: the file name without extension, the folder name as is.</summary>
    public string ListName => Kind == EntryKind.Track ? Paths.WithoutExtension(Name) : Name;

    private static readonly Regex leadingNumber = new(@"^\d{1,3}(\s*[-–._)]\s*|\s+)", RegexOptions.Compiled);

    /// <summary>File name without extension or leading number ("01 - ", "1. ", "01_").</summary>
    public string Title
    {
        get
        {
            var name = Paths.WithoutExtension(Name);
            var stripped = leadingNumber.Replace(name, "", 1);
            return stripped.Length == 0 ? name : stripped;
        }
    }

    /// <summary>Name of the folder containing the entry.</summary>
    public string FolderName => Paths.LastComponent(ParentPath);

    /// <summary>Path of the folder containing the entry.</summary>
    public string ParentPath => Paths.Parent(Path);

    /// <summary>The album's folder: the one holding the track, or the one above a disc folder ("CD 1").</summary>
    public string AlbumPath
    {
        get
        {
            var folder = ParentPath;
            while (folder.Length > 0 && AlbumGuess.IsDiscFolder(Paths.LastComponent(folder))) folder = Paths.Parent(folder);
            return folder;
        }
    }

    /// <summary>The folder above the album, as it is named: usually the artist. Folders, never tags.</summary>
    public string? ArtistFolder => Paths.LastComponent(Paths.Parent(AlbumPath)) is { Length: > 0 } name ? name : null;

    /// <summary>"Fleetwood Mac · Rumours (1977)": the artist's and the album's folders.</summary>
    public string FolderLine => string.Join(" · ", new[] { ArtistFolder, Paths.LastComponent(AlbumPath) }.Where(s => !string.IsNullOrEmpty(s)));
}

/// <summary>Helpers for the sources' '/' paths, whatever the OS.</summary>
public static class Paths
{
    public static string Extension(string name)
    {
        var dot = name.LastIndexOf('.');
        return dot <= 0 || dot == name.Length - 1 ? "" : name[(dot + 1)..];
    }

    public static string WithoutExtension(string name)
    {
        var dot = name.LastIndexOf('.');
        return dot <= 0 ? name : name[..dot];
    }

    public static string Parent(string path)
    {
        var slash = path.LastIndexOf('/');
        return slash < 0 ? "" : path[..slash];
    }

    public static string LastComponent(string path)
    {
        var slash = path.LastIndexOf('/');
        return slash < 0 ? path : path[(slash + 1)..];
    }

    public static string Join(string folder, string name) => folder.Length == 0 ? name : $"{folder}/{name}";
}

public enum SourceKind { Local, Server, Jellyfin, CD }

/// <summary>A folder tree the app plays from. The player doesn't know where the music comes from.</summary>
public interface IMusicSource
{
    Guid Id { get; }
    string Name { get; }
    SourceKind Kind { get; }
    /// <summary>Folders and tracks in <paramref name="path"/> ("" is the root), folders first, natural order.</summary>
    Task<IReadOnlyList<Entry>> List(string path);
    /// <summary>Where the track plays from: a file path, an http(s) URL, or cdda://D/3 for a disc (see <see cref="Locations"/>).</summary>
    Task<string> Url(Entry track);
    /// <summary>An image file the user put in the folder (cover.jpg…), or null. Never from tags.</summary>
    Task<string?> Artwork(string folderPath) => Task.FromResult<string?>(null);
    /// <summary>Name of the source's own folder when it is a real folder (the artist, if the user added one artist).</summary>
    string? RootFolderName => null;
    /// <summary>A track's URL failed to play: a server may have dropped its session.</summary>
    Task StreamFailed() => Task.CompletedTask;
}

public sealed class SourceException(string message) : Exception(message)
{
    public static SourceException MissingFolder(string name) => new(L.F("Pasta em falta: {0}", name));
    public static SourceException ServerUnavailable() => new(L.T("Servidor offline"));
    public static SourceException LoginFailed() => new(L.T("Utilizador ou palavra-passe errados"));
    public static SourceException NoMusicLibrary() => new(L.T("Sem biblioteca de música neste utilizador"));
    public static SourceException UnexpectedResponse() => new(L.T("Resposta inesperada. Confirmar o endereço do servidor"));
}

/// <summary>
/// Track locations are plain strings, not Uri: a file path stays exactly as it is (Uri would turn a
/// file named "a%20b" into "a b"), and a URL is a URL.
/// </summary>
public static class Locations
{
    public static bool IsFile(string location) => !location.Contains("://", StringComparison.Ordinal);
}

public static class Playable
{
    public static readonly HashSet<string> Extensions = ["flac", "mp3", "m4a", "aac", "alac", "wav", "aiff"];

    public static bool IsPlayable(string name) => Extensions.Contains(Paths.Extension(name).ToLowerInvariant());
}

public static class ArtworkFiles
{
    /// <summary>File names that count as the folder's artwork, in order of preference ("capa" is Portuguese).</summary>
    public static readonly string[] Names = ["cover", "folder", "front", "album", "capa"];
    public static readonly HashSet<string> Extensions = ["jpg", "jpeg", "png"];

    /// <summary>The artwork among a folder's file names, or null. Case-insensitive.</summary>
    public static string? Pick(IEnumerable<string> fileNames)
    {
        var candidates = fileNames.Where(n => Extensions.Contains(Paths.Extension(n).ToLowerInvariant())).ToList();
        foreach (var name in Names)
        {
            var match = candidates
                .Where(c => Paths.WithoutExtension(c).Equals(name, StringComparison.OrdinalIgnoreCase))
                .OrderBy(c => c, StringComparer.Ordinal)
                .FirstOrDefault();
            if (match != null) return match;
        }
        return null;
    }
}

/// <summary>
/// Natural order, as the Mac's localizedStandardCompare (and Explorer): runs of digits compare as numbers,
/// the rest by the culture's rules ignoring case. "Track 2" before "Track 10".
/// </summary>
public sealed class NaturalComparer : IComparer<string>
{
    public static readonly NaturalComparer Instance = new();
    private static readonly CompareInfo compare = CultureInfo.CurrentCulture.CompareInfo;

    public int Compare(string? a, string? b)
    {
        if (ReferenceEquals(a, b)) return 0;
        if (a == null) return -1;
        if (b == null) return 1;
        int i = 0, j = 0;
        while (i < a.Length && j < b.Length)
        {
            if (char.IsAsciiDigit(a[i]) && char.IsAsciiDigit(b[j]))
            {
                int si = i, sj = j;
                while (i < a.Length && char.IsAsciiDigit(a[i])) i++;
                while (j < b.Length && char.IsAsciiDigit(b[j])) j++;
                var da = a[si..i].TrimStart('0');
                var db = b[sj..j].TrimStart('0');
                if (da.Length != db.Length) return da.Length < db.Length ? -1 : 1;
                var order = string.CompareOrdinal(da, db);
                if (order != 0) return order < 0 ? -1 : 1;
            }
            else
            {
                int si = i, sj = j;
                while (i < a.Length && !char.IsAsciiDigit(a[i])) i++;
                while (j < b.Length && !char.IsAsciiDigit(b[j])) j++;
                var order = compare.Compare(a, si, i - si, b, sj, j - sj, CompareOptions.IgnoreCase);
                if (order != 0) return order < 0 ? -1 : 1;
            }
        }
        if (i < a.Length) return 1;
        if (j < b.Length) return -1;
        // Equal ignoring case and leading zeros: fall back to a stable, case-sensitive order.
        return string.CompareOrdinal(a, b) switch { < 0 => -1, > 0 => 1, _ => 0 };
    }
}

public static class EntryOrder
{
    /// <summary>Folders first, then tracks; within each group, natural name order.</summary>
    public static List<Entry> NaturallySorted(this IEnumerable<Entry> entries) =>
        entries.OrderBy(e => e.Kind == EntryKind.Folder ? 0 : 1).ThenBy(e => e.Name, NaturalComparer.Instance).ToList();
}
