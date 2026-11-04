using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using NuVa.Core;

namespace NuVa.UI;

/// <summary>A design-system text style: family (sans or mono), size in px and weight.</summary>
public readonly record struct TextStyle(bool Mono, double Size, int Weight)
{
    public static readonly TextStyle DisplayTime = new(true, 28, 300);
    public static readonly TextStyle DisplayTimeMini = new(true, 17, 400);
    public static readonly TextStyle DisplayMeta = new(true, 11, 400);
    public static readonly TextStyle Title = new(false, 15, 500);
    public static readonly TextStyle Body = new(false, 13, 400);
    public static readonly TextStyle Label = new(false, 11, 500);
    public static readonly TextStyle Caption = new(false, 11, 400);
    /// <summary>Legend printed on the chassis, always lowercase.</summary>
    public static readonly TextStyle Legend = new(false, 10, 400);
    public static readonly TextStyle Duration = new(true, 12, 400);
    public static readonly TextStyle Scale = new(true, 9, 400);
    public static readonly TextStyle Hint = new(true, 10, 400);
    /// <summary>A document's title (Terms and Privacy).</summary>
    public static readonly TextStyle DocumentTitle = new(false, 20, 600);

    public TextStyle Sized(double size) => this with { Size = size };

    public FontFamily Family => Mono ? Fonts.Mono(Theme.FontSet) : Fonts.Sans(Theme.FontSet);
    public FontWeight FontWeight => FontWeight.FromOpenTypeWeight(Weight);

    public Typeface Typeface => new(Family, FontStyles.Normal, FontWeight, FontStretches.Normal);

    /// <summary>Applies the style to a TextBlock.</summary>
    public void Apply(TextBlock block)
    {
        block.FontFamily = Family;
        block.FontSize = Size;
        block.FontWeight = FontWeight;
        if (Mono) Typography.SetNumeralAlignment(block, FontNumeralAlignment.Tabular);
    }

    /// <summary>Text laid out for drawing in OnRender.</summary>
    public FormattedText Format(string text, Brush brush, double pixelsPerDip, double maxWidth = 0)
    {
        var formatted = new FormattedText(text ?? "", System.Globalization.CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight, Typeface, Size, brush, pixelsPerDip)
        {
            Trimming = TextTrimming.CharacterEllipsis,
            MaxLineCount = 1,
        };
        if (maxWidth > 0) formatted.MaxTextWidth = Math.Max(1, maxWidth);
        return formatted;
    }
}

/// <summary>The embedded font families (OFL), and the system's for the Segoe set.</summary>
public static class Fonts
{
    private static readonly Uri root = new("pack://application:,,,/NuVa;component/Fonts/");

    private static FontFamily Embedded(string family, string fallback) => new(root, $"./#{family}, {fallback}");

    private static readonly FontFamily inter = Embedded("Inter", "Segoe UI");
    private static readonly FontFamily plexSans = Embedded("IBM Plex Sans", "Segoe UI");
    private static readonly FontFamily dmSans = Embedded("DM Sans", "Segoe UI");
    private static readonly FontFamily shareTech = Embedded("Share Tech", "Segoe UI");
    private static readonly FontFamily segoe = new("Segoe UI Variable Text, Segoe UI");
    private static readonly FontFamily plexMono = Embedded("IBM Plex Mono", "Consolas");
    private static readonly FontFamily dmMono = Embedded("DM Mono", "Consolas");
    private static readonly FontFamily shareTechMono = Embedded("Share Tech Mono", "Consolas");
    private static readonly FontFamily cascadia = new("Cascadia Mono, Consolas");

    public static FontFamily Sans(FontSet set) => set switch
    {
        FontSet.Inter => inter,
        FontSet.System => segoe,
        FontSet.Plex => plexSans,
        FontSet.DM => dmSans,
        _ => shareTech,
    };

    public static FontFamily Mono(FontSet set) => set switch
    {
        FontSet.Inter or FontSet.Plex => plexMono,
        FontSet.DM => dmMono,
        FontSet.ShareTech => shareTechMono,
        _ => cascadia,
    };
}
