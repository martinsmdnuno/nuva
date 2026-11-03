using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace NuVa.Core.Library;

/// <summary>Where a Jellyfin password lives: Windows Credential Manager in the app, memory in tests.</summary>
public interface ICredentialStore
{
    string? Password(string account);
    void SetPassword(string password, string account);
    void DeletePassword(string account);
}

/// <summary>The app's sources, remembered across launches in the settings (key "sources").</summary>
public sealed class SourceStore
{
    public sealed record Record(Guid Id, string Name, SourceKind Kind, string? Path = null, string? Server = null, string? Username = null);

    private readonly Settings settings;
    private readonly ICredentialStore credentials;
    private List<Record> records = [];
    // Replaced, never changed in place: the decoder thread reads it while the UI may add a source.
    private volatile IMusicSource[] sources = [];

    /// <summary>Saved sources that failed to open (a folder deleted, a share offline), by id, with the message.</summary>
    public Dictionary<Guid, string> Failed { get; } = new();

    public IReadOnlyList<IMusicSource> Sources => sources;

    /// <summary>The sources changed (added, removed, a disc in or out).</summary>
    public event Action? Changed;

    /// <summary>Makes a Jellyfin source from its record (set by the app once Jellyfin is available).</summary>
    public Func<Record, ICredentialStore, string, IMusicSource?>? MakeJellyfin { get; set; }

    public SourceStore(Settings settings, ICredentialStore credentials)
    {
        this.settings = settings;
        this.credentials = credentials;
    }

    /// <summary>Opens the saved sources. Call once, after setting <see cref="MakeJellyfin"/>.</summary>
    public void Load()
    {
        records = settings.Get<List<Record>>("sources", []);
        foreach (var record in records)
        {
            switch (record.Kind)
            {
                case SourceKind.Local when record.Path != null:
                    var local = new LocalSource(record.Id, record.Name, record.Path);
                    if (local.IsReachable) sources = [.. sources, local];
                    else Failed[record.Id] = SourceException.MissingFolder(record.Name).Message;
                    break;
                case SourceKind.Jellyfin:
                    if (MakeJellyfin?.Invoke(record, credentials, DeviceId) is { } jellyfin) sources = [.. sources, jellyfin];
                    break;
            }
        }
    }

    /// <summary>The saved records (for the list of sources that failed).</summary>
    public IReadOnlyList<Record> Records => records;

    public IMusicSource? Source(Guid id) => sources.FirstOrDefault(s => s.Id == id);

    /// <summary>Opens again the saved Local sources that failed. Returns whether <paramref name="id"/>, if given, opened.</summary>
    public bool RetryFailed(Guid? id = null)
    {
        var changed = false;
        foreach (var record in records.Where(r => Failed.ContainsKey(r.Id) && (id == null || r.Id == id)).ToList())
        {
            if (record.Kind != SourceKind.Local || record.Path == null) continue;
            var source = new LocalSource(record.Id, record.Name, record.Path);
            if (!source.IsReachable) continue;
            Failed.Remove(record.Id);
            sources = [.. sources, source];
            changed = true;
        }
        if (changed) Changed?.Invoke();
        return id is { } one ? !Failed.ContainsKey(one) && Source(one) != null : changed;
    }

    /// <summary>Adds a folder (or returns the source already there for it).</summary>
    public IMusicSource AddLocal(string path)
    {
        path = System.IO.Path.TrimEndingDirectorySeparator(path);
        if (path.EndsWith(':')) path += System.IO.Path.DirectorySeparatorChar; // "D:" is the drive's current folder; "D:\" its root.
        var existing = sources.OfType<LocalSource>().FirstOrDefault(s => string.Equals(s.Root, path, StringComparison.OrdinalIgnoreCase));
        if (existing != null) return existing;
        var name = System.IO.Path.GetFileName(path.TrimEnd('\\', '/'));
        if (string.IsNullOrEmpty(name)) name = path;
        var record = new Record(Guid.NewGuid(), name, SourceKind.Local, Path: path);
        var source = new LocalSource(record.Id, record.Name, path);
        records.Add(record);
        sources = [.. sources, source];
        Save();
        return source;
    }

    /// <summary>Adds a signed-in Jellyfin server. The password goes to the credential store.</summary>
    public IMusicSource? AddJellyfin(string name, string server, string username, string password)
    {
        var record = new Record(Guid.NewGuid(), name, SourceKind.Jellyfin, Server: server, Username: username);
        credentials.SetPassword(password, record.Id.ToString());
        var source = MakeJellyfin?.Invoke(record, credentials, DeviceId);
        if (source == null) return null;
        records.Add(record);
        sources = [.. sources, source];
        Save();
        return source;
    }

    /// <summary>Adds a CD while it is in the drive. Not saved: it goes away with the disc.</summary>
    public void AddTransient(IMusicSource source)
    {
        if (Source(source.Id) != null) return;
        sources = [.. sources, source];
        Changed?.Invoke();
    }

    public void Remove(Guid id)
    {
        if (records.FirstOrDefault(r => r.Id == id)?.Kind == SourceKind.Jellyfin) credentials.DeletePassword(id.ToString());
        records.RemoveAll(r => r.Id == id);
        sources = sources.Where(s => s.Id != id).ToArray();
        Failed.Remove(id);
        Save();
    }

    /// <summary>Identifies this computer to Jellyfin (shown under Devices in its dashboard).</summary>
    public string DeviceId
    {
        get
        {
            var id = settings.Get<string?>("deviceID", null);
            if (id != null) return id;
            id = Guid.NewGuid().ToString().ToUpperInvariant();
            settings.Set("deviceID", id);
            return id;
        }
    }

    private void Save()
    {
        settings.Set("sources", records);
        Changed?.Invoke();
    }

    /// <summary>Playable location of a track, through the source it belongs to.</summary>
    public async Task<string> Resolve(Entry entry)
    {
        var source = Source(entry.SourceId) ?? throw SourceException.MissingFolder(entry.FolderName);
        return await source.Url(entry);
    }

    public Task StreamFailed(Entry entry) => Source(entry.SourceId)?.StreamFailed() ?? Task.CompletedTask;

    /// <summary>The image file in the folder holding <paramref name="entry"/>; a disc folder ("CD 1") also looks in the album folder above.</summary>
    public async Task<string?> Artwork(Entry entry)
    {
        if (Source(entry.SourceId) is not { } source) return null;
        var folder = entry.ParentPath;
        while (true)
        {
            if (await source.Artwork(folder) is { } url) return url;
            if (!AlbumGuess.IsDiscFolder(Paths.LastComponent(folder)) || folder.Length == 0) return null;
            folder = Paths.Parent(folder);
        }
    }
}
