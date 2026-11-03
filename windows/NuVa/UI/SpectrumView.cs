using System;
using System.Windows;
using System.Windows.Media;
using NuVa.Core;
using NuVa.Core.Audio;
using NuVa.Core.Player;

namespace NuVa.UI;

/// <summary>
/// The spectrum meter on the display (Spectrum.md): the equalizer's 10 bands as columns of 12 LED
/// segments. Lit in led, unlit in display-track, the peak in display-ink. Moves only with the music:
/// drawn every frame while playing, and for 2 s after a pause so the columns fall instead of freezing.
/// </summary>
public sealed class SpectrumView : FrameworkElement
{
    public const int Segments = 12;
    private const double SegmentHeight = 3, SegmentGap = 1, ColumnGap = 3;
    public static readonly double MeterHeight = Segments * (SegmentHeight + SegmentGap) - SegmentGap;

    private readonly SpectrumShared spectrum;
    private readonly Func<(bool Playing, double Time)> clock;
    private readonly SpectrumMeter meter = new();
    private bool watching;
    private bool rendering;
    private DateTime settleUntil;

    /// <summary>For snapshots: a still moment instead of live levels.</summary>
    public float[]? Still { get; set; }

    public SpectrumView(SpectrumShared spectrum, Func<(bool Playing, double Time)> clock)
    {
        this.spectrum = spectrum;
        this.clock = clock;
        Height = MeterHeight;
        IsHitTestVisible = true;
        ToolTip = L.T("Espectro") + " Ctrl+Shift+V";
        Loaded += (_, _) => { if (!watching) { watching = true; spectrum.Watch(true); } Hook(); };
        Unloaded += (_, _) => { if (watching) { watching = false; spectrum.Watch(false); } Unhook(); };
    }

    /// <summary>Called when the player starts or stops.</summary>
    public void PlayingChanged(bool playing)
    {
        if (!playing) settleUntil = DateTime.UtcNow.AddSeconds(2);
        Hook();
    }

    private void Hook()
    {
        if (rendering || Still != null) return;
        rendering = true;
        CompositionTarget.Rendering += OnFrame;
    }

    private void Unhook()
    {
        if (!rendering) return;
        rendering = false;
        CompositionTarget.Rendering -= OnFrame;
    }

    private void OnFrame(object? sender, EventArgs e)
    {
        var (playing, time) = clock();
        meter.Update(Environment.TickCount64 / 1000.0, playing ? spectrum.Levels(time) : null);
        InvalidateVisual();
        if (!playing && DateTime.UtcNow > settleUntil) Unhook();
    }

    protected override void OnRender(DrawingContext dc)
    {
        var levels = Still ?? meter.Levels;
        var peaks = Still == null ? meter.Peaks : Array.ConvertAll(Still, v => v > 0 ? Math.Min(1, v + 0.2f) : 0);
        var columns = levels.Length;
        var width = (ActualWidth - ColumnGap * (columns - 1)) / columns;
        var led = Theme.Brush(Token.Led);
        var ink = Theme.Brush(Token.DisplayInk);
        var track = Theme.Brush(Token.DisplayTrack);
        for (var c = 0; c < columns; c++)
        {
            var x = c * (width + ColumnGap);
            var lit = (int)Math.Round(levels[c] * Segments);
            var peak = (int)Math.Round(peaks[c] * Segments) - 1;
            for (var s = 0; s < Segments; s++)
            {
                var y = ActualHeight - (s + 1) * (SegmentHeight + SegmentGap) + SegmentGap;
                var brush = s < lit ? led : s == peak && peak >= lit ? ink : track;
                dc.DrawRectangle(brush, null, new Rect(x, y, width, SegmentHeight));
            }
        }
    }
}
