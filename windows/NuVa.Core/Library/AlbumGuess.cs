using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace NuVa.Core.Library;

/// <summary>Artist and album to look up online, read from folder names (never from tags).</summary>
public sealed record AlbumQuery(string Artist, string Album)
{
    /// <summary>Key shared by every folder with the same artist and album.</summary>
    public string Key => $"{AlbumGuess.Normalize(Artist)}|{AlbumGuess.Normalize(Album)}";

    private static readonly Regex title = new(@"^(?i:ms|mrs|mr|miss|dr|sir|dame)\.?\s+(.+)$");

    /// <summary>The same query without a title before the artist's name ("Ms. Lauryn Hill" → "Lauryn Hill"), or null.</summary>
    public AlbumQuery? WithoutTitle
    {
        get
        {
            var match = title.Match(Artist);
            return match.Success ? new AlbumQuery(match.Groups[1].Value, Album) : null;
        }
    }
}

/// <summary>A port of AlbumGuess.swift: the artist and album that folder names imply.</summary>
public static class AlbumGuess
{
    private static readonly Regex disc = new(@"^(cd|disc|disk|disco)[\s._-]*\d+\b", RegexOptions.IgnoreCase);
    private static readonly Regex brackets = new(@"\s*[\(\[\{][^\)\]\}]*[\)\]\}]");
    private static readonly Regex leadingYear = new(@"^\s*(19|20)\d{2}\s*[-–.]\s*");
    private static readonly Regex trailing = new(@"(\s*[-–]?\s*((19|20)\d{2}|flac|mp3|alac|wav|hi-?res|24[\s-]?bit|\d{2}[-/]\d{2,3}))+\s*$", RegexOptions.IgnoreCase);
    private static readonly HashSet<string> generic = ["music", "música", "musica", "flac", "mp3", "albums", "álbuns", "albuns", "library", "biblioteca"];

    /// <summary>"Artist/Album (1977)/CD 01" → Fleetwood Mac, Rumours. <paramref name="root"/> is the source folder's own name.</summary>
    public static AlbumQuery? From(string path, string? root = null)
    {
        var parts = path.Split('/', StringSplitOptions.RemoveEmptyEntries).ToList();
        if (!string.IsNullOrEmpty(root)) parts.Insert(0, root);
        // Disc folders belong to the album above them.
        while (parts.Count > 0 && IsDiscFolder(parts[^1])) parts.RemoveAt(parts.Count - 1);
        if (parts.Count == 0) return null;
        var folder = parts[^1];

        // "Artist - Album" in a single folder name.
        if (parts.Count == 1 || IsGeneric(parts[^2]))
        {
            var pieces = folder.Split(" - ");
            if (pieces.Length >= 2) return Valid(Clean(pieces[0]), Clean(string.Join(" - ", pieces.Skip(1))));
            return null;
        }
        var album = Clean(folder);
        var artist = Clean(parts[^2]);
        // "Artist - Album" inside the artist folder: drop the repeated artist.
        var prefix = artist + " - ";
        if (album.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) album = album[prefix.Length..];
        return Valid(artist, album);
    }

    private static AlbumQuery? Valid(string artist, string album) =>
        artist.Length == 0 || album.Length == 0 ? null : new AlbumQuery(artist, album);

    public static bool IsDiscFolder(string name) => disc.IsMatch(name);

    /// <summary>Library-level folders that are not an artist.</summary>
    private static bool IsGeneric(string name) => generic.Contains(name.ToLowerInvariant());

    /// <summary>Removes years, formats and editions: "1977 - Rumours (Remastered) [FLAC 24-96]" → "Rumours".</summary>
    public static string Clean(string name)
    {
        var s = name.Replace('_', ' ');
        s = brackets.Replace(s, "");
        s = leadingYear.Replace(s, "");
        s = trailing.Replace(s, "");
        return s.Trim(' ', '\t', '-', '–', '.');
    }

    /// <summary>For comparing names: lowercase, no accents or punctuation, "&amp;" as "and", no leading "the".</summary>
    public static string Normalize(string s)
    {
        var folded = new StringBuilder();
        foreach (var c in s.ToLowerInvariant().Normalize(NormalizationForm.FormD))
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) folded.Append(c);
        var t = folded.ToString().Normalize(NormalizationForm.FormC).Replace("&", " and ");
        t = Regex.Replace(t, "[^a-z0-9 ]", "");
        t = Regex.Replace(t, @"\s+", " ").Trim();
        if (t.StartsWith("the ")) t = t[4..];
        return t;
    }
}
