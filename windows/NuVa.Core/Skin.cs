using System;
using System.Collections.Generic;
using System.Linq;

namespace NuVa.Core;

/// <summary>The design system's colour tokens (docs/design-system/tokens.json).</summary>
public enum Token
{
    Surface0, Surface1, Surface2, Display, DisplayInk, DisplayMuted, DisplayTrack, Ink, InkMuted, Line,
    KeyFace, KeyMode, KeyPlay, KeyInk, KeyModeInk, Track, Fill, Led, LedOff, Signal, Danger, Focus,
}

/// <summary>The families behind the text styles. Sizes and weights are the same in every set; only the family changes.</summary>
public enum FontSet { Inter, System, Plex, DM, ShareTech }

public static class FontSets
{
    public static readonly FontSet[] All = [FontSet.Inter, FontSet.System, FontSet.Plex, FontSet.DM, FontSet.ShareTech];

    public static string Name(FontSet set) => set switch
    {
        FontSet.Inter => "Inter + IBM Plex Mono",
        // The Mac's SF Pro + SF Mono: Windows' own interface and code fonts.
        FontSet.System => "Segoe UI + Cascadia Mono",
        FontSet.Plex => "IBM Plex Sans + Plex Mono",
        FontSet.DM => "DM Sans + DM Mono",
        _ => "Share Tech + Share Tech Mono",
    };

    public static string Id(FontSet set) => set switch
    {
        FontSet.Inter => "inter", FontSet.System => "system", FontSet.Plex => "plex", FontSet.DM => "dm", _ => "shareTech",
    };

    public static FontSet? FromId(string? id) => All.Cast<FontSet?>().FirstOrDefault(s => Id(s!.Value) == id);
}

/// <summary>A skin: colours, appearance policy and default font set. Same layout and sizes in every skin (port of Skin.swift).</summary>
public sealed class Skin
{
    public string Id { get; }
    public string Name { get; }
    /// <summary>True: always the dark values. False: light and dark follow Windows' app mode (Rams).</summary>
    public bool AlwaysDark { get; }
    public FontSet FontSet { get; }
    private readonly Dictionary<Token, (uint Light, uint Dark)> palette;

    private Skin(string id, string name, bool alwaysDark, FontSet fontSet, Dictionary<Token, (uint, uint)> palette)
    {
        Id = id; Name = name; AlwaysDark = alwaysDark; FontSet = fontSet; this.palette = palette;
    }

    /// <summary>The token's sRGB value as 0xRRGGBB.</summary>
    public uint Color(Token token, bool dark)
    {
        var pair = palette[token];
        return dark || AlwaysDark ? pair.Dark : pair.Light;
    }

    // Rams: Lead (chumbo, dark) and Aluminium (aluminio, light), from tokens.json.
    public static readonly Skin Rams = new("rams", "Rams", false, FontSet.Inter, new()
    {
        [Token.Surface0] = (0xE4E3E0, 0x1E2023),
        [Token.Surface1] = (0xF2F1EE, 0x2B2D30),
        [Token.Surface2] = (0xFFFFFF, 0x36393D),
        [Token.Display] = (0x1A1C1E, 0x141517),
        [Token.DisplayInk] = (0xE8E6E1, 0xE8E6E1),
        [Token.DisplayMuted] = (0x8E8C87, 0x8E8C87),
        [Token.DisplayTrack] = (0x2E3033, 0x2E3033),
        [Token.Ink] = (0x1E2023, 0xE8E6E1),
        [Token.InkMuted] = (0x55575B, 0xA6A49F),
        [Token.Line] = (0xCFCDC8, 0x44474B),
        [Token.KeyFace] = (0x7E7C77, 0xC9C6BF),
        [Token.KeyMode] = (0x3A3D41, 0x6B6E73),
        [Token.KeyPlay] = (0xAE7410, 0xE0A93E),
        [Token.KeyInk] = (0x0E0F10, 0x1E2023),
        [Token.KeyModeInk] = (0xE8E6E1, 0xF8F7F4),
        [Token.Track] = (0xCFCDC8, 0x44474B),
        [Token.Fill] = (0x3A3D41, 0xC9C6BF),
        [Token.Led] = (0xAE7410, 0xE0A93E),
        [Token.LedOff] = (0xCFCDC8, 0x3A3D41),
        [Token.Signal] = (0x845A0D, 0xE0A93E),
        [Token.Danger] = (0xB0362E, 0xEE7A72),
        [Token.Focus] = (0x2F6DB5, 0x8FB4E3),
    });

    /// <summary>Graphite Orange (skins/graphite.md). Only the accent differs from the retired green twin.</summary>
    public static readonly Skin GraphiteOrange = Dark("graphite-orange", "Graphite Orange", FontSet.System, new()
    {
        [Token.Surface0] = 0x0B0F10,
        [Token.Surface1] = 0x1C2427,
        [Token.Surface2] = 0x382E22,
        [Token.Display] = 0x050708,
        [Token.DisplayInk] = 0xF2F4F5,
        [Token.DisplayMuted] = 0x9AA3A7,
        [Token.DisplayTrack] = 0x252C2F,
        [Token.Ink] = 0xF2F4F5,
        [Token.InkMuted] = 0x9AA3A7,
        [Token.Line] = 0x2A3032,
        [Token.KeyFace] = 0xC9CED0,
        [Token.KeyMode] = 0x5B656C,
        [Token.KeyPlay] = 0xFF6A00,
        [Token.KeyInk] = 0x0B0F10,
        [Token.KeyModeInk] = 0xF2F4F5,
        [Token.Track] = 0x363E41,
        [Token.Fill] = 0xC9CED0,
        [Token.Led] = 0xFF6A00,
        [Token.LedOff] = 0x2A3032,
        [Token.Signal] = 0xFF6A00,
        [Token.Danger] = 0xFF6F8A,
        [Token.Focus] = 0x8FB4E3,
    });

    /// <summary>Phosphor (skins/phosphor.md): a black display with phosphor-green ink, a blue-grey chassis.</summary>
    public static readonly Skin Phosphor = Dark("phosphor", "Phosphor", FontSet.Inter, new()
    {
        [Token.Surface0] = 0x1C1C2B,
        [Token.Surface1] = 0x2C2C44,
        [Token.Surface2] = 0x1B2A8F,
        [Token.Display] = 0x000000,
        [Token.DisplayInk] = 0x00E838,
        [Token.DisplayMuted] = 0x1FA83C,
        [Token.DisplayTrack] = 0x0E3A18,
        [Token.Ink] = 0xD8DCE6,
        [Token.InkMuted] = 0xA4A8BE,
        [Token.Line] = 0x34344C,
        [Token.KeyFace] = 0xB6BACB,
        [Token.KeyMode] = 0x66668E,
        [Token.KeyPlay] = 0x00D02A,
        [Token.KeyInk] = 0x10101C,
        [Token.KeyModeInk] = 0xF6F7FB,
        [Token.Track] = 0x3E3E58,
        [Token.Fill] = 0xB6BACB,
        [Token.Led] = 0x00D02A,
        [Token.LedOff] = 0x34344C,
        [Token.Signal] = 0x00D02A,
        [Token.Danger] = 0xFF6B6B,
        [Token.Focus] = 0xF2C744,
    });

    public static readonly Skin[] All = [Rams, GraphiteOrange, Phosphor];

    public static Skin With(string? id)
    {
        // "nuno" is Rams's id before 1.5; Graphite Green was retired in 1.10.1 for its orange twin.
        id = id == "nuno" ? "rams" : id == "graphite-green" ? "graphite-orange" : id;
        return All.FirstOrDefault(s => s.Id == id) ?? Rams;
    }

    private static Skin Dark(string id, string name, FontSet fontSet, Dictionary<Token, uint> values) =>
        new(id, name, true, fontSet, values.ToDictionary(kv => kv.Key, kv => (kv.Value, kv.Value)));

    /// <summary>WCAG contrast ratio of two sRGB colours.</summary>
    public static double Contrast(uint a, uint b)
    {
        double L(uint c)
        {
            double Ch(uint v) { var s = v / 255.0; return s <= 0.03928 ? s / 12.92 : Math.Pow((s + 0.055) / 1.055, 2.4); }
            return 0.2126 * Ch((c >> 16) & 0xFF) + 0.7152 * Ch((c >> 8) & 0xFF) + 0.0722 * Ch(c & 0xFF);
        }
        double la = L(a), lb = L(b);
        return (Math.Max(la, lb) + 0.05) / (Math.Min(la, lb) + 0.05);
    }
}
