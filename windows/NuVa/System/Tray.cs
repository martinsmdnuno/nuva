using System;
using System.Windows;
using System.Windows.Controls;
using NuVa.Core;
using NuVa.UI;

namespace NuVa.Platform;

/// <summary>
/// NuVa in the notification area while the window is closed (the Mac's menu bar icon): a click opens
/// the mini player, a right-click a short menu, a double-click the window.
/// </summary>
public sealed class Tray : IDisposable
{
    private readonly App app;
    private readonly System.Windows.Forms.NotifyIcon icon;
    private MiniPlayer? mini;

    public Tray(App app)
    {
        this.app = app;
        using var stream = Application.GetResourceStream(new Uri("pack://application:,,,/NuVa;component/Assets/NuVa.ico")).Stream;
        icon = new System.Windows.Forms.NotifyIcon
        {
            Icon = new System.Drawing.Icon(stream, System.Windows.Forms.SystemInformation.SmallIconSize),
            Text = "NuVa",
            Visible = false,
        };
        icon.MouseClick += (_, e) =>
        {
            if (e.Button == System.Windows.Forms.MouseButtons.Left) app.Dispatcher.BeginInvoke(ToggleMini);
            else if (e.Button == System.Windows.Forms.MouseButtons.Right) app.Dispatcher.BeginInvoke(ShowMenu);
        };
        icon.MouseDoubleClick += (_, _) => app.Dispatcher.BeginInvoke(app.ShowMainWindow);
        app.Model.Player.Changed += UpdateTip;
    }

    public bool Visible
    {
        get => icon.Visible;
        set
        {
            icon.Visible = value;
            if (!value) mini?.Close();
        }
    }

    private void UpdateTip()
    {
        var entry = app.Model.Player.Current?.Entry;
        var text = entry == null ? "NuVa" : $"NuVa · {entry.Title}";
        // The notification area's tooltip holds 127 characters.
        icon.Text = text.Length > 127 ? text[..127] : text;
    }

    private void ToggleMini()
    {
        if (mini is { IsVisible: true })
        {
            mini.Close();
            return;
        }
        mini = new MiniPlayer(app);
        mini.Closed += (_, _) => mini = null;
        mini.ShowNearTray();
    }

    private void ShowMenu()
    {
        var player = app.Model.Player;
        var menu = new ContextMenu { Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint };
        menu.Items.Add(QueueView.Item(L.T("Abrir NuVa"), app.ShowMainWindow));
        menu.Items.Add(new Separator());
        menu.Items.Add(QueueView.Item(player.IsPlaying ? L.T("Pausa") : L.T("Tocar"), app.Model.PlayOrBrowse));
        menu.Items.Add(QueueView.Item(L.T("Seguinte"), player.Next));
        menu.Items.Add(QueueView.Item(L.T("Anterior"), player.Previous));
        menu.Items.Add(new Separator());
        menu.Items.Add(QueueView.Item(L.T("Sair da NuVa"), app.Quit));
        menu.IsOpen = true;
    }

    public void Dispose()
    {
        icon.Visible = false;
        icon.Dispose();
    }
}
