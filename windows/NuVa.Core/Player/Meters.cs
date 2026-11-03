using System;
using System.Linq;

namespace NuVa.Core.Player;

/// <summary>
/// Ballistics, like a hardware meter (SpectrumMeter in SpectrumView.swift): a column jumps up to the
/// level and falls back at a steady rate; the peak holds for a moment, then falls too (steadily, or with
/// gravity, like the peak caps of a hi-fi spectrum analyser). Lives across frames.
/// </summary>
public sealed class SpectrumMeter
{
    public float Floor { get; }
    public float Ceiling { get; }
    /// <summary>Full scale per second.</summary>
    public float Fall { get; }
    /// <summary>Seconds a column takes to rise to a new level; 0 jumps at once.</summary>
    public float Attack { get; }
    public const float PeakFall = 0.6f;
    public const double PeakHold = 0.8;
    /// <summary>Full scale per second², for peaks that fall faster and faster; 0 falls at PeakFall.</summary>
    public float Gravity { get; }

    public float[] Levels { get; }
    public float[] Peaks { get; }
    private readonly double[] peakTimes;
    private readonly float[] peakSpeeds;
    private double? last;

    public SpectrumMeter(int count = 10, float floor = -54, float ceiling = -6, float fall = 1.6f, float attack = 0, float gravity = 0)
    {
        Floor = floor;
        Ceiling = ceiling;
        Fall = fall;
        Attack = attack;
        Gravity = gravity;
        Levels = new float[count];
        Peaks = new float[count];
        peakTimes = Enumerable.Repeat(double.NegativeInfinity, count).ToArray();
        peakSpeeds = new float[count];
    }

    /// <summary><paramref name="measured"/> in dBFS per column, or null when nothing plays (the columns fall). <paramref name="now"/> in seconds.</summary>
    public void Update(double now, float[]? measured)
    {
        var dt = (float)Math.Clamp(now - (last ?? now), 0, 0.1);
        last = now;
        for (var b = 0; b < Levels.Length; b++)
        {
            var target = measured == null ? 0 : Math.Clamp((measured[b] - Floor) / (Ceiling - Floor), 0, 1);
            if (target > Levels[b])
                Levels[b] = Attack > 0 ? Levels[b] + (target - Levels[b]) * Math.Min(1, dt / Attack) : target;
            else
                Levels[b] = Math.Max(target, Levels[b] - Fall * dt);
            if (Levels[b] >= Peaks[b])
            {
                Peaks[b] = Levels[b];
                peakTimes[b] = now;
                peakSpeeds[b] = 0;
            }
            else if (now - peakTimes[b] > PeakHold)
            {
                if (Gravity > 0)
                {
                    peakSpeeds[b] += Gravity * dt;
                    Peaks[b] = Math.Max(Levels[b], Peaks[b] - peakSpeeds[b] * dt);
                }
                else
                {
                    Peaks[b] = Math.Max(Levels[b], Peaks[b] - PeakFall * dt);
                }
            }
        }
    }
}

/// <summary>Left and right with their own ballistics: Levels is what the face draws, Peaks the last half second's highest, in dBFS.</summary>
public interface IStereoMeter
{
    float[] Levels { get; }
    float[] Peaks { get; }
    /// <summary>RMS L, RMS R, peak L, peak R in dBFS, or null when nothing plays.</summary>
    void Update(double now, float[]? measured);
}

/// <summary>Slow ballistics for the valves' filaments: they rise and fall over a fraction of a second, like a heater.</summary>
public sealed class SlowMeter(float floor, float ceiling, float rise, float fall) : IStereoMeter
{
    public float[] Levels { get; } = new float[2];
    public float[] Peaks { get; } = [-120f, -120f];
    private readonly double[] peakTimes = [double.NegativeInfinity, double.NegativeInfinity];
    private double? last;

    public void Update(double now, float[]? measured)
    {
        var dt = (float)Math.Clamp(now - (last ?? now), 0, 0.1);
        last = now;
        for (var c = 0; c < 2; c++)
        {
            var target = measured == null ? 0 : Math.Clamp((measured[c] - floor) / (ceiling - floor), 0, 1);
            var rate = target > Levels[c] ? rise : fall;
            Levels[c] += (target - Levels[c]) * Math.Min(1, rate * dt);
            Hold(Peaks, peakTimes, c, now, measured?[c + 2]);
        }
    }

    internal static void Hold(float[] peaks, double[] times, int c, double now, float? peak)
    {
        if (peak is { } p && p >= peaks[c])
        {
            peaks[c] = p;
            times[c] = now;
        }
        else if (now - times[c] > 0.5)
        {
            peaks[c] = peak ?? -120f;
        }
    }
}

/// <summary>
/// A VU meter's movement (VUNeedle.swift): a needle on a damped spring, driven by the signal's voltage.
/// Tuned to IEC 60268-17: 99% of a steady tone's reading in 300 ms, about 1.2% overshoot. It rests on a
/// pin left of the scale and bounces softly off the pins.
/// </summary>
public sealed class VUNeedle
{
    public const double Frequency = 13.5;
    public const double Damping = 0.81;
    public const double EndStop = 1.08;
    public const double Bounce = 0.2;

    /// <summary>Deflection for a level in VU: proportional to voltage, 1 at +3 VU.</summary>
    public static double Deflection(double vu) => Math.Pow(10, (vu - 3) / 20);

    public double Position { get; private set; }
    private double velocity;

    /// <summary>Moves dt seconds towards the target, in 1 ms steps so it is stable at any frame rate.</summary>
    public void Step(double target, double dt)
    {
        var remaining = Math.Clamp(dt, 0, 0.25);
        while (remaining > 0)
        {
            var h = Math.Min(remaining, 0.001);
            velocity += (Frequency * Frequency * (target - Position) - 2 * Damping * Frequency * velocity) * h;
            Position += velocity * h;
            if (Position < 0)
            {
                Position = 0;
                velocity = -velocity * Bounce;
            }
            else if (Position > EndStop)
            {
                Position = EndStop;
                velocity = -velocity * Bounce;
            }
            remaining -= h;
        }
    }
}

/// <summary>Two needles fed from the RMS levels; 0 VU is −14 dBFS RMS. Peaks held half a second, for the peak light.</summary>
public sealed class NeedleMeter : IStereoMeter
{
    public const float Reference = -14f;
    private readonly VUNeedle[] needles = [new(), new()];
    public float[] Levels { get; } = new float[2];
    public float[] Peaks { get; } = [-120f, -120f];
    private readonly double[] peakTimes = [double.NegativeInfinity, double.NegativeInfinity];
    private double? last;

    public void Update(double now, float[]? measured)
    {
        var dt = now - (last ?? now);
        last = now;
        for (var c = 0; c < 2; c++)
        {
            var target = measured == null ? 0 : VUNeedle.Deflection(measured[c] - Reference);
            needles[c].Step(target, dt);
            Levels[c] = (float)needles[c].Position;
            SlowMeter.Hold(Peaks, peakTimes, c, now, measured?[c + 2]);
        }
    }
}

/// <summary>The cover glow's breath: follows the bass's loudness, quick to swell (50 ms), slow to settle (450 ms).</summary>
public sealed class GlowPulse
{
    public double Level { get; private set; }
    private double? last;

    public double Update(double now, float[]? bands)
    {
        var dt = Math.Clamp(now - (last ?? now), 0, 0.1);
        last = now;
        var loudest = bands == null ? -120.0 : Math.Max(bands[0], Math.Max(bands[1], bands[2]));
        var target = Math.Clamp((loudest + 42) / 30, 0, 1);
        var time = target > Level ? 0.05 : 0.45;
        Level += (target - Level) * (1 - Math.Exp(-dt / time));
        return Level;
    }
}
