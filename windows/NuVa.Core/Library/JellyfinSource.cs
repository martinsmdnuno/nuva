using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;

namespace NuVa.Core.Library;

/// <summary>
/// A source on a Jellyfin server (port of JellyfinSource.swift). Browses the server's disk folders (each
/// item's Path), not Jellyfin's artists and albums, and plays the original file, without conversion.
/// </summary>
public sealed class JellyfinSource : IMusicSource
{
    public sealed record Session(string Token, string UserId);

    public sealed class Item
    {
        [JsonPropertyName("Id")] public string Id { get; set; } = "";
        [JsonPropertyName("Name")] public string? Name { get; set; }
        [JsonPropertyName("IsFolder")] public bool? IsFolder { get; set; }
        [JsonPropertyName("Path")] public string? Path { get; set; }
        [JsonPropertyName("Container")] public string? Container { get; set; }
        [JsonPropertyName("RunTimeTicks")] public long? RunTimeTicks { get; set; }
        [JsonPropertyName("CollectionType")] public string? CollectionType { get; set; }

        /// <summary>Path with forward slashes (Windows servers use '\').</summary>
        public string? UnixPath => Path?.Replace('\\', '/');
    }

    private sealed class Items
    {
        [JsonPropertyName("Items")] public List<Item> List { get; set; } = [];
    }

    /// <summary>Known folder: item id and path on the server's disk (null at the library root).</summary>
    private sealed record Node(string Id, string? Abs);

    public sealed class HttpStatusException(int status) : Exception(L.F("O servidor respondeu {0}", status))
    {
        public int Status { get; } = status;
    }

    public Guid Id { get; }
    public string Name { get; }
    public SourceKind Kind => SourceKind.Jellyfin;
    public Uri Server { get; }
    public string Username { get; }
    private readonly string deviceId;
    private readonly Func<string?> password;
    private readonly HttpClient http;
    private readonly SemaphoreSlim gate = new(1, 1);
    private readonly SemaphoreSlim signIn = new(1, 1);

    private Session? session;
    private bool legacyRoutes;
    private bool rootLoaded;
    /// <summary>With more than one music library, the root shows the libraries.</summary>
    private List<Item> libraries = [];
    private readonly Dictionary<string, Node> nodes = new();
    private readonly Dictionary<string, string> tracks = new();
    private readonly HashSet<string> listed = [];
    private readonly Dictionary<string, (List<Item> Items, DateTime At)> cache = new();
    private static readonly TimeSpan cacheTtl = TimeSpan.FromMinutes(5);
    private static readonly HttpClient shared = new() { Timeout = TimeSpan.FromSeconds(30) };

    public JellyfinSource(Guid id, string name, Uri server, string username, string deviceId, Func<string?> password, HttpClient? http = null)
    {
        Id = id;
        Name = name;
        Server = server;
        Username = username;
        this.deviceId = deviceId;
        this.password = password;
        this.http = http ?? shared;
    }

    /// <summary>"jellyfin.exemplo.pt" without a scheme means https; the trailing slash goes. Null when it isn't an address.</summary>
    public static Uri? ServerUrl(string text)
    {
        text = text.Trim();
        if (text.Length == 0) return null;
        if (!text.Contains("://")) text = "https://" + text;
        text = text.TrimEnd('/');
        return Uri.TryCreate(text, UriKind.Absolute, out var url) && url.Host.Length > 0 && url.Scheme is "http" or "https" ? url : null;
    }

    private Uri Endpoint(string path, IEnumerable<(string Key, string Value)>? query = null)
    {
        var builder = new StringBuilder(Server.AbsoluteUri.TrimEnd('/')).Append('/').Append(path);
        var first = true;
        foreach (var (key, value) in query ?? [])
        {
            builder.Append(first ? '?' : '&').Append(Uri.EscapeDataString(key)).Append('=').Append(Uri.EscapeDataString(value));
            first = false;
        }
        return new Uri(builder.ToString());
    }

    // MARK: IMusicSource

    public async Task<IReadOnlyList<Entry>> List(string path)
    {
        await gate.WaitAsync();
        try
        {
            return await ListLocked(path);
        }
        finally
        {
            gate.Release();
        }
    }

    private async Task<IReadOnlyList<Entry>> ListLocked(string path)
    {
        if (!rootLoaded) await LoadRoot();
        if (path.Length == 0 && libraries.Count > 0)
        {
            listed.Add("");
            return libraries.Select(l => new Entry(Id, l.Name ?? l.Id, l.Name ?? l.Id, EntryKind.Folder)).NaturallySorted();
        }
        var (anchorRel, anchor) = await Anchor(path);
        var children = await ItemsIn(anchor.Id);
        var placed = children.Select(item => (item, Register(item, anchorRel, anchor.Abs))).ToList();
        listed.Add(path);

        // Direct children of path; deeper items (an album with CD1/CD2) yield folders from the path.
        var result = new List<Entry>();
        var seen = new HashSet<string>();
        var prefix = path.Length == 0 ? "" : path + "/";
        foreach (var (item, rel) in placed)
        {
            if (!rel.StartsWith(prefix, StringComparison.Ordinal)) continue;
            var rest = rel[prefix.Length..];
            var slash = rest.IndexOf('/');
            if (slash >= 0)
            {
                var sub = prefix + rest[..slash];
                if (seen.Add(sub)) result.Add(new Entry(Id, sub, rest[..slash], EntryKind.Folder));
            }
            else if (item.IsFolder == true)
            {
                if (seen.Add(rel)) result.Add(new Entry(Id, rel, rest, EntryKind.Folder));
            }
            else if (Playable.IsPlayable(rel))
            {
                double? duration = item.RunTimeTicks is { } ticks ? ticks / 10_000_000.0 : null;
                result.Add(new Entry(Id, rel, rest, EntryKind.Track, duration));
            }
        }
        return result.NaturallySorted();
    }

    public async Task<string> Url(Entry track)
    {
        string? itemId;
        await gate.WaitAsync();
        try
        {
            if (!tracks.ContainsKey(track.Path)) await ListLocked(track.ParentPath);
            tracks.TryGetValue(track.Path, out itemId);
        }
        finally
        {
            gate.Release();
        }
        if (itemId == null) throw SourceException.MissingFolder(track.FolderName);
        var token = (await CurrentSession()).Token;
        var ext = Paths.Extension(track.Name).ToLowerInvariant();
        // static=true: the original file, no transcoding.
        return Endpoint($"Audio/{itemId}/stream.{ext}", [("static", "true"), ("api_key", token)]).AbsoluteUri;
    }

    /// <summary>The stream URL carries the token, so a revoked token only shows up as a failed stream.</summary>
    public Task StreamFailed()
    {
        session = null;
        return Task.CompletedTask;
    }

    // MARK: Folder tree

    /// <summary>Relative path of an item: the part of Path below the anchor folder or, without one, the last name.</summary>
    public static string RelativePath(Item item, string anchorRel, string? anchorAbs)
    {
        string leaf;
        if (anchorAbs != null && item.UnixPath is { } path && path.StartsWith(anchorAbs + "/", StringComparison.Ordinal))
            leaf = path[(anchorAbs.Length + 1)..];
        else if (item.UnixPath is { } p)
            leaf = Paths.LastComponent(p);
        else
        {
            var name = item.Name ?? item.Id;
            leaf = item.IsFolder == true || item.Container == null ? name : $"{name}.{item.Container}";
        }
        return anchorRel.Length == 0 ? leaf : $"{anchorRel}/{leaf}";
    }

    private string Register(Item item, string anchorRel, string? anchorAbs)
    {
        var rel = RelativePath(item, anchorRel, anchorAbs);
        if (item.IsFolder == true) nodes[rel] = new Node(item.Id, item.UnixPath);
        else tracks[rel] = item.Id;
        return rel;
    }

    /// <summary>The closest known folder to path. After reopening the app the ids aren't in memory: lists each level from the root until they're found.</summary>
    private async Task<(string, Node)> Anchor(string path)
    {
        var prefix = "";
        foreach (var part in path.Split('/', StringSplitOptions.RemoveEmptyEntries))
        {
            var next = prefix.Length == 0 ? part : $"{prefix}/{part}";
            if (!nodes.ContainsKey(next) && !listed.Contains(prefix)) await ListLocked(prefix);
            prefix = next;
        }
        var p = path;
        while (true)
        {
            if (nodes.TryGetValue(p, out var node)) return (p, node);
            if (p.Length == 0) throw SourceException.MissingFolder(Paths.LastComponent(path));
            p = Paths.Parent(p);
        }
    }

    private async Task LoadRoot()
    {
        var views = (await UserViews()).Where(v => v.CollectionType == "music").ToList();
        if (views.Count == 0) throw SourceException.NoMusicLibrary();
        if (views.Count == 1)
        {
            nodes[""] = new Node(views[0].Id, null);
        }
        else
        {
            libraries = views;
            foreach (var view in views) nodes[view.Name ?? view.Id] = new Node(view.Id, null);
        }
        rootLoaded = true;
    }

    // MARK: API

    private async Task<List<Item>> UserViews()
    {
        var userId = (await CurrentSession()).UserId;
        if (!legacyRoutes)
        {
            try
            {
                return await Get("UserViews", [("userId", userId)]);
            }
            catch (HttpStatusException e) when (e.Status == 404)
            {
                legacyRoutes = true;
            }
        }
        return await Get($"Users/{userId}/Views", []);
    }

    private async Task<List<Item>> ItemsIn(string parentId)
    {
        if (cache.TryGetValue(parentId, out var hit) && DateTime.UtcNow - hit.At < cacheTtl) return hit.Items;
        var userId = (await CurrentSession()).UserId;
        (string, string)[] query = [("parentId", parentId), ("fields", "Path"), ("enableImages", "false"), ("enableUserData", "false")];
        List<Item> result;
        if (!legacyRoutes)
        {
            try
            {
                result = await Get("Items", [.. query, ("userId", userId)]);
            }
            catch (HttpStatusException e) when (e.Status == 404)
            {
                legacyRoutes = true;
                result = await Get($"Users/{userId}/Items", query);
            }
        }
        else
        {
            result = await Get($"Users/{userId}/Items", query);
        }
        cache[parentId] = (result, DateTime.UtcNow);
        return result;
    }

    private async Task<List<Item>> Get(string path, (string, string)[] query, bool retry = true)
    {
        var current = await CurrentSession();
        using var request = new HttpRequestMessage(HttpMethod.Get, Endpoint(path, query));
        request.Headers.TryAddWithoutValidation("Authorization", Authorization(deviceId, current.Token));
        var (data, status) = await Send(request, http);
        if (status == 401 && retry)
        {
            // Token revoked or expired: sign in again with the saved password.
            session = null;
            return await Get(path, query, retry: false);
        }
        if (status is < 200 or >= 300) throw new HttpStatusException(status);
        try
        {
            return JsonSerializer.Deserialize<Items>(data)?.List ?? throw SourceException.UnexpectedResponse();
        }
        catch (JsonException)
        {
            throw SourceException.UnexpectedResponse();
        }
    }

    private async Task<Session> CurrentSession()
    {
        if (session is { } ready) return ready;
        await signIn.WaitAsync();
        try
        {
            if (session is { } signedIn) return signedIn;
            var pw = password() ?? throw SourceException.LoginFailed();
            session = await Login(Server, Username, pw, deviceId, http);
            return session;
        }
        finally
        {
            signIn.Release();
        }
    }

    public static async Task<Session> Login(Uri server, string username, string password, string deviceId, HttpClient? http = null)
    {
        http ??= shared;
        var url = new Uri(server.AbsoluteUri.TrimEnd('/') + "/Users/AuthenticateByName");
        using var request = new HttpRequestMessage(HttpMethod.Post, url)
        {
            Content = new StringContent(JsonSerializer.Serialize(new Dictionary<string, string> { ["Username"] = username, ["Pw"] = password }), Encoding.UTF8, "application/json"),
        };
        request.Headers.TryAddWithoutValidation("Authorization", Authorization(deviceId, null));
        var (data, status) = await Send(request, http);
        if (status is 401 or 403) throw SourceException.LoginFailed();
        if (status is < 200 or >= 300) throw new HttpStatusException(status);
        try
        {
            using var doc = JsonDocument.Parse(data);
            var token = doc.RootElement.GetProperty("AccessToken").GetString();
            var user = doc.RootElement.GetProperty("User").GetProperty("Id").GetString();
            if (token == null || user == null) throw SourceException.UnexpectedResponse();
            return new Session(token, user);
        }
        catch (Exception e) when (e is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            throw SourceException.UnexpectedResponse();
        }
    }

    /// <summary>The app's version, for the Authorization header (set at launch).</summary>
    public static string ClientVersion { get; set; } = "0.1";

    private static string Authorization(string deviceId, string? token)
    {
        var value = $"MediaBrowser Client=\"NuVa\", Device=\"Windows\", DeviceId=\"{deviceId}\", Version=\"{ClientVersion}\"";
        if (token != null) value += $", Token=\"{token}\"";
        return value;
    }

    private static async Task<(byte[], int)> Send(HttpRequestMessage request, HttpClient http)
    {
        try
        {
            using var response = await http.SendAsync(request);
            return (await response.Content.ReadAsByteArrayAsync(), (int)response.StatusCode);
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            throw SourceException.ServerUnavailable();
        }
    }
}
