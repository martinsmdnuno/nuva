using System;
using System.Windows;
using System.Windows.Controls;
using NuVa.Core;

namespace NuVa.UI;

/// <summary>
/// The mini player that opens from the notification area while the window is closed (the Mac's menu bar
/// player): the display and the playback keys, a key for ambient and the skin, Open NuVa and Quit.
/// Closes when it loses focus, like a flyout.
/// </summary>
public sealed class MiniPlayer : Window
{
    private readonly App app;
    private readonly DisplayView display;
    private readonly KeyButton play;
    private readonly System.Windows.Threading.DispatcherTimer ticker;

    public MiniPlayer(App app)
    {
        this.app = app;
        var model = app.Model;
        var player = model.Player;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        SizeToContent = SizeToContent.Height;
        Width = 360;
        Background = Theme.Brush(Token.Surface0);
        BorderBrush = Theme.Brush(Token.Line);
        BorderThickness = new Thickness(1);
        UseLayoutRounding = true;

        display = new DisplayView(model, allowsArtwork: true, isMain: false);
        display.EqualizerClicked += () => EqualizerPanel.Open(model.Equalizer, display.EqualizerAnchor);
        display.OutputClicked += app.ShowOutputMenu;
        app.ApplyArtwork(display);
        var keys = new DockPanel { Margin = new Thickness(0, Space.S3, 0, 0), LastChildFill = false };
        var previous = new KeyButton(Tone.Transport, NuVa.UI.Icon.Previous, L.T("Anterior"), player.Previous);
        play = new KeyButton(Tone.Play, NuVa.UI.Icon.Play, "", () =>
        {
            if (player.Queue.Count == 0) app.ShowMainWindow();
            else player.TogglePlayPause();
        }) { Margin = new Thickness(Space.S1, 0, Space.S1, 0) };
        var next = new KeyButton(Tone.Transport, NuVa.UI.Icon.Next, L.T("Seguinte"), player.Next);
        keys.Children.Add(previous);
        keys.Children.Add(play);
        keys.Children.Add(next);
        var quit = new KeyButton(L.T("Sair"), null, app.Quit) { Margin = new Thickness(Space.S1, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        var open = new KeyButton(L.T("Abrir NuVa"), null, () => { Close(); app.ShowMainWindow(); }) { Margin = new Thickness(Space.S1, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        var view = new KeyButton(Tone.Mode, NuVa.UI.Icon.Ambient, L.T("Ambiente e skin"));
        view.Click += () =>
        {
            var menu = new ContextMenu { PlacementTarget = view, Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom };
            menu.Items.Add(QueueView.Item(app.AmbientOpen ? L.T("Sair do Ambiente") : L.T("Ambiente"), () => { Close(); app.ToggleAmbient(); }));
            menu.Items.Add(new Separator());
            foreach (var item in AppMenu.SkinItems(app)) menu.Items.Add(item);
            menu.IsOpen = true;
        };
        DockPanel.SetDock(quit, Dock.Right);
        DockPanel.SetDock(open, Dock.Right);
        DockPanel.SetDock(view, Dock.Right);
        keys.Children.Add(quit);
        keys.Children.Add(open);
        keys.Children.Add(view);

        var stack = new StackPanel { Margin = new Thickness(Space.S3) };
        stack.Children.Add(display);
        stack.Children.Add(keys);
        Content = stack;

        player.Changed += Refresh;
        app.ArtworkChanged += Refresh;
        ticker = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
        ticker.Tick += (_, _) => display.Tick();
        ticker.Start();
        Closed += (_, _) =>
        {
            player.Changed -= Refresh;
            app.ArtworkChanged -= Refresh;
            ticker.Stop();
        };
        Deactivated += (_, _) => { if (IsVisible) Close(); };
        KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Escape) Close(); };
        Refresh();
    }

    private void Refresh()
    {
        display.Refresh();
        app.ApplyArtwork(display);
        play.Icon = app.Model.Player.IsPlaying ? NuVa.UI.Icon.Pause : NuVa.UI.Icon.Play;
        play.Help = app.Model.Player.IsPlaying ? L.T("Pausa") : L.T("Tocar");
    }

    /// <summary>Opens above the notification area, at the bottom right of the work area (or wherever the taskbar is).</summary>
    public void ShowNearTray()
    {
        Show();
        UpdateLayout();
        var area = SystemParameters.WorkArea;
        var cursor = System.Windows.Forms.Cursor.Position;
        var dpi = System.Windows.Media.VisualTreeHelper.GetDpi(this);
        var x = cursor.X / dpi.DpiScaleX;
        var y = cursor.Y / dpi.DpiScaleY;
        Left = Math.Clamp(x - ActualWidth / 2, area.Left + 8, area.Right - ActualWidth - 8);
        Top = y > area.Top + area.Height / 2 ? area.Bottom - ActualHeight - 8 : area.Top + 8;
        Activate();
    }
}
