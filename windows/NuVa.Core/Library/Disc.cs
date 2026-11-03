using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace NuVa.Core.Library;

/// <summary>
/// Table of contents of an audio CD (port of DiscTOC.swift). Only the audio tracks count. Starts are in
/// sectors (75 a second) from the end of the 2 s pregap.
/// </summary>
public sealed record DiscToc(int FirstTrack, int LastTrack, IReadOnlyDictionary<int, int> Starts, int Leadout)
{
    /// <summary>Sectors before the first track; MusicBrainz offsets include it.</summary>
    public const int Pregap = 150;
    /// <summary>Gap between the audio session and a data session on an enhanced CD.</summary>
    public const int DataSessionGap = 11_400;

    /// <summary>From the drive's TOC: each track's number, start (from the disc's start, pregap included) and whether it is data; the lead-out likewise.</summary>
    public static DiscToc? From(IEnumerable<(int Number, int Start, bool IsData)> entries, int leadout)
    {
        var tracks = entries.Where(t => t.Number is >= 1 and <= 99).OrderBy(t => t.Number).Select(t => (t.Number, Start: t.Start - Pregap, t.IsData)).ToList();
        var audio = tracks.Where(t => !t.IsData).ToList();
        if (audio.Count == 0) return null;
        var last = audio[^1];
        // Enhanced CD: a data track after the audio ends the audio early.
        var data = tracks.FirstOrDefault(t => t.IsData && t.Number > last.Number);
        var end = data.Number > 0 ? data.Start - DataSessionGap : leadout - Pregap;
        return new DiscToc(audio[0].Number, last.Number, audio.GroupBy(t => t.Number).ToDictionary(g => g.Key, g => g.First().Start), end);
    }

    /// <summary>A track's first and last-plus-one sector, or null if it isn't on the disc.</summary>
    public (int Start, int End)? Span(int track)
    {
        if (!Starts.TryGetValue(track, out var start)) return null;
        var next = Starts.Where(kv => kv.Key > track).Select(kv => kv.Value).DefaultIfEmpty(Leadout).Min();
        return (start, next);
    }

    public double? Duration(int track) => Span(track) is { } s ? (s.End - s.Start) / 75.0 : null;

    /// <summary>MusicBrainz disc ID: SHA-1 of the first and last track and 100 offsets, in URL-safe Base64.</summary>
    public string MusicBrainzId
    {
        get
        {
            var text = new StringBuilder($"{FirstTrack:X2}{LastTrack:X2}{Leadout + Pregap:X8}");
            for (var n = 1; n <= 99; n++) text.Append($"{(Starts.TryGetValue(n, out var s) ? s + Pregap : 0):X8}");
            return Convert.ToBase64String(SHA1.HashData(Encoding.ASCII.GetBytes(text.ToString()))).Replace('+', '.').Replace('/', '_').Replace('=', '-');
        }
    }

    /// <summary>The TOC as MusicBrainz takes it for a fuzzy lookup: first, last, leadout, then each offset.</summary>
    public string MusicBrainzToc =>
        string.Join(" ", new[] { FirstTrack, LastTrack, Leadout + Pregap }.Concat(Enumerable.Range(FirstTrack, LastTrack - FirstTrack + 1).Where(Starts.ContainsKey).Select(n => Starts[n] + Pregap)));
}

/// <summary>What MusicBrainz knows about a CD: the names a disc doesn't carry.</summary>
public sealed record DiscInfo(string Artist, string Album, List<string> Titles, string ReleaseId);

/// <summary>
/// Names and covers of audio CDs, by MusicBrainz disc ID (port of DiscLookup.swift). A CD has no folder
/// or file names to respect, so this is the second agreed exception to "no online lookups". Answers are
/// kept in %LOCALAPPDATA%\NuVa\Discs, so a known disc works offline.
/// </summary>
public sealed class DiscLookup(string root, CoverArtArchive online)
{
    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(8);

    private string File(DiscToc toc, string ext) => Path.Combine(root, $"disc-{toc.MusicBrainzId}.{ext}");

    public async Task<DiscInfo?> Info(DiscToc toc)
    {
        var file = File(toc, "json");
        try
        {
            if (System.IO.File.Exists(file)) return JsonSerializer.Deserialize<DiscInfo>(await System.IO.File.ReadAllTextAsync(file));
        }
        catch (Exception)
        {
        }
        var lookup = Lookup(toc);
        var first = await Task.WhenAny(lookup, Task.Delay(Timeout));
        var found = first == lookup ? await lookup : null;
        if (found != null)
        {
            try
            {
                Directory.CreateDirectory(root);
                await System.IO.File.WriteAllTextAsync(file, JsonSerializer.Serialize(found));
            }
            catch (Exception)
            {
            }
        }
        return found;
    }

    private async Task<DiscInfo?> Lookup(DiscToc toc)
    {
        try
        {
            var url = $"https://musicbrainz.org/ws/2/discid/{toc.MusicBrainzId}?toc={Uri.EscapeDataString(toc.MusicBrainzToc)}&cdstubs=no&inc={Uri.EscapeDataString("artist-credits recordings")}&fmt=json";
            var (data, status, _) = await online.Get(url, "application/json");
            if (status != 200) return null;
            return Pick(JsonSerializer.Deserialize<DiscResponse>(data)?.Releases ?? [], toc);
        }
        catch (Exception e)
        {
            Log.Write($"disc: lookup failed ({e.Message})");
            return null;
        }
    }

    /// <summary>The release's front cover, downloaded once and kept next to the names.</summary>
    public async Task<string?> Cover(DiscToc toc, DiscInfo info)
    {
        var file = File(toc, "jpg");
        if (System.IO.File.Exists(file)) return file;
        try
        {
            if (await online.Front(info.ReleaseId, "release") is not { } data) return null;
            Directory.CreateDirectory(root);
            await System.IO.File.WriteAllBytesAsync(file, data);
            return file;
        }
        catch (Exception)
        {
            return null;
        }
    }

    public sealed class DiscResponse
    {
        [JsonPropertyName("releases")] public List<Release>? Releases { get; set; }
    }

    public sealed class Release
    {
        public sealed class Credit
        {
            [JsonPropertyName("name")] public string Name { get; set; } = "";
            [JsonPropertyName("joinphrase")] public string? JoinPhrase { get; set; }
        }
        public sealed class Medium
        {
            public sealed class Disc { [JsonPropertyName("id")] public string Id { get; set; } = ""; }
            public sealed class Track { [JsonPropertyName("title")] public string Title { get; set; } = ""; }
            [JsonPropertyName("discs")] public List<Disc>? Discs { get; set; }
            [JsonPropertyName("tracks")] public List<Track>? Tracks { get; set; }
        }
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("title")] public string Title { get; set; } = "";
        [JsonPropertyName("artist-credit")] public List<Credit>? ArtistCredit { get; set; }
        [JsonPropertyName("media")] public List<Medium>? Media { get; set; }
        public string Artist => string.Concat((ArtistCredit ?? []).Select(c => c.Name + (c.JoinPhrase ?? "")));
    }

    /// <summary>The medium with this exact disc ID wins; otherwise the first with the same number of tracks.</summary>
    public static DiscInfo? Pick(List<Release> releases, DiscToc toc)
    {
        var count = toc.Starts.Count;
        var candidates = releases.SelectMany(r => (r.Media ?? []).Select(m => (r, m))).ToList();
        var exact = candidates.FirstOrDefault(c => c.m.Discs?.Any(d => d.Id == toc.MusicBrainzId) == true);
        var (release, medium) = exact.r != null ? exact : candidates.FirstOrDefault(c => c.m.Tracks?.Count == count);
        if (release == null || medium?.Tracks is not { } tracks || tracks.Count != count) return null;
        return new DiscInfo(release.Artist, release.Title, tracks.Select(t => t.Title).ToList(), release.Id);
    }
}

/// <summary>
/// An audio CD in the drive (port of DiscSource.swift): one folder named "Artist – Album" when MusicBrainz
/// knows it, else "Audio CD", with the tracks inside. Lives only while the disc is in; never saved.
/// Tracks play from cdda://D/3 (drive letter, track number).
/// </summary>
public sealed class DiscSource : IMusicSource
{
    public Guid Id { get; }
    public SourceKind Kind => SourceKind.CD;
    public char Drive { get; }
    public DiscToc Toc { get; }
    public DiscInfo? Info { get; }
    /// <summary>The disc's one folder, also the source's name.</summary>
    public string Folder { get; }
    private readonly DiscLookup lookup;

    public string Name => Folder;

    public DiscSource(char drive, DiscToc toc, DiscInfo? info, DiscLookup lookup)
    {
        Drive = char.ToUpperInvariant(drive);
        Toc = toc;
        Info = info;
        this.lookup = lookup;
        // The same disc gets the same id every time, so its artwork choice and durations stick.
        Id = new Guid(SHA256.HashData(Encoding.UTF8.GetBytes("disc/" + toc.MusicBrainzId)).AsSpan(0, 16));
        var name = info != null ? $"{info.Artist} – {info.Album}" : L.T("CD áudio");
        // A "/" would split the path (AC/DC).
        Folder = name.Replace('/', '∕');
    }

    public Task<IReadOnlyList<Entry>> List(string path)
    {
        if (path.Length == 0) return Task.FromResult<IReadOnlyList<Entry>>([new Entry(Id, Folder, Folder, EntryKind.Folder)]);
        if (path != Folder) throw SourceException.MissingFolder(Folder);
        var entries = Enumerable.Range(Toc.FirstTrack, Toc.LastTrack - Toc.FirstTrack + 1).Where(Toc.Starts.ContainsKey).Select(n =>
        {
            var index = n - Toc.FirstTrack;
            var title = Info != null && index < Info.Titles.Count ? Info.Titles[index] : L.F("Faixa {0}", n);
            // Numbered like a file, so the title drops the number and the list keeps disc order.
            var name = $"{n:00} {title.Replace('/', '∕')}.cd";
            return new Entry(Id, $"{Folder}/{n:00}", name, EntryKind.Track, Toc.Duration(n));
        }).ToList();
        return Task.FromResult<IReadOnlyList<Entry>>(entries);
    }

    public Task<string> Url(Entry track)
    {
        var number = int.Parse(Paths.LastComponent(track.Path));
        return Task.FromResult($"cdda://{Drive}/{number}");
    }

    /// <summary>The release's cover from the Cover Art Archive (only asked for while artwork is on).</summary>
    public async Task<string?> Artwork(string folderPath) =>
        folderPath == Folder && Info != null ? await lookup.Cover(Toc, Info) : null;
}
