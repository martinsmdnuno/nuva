using System;
using System.Collections.Generic;
using System.Windows.Media;
using Microsoft.Win32;
using NuVa.Core;

namespace NuVa.UI;

/// <summary>
/// The current skin's colours as WPF brushes. Rams follows Windows' app mode (Aluminium when light, Lead
/// when dark); the other skins are always dark. Views read <see cref="Brush"/> when they draw and redraw on
/// <see cref="Changed"/>.
/// </summary>
public static class Theme
{
    private static readonly Dictionary<(Token, bool), SolidColorBrush> cache = new();

    public static Skin Skin { get; private set; } = Skin.Rams;
    public static FontSet? FontChoice { get; private set; }
    public static FontSet FontSet => FontChoice ?? Skin.FontSet;
    /// <summary>Windows' "app mode" is dark.</summary>
    public static bool SystemDark { get; private set; } = ReadSystemDark();
    public static bool Dark => Skin.AlwaysDark || SystemDark;

    public static event Action? Changed;

    public static void Set(Skin skin, FontSet? fonts)
    {
        Skin = skin;
        FontChoice = fonts;
        Changed?.Invoke();
    }

    /// <summary>Re-reads the app mode (after WM_SETTINGCHANGE "ImmersiveColorSet").</summary>
    public static void RefreshSystem()
    {
        var dark = ReadSystemDark();
        if (dark == SystemDark) return;
        SystemDark = dark;
        Changed?.Invoke();
    }

    public static uint Hex(Token token) => Skin.Color(token, Dark);

    public static Color Color(Token token, double opacity = 1)
    {
        var hex = Hex(token);
        return System.Windows.Media.Color.FromArgb((byte)Math.Round(255 * opacity), (byte)(hex >> 16), (byte)(hex >> 8), (byte)hex);
    }

    public static SolidColorBrush Brush(Token token)
    {
        var hex = Hex(token);
        if (!cache.TryGetValue((token, Dark), out var brush) || brush.Color != Color(token))
        {
            brush = new SolidColorBrush(Color(token));
            brush.Freeze();
            cache[(token, Dark)] = brush;
        }
        return brush;
    }

    public static SolidColorBrush Brush(Token token, double opacity)
    {
        var brush = new SolidColorBrush(Color(token, opacity));
        brush.Freeze();
        return brush;
    }

    /// <summary>A token lifted by <paramref name="amount"/> (0–1) in each channel, as SwiftUI's brightness().</summary>
    public static SolidColorBrush Brighter(Token token, double amount)
    {
        var hex = Hex(token);
        byte Lift(uint channel) => (byte)Math.Min(255, Math.Round((channel & 0xFF) + 255 * amount));
        var brush = new SolidColorBrush(System.Windows.Media.Color.FromRgb(Lift(hex >> 16), Lift(hex >> 8), Lift(hex)));
        brush.Freeze();
        return brush;
    }

    /// <summary>A skin's 0xRRGGBB token value (<see cref="Skin.Color"/>) as a colour, with an opacity (0–1).</summary>
    public static Color Rgb(uint hex, double opacity = 1) =>
        System.Windows.Media.Color.FromArgb((byte)Math.Round(255 * Math.Clamp(opacity, 0, 1)), (byte)(hex >> 16), (byte)(hex >> 8), (byte)hex);

    /// <summary>Brush for a skin's 0xRRGGBB token value.</summary>
    public static SolidColorBrush Hex(uint hex, double opacity = 1)
    {
        var brush = new SolidColorBrush(Rgb(hex, opacity));
        brush.Freeze();
        return brush;
    }

    private static bool ReadSystemDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int light && light == 0;
        }
        catch
        {
            return true;
        }
    }
}
