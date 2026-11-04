using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Threading;
using NuVa.Core;
using NuVa.Core.Library;
using Windows.Media;
using Windows.Storage;
using Windows.Storage.Streams;

namespace NuVa.Platform;

/// <summary>
/// The system media controls (the Mac's MPRemoteCommandCenter and MPNowPlayingInfoCenter): the media
/// keys, the volume flyout's and lock screen's player, with the title, the folder and the cover. A
/// MediaPlayer that plays nothing lends NuVa its SMTC, driven by hand (no command manager).
/// </summary>
public sealed class MediaControls
{
    private readonly AppModel model;
    private readonly Dispatcher ui;
    private readonly Windows.Media.Playback.MediaPlayer host;
    private readonly SystemMediaTransportControls smtc;
    private string? shownKey;
    private string? defaultArtwork;
    private DateTime lastTimeline;

    /// <summary>The cover file for the current track (folder or online), or null for NuVa's own.</summary>
    public Func<string?>? ArtworkFile { get; set; }

    private MediaControls(AppModel model, Dispatcher ui)
    {
        this.model = model;
        this.ui = ui;
        host = new Windows.Media.Playback.MediaPlayer();
        host.CommandManager.IsEnabled = false;
        smtc = host.SystemMediaTransportControls;
        smtc.IsEnabled = true;
        smtc.IsPlayEnabled = true;
        smtc.IsPauseEnabled = true;
        smtc.IsStopEnabled = true;
        smtc.IsNextEnabled = true;
        smtc.IsPreviousEnabled = true;
        smtc.ButtonPressed += (_, e) => ui.BeginInvoke(() => Pressed(e.Button));
        smtc.PlaybackPositionChangeRequested += (_, e) => ui.BeginInvoke(() => model.Player.Seek(e.RequestedPlaybackPosition.TotalSeconds));
        model.Player.Changed += Update;
        model.Player.Seeked += () => UpdateTimeline(force: true);
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
        timer.Tick += (_, _) => UpdateTimeline(force: false);
        timer.Start();
        Update();
    }

    /// <summary>Null when Windows won't give NuVa the controls (the media keys then go to the window).</summary>
    public static MediaControls? Start(AppModel model, Dispatcher ui)
    {
        try
        {
            var controls = new MediaControls(model, ui);
            Log.Write("media controls: on");
            return controls;
        }
        catch (Exception e)
        {
            Log.Write($"media controls: unavailable ({e.Message})");
            return null;
        }
    }

    private void Pressed(SystemMediaTransportControlsButton button)
    {
        var player = model.Player;
        switch (button)
        {
            case SystemMediaTransportControlsButton.Play:
                if (!player.IsPlaying) model.PlayOrBrowse();
                break;
            case SystemMediaTransportControlsButton.Pause:
                player.Pause();
                break;
            case SystemMediaTransportControlsButton.Stop:
                player.Stop();
                break;
            case SystemMediaTransportControlsButton.Next:
                player.Next();
                break;
            case SystemMediaTransportControlsButton.Previous:
                player.Previous();
                break;
        }
    }

    /// <summary>Updates when the track, state, duration or artwork changes.</summary>
    public async void Update()
    {
        var player = model.Player;
        var entry = player.Current?.Entry;
        try
        {
            smtc.PlaybackStatus = entry == null ? MediaPlaybackStatus.Stopped : player.IsPlaying ? MediaPlaybackStatus.Playing : MediaPlaybackStatus.Paused;
            var artwork = ArtworkFile?.Invoke() ?? DefaultArtwork();
            var key = $"{entry?.Id}|{player.Duration:F0}|{artwork}";
            if (key != shownKey)
            {
                shownKey = key;
                var updater = smtc.DisplayUpdater;
                updater.ClearAll();
                if (entry != null)
                {
                    updater.Type = MediaPlaybackType.Music;
                    updater.AppMediaId = "NuVa";
                    updater.MusicProperties.Title = entry.Title;
                    // Never from tags: the album's folder, and the one above it for the artist.
                    updater.MusicProperties.AlbumTitle = Paths.LastComponent(entry.AlbumPath);
                    updater.MusicProperties.Artist = entry.ArtistFolder ?? "";
                    if (artwork != null)
                    {
                        var file = await StorageFile.GetFileFromPathAsync(artwork);
                        // Another track came while the file opened: its own update shows it.
                        if (key != shownKey) return;
                        updater.Thumbnail = RandomAccessStreamReference.CreateFromFile(file);
                    }
                }
                updater.Update();
            }
            UpdateTimeline(force: true);
        }
        catch (Exception e)
        {
            Log.Write($"media controls: {e.Message}");
        }
    }

    private void UpdateTimeline(bool force)
    {
        var player = model.Player;
        if (!force && (!player.IsPlaying || DateTime.UtcNow - lastTimeline < TimeSpan.FromSeconds(4))) return;
        lastTimeline = DateTime.UtcNow;
        try
        {
            smtc.UpdateTimelineProperties(new SystemMediaTransportControlsTimelineProperties
            {
                StartTime = TimeSpan.Zero,
                MinSeekTime = TimeSpan.Zero,
                EndTime = TimeSpan.FromSeconds(Math.Max(0, player.Duration)),
                MaxSeekTime = TimeSpan.FromSeconds(Math.Max(0, player.Duration)),
                Position = TimeSpan.FromSeconds(Math.Max(0, player.CurrentTime)),
            });
        }
        catch (Exception)
        {
        }
    }

    /// <summary>Without folder artwork: NuVa's icon, as the Mac shows the NuVa folder.</summary>
    private string? DefaultArtwork()
    {
        if (defaultArtwork != null) return defaultArtwork;
        try
        {
            var path = Path.Combine(App.LocalFolder, "nowplaying.png");
            if (!File.Exists(path))
            {
                Directory.CreateDirectory(App.LocalFolder);
                using var source = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/NuVa;component/Assets/icon-256.png")).Stream;
                using var target = File.Create(path);
                source.CopyTo(target);
            }
            defaultArtwork = path;
        }
        catch (Exception)
        {
        }
        return defaultArtwork;
    }
}
