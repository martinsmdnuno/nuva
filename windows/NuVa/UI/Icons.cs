using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;

namespace NuVa.UI;

/// <summary>
/// The keys' and lists' symbols, drawn after the SF Symbols the Mac uses (as android/…/ui/Icons.kt):
/// a 24 × 24 grid, regular weight (1.8 strokes, round), filled only for play and pause.
/// </summary>
public enum Icon
{
    Play, Pause, Previous, Next, Shuffle, Repeat, RepeatOne, Folders, Back, Folder, Drive, Server, Disc,
    Eject, Speaker, Ambient, Leave, Menu, Check,
}

public static class Icons
{
    private static readonly Dictionary<Icon, (Geometry Geometry, bool Filled)> cache = new();

    public static (Geometry Geometry, bool Filled) Get(Icon icon)
    {
        if (cache.TryGetValue(icon, out var found)) return found;
        var (data, filled) = icon switch
        {
            Icon.Play => ("M7,4.5 L19,12 L7,19.5 Z", true),
            Icon.Pause => ("M6.5,5 L10,5 L10,19 L6.5,19 Z M14,5 L17.5,5 L17.5,19 L14,19 Z", true),
            Icon.Previous => ("M6,5 L6,19 M18,5 L9,12 L18,19 Z", false),
            Icon.Next => ("M18,5 L18,19 M6,5 L15,12 L6,19 Z", false),
            Icon.Shuffle => ("M3,7 L7,7 C12,7 12,17 17,17 L21,17 M3,17 L7,17 C12,17 12,7 17,7 L21,7 M18,4 L21,7 L18,10 M18,14 L21,17 L18,20", false),
            Icon.Repeat => ("M4,11 L4,9 C4,7.9 4.9,7 6,7 L20,7 M17,4 L20,7 L17,10 M20,13 L20,15 C20,16.1 19.1,17 18,17 L4,17 M7,14 L4,17 L7,20", false),
            Icon.RepeatOne => ("M4,11 L4,9 C4,7.9 4.9,7 6,7 L20,7 M17,4 L20,7 L17,10 M20,13 L20,15 C20,16.1 19.1,17 18,17 L4,17 M7,14 L4,17 L7,20 M11,11 L12.5,10 L12.5,14.5", false),
            // sidebar.left: a window with its sidebar.
            Icon.Folders => ("M3,5 L21,5 L21,19 L3,19 Z M9,5 L9,19 M5,8.5 L7,8.5 M5,11.5 L7,11.5", false),
            Icon.Back => ("M15,5 L8,12 L15,19", false),
            Icon.Folder => ("M3,7 L3,18 L21,18 L21,9 L11,9 L9,7 Z", false),
            Icon.Drive => ("M3,8 L21,8 L21,16 L3,16 Z M17,12 L17.5,12", false),
            Icon.Server => ("M4,4 L20,4 L20,10 L4,10 Z M4,14 L20,14 L20,20 L4,20 Z M7,7 L8,7 M7,17 L8,17", false),
            Icon.Disc => ("M12,3 A9,9 0 1 1 11.99,3 Z M12,9.5 A2.5,2.5 0 1 1 11.99,9.5 Z", false),
            Icon.Eject => ("M12,5 L19,14 L5,14 Z M5,18.5 L19,18.5", false),
            // airplayaudio becomes a speaker: the system's output device.
            Icon.Speaker => ("M4,9 L8,9 L13,5 L13,19 L8,15 L4,15 Z M16.5,9 C18,10.5 18,13.5 16.5,15 M19,6.5 C22,9.5 22,14.5 19,17.5", false),
            Icon.Ambient => ("M3,5 L21,5 L21,17 L3,17 Z M8,20 L16,20", false),
            // arrow.down.right.and.arrow.up.left: leave full screen.
            Icon.Leave => ("M4,20 L10,14 M10,19 L10,14 L5,14 M20,4 L14,10 M14,5 L14,10 L19,10", false),
            Icon.Menu => ("M4,7 L20,7 M4,12 L20,12 M4,17 L20,17", false),
            Icon.Check => ("M5,12.5 L10,17 L19,7", false),
            _ => throw new ArgumentOutOfRangeException(nameof(icon)),
        };
        var geometry = Geometry.Parse(data);
        geometry.Freeze();
        cache[icon] = (geometry, filled);
        return cache[icon];
    }

    /// <summary>Draws an icon of <paramref name="size"/> px centred on <paramref name="centre"/>.</summary>
    public static void Draw(DrawingContext dc, Icon icon, Point centre, double size, Brush brush)
    {
        var (geometry, filled) = Get(icon);
        var scale = size / 24;
        dc.PushTransform(new TranslateTransform(centre.X - size / 2, centre.Y - size / 2));
        dc.PushTransform(new ScaleTransform(scale, scale));
        if (filled)
        {
            dc.DrawGeometry(brush, null, geometry);
        }
        else
        {
            // 1.8 on the 24 grid: SF's regular weight at the key sizes.
            var pen = new Pen(brush, 1.8) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
            dc.DrawGeometry(null, pen, geometry);
        }
        dc.Pop();
        dc.Pop();
    }
}

/// <summary>An icon as an element (lists, readouts).</summary>
public sealed class IconView : FrameworkElement
{
    private Icon icon;
    private Brush brush = Brushes.Gray;

    public IconView(Icon icon, double size)
    {
        this.icon = icon;
        Width = size;
        Height = size;
        IsHitTestVisible = false;
    }

    public Icon Icon
    {
        get => icon;
        set { icon = value; InvalidateVisual(); }
    }

    public Brush Brush
    {
        get => brush;
        set { brush = value; InvalidateVisual(); }
    }

    protected override void OnRender(DrawingContext dc) =>
        Icons.Draw(dc, icon, new Point(ActualWidth / 2, ActualHeight / 2), Math.Min(ActualWidth, ActualHeight), brush);
}
