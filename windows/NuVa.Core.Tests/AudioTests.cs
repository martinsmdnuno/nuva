using System;
using System.Linq;
using NuVa.Core.Audio;

namespace NuVa.Core.Tests;

/// <summary>The same checks as the Android port's AudioTest (and the Mac's SpectrumTests).</summary>
public static class AudioTests
{
    /// <summary>A stereo sine through the analyzer.</summary>
    private static SpectrumShared Measure(double frequency, float amplitude, int rate, float? right = null)
    {
        var analyzer = new SpectrumAnalyzer(rate);
        var shared = new SpectrumShared();
        const int frames = 1024;
        var block = new float[frames * 2];
        var n = 0;
        for (var round = 0; round < 40; round++)
        {
            for (var j = 0; j < frames; j++)
            {
                var v = (float)Math.Sin(2 * Math.PI * frequency * (n + j) / rate);
                block[2 * j] = amplitude * v;
                block[2 * j + 1] = (right ?? amplitude) * v;
            }
            n += frames;
            analyzer.Process(block, 2, frames, (double)n / rate, shared);
        }
        return shared;
    }

    [Test]
    public static void FullScaleSineReadsZeroInItsBand()
    {
        foreach (var rate in new[] { 44_100, 96_000, 192_000 })
        {
            var levels = Measure(1000, 1, rate).Levels(40 * 1024.0 / rate, 1)!;
            Assert.True(Math.Abs(levels[5]) < 1.5f, $"rate {rate}: {levels[5]}");
            foreach (var b in new[] { 0, 1, 2, 8, 9 }) Assert.True(levels[b] < -40, $"rate {rate} band {b}: {levels[b]}");
        }
    }

    [Test]
    public static void StereoLevelsAreRmsAndPeak()
    {
        var stereo = Measure(1000, 0.1f, 48_000, right: 0).Stereo(40 * 1024.0 / 48_000, 1)!;
        Assert.Near(-23, stereo[0], 0.5);
        Assert.Near(-20, stereo[2], 0.5);
        Assert.True(stereo[1] < -100);
    }

    [Test]
    public static void BassBandsAreToldApart()
    {
        var fine = Measure(40, 0.5f, 48_000).FineLevels(40 * 1024.0 / 48_000, 1)!;
        var loudest = Enumerable.Range(0, fine.Length).MaxBy(i => fine[i]);
        var centre = SpectrumShared.FineCentres[loudest];
        Assert.True(centre > 32 && centre < 50, $"centre {centre}");
        Assert.True(fine[0] < fine[loudest] - 10);
    }

    [Test]
    public static void LookupBlendsTheMeasurementsAroundTheTime()
    {
        var shared = new SpectrumShared();
        shared.Write(10, Enumerable.Repeat(-10f, 10).ToArray(), new float[28], [-10, -10, -10, -10]);
        shared.Write(10.1, Enumerable.Repeat(-30f, 10).ToArray(), new float[28], [-30, -30, -30, -30]);
        Assert.Near(-20, shared.Levels(10.05)![0], 0.01);
        Assert.Equal(null, shared.Levels(11));
    }

    [Test]
    public static void EqualizerBoostsItsBandAndKeepsHeadroom()
    {
        const int rate = 48_000;
        var gains = new float[10];
        gains[5] = 12;
        var filter = new EqFilter();
        const int frames = 48_000;
        var samples = Enumerable.Range(0, frames).Select(i => (float)Math.Sin(2 * Math.PI * 1000 * i / rate) * 0.25f).ToArray();
        filter.Process(samples, frames, 1, rate, new Equalizer.Snapshot(gains, true, 1));
        var peak = samples.Skip(frames / 2).Max(Math.Abs);
        // +12 dB at 1 kHz with -12 dB of pre-gain: the 1 kHz tone comes out at the same level.
        Assert.Near(0.25, peak, 0.02);
        var off = new[] { 0.5f, 0.5f, 0.5f, 0.5f };
        Assert.True(!new EqFilter().Process(off, 4, 1, rate, new Equalizer.Snapshot(new float[10], false, 1)));
        Assert.Equal(0.5f, off[0]);
    }

    [Test]
    public static void PresetsAndNudges()
    {
        var eq = new Equalizer(new Settings(null));
        Assert.Equal("Plano", eq.Preset);
        eq.Apply(Equalizer.Presets[5]);
        Assert.Equal("Rock", eq.Preset);
        Assert.True(eq.Enabled);
        eq.Nudge(0, 1);
        Assert.Equal(4.5f, eq.Gains[0]);
        Assert.Equal(Equalizer.Custom, eq.Preset);
        eq.Nudge(0, -1);
        Assert.Equal("Rock", eq.Preset);
        for (var i = 0; i < 40; i++) eq.Nudge(1, 1);
        Assert.Equal(12f, eq.Gains[1]);
    }
}
