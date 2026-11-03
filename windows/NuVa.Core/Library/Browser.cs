using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace NuVa.Core.Library;

/// <summary>Where the browser is: in a folder of a source ("" is its root).</summary>
public sealed record BrowserLocation(Guid SourceId, string Path);

/// <summary>Folder browser state (port of Browser.swift). Used from the UI thread; awaits resume there.</summary>
public sealed class Browser(SourceStore sources)
{
    private int loadToken;

    /// <summary>Null: the list of sources.</summary>
    public BrowserLocation? Location { get; private set; }
    public IReadOnlyList<Entry> Entries { get; private set; } = [];
    public string? ErrorMessage { get; private set; }
    public bool IsLoading { get; private set; }
    /// <summary>Summary per folder id: "12 faixas", "2 pastas".</summary>
    public Dictionary<string, string> Summaries { get; } = new();

    /// <summary>Anything above changed.</summary>
    public event Action? Changed;

    public IMusicSource? Source => Location == null ? null : sources.Source(Location.SourceId);

    /// <summary>Name of the current location: folder, source, or "Fontes".</summary>
    public string Title => Location == null ? L.T("Fontes")
        : Location.Path.Length == 0 ? Source?.Name ?? "" : Paths.LastComponent(Location.Path);

    public async void Open(BrowserLocation? location)
    {
        Location = location;
        Entries = [];
        ErrorMessage = null;
        var token = ++loadToken;
        if (location == null || sources.Source(location.SourceId) is not { } source)
        {
            IsLoading = false;
            Changed?.Invoke();
            return;
        }
        IsLoading = true;
        Changed?.Invoke();
        try
        {
            var items = await source.List(location.Path);
            if (token != loadToken) return;
            Entries = items;
        }
        catch (Exception e)
        {
            if (token != loadToken) return;
            ErrorMessage = e is SourceException ? e.Message : L.T("Servidor offline");
            Log.Write($"browser: {location.Path}: {e.Message}");
        }
        IsLoading = false;
        Changed?.Invoke();
    }

    public void Reload() => Open(Location);

    public void Enter(Entry folder) => Open(new BrowserLocation(folder.SourceId, folder.Path));

    /// <summary>Up one level; from a source's root, back to the source list.</summary>
    public void Up()
    {
        if (Location == null) return;
        Open(Location.Path.Length == 0 ? null : Location with { Path = Paths.Parent(Location.Path) });
    }

    public async Task LoadSummary(Entry folder)
    {
        if (Summaries.ContainsKey(folder.Id) || sources.Source(folder.SourceId) is not { } source) return;
        try
        {
            var items = await source.List(folder.Path);
            var tracks = items.Count(e => e.Kind == EntryKind.Track);
            var folders = items.Count - tracks;
            Summaries[folder.Id] = tracks > 0 ? L.F("{0} faixas", tracks) : folders > 0 ? L.F("{0} pastas", folders) : L.T("vazia");
            Changed?.Invoke();
        }
        catch (Exception)
        {
        }
    }

    /// <summary>Tracks in a folder and its subfolders, in natural order (CD 01 before CD 02).</summary>
    public async Task<List<Entry>> Tracks(BrowserLocation folder)
    {
        if (sources.Source(folder.SourceId) is not { } source) return [];
        return await Collect(source, folder.Path);
    }

    private static async Task<List<Entry>> Collect(IMusicSource source, string path)
    {
        IReadOnlyList<Entry> items;
        try
        {
            items = await source.List(path);
        }
        catch (Exception)
        {
            return [];
        }
        var result = items.Where(e => e.Kind == EntryKind.Track).ToList();
        foreach (var sub in items.Where(e => e.Kind == EntryKind.Folder))
            result.AddRange(await Collect(source, sub.Path));
        return result;
    }
}
