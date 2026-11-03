using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using NuVa.Core;

namespace NuVa.UI;

/// <summary>
/// A list row (ListRow.md): folders in the browser, tracks in the queue, sources. 28px, no dividers.
/// Leading: an icon or the playing LED; the name in body (signal while playing, danger on error);
/// trailing: a duration in mono or a count in caption. Hover in surface-1, selection in surface-2.
/// </summary>
public sealed class RowView : FrameworkElement
{
    private bool selected;
    private bool playing;
    private string trailing = "";

    public Icon? LeadingIcon { get; init; }
    public string Name2 { get; init; } = "";
    public bool TrailingIsDuration { get; init; } = true;
    public bool IsError { get; init; }
    public object? Tag2 { get; init; }

    public RowView()
    {
        Height = Space.Row;
        SnapsToDevicePixels = true;
        MouseEnter += (_, _) => InvalidateVisual();
        MouseLeave += (_, _) => InvalidateVisual();
    }

    public bool Selected
    {
        get => selected;
        set { if (selected != value) { selected = value; InvalidateVisual(); } }
    }

    public bool Playing
    {
        get => playing;
        set { if (playing != value) { playing = value; InvalidateVisual(); } }
    }

    public string Trailing
    {
        get => trailing;
        set { if (trailing != value) { trailing = value ?? ""; InvalidateVisual(); } }
    }

    protected override void OnRender(DrawingContext dc)
    {
        var w = ActualWidth;
        var h = ActualHeight;
        var bounds = new Rect(0, 0, w, h);
        if (selected) dc.DrawRoundedRectangle(Theme.Brush(Token.Surface2), null, bounds, Space.RadiusSm, Space.RadiusSm);
        else if (IsMouseOver) dc.DrawRoundedRectangle(Theme.Brush(Token.Surface1), null, bounds, Space.RadiusSm, Space.RadiusSm);
        else dc.DrawRectangle(Brushes.Transparent, null, bounds);
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var x = Space.S2;
        if (LeadingIcon is { } icon)
        {
            Icons.Draw(dc, icon, new Point(x + 6, h / 2), 14, Theme.Brush(IsError ? Token.Danger : Token.InkMuted));
        }
        else if (playing)
        {
            dc.DrawEllipse(Theme.Brush(Token.Led), null, new Point(x + 6, h / 2), Space.Led / 2, Space.Led / 2);
        }
        x += 12 + Space.S2;
        var right = w - Space.S2;
        if (trailing.Length > 0)
        {
            var style = TrailingIsDuration ? TextStyle.Duration : TextStyle.Caption;
            var t = style.Format(trailing, Theme.Brush(Token.InkMuted), dpi);
            dc.DrawText(t, new Point(right - t.Width, (h - t.Height) / 2));
            right -= t.Width + Space.S2;
        }
        var color = IsError ? Token.Danger : playing ? Token.Signal : Token.Ink;
        var name = TextStyle.Body.Format(Name2, Theme.Brush(color), dpi, Math.Max(1, right - x));
        dc.DrawText(name, new Point(x, (h - name.Height) / 2));
    }
}

/// <summary>
/// A keyboard-first list of rows in a scroll view: ↑ ↓ select, Enter activates, a double-click
/// activates; the caller adds its own keys and menus. Rows are plain elements (albums are short).
/// </summary>
public sealed class RowList : ScrollViewer
{
    private readonly StackPanel panel = new();
    private readonly List<RowView> rows = [];
    private int selected = -1;
    private int dragFrom = -1;
    private Point dragStart;
    private bool dragging;
    private readonly Border dropLine = new() { Height = 2, IsHitTestVisible = false, VerticalAlignment = VerticalAlignment.Top, Visibility = Visibility.Collapsed };
    private readonly Grid host = new();

    public event Action<int>? Activated;
    public event Action<int>? SelectionChanged;
    /// <summary>A row dragged to before another (queue reorder). Null: rows don't move.</summary>
    public Action<int, int>? Reorder { get; set; }
    public Func<int, ContextMenu?>? MenuFor { get; set; }

    public RowList()
    {
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled;
        Focusable = true;
        FocusVisualStyle = null;
        Background = Brushes.Transparent;
        dropLine.Background = Theme.Brush(Token.Focus);
        host.Children.Add(panel);
        host.Children.Add(dropLine);
        Content = host;
        PreviewMouseLeftButtonDown += OnDown;
        PreviewMouseMove += OnMove;
        PreviewMouseLeftButtonUp += OnUp;
        MouseRightButtonUp += OnRight;
    }

    public IReadOnlyList<RowView> Rows => rows;
    public int Selected => selected;
    /// <summary>Extra content under the rows (the browser's add keys).</summary>
    public UIElement? Footer { get; set; }

    public void SetRows(IEnumerable<RowView> items, int select = -1)
    {
        panel.Children.Clear();
        rows.Clear();
        foreach (var row in items)
        {
            rows.Add(row);
            panel.Children.Add(row);
        }
        if (Footer != null) panel.Children.Add(Footer);
        selected = -1;
        if (select >= 0 && select < rows.Count) Select(select, scroll: true);
    }

    public void Select(int index, bool scroll = true)
    {
        if (selected >= 0 && selected < rows.Count) rows[selected].Selected = false;
        selected = index >= 0 && index < rows.Count ? index : -1;
        if (selected >= 0)
        {
            rows[selected].Selected = true;
            if (scroll) rows[selected].BringIntoView();
        }
        SelectionChanged?.Invoke(selected);
    }

    /// <summary>Scrolls a row to the middle (Ctrl+L, the current track).</summary>
    public void Reveal(int index)
    {
        if (index < 0 || index >= rows.Count) return;
        Select(index, scroll: false);
        UpdateLayout();
        var top = rows[index].TranslatePoint(new Point(0, 0), panel).Y;
        ScrollToVerticalOffset(Math.Max(0, top - ViewportHeight / 2 + Space.Row / 2));
    }

    private int RowAt(MouseEventArgs e)
    {
        var y = e.GetPosition(panel).Y;
        var i = (int)Math.Floor(y / Space.Row);
        return i >= 0 && i < rows.Count ? i : -1;
    }

    private void OnDown(object sender, MouseButtonEventArgs e)
    {
        var i = RowAt(e);
        if (i < 0) return;
        Focus();
        Select(i, scroll: false);
        if (e.ClickCount == 2)
        {
            Activated?.Invoke(i);
            e.Handled = true;
            return;
        }
        dragFrom = Reorder != null ? i : -1;
        dragStart = e.GetPosition(panel);
    }

    private void OnMove(object sender, MouseEventArgs e)
    {
        if (dragFrom < 0 || e.LeftButton != MouseButtonState.Pressed) return;
        var p = e.GetPosition(panel);
        if (!dragging && Math.Abs(p.Y - dragStart.Y) < 6) return;
        if (!dragging)
        {
            dragging = true;
            CaptureMouse();
        }
        var target = Math.Clamp((int)Math.Round(p.Y / Space.Row), 0, rows.Count);
        dropLine.Margin = new Thickness(Space.S2, target * Space.Row - 1, Space.S2, 0);
        dropLine.Visibility = Visibility.Visible;
    }

    private void OnUp(object sender, MouseButtonEventArgs e)
    {
        if (dragging)
        {
            var target = Math.Clamp((int)Math.Round(e.GetPosition(panel).Y / Space.Row), 0, rows.Count);
            var from = dragFrom;
            dragging = false;
            dropLine.Visibility = Visibility.Collapsed;
            ReleaseMouseCapture();
            if (target != from && target != from + 1) Reorder?.Invoke(from, target);
            e.Handled = true;
        }
        dragFrom = -1;
    }

    private void OnRight(object sender, MouseButtonEventArgs e)
    {
        var i = RowAt(e);
        if (i < 0 || MenuFor?.Invoke(i) is not { } menu) return;
        Select(i, scroll: false);
        menu.PlacementTarget = this;
        menu.IsOpen = true;
        e.Handled = true;
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (Keyboard.Modifiers == ModifierKeys.None)
        {
            switch (e.Key)
            {
                case Key.Up:
                    MoveSelection(-1);
                    e.Handled = true;
                    return;
                case Key.Down:
                    MoveSelection(1);
                    e.Handled = true;
                    return;
                case Key.Enter:
                    if (selected >= 0) Activated?.Invoke(selected);
                    e.Handled = true;
                    return;
                case Key.Home:
                    if (rows.Count > 0) Select(0);
                    e.Handled = true;
                    return;
                case Key.End:
                    if (rows.Count > 0) Select(rows.Count - 1);
                    e.Handled = true;
                    return;
            }
        }
        base.OnKeyDown(e);
    }

    public void MoveSelection(int delta)
    {
        if (rows.Count == 0) return;
        var current = selected >= 0 ? selected : delta > 0 ? -1 : rows.Count;
        Select(Math.Clamp(current + delta, 0, rows.Count - 1));
    }
}
