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
