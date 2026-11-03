using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;

namespace NuVa.Core.Library;

/// <summary>Where an album's artwork came from.</summary>
public enum ArtworkOrigin
{
    /// <summary>An image file in the folder. Always wins; the user's own file is never "wrong".</summary>
    Folder,
    /// <summary>Picked by the user for this folder (an image, or found by searching again).</summary>
    User,
    /// <summary>Found online from the folder names (MusicBrainz + Cover Art Archive).</summary>
    Online,
}

public sealed record ResolvedArtwork(string File, ArtworkOrigin Origin);

/// <summary>
/// Artwork files kept by NuVa in %LOCALAPPDATA%\NuVa\Artwork, never in the user's folders (port of
/// ArtworkCache). online\ is shared by artist and album; user\ is per folder; a .none file means "no artwork".
/// </summary>
public sealed class ArtworkCache(string root)
{
    /// <summary>How long a failed online lookup is remembered before trying again.</summary>
    public static readonly TimeSpan MissLifetime = TimeSpan.FromDays(14);

    public enum Kind { Image, None, Unknown }

    public (Kind, string?) Online(AlbumQuery query) => Lookup("online", query.Key, missExpires: true);
    public (Kind, string?) User(string folder) => Lookup("user", folder, missExpires: false);
    public string? SaveOnline(byte[]? data, AlbumQuery query) => Save(data, "online", query.Key);
    /// <summary>Null data records "no artwork" for this folder.</summary>
    public string? SaveUser(byte[]? data, string folder) => Save(data, "user", folder);

    private (Kind, string?) Lookup(string dir, string key, bool missExpires)
    {
        var path = FileFor(dir, key);
        if (File.Exists(path + ".jpg")) return (Kind.Image, path + ".jpg");
        var miss = path + ".none";
        if (!File.Exists(miss)) return (Kind.Unknown, null);
        return missExpires && DateTime.UtcNow - File.GetLastWriteTimeUtc(miss) > MissLifetime ? (Kind.Unknown, null) : (Kind.None, null);
    }

    private string? Save(byte[]? data, string dir, string key)
    {
        var path = FileFor(dir, key);
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.Delete(path + ".jpg");
            File.Delete(path + ".none");
            if (data != null)
            {
                File.WriteAllBytes(path + ".jpg", data);
                return path + ".jpg";
            }
            File.WriteAllBytes(path + ".none", []);
        }
        catch (Exception e)
        {
            Log.Write($"artwork: not saved ({e.Message})");
        }
        return null;
    }

    private string FileFor(string dir, string key)
    {
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(key))).ToLowerInvariant();
        return Path.Combine(root, dir, hash[..32]);
    }
}

/// <summary>
/// Album covers from MusicBrainz (finds the album) and the Cover Art Archive (serves the image). Open
/// data, no key. Only confident matches count: a wrong cover is worse than none.
/// </summary>
public sealed class CoverArtArchive
{
    public sealed class ReleaseGroup
    {
        public sealed class Credit { [JsonPropertyName("name")] public string Name { get; set; } = ""; }
        [JsonPropertyName("id")] public string Id { get; set; } = "";
        [JsonPropertyName("score")] public int Score { get; set; }
        [JsonPropertyName("title")] public string Title { get; set; } = "";
        [JsonPropertyName("artist-credit")] public List<Credit>? ArtistCredit { get; set; }
        public string Artist => string.Join(" ", (ArtistCredit ?? []).Select(c => c.Name));
    }

    private sealed class SearchResponse
    {
        [JsonPropertyName("release-groups")] public List<ReleaseGroup> ReleaseGroups { get; set; } = [];
    }

    /// <summary>Rate limited, server down…: an error, so a miss isn't remembered.</summary>
    public sealed class StatusException(int code) : Exception($"HTTP {code}")
    {
        public int Code { get; } = code;
    }

    /// <summary>MusicBrainz asks for an identifying User-Agent and at most one request per second.</summary>
    public static string UserAgent { get; set; } = "NuVa/1 ( https://github.com/martinsmdnuno/nuva )";

    public static CoverArtArchive Shared { get; } = new(new HttpClient { Timeout = TimeSpan.FromSeconds(15) });

    private readonly HttpClient http;
    private readonly SemaphoreSlim gate = new(1, 1);
    private DateTime lastRequest = DateTime.MinValue;

    public CoverArtArchive(HttpClient http) => this.http = http;

    /// <summary>JPEG of the front cover (500 px), or null when the album isn't found with confidence or has no cover.</summary>
    public async Task<byte[]?> Cover(AlbumQuery query)
    {
        foreach (var group in await Search(query))
        {
            if (!Matches(group, query)) continue;
            if (await Front(group.Id) is { } data) return data;
        }
        return null;
    }

    public async Task<List<ReleaseGroup>> Search(AlbumQuery query)
    {
        var lucene = $"releasegroup:\"{Escape(query.Album)}\" AND artist:\"{Escape(query.Artist)}\"";
        var url = $"https://musicbrainz.org/ws/2/release-group/?query={Uri.EscapeDataString(lucene)}&fmt=json&limit=5";
        var (data, status, _) = await Get(url, "application/json");
        if (status != 200) throw new StatusException(status);
        return JsonSerializer.Deserialize<SearchResponse>(data)?.ReleaseGroups ?? [];
    }

    /// <summary>The front image of a release group (or of a release, for a CD found by its disc ID).</summary>
    public async Task<byte[]?> Front(string id, string kind = "release-group")
    {
        var (data, status, type) = await Get($"https://coverartarchive.org/{kind}/{id}/front-500");
        if (status == 404) return null;
        if (status != 200) throw new StatusException(status);
        return type?.StartsWith("image/") == true ? data : null;
    }

    /// <summary>A confident match: high MusicBrainz score, same artist and album title once normalised.</summary>
    public static bool Matches(ReleaseGroup group, AlbumQuery query)
    {
        if (group.Score < 90) return false;
        var artist = AlbumGuess.Normalize(query.Artist);
        var album = AlbumGuess.Normalize(query.Album);
        var foundArtist = AlbumGuess.Normalize(group.Artist);
        var foundAlbum = AlbumGuess.Normalize(group.Title);
        var sameArtist = foundArtist == artist || foundArtist.StartsWith(artist + " ") || artist.StartsWith(foundArtist + " ");
        var sameAlbum = foundAlbum == album || AlbumGuess.Normalize(AlbumGuess.Clean(group.Title)) == album;
        return sameArtist && sameAlbum;
    }

    /// <summary>Lucene special characters inside a quoted phrase.</summary>
    public static string Escape(string s) => s.Replace("\\", "\\\\").Replace("\"", "\\\"");

    public async Task<(byte[] Data, int Status, string? Type)> Get(string url, string? accept = null)
    {
        await gate.WaitAsync();
        try
        {
            // At most one request per second (MusicBrainz's limit; applied to both hosts for simplicity).
            var wait = TimeSpan.FromSeconds(1.1) - (DateTime.UtcNow - lastRequest);
            if (wait > TimeSpan.Zero) await Task.Delay(wait);
            var result = await Send(url, accept);
            if (result.Status == 503)
            {
                // MusicBrainz is throttling: one more try after a pause.
                await Task.Delay(TimeSpan.FromSeconds(2));
                result = await Send(url, accept);
            }
            return result;
        }
        finally
        {
            lastRequest = DateTime.UtcNow;
            gate.Release();
        }
    }

    private async Task<(byte[] Data, int Status, string? Type)> Send(string url, string? accept)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.TryAddWithoutValidation("User-Agent", UserAgent);
        if (accept != null) request.Headers.TryAddWithoutValidation("Accept", accept);
        using var response = await http.SendAsync(request);
        return (await response.Content.ReadAsByteArrayAsync(), (int)response.StatusCode, response.Content.Headers.ContentType?.MediaType);
    }
}

/// <summary>Finds a folder's artwork: the folder's image, then the user's choice, then online by the folder names.</summary>
public sealed class ArtworkResolver(SourceStore sources, ArtworkCache cache, CoverArtArchive online)
{
    public ArtworkCache Cache => cache;
    public CoverArtArchive Online => online;

    /// <summary>Key of the folder that holds the entry (disc folders count as their album).</summary>
    public static string FolderKey(Entry entry)
    {
        var folder = entry.ParentPath;
        while (folder.Length > 0 && AlbumGuess.IsDiscFolder(Paths.LastComponent(folder))) folder = Paths.Parent(folder);
        return $"{entry.SourceId.ToString().ToUpperInvariant()}/{folder}";
    }

    /// <summary>Artist and album guessed from the folders holding the entry.</summary>
    public AlbumQuery? Query(Entry entry) => AlbumGuess.From(entry.ParentPath, sources.Source(entry.SourceId)?.RootFolderName);

    public async Task<ResolvedArtwork?> Resolve(Entry entry)
    {
        if (await sources.Artwork(entry) is { } file && (Locations.IsFile(file) || file.StartsWith("http"))) return new ResolvedArtwork(file, ArtworkOrigin.Folder);
        var (kind, user) = cache.User(FolderKey(entry));
        if (kind == ArtworkCache.Kind.Image) return new ResolvedArtwork(user!, ArtworkOrigin.User);
        if (kind == ArtworkCache.Kind.None) return null;
        if (Query(entry) is not { } query) return null;
        // The folder's names first; then, if they find nothing, without a title before the artist.
        foreach (var candidate in new[] { query, query.WithoutTitle }.OfType<AlbumQuery>())
        {
            var (found, path) = cache.Online(candidate);
            if (found == ArtworkCache.Kind.Image) return new ResolvedArtwork(path!, ArtworkOrigin.Online);
            if (found == ArtworkCache.Kind.None) continue;
            try
            {
                var data = await online.Cover(candidate);
                if (cache.SaveOnline(data, candidate) is { } saved) return new ResolvedArtwork(saved, ArtworkOrigin.Online);
            }
            catch (Exception e)
            {
                // Offline or a server error: try again next launch, don't record a miss.
                Log.Write($"artwork: lookup failed ({e.Message})");
                return null;
            }
        }
        return null;
    }
}
