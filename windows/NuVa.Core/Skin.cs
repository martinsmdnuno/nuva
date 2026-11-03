using System;
using System.Collections.Generic;
using System.Linq;

namespace NuVa.Core;

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

    // The values come from docs/design-system/tokens.json, through the generated TokenPalettes.cs.
    public static readonly Skin Rams = new("rams", "Rams", false, FontSet.Inter, new(TokenPalettes.Rams));

    /// <summary>Graphite Orange (skins/graphite.md). Only the accent differs from the retired green twin.</summary>
    public static readonly Skin GraphiteOrange = Dark("graphite-orange", "Graphite Orange", FontSet.System, TokenPalettes.GraphiteOrange);

    /// <summary>Phosphor (skins/phosphor.md): a black display with phosphor-green ink, a blue-grey chassis.</summary>
    public static readonly Skin Phosphor = Dark("phosphor", "Phosphor", FontSet.Inter, TokenPalettes.Phosphor);

    public static readonly Skin[] All = [Rams, GraphiteOrange, Phosphor];

    public static Skin With(string? id)
    {
        // "nuno" is Rams's id before 1.5; Graphite Green was retired in 1.10.1 for its orange twin.
        id = id == "nuno" ? "rams" : id == "graphite-green" ? "graphite-orange" : id;
        return All.FirstOrDefault(s => s.Id == id) ?? Rams;
    }

    private static Skin Dark(string id, string name, FontSet fontSet, IReadOnlyDictionary<Token, uint> values) =>
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
