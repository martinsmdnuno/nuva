using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using NuVa.Audio;
using NuVa.Core;
using NuVa.Core.Audio;
using NuVa.Core.Library;
using NuVa.Core.Player;

namespace NuVa;

/// <summary>What sits below the keys. The window is the same device in every mode: 360 to 480 wide.</summary>
public enum WindowMode { Player, Browser, Compact }

/// <summary>App state: sources, player, queue durations, and the View menu's choices (port of AppModel.swift).</summary>
public sealed class AppModel
{
    public Settings Settings { get; }
    public SourceStore Sources { get; }
    public Browser Browser { get; }
    public Equalizer Equalizer { get; }
    public SpectrumShared Spectrum { get; } = new();
    public GraphOutput Output { get; }
    public Pipeline Pipeline { get; }
    public PlayerController Player { get; }
    public TrackDurations Durations { get; }
    public Dispatcher Ui { get; }

    /// <summary>The window mode, the View menu's toggles, the skin: anything the window lays out from.</summary>
    public event Action? Changed;

    public AppModel(Settings settings, Dispatcher ui)
    {
        Settings = settings;
        Ui = ui;
        Sources = new SourceStore(settings, new CredentialStore());
        Browser = new Browser(Sources);
        Equalizer = new Equalizer(settings);
        Output = new GraphOutput();
        Pipeline = new Pipeline(new DecoderFactory(), Output, new Tap(Equalizer, Spectrum));
        Player = new PlayerController(Pipeline, async (entry, _) => await Sources.Resolve(entry), SynchronizationContext.Current)
        {
            OnStreamFailure = entry => Sources.StreamFailed(entry),
            ApplyVolume = v => Output.Volume = v,
        };
        Player.Volume = settings.Get("volume", 1f);
        Durations = new TrackDurations(Sources, ui);
        windowMode = settings.Get("windowMode", "player") switch { "browser" => WindowMode.Browser, "compact" => WindowMode.Compact, _ => WindowMode.Player };
        showsArtwork = settings.Get("showsArtwork", false);
        showsSpectrum = settings.Get("showsSpectrum", true);
        showsRemaining = settings.Get("showsRemaining", false);
    }

    /// <summary>Opens the saved sources (after the Jellyfin factory is set) and the browser's first place.</summary>
    public void Start()
    {
        Sources.Load();
        if (Sources.Sources.Count == 1) Browser.Open(new BrowserLocation(Sources.Sources[0].Id, ""));
        else Browser.Open(null);
    }

    private WindowMode windowMode;
    public WindowMode WindowMode
    {
        get => windowMode;
        set
        {
            if (windowMode == value) return;
            windowMode = value;
            Settings.Set("windowMode", value switch { WindowMode.Browser => "browser", WindowMode.Compact => "compact", _ => "player" });
            Changed?.Invoke();
        }
    }

    private bool showsArtwork;
    /// <summary>Folder artwork in the display, the mini player and the media controls. Off by default.</summary>
    public bool ShowsArtwork
    {
        get => showsArtwork;
        set { showsArtwork = value; Settings.Set("showsArtwork", value); Changed?.Invoke(); }
    }

    private bool showsSpectrum;
    /// <summary>Spectrum meter on the display (View ▸ Show Spectrum). On by default.</summary>
    public bool ShowsSpectrum
    {
        get => showsSpectrum;
        set { showsSpectrum = value; Settings.Set("showsSpectrum", value); Changed?.Invoke(); }
    }

    private bool showsRemaining;
    /// <summary>The position row's end shows the time left ("-03:10") instead of the duration.</summary>
    public bool ShowsRemaining
    {
        get => showsRemaining;
        set { showsRemaining = value; Settings.Set("showsRemaining", value); }
    }

    public void Notify() => Changed?.Invoke();

    /// <summary>Source label of the current track ("Local", "Jellyfin").</summary>
    public string CurrentSourceLabel => Player.Current?.Entry is { } entry && Sources.Source(entry.SourceId) is { } source ? KindLabel(source.Kind) : "";

    public static string KindLabel(SourceKind kind) => kind switch
    {
        SourceKind.Local => L.T("Local"),
        SourceKind.Server => L.T("Servidor"),
        SourceKind.Jellyfin => "Jellyfin",
        _ => "CD",
    };

    public void ToggleBrowser() => WindowMode = WindowMode == WindowMode.Browser ? WindowMode.Player : WindowMode.Browser;

    /// <summary>Shows or hides the queue: player ↔ compact.</summary>
    public void ToggleQueue() => WindowMode = WindowMode == WindowMode.Compact ? WindowMode.Player : WindowMode.Compact;

    /// <summary>Play with no queue opens the folder browser.</summary>
    public void PlayOrBrowse()
    {
        if (Player.Queue.Count == 0) WindowMode = WindowMode.Browser;
        else Player.TogglePlayPause();
    }

    /// <summary>Asks for a folder (on this computer or a network share) and adds it as a source.</summary>
    public void AddFolder(Window? owner)
    {
        WindowMode = WindowMode.Browser;
        var dialog = new Microsoft.Win32.OpenFolderDialog
        {
            Title = L.T("Escolher a pasta da música"),
            Multiselect = false,
        };
        if (dialog.ShowDialog(owner) != true) return;
        var source = Sources.AddLocal(dialog.FolderName);
        Browser.Open(new BrowserLocation(source.Id, ""));
    }

    /// <summary>Plays a folder (with subfolders), starting at a track if given.</summary>
    public async Task PlayFolder(BrowserLocation folder, Entry? startingAt = null)
    {
        var tracks = await Browser.Tracks(folder);
        if (tracks.Count == 0) return;
        var start = startingAt == null ? 0 : Math.Max(0, tracks.FindIndex(t => t.Id == startingAt.Id));
        Player.SetQueue(tracks, start);
        // The folders give way to the queue, now holding what was chosen.
        if (WindowMode == WindowMode.Browser) WindowMode = WindowMode.Player;
    }

    /// <summary>Appends a track or a whole folder to the end of the queue.</summary>
    public async Task Enqueue(Entry entry)
    {
        if (entry.Kind == EntryKind.Track) Player.Append([entry]);
        else Player.Append(await Browser.Tracks(new BrowserLocation(entry.SourceId, entry.Path)));
    }

    /// <summary>A source goes: its tracks leave the queue, the browser leaves it, and it is forgotten.</summary>
    public void RemoveSource(Guid id)
    {
        Player.RemoveAll(e => e.SourceId == id);
        if (Browser.Location?.SourceId == id) Browser.Open(null);
        Sources.Remove(id);
        Changed?.Invoke();
    }

    public void SaveState()
    {
        Settings.Set("volume", Player.Volume);
        Settings.Save();
    }
}
