using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using NuVa.Core;
using NuVa.Core.Library;

namespace NuVa.UI;

/// <summary>
/// The folder browser, below the keys in place of the queue. Enter or double-click opens a folder or
/// plays from the track; Ctrl+Enter adds to the queue; ← or Backspace goes up; → enters a folder.
/// </summary>
public sealed class BrowserView : Grid
{
    private abstract record Row(string Id);
    private sealed record SourceRow(Guid SourceId, string Name, Icon Icon, string? Error) : Row($"source/{SourceId}");
    private sealed record EntryRow(Entry Entry) : Row(Entry.Id);

    private readonly AppModel model;
    private readonly Window owner;
    private readonly RowList list = new();
    private readonly TextBlock note = Text.Make("", TextStyle.Caption, Token.InkMuted);
    private readonly StackPanel error = new() { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
    private List<Row> rows = [];
    private readonly DispatcherTimer loading;
    private string? selectAfter;
    private BrowserLocation? shown;

    public BrowserView(AppModel model, Window owner)
    {
        this.model = model;
        this.owner = owner;
        note.Margin = new Thickness(Space.S2, Space.S4, Space.S2, 0);
        note.VerticalAlignment = VerticalAlignment.Top;
        Children.Add(list);
        Children.Add(note);
        Children.Add(error);
        list.Activated += i => Activate(rows[i]);
        list.MenuFor = i => Menu(rows[i]);
        list.PreviewKeyDown += OnKey;
        // "Loading…" only after a moment, so a fast folder doesn't flash it.
        loading = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) };
        loading.Tick += (_, _) =>
        {
            loading.Stop();
            if (model.Browser.IsLoading) note.Text = L.T("A carregar…");
        };
        model.Browser.Changed += Refresh;
        Unloaded += (_, _) => model.Browser.Changed -= Refresh;
        Refresh();
        Loaded += (_, _) => list.Focus();
    }

    public void Refresh()
    {
        var browser = model.Browser;
        // Going up, the folder you came from stays selected.
        if (!Equals(shown, browser.Location))
        {
            selectAfter = CameFrom(shown, browser.Location);
            shown = browser.Location;
        }
        error.Children.Clear();
        error.Visibility = Visibility.Collapsed;
        note.Text = "";
        if (browser.ErrorMessage is { } message)
        {
            list.Visibility = Visibility.Collapsed;
            error.Visibility = Visibility.Visible;
            var label = Text.Make(message, TextStyle.Caption, Token.Danger);
            label.HorizontalAlignment = HorizontalAlignment.Center;
            label.Margin = new Thickness(0, 0, 0, Space.S3);
            error.Children.Add(label);
            error.Children.Add(new KeyButton(L.T("Tentar de novo"), null, browser.Reload) { HorizontalAlignment = HorizontalAlignment.Center });
            return;
        }
        if (browser.Location != null && browser.Entries.Count == 0)
        {
            list.Visibility = Visibility.Collapsed;
            if (browser.IsLoading) loading.Start();
            else note.Text = L.T("Sem música nesta pasta");
            return;
        }
        list.Visibility = Visibility.Visible;
        rows = CurrentRows();
        list.Footer = browser.Location == null ? AddKeys() : null;
        var views = rows.Select(View).ToList();
        var select = selectAfter == null ? -1 : rows.FindIndex(r => r.Id == selectAfter);
        var previous = list.Selected >= 0 && list.Selected < list.Rows.Count && !ReferenceEquals(list.Rows, null) ? list.Selected : -1;
        list.SetRows(views, select >= 0 ? select : -1);
        selectAfter = null;
        foreach (var row in rows.OfType<EntryRow>().Where(r => r.Entry.Kind == EntryKind.Folder)) _ = browser.LoadSummary(row.Entry);
    }

    private List<Row> CurrentRows()
    {
        if (model.Browser.Location == null)
        {
            var open = model.Sources.Sources.Select(s => (Row)new SourceRow(s.Id, s.Name, QueueHeader.SourceIcon(s.Kind), null));
            var failed = model.Sources.Failed.OrderBy(f => f.Value).Select(f => (Row)new SourceRow(f.Key, f.Value, Icon.Drive, f.Value));
            return open.Concat(failed).ToList();
        }
        return model.Browser.Entries.Select(e => (Row)new EntryRow(e)).ToList();
    }

    private RowView View(Row row)
    {
        switch (row)
        {
            case SourceRow s:
                return new RowView { LeadingIcon = s.Icon, Name2 = s.Name, IsError = s.Error != null, ToolTip = s.Error ?? s.Name };
            case EntryRow { Entry.Kind: EntryKind.Folder } f:
                return new RowView { LeadingIcon = Icon.Folder, Name2 = f.Entry.Name, TrailingIsDuration = false, Trailing = model.Browser.Summaries.GetValueOrDefault(f.Entry.Id) ?? "", ToolTip = f.Entry.Name };
            case EntryRow t:
                model.Durations.Load(t.Entry);
                return new RowView
                {
                    Name2 = t.Entry.ListName,
                    Trailing = model.Durations.Get(t.Entry) is { } d ? TimeFormat.Short(d) : "",
                    Playing = model.Player.Current?.Entry == t.Entry,
                    ToolTip = t.Entry.Name,
                };
            default:
                throw new InvalidOperationException();
        }
    }

    /// <summary>The playing LED, durations and folder summaries, in place.</summary>
    public void RefreshRows()
    {
        if (list.Rows.Count != rows.Count) return;
        for (var i = 0; i < rows.Count; i++)
        {
            if (rows[i] is not EntryRow e) continue;
            if (e.Entry.Kind == EntryKind.Folder)
            {
                list.Rows[i].Trailing = model.Browser.Summaries.GetValueOrDefault(e.Entry.Id) ?? "";
            }
            else
            {
                list.Rows[i].Playing = model.Player.Current?.Entry == e.Entry;
                list.Rows[i].Trailing = model.Durations.Get(e.Entry) is { } d ? TimeFormat.Short(d) : "";
            }
        }
    }

    private UIElement AddKeys()
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, Space.S3, 0, Space.S3) };
        row.Children.Add(new KeyButton(L.T("Adicionar pasta"), "Ctrl+O", () => model.AddFolder(owner)));
        row.Children.Add(new KeyButton(L.T("Adicionar Jellyfin"), "Ctrl+Shift+O", () => App.Current.AddJellyfin()) { Margin = new Thickness(Space.S2, 0, 0, 0) });
        return row;
    }

    private ContextMenu Menu(Row row)
    {
        var menu = new ContextMenu();
        switch (row)
        {
            case SourceRow s:
                if (model.Sources.Source(s.SourceId)?.Kind == SourceKind.CD) menu.Items.Add(QueueView.Item(L.T("Ejetar CD"), () => App.Current.EjectDisc(s.SourceId)));
                else menu.Items.Add(QueueView.Item(L.T("Remover fonte"), () => model.RemoveSource(s.SourceId)));
                break;
            case EntryRow { Entry.Kind: EntryKind.Folder } f:
                menu.Items.Add(QueueView.Item(L.T("Tocar pasta"), () => _ = model.PlayFolder(new BrowserLocation(f.Entry.SourceId, f.Entry.Path))));
                menu.Items.Add(QueueView.Item(L.T("Adicionar à fila") + "\tCtrl+Enter", () => _ = model.Enqueue(f.Entry)));
                break;
            case EntryRow t:
                menu.Items.Add(QueueView.Item(L.T("Tocar"), () => Activate(row)));
                menu.Items.Add(QueueView.Item(L.T("Adicionar à fila") + "\tCtrl+Enter", () => _ = model.Enqueue(t.Entry)));
                break;
        }
        return menu;
    }

    private void Activate(Row row)
    {
        switch (row)
        {
            case SourceRow s:
                // A missing folder: try it again (the disk may be back) before giving up.
                if (s.Error != null && !model.Sources.RetryFailed(s.SourceId))
                {
                    System.Media.SystemSounds.Beep.Play();
                    return;
                }
                model.Browser.Open(new BrowserLocation(s.SourceId, ""));
                break;
            case EntryRow { Entry.Kind: EntryKind.Folder } f:
                model.Browser.Enter(f.Entry);
                break;
            case EntryRow t:
                _ = model.PlayFolder(new BrowserLocation(t.Entry.SourceId, t.Entry.ParentPath), t.Entry);
                break;
        }
    }

    private void OnKey(object sender, KeyEventArgs e)
    {
        var selected = list.Selected >= 0 && list.Selected < rows.Count ? rows[list.Selected] : null;
        if (Keyboard.Modifiers == ModifierKeys.None && e.Key is Key.Left or Key.Back)
        {
            model.Browser.Up();
            e.Handled = true;
        }
        else if (Keyboard.Modifiers == ModifierKeys.None && e.Key == Key.Right && selected is EntryRow { Entry.Kind: EntryKind.Folder })
        {
            Activate(selected);
            e.Handled = true;
        }
        else if (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.Enter && selected is EntryRow add)
        {
            _ = model.Enqueue(add.Entry);
            e.Handled = true;
        }
    }

    private static string? CameFrom(BrowserLocation? old, BrowserLocation? now)
    {
        if (old == null) return null;
        if (now == null) return $"source/{old.SourceId}";
        var isParent = now.SourceId == old.SourceId && old.Path.Length > 0 && Paths.Parent(old.Path) == now.Path;
        return isParent ? $"{old.SourceId}/{old.Path}" : null;
    }
}
