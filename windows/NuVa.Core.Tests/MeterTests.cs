using System;
using NuVa.Core.Player;

namespace NuVa.Core.Tests;

public static class MeterTests
{
    [Test]
    public static void NeedleReachesItsReadingInThreeHundredMilliseconds()
    {
        var needle = new VUNeedle();
        var target = VUNeedle.Deflection(0);
        var max = 0.0;
        for (var t = 0; t < 300; t++) { needle.Step(target, 0.001); max = Math.Max(max, needle.Position); }
        Assert.Near(target, needle.Position, target * 0.02);
        for (var t = 0; t < 700; t++) { needle.Step(target, 0.001); max = Math.Max(max, needle.Position); }
        Assert.True(max < target * 1.03, $"overshoot {max / target}");
        Assert.Near(0.708, target, 0.01);
    }

    [Test]
    public static void ColumnsJumpUpAndFallSteadily()
    {
        var meter = new SpectrumMeter(1);
        meter.Update(0, [-6]);
        Assert.Equal(1f, meter.Levels[0]);
        meter.Update(0.1, null);
        Assert.Near(1 - 0.16, meter.Levels[0], 0.001);
        Assert.Equal(1f, meter.Peaks[0]);
    }
}
