using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using NuVa.Core;

namespace NuVa.UI;

/// <summary>
/// Header of what sits below the keys, as if printed on the chassis: the folders key and the "pastas"
/// legend on the left, the "fila" legend with the total on the right. With the folders, the browser's
/// keys take the row (up, where you are, Play Folder, eject).
/// </summary>
public sealed class QueueHeader : DockPanel
{
    private readonly AppModel model;

    public QueueHeader(AppModel model, Action<Guid> eject)
    {
        this.model = model;
        LastChildFill = true;
        var isOpen = model.WindowMode == WindowMode.Browser;
        var folders = new KeyWithLed(new KeyButton(Tone.Mode, Icon.Folders,
            (isOpen ? L.T("Mostrar fila") : L.T("Mostrar pastas")) + " Ctrl+B", model.ToggleBrowser), true);
        folders.Led!.Set(isOpen);
        folders.VerticalAlignment = VerticalAlignment.Bottom;
        SetDock(folders, Dock.Left);
        Children.Add(folders);
        if (isOpen)
        {
            Children.Add(BrowserControls(eject));
            return;
        }
        // Centred on the key's face.
        var legend = Text.Legend(L.T("pastas"));
        legend.VerticalAlignment = VerticalAlignment.Bottom;
        legend.Margin = new Thickness(Space.S2, 0, 0, Space.S3);
        SetDock(legend, Dock.Left);
        Children.Add(legend);

        // Switches between the queue and compact mode.
        var toggle = new Readout(Token.InkMuted, Token.Ink) { HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, Space.S2, Space.S3) };
        var led = new Led { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, Space.S1 + 2, 0) };
        led.Set(model.WindowMode == WindowMode.Player);
        toggle.Children.Add(led);
        toggle.Children.Add(Text.Make(L.T("fila"), TextStyle.Legend, Token.InkMuted));
        if (model.Player.Queue.Count > 0)
        {
            var detail = Text.Make(Summary(), TextStyle.Hint, Token.InkMuted);
            detail.Margin = new Thickness(Space.S1 + 2, 0, 0, 0);
            toggle.Children.Add(detail);
        }
        toggle.Lit = model.WindowMode == WindowMode.Player;
        toggle.ToolTip = model.WindowMode == WindowMode.Player ? L.T("Esconder fila") + " Ctrl+3" : L.T("Mostrar fila") + " Ctrl+1";
        toggle.Click += model.ToggleQueue;
        Children.Add(toggle);
    }

    /// <summary>"11 faixas · 39:18"; no total while durations are missing.</summary>
    private string Summary()
    {
        var queue = model.Player.Queue;
        var label = L.F("{0} faixas", queue.Count);
        var known = queue.Select(q => model.Durations.Get(q.Entry)).ToList();
        if (known.Any(d => d == null)) return label;
        return $"{label} · {TimeFormat.Short(known.Sum(d => d!.Value))}";
    }

    private DockPanel BrowserControls(Action<Guid> eject)
    {
        var browser = model.Browser;
        var row = new DockPanel { LastChildFill = true, Height = Space.Key, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(Space.S2, 0, 0, 0) };
        if (browser.Location != null)
        {
            var up = new KeyButton(Tone.Mode, Icon.Back, L.T("Subir") + " ←", browser.Up) { Margin = new Thickness(0, 0, Space.S2, 0) };
            SetDock(up, Dock.Left);
            row.Children.Add(up);
        }
        if (browser.Source is { } source)
        {
            var icon = new IconView(SourceIcon(source.Kind), 14) { Brush = Theme.Brush(Token.InkMuted), Margin = new Thickness(0, 0, Space.S2, 0), VerticalAlignment = VerticalAlignment.Center };
            SetDock(icon, Dock.Left);
            row.Children.Add(icon);
        }
        if (browser.Source is { Kind: Core.Library.SourceKind.CD } disc)
        {
            var ejectKey = new KeyButton(Tone.Mode, Icon.Eject, L.T("Ejetar CD") + " Ctrl+E", () => eject(disc.Id)) { Margin = new Thickness(Space.S2, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            SetDock(ejectKey, Dock.Right);
            row.Children.Add(ejectKey);
        }
        if (browser.Location is { } location)
        {
            var playFolder = new KeyButton(L.T("Tocar pasta"), null, () => _ = model.PlayFolder(location)) { Margin = new Thickness(Space.S2, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
            SetDock(playFolder, Dock.Right);
            row.Children.Add(playFolder);
        }
        var title = Text.Make(browser.Title, TextStyle.Label, Token.Ink);
        title.VerticalAlignment = VerticalAlignment.Center;
        title.ToolTip = browser.Location?.Path;
        row.Children.Add(title);
        return row;
    }

    public static Icon SourceIcon(Core.Library.SourceKind kind) => kind switch
    {
        Core.Library.SourceKind.Local => Icon.Drive,
        Core.Library.SourceKind.CD => Icon.Disc,
        _ => Icon.Server,
    };
}

/// <summary>The queue. Double-click or Enter plays; Delete removes; drag or Ctrl+Shift+↑ Ctrl+Shift+↓ reorders.</summary>
public sealed class QueueView : Grid
{
    private readonly AppModel model;
    private readonly RowList list = new();
    private long? selectedId;

    public QueueView(AppModel model, Window owner)
    {
        this.model = model;
        var player = model.Player;
        if (player.Queue.Count == 0)
        {
            Children.Add(EmptyState(owner));
            return;
        }
        list.Activated += i => player.Play(player.Queue[i].Id);
        list.SelectionChanged += i => selectedId = i >= 0 && i < player.Queue.Count ? player.Queue[i].Id : null;
        list.Reorder = (from, to) =>
        {
            selectedId = player.Queue[from].Id;
            player.Move([from], to);
        };
        list.MenuFor = Menu;
        list.PreviewKeyDown += OnKey;
        Children.Add(list);
        Rebuild();
        Loaded += (_, _) => list.Focus();
    }

    public RowList List => list;

    public void Rebuild()
    {
        var player = model.Player;
        if (player.Queue.Count == 0) return;
        var rows = player.Queue.Select(item =>
        {
            model.Durations.Load(item.Entry);
            return new RowView
            {
                Name2 = item.Entry.ListName,
                Trailing = model.Durations.Get(item.Entry) is { } d ? TimeFormat.Short(d) : "",
                Playing = player.CurrentId == item.Id,
                ToolTip = item.Entry.Name,
            };
        }).ToList();
        var offset = list.VerticalOffset;
        var select = selectedId is { } id ? player.Queue.ToList().FindIndex(q => q.Id == id) : -1;
        list.SetRows(rows);
        if (select >= 0) list.Select(select, scroll: false);
        list.ScrollToVerticalOffset(offset);
    }

    /// <summary>The playing LED and the durations, without rebuilding the rows.</summary>
    public void Refresh()
    {
        var player = model.Player;
        if (list.Rows.Count != player.Queue.Count) { Rebuild(); return; }
        for (var i = 0; i < list.Rows.Count; i++)
        {
            var item = player.Queue[i];
            list.Rows[i].Playing = player.CurrentId == item.Id;
            list.Rows[i].Trailing = model.Durations.Get(item.Entry) is { } d ? TimeFormat.Short(d) : "";
        }
    }

    /// <summary>Ctrl+L: reveal and select the current track.</summary>
    public void RevealCurrent()
    {
        var player = model.Player;
        var i = player.Queue.ToList().FindIndex(q => q.Id == player.CurrentId);
        if (i >= 0) list.Reveal(i);
        list.Focus();
    }

    private void OnKey(object sender, KeyEventArgs e)
    {
        var player = model.Player;
        var i = list.Selected;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (Keyboard.Modifiers == (ModifierKeys.Control | ModifierKeys.Shift) && key is Key.Up or Key.Down && i >= 0)
        {
            Move(i, key == Key.Up ? -1 : 1);
            e.Handled = true;
        }
        else if (Keyboard.Modifiers == ModifierKeys.None && key is Key.Delete or Key.Back && i >= 0)
        {
            var next = i + 1 < player.Queue.Count ? player.Queue[i + 1].Id : i > 0 ? player.Queue[i - 1].Id : (long?)null;
            player.Remove([i]);
            selectedId = next;
            e.Handled = true;
        }
    }

    /// <summary>Moves a track one place up or down, keeping it selected.</summary>
    private void Move(int index, int step)
    {
        var player = model.Player;
        if (index + step < 0 || index + step >= player.Queue.Count) return;
        selectedId = player.Queue[index].Id;
        player.Move([index], step < 0 ? index - 1 : index + 2);
    }

    private ContextMenu Menu(int index)
    {
        var player = model.Player;
        var menu = new ContextMenu();
        menu.Items.Add(Item(L.T("Tocar"), () => player.Play(player.Queue[index].Id)));
        menu.Items.Add(Item(L.T("Mover para cima") + "\tCtrl+Shift+↑", () => Move(index, -1), index > 0));
        menu.Items.Add(Item(L.T("Mover para baixo") + "\tCtrl+Shift+↓", () => Move(index, 1), index < player.Queue.Count - 1));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item(L.T("Remover da fila"), () => player.Remove([index])));
        return menu;
    }

    public static MenuItem Item(string header, Action action, bool enabled = true, bool? check = null)
    {
        var parts = header.Split('\t');
        var item = new MenuItem { Header = parts[0], IsEnabled = enabled };
        if (parts.Length > 1) item.InputGestureText = parts[1];
        if (check is { } c) { item.IsCheckable = true; item.IsChecked = c; }
        item.Click += (_, _) => action();
        return item;
    }

    /// <summary>Sources, empty queue: a way to the folders. No sources: the two ways to bring in music.</summary>
    private UIElement EmptyState(Window owner)
    {
        var stack = new StackPanel { Margin = new Thickness(Space.S2, Space.S1, Space.S2, 0) };
        if (model.Sources.Sources.Count == 0 && model.Sources.Failed.Count == 0)
        {
            stack.Children.Add(Text.Legend(L.T("começar")));
            stack.Children.Add(Way(L.T("Adicionar pasta"), L.T("Música no computador ou num disco de rede"), "Ctrl+O", () => model.AddFolder(owner)));
            stack.Children.Add(Way(L.T("Adicionar Jellyfin"), L.T("Servidor Jellyfin, com o teu utilizador"), "Ctrl+Shift+O", () => App.Current.AddJellyfin()));
            var hint = Text.Make(L.T("Clicar com o botão direito para o menu"), TextStyle.Caption, Token.InkMuted);
            hint.Margin = new Thickness(0, Space.S4, 0, 0);
            stack.Children.Add(hint);
            return stack;
        }
        stack.Margin = new Thickness(Space.S2, Space.S4, Space.S2, 0);
        stack.Children.Add(Text.Make(L.T("Fila vazia"), TextStyle.Body, Token.Ink));
        var note = Text.Make(L.T("Abrir as pastas e tocar uma."), TextStyle.Caption, Token.InkMuted);
        note.Margin = new Thickness(0, Space.S1, 0, Space.S3);
        stack.Children.Add(note);
        stack.Children.Add(new KeyButton(L.T("Mostrar pastas"), "Ctrl+B", () => model.WindowMode = WindowMode.Browser) { HorizontalAlignment = HorizontalAlignment.Left });
        return stack;
    }

    private static UIElement Way(string title, string detail, string shortcut, Action action)
    {
        var row = new DockPanel { Margin = new Thickness(0, Space.S2, 0, 0), LastChildFill = true };
        var key = new KeyButton(title, null, action) { Width = 116, VerticalAlignment = VerticalAlignment.Center };
        DockPanel.SetDock(key, Dock.Left);
        row.Children.Add(key);
        var text = new StackPanel { Margin = new Thickness(Space.S3, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        var d = Text.Make(detail, TextStyle.Caption, Token.Ink);
        d.TextWrapping = TextWrapping.Wrap;
        text.Children.Add(d);
        var s = Text.Make(shortcut, TextStyle.Hint, Token.InkMuted);
        s.Margin = new Thickness(0, 2, 0, 0);
        text.Children.Add(s);
        row.Children.Add(text);
        return row;
    }
}
