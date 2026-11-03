using System;
using System.Linq;

namespace NuVa.Core.Player;

/// <summary>
/// Ambient mode's glow from the cover (ArtworkGlow.swift, by way of the Android port): the cover reduced
/// to a 4 × 4 grid of its own colours, each darkened until display-muted keeps 4.5:1 on it, blurred into a
/// soft field that keeps the cover's layout, falling towards the display's colour at the edges.
/// Colours are 0xRRGGBB.
/// </summary>
public static class ArtworkGlow
{
    private const int Grid = 4;
    public const int Width = 64, Height = 40;

    /// <param name="cover">The cover scaled to 16 × 16, row by row.</param>
    /// <returns>A 64 × 40 field, or null when the display is too light for any glow under muted text.</returns>
    public static uint[]? Field(uint[] cover, uint display, uint muted)
    {
        var ceiling = (Luminance(muted) + 0.05) / 4.5 - 0.05;
        if (ceiling <= Luminance(display) + 0.002 || cover.Length < 256) return null;
        var cells = new uint[Grid * Grid];
        for (var cell = 0; cell < cells.Length; cell++)
        {
            int row = cell / Grid, column = cell % Grid;
            double r = 0, g = 0, b = 0;
            for (var y = row * 4; y < row * 4 + 4; y++)
                for (var x = column * 4; x < column * 4 + 4; x++)
                {
                    var p = cover[y * 16 + x];
                    r += (p >> 16) & 0xFF; g += (p >> 8) & 0xFF; b += p & 0xFF;
                }
            cells[cell] = Rgb(r / 16, g / 16, b / 16);
        }
        var brightest = cells.Max(Luminance);
        var safe = ceiling * 0.95;
        var shaded = cells.Select(c => Shade(c, brightest > 0 ? Luminance(c) / brightest : 0, safe)).ToArray();

        var field = new uint[Width * Height];
        for (var y = 0; y < Height; y++)
            for (var x = 0; x < Width; x++)
            {
                // Bilinear between cell centres, then a vignette towards the display colour.
                var gx = (x + 0.5) / Width * Grid - 0.5;
                var gy = (y + 0.5) / Height * Grid - 0.5;
                var x0 = Math.Clamp((int)gx, 0, Grid - 1); var x1 = Math.Min(x0 + 1, Grid - 1);
                var y0 = Math.Clamp((int)gy, 0, Grid - 1); var y1 = Math.Min(y0 + 1, Grid - 1);
                var fx = Math.Clamp(gx - x0, 0, 1); var fy = Math.Clamp(gy - y0, 0, 1);
                var dx = (x + 0.5) / Width - 0.5;
                var dy = ((y + 0.5) / Height - 0.5) * Height / Width;
                var edge = Math.Clamp((Math.Sqrt(dx * dx + dy * dy) - 0.22) / (0.62 - 0.22), 0, 1) * 0.55;
                double Channel(int shift)
                {
                    double C(uint c) => (c >> shift) & 0xFF;
                    var top = C(shaded[y0 * Grid + x0]) * (1 - fx) + C(shaded[y0 * Grid + x1]) * fx;
                    var bottom = C(shaded[y1 * Grid + x0]) * (1 - fx) + C(shaded[y1 * Grid + x1]) * fx;
                    return (top * (1 - fy) + bottom * fy) * (1 - edge) + C(display) * edge;
                }
                field[y * Width + x] = Rgb(Channel(16), Channel(8), Channel(0));
            }
        return Blur(Blur(field));
    }

    /// <summary>A 5-tap box blur, horizontal then vertical.</summary>
    private static uint[] Blur(uint[] px)
    {
        uint[] Pass(uint[] src, bool horizontal)
        {
            var dst = new uint[src.Length];
            for (var i = 0; i < src.Length; i++)
            {
                int x = i % Width, y = i / Width;
                int r = 0, g = 0, b = 0;
                for (var k = -2; k <= 2; k++)
                {
                    var j = horizontal ? y * Width + Math.Clamp(x + k, 0, Width - 1) : Math.Clamp(y + k, 0, Height - 1) * Width + x;
                    r += (int)((src[j] >> 16) & 0xFF); g += (int)((src[j] >> 8) & 0xFF); b += (int)(src[j] & 0xFF);
                }
                dst[i] = Rgb(r / 5.0, g / 5.0, b / 5.0);
            }
            return dst;
        }
        return Pass(Pass(px, true), false);
    }

    /// <summary>The colour's hue, a little more saturated, at a luminance from 40% of the ceiling (darkest parts) to all of it.</summary>
    private static uint Shade(uint color, double relative, double ceiling)
    {
        var (h, s, _) = ToHsv(color);
        var saturation = Math.Min(0.9, s * 1.15);
        var target = ceiling * (0.4 + 0.6 * Math.Clamp(relative, 0, 1));
        double low = 0, high = 1;
        for (var i = 0; i < 20; i++)
        {
            var middle = (low + high) / 2;
            if (Luminance(FromHsv(h, saturation, middle)) > target) high = middle; else low = middle;
        }
        return FromHsv(h, saturation, low);
    }

    /// <summary>WCAG relative luminance.</summary>
    public static double Luminance(uint c)
    {
        static double Linear(uint v)
        {
            var s = v / 255.0;
            return s <= 0.04045 ? s / 12.92 : Math.Pow((s + 0.055) / 1.055, 2.4);
        }
        return 0.2126 * Linear((c >> 16) & 0xFF) + 0.7152 * Linear((c >> 8) & 0xFF) + 0.0722 * Linear(c & 0xFF);
    }

    private static uint Rgb(double r, double g, double b) =>
        ((uint)Math.Clamp((int)r, 0, 255) << 16) | ((uint)Math.Clamp((int)g, 0, 255) << 8) | (uint)Math.Clamp((int)b, 0, 255);

    private static (double H, double S, double V) ToHsv(uint c)
    {
        double r = ((c >> 16) & 0xFF) / 255.0, g = ((c >> 8) & 0xFF) / 255.0, b = (c & 0xFF) / 255.0;
        var max = Math.Max(r, Math.Max(g, b));
        var min = Math.Min(r, Math.Min(g, b));
        var d = max - min;
        double h = 0;
        if (d > 0)
        {
            if (max == r) h = 60 * (((g - b) / d) % 6);
            else if (max == g) h = 60 * ((b - r) / d + 2);
            else h = 60 * ((r - g) / d + 4);
        }
        if (h < 0) h += 360;
        return (h, max == 0 ? 0 : d / max, max);
    }

    private static uint FromHsv(double h, double s, double v)
    {
        var c = v * s;
        var x = c * (1 - Math.Abs(h / 60 % 2 - 1));
        var m = v - c;
        var (r, g, b) = (int)(h / 60) switch
        {
            0 => (c, x, 0.0), 1 => (x, c, 0.0), 2 => (0.0, c, x), 3 => (0.0, x, c), 4 => (x, 0.0, c), _ => (c, 0.0, x),
        };
        return Rgb((r + m) * 255, (g + m) * 255, (b + m) * 255);
    }
}
