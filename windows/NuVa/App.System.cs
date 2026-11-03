using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;
using System.Windows.Shell;
using NuVa.Core;
using NuVa.Platform;
using NuVa.UI;

namespace NuVa;

// Windows' own places for a player: the media controls, the taskbar, the notification area.
public sealed partial class App
{
    private readonly List<Action> started = [];
    private readonly List<Action> launched = [];
    private readonly List<Action> quitting = [];
    private MediaControls? mediaControls;
    private Tray? tray;
    private ThumbButtonInfo? thumbPlay;

    /// <summary>The system media controls took the media keys.</summary>
    public bool SystemMediaControls => mediaControls != null;

    private void StartFeatures()
    {
        mediaControls = MediaControls.Start(Model, Dispatcher);
        if (mediaControls != null) mediaControls.ArtworkFile = () => CurrentArtworkFile;
        tray = new Tray(this);
        foreach (var start in started) start();
    }

    private void AfterLaunch()
    {
        AddTaskbarButtons();
        ScanDrives();
        CheckAtLaunch();
        foreach (var then in launched) then();
    }

    private void BeforeQuit()
    {
        foreach (var stop in quitting) stop();
        tray?.Dispose();
    }

    /// <summary>The window closed: NuVa stays in the notification area, still playing.</summary>
    public void WindowHidden()
    {
        if (tray != null) tray.Visible = true;
    }

    public void WindowShown()
    {
        if (tray != null) tray.Visible = false;
    }

    /// <summary>Previous, play/pause and next on the taskbar's thumbnail.</summary>
    private void AddTaskbarButtons()
    {
        var player = Model.Player;
        ImageSource Glyph(Icon icon)
        {
            var (geometry, filled) = Icons.Get(icon);
            var drawing = filled
                ? new GeometryDrawing(Brushes.White, null, geometry)
                : new GeometryDrawing(null, new Pen(Brushes.White, 1.8) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round }, geometry);
            var group = new DrawingGroup();
            group.Children.Add(new GeometryDrawing(Brushes.Transparent, null, new RectangleGeometry(new Rect(0, 0, 24, 24))));
            group.Children.Add(drawing);
            var image = new DrawingImage(group);
            image.Freeze();
            return image;
        }
        ThumbButtonInfo Button(Icon icon, string help, Action action)
        {
            var button = new ThumbButtonInfo { ImageSource = Glyph(icon), Description = help };
            button.Click += (_, _) => action();
            return button;
        }
        thumbPlay = Button(Icon.Play, L.T("Tocar"), Model.PlayOrBrowse);
        MainWindow.TaskbarItemInfo = new TaskbarItemInfo
        {
            ThumbButtonInfos = [Button(Icon.Previous, L.T("Anterior"), player.Previous), thumbPlay, Button(Icon.Next, L.T("Seguinte"), player.Next)],
        };
        void Update()
        {
            thumbPlay.ImageSource = Glyph(player.IsPlaying ? Icon.Pause : Icon.Play);
            thumbPlay.Description = player.IsPlaying ? L.T("Pausa") : L.T("Tocar");
        }
        player.Changed += Update;
        Update();
    }
}
