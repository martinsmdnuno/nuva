using System;
using System.Linq;

namespace NuVa.Core.Audio;

/// <summary>
/// Levels of the equalizer's 10 bands, the ambient face's 28 fine bands, and left and right, measured
/// after the equalizer so the meters show what is heard. Each measurement carries its track time: the
/// tap runs ahead of the speakers, and the display asks for the moment being played. A port of
/// Spectrum.swift (by way of the Android port).
/// </summary>
public sealed class SpectrumShared
{
    public const int Bands = 10;
    public const int FineBands = 28;
    /// <summary>28 bands evenly spaced in log frequency from 20 Hz to 20 kHz.</summary>
    public static readonly double[] FineCentres = Enumerable.Range(0, FineBands).Select(i => 20 * Math.Pow(1000, (i + 0.5) / FineBands)).ToArray();
    /// <summary>About 4 s of measurements at 120 a second, more than the output's buffer.</summary>
    public const int Capacity = 512;

    private readonly double[] times = Enumerable.Repeat(-1.0, Capacity).ToArray();
    private readonly float[] levels = new float[Capacity * Bands];
    private readonly float[] fine = Enumerable.Repeat(-120f, Capacity * FineBands).ToArray();
    /// <summary>Per measurement: RMS left, RMS right, peak left, peak right, in dBFS.</summary>
    private readonly float[] stereo = Enumerable.Repeat(-120f, Capacity * 4).ToArray();
    private int next;
    private int watchers;
    private readonly object gate = new();

    /// <summary>Meters on screen. With none, nothing is measured.</summary>
    public bool IsWatched
    {
        get { lock (gate) return watchers > 0; }
    }

    public void Watch(bool on)
    {
        lock (gate) watchers = Math.Max(0, watchers + (on ? 1 : -1));
    }

    /// <summary>Forgets everything: a seek or a new chain.</summary>
    public void Clear()
    {
        lock (gate) Array.Fill(times, -1);
    }

    public void Write(double time, float[] levels, float[] fine, float[] stereo)
    {
        lock (gate)
        {
            var i = next;
            times[i] = time;
            Array.Copy(levels, 0, this.levels, i * Bands, Bands);
            Array.Copy(fine, 0, this.fine, i * FineBands, FineBands);
            Array.Copy(stereo, 0, this.stereo, i * 4, 4);
            next = (i + 1) % Capacity;
        }
    }

    /// <summary>Band levels at <paramref name="time"/>, between the measurements either side, or null when none is close.</summary>
    public float[]? Levels(double time, double tolerance = 0.15) => Read(levels, Bands, time, tolerance);
    public float[]? FineLevels(double time, double tolerance = 0.15) => Read(fine, FineBands, time, tolerance);
    /// <summary>RMS L, RMS R, peak L, peak R in dBFS at <paramref name="time"/>.</summary>
    public float[]? Stereo(double time, double tolerance = 0.15) => Read(stereo, 4, time, tolerance);

    private float[]? Read(float[] values, int width, double time, double tolerance)
    {
        lock (gate)
        {
            int before = -1, after = -1;
            double early = double.NegativeInfinity, late = double.PositiveInfinity;
            for (var i = 0; i < Capacity; i++)
            {
                var t = times[i];
                if (t < 0 || Math.Abs(t - time) > tolerance) continue;
                if (t <= time && t > early) { before = i; early = t; }
                if (t >= time && t < late) { after = i; late = t; }
            }
            if (before < 0 && after < 0) return null;
            if (before < 0) before = after;
            if (after < 0) after = before;
            var weight = late > early && double.IsFinite(late) && double.IsFinite(early) ? (float)((time - early) / (late - early)) : 0f;
            var result = new float[width];
            for (var k = 0; k < width; k++)
            {
                var x = values[before * width + k];
                result[k] = x + (values[after * width + k] - x) * weight;
            }
            return result;
        }
    }
}

/// <summary>
/// Keeps the last samples in mono and, 120 times a second, sums FFT power into the equalizer's octave
/// bands and the 28 fine bands, with the left and right levels of the same moment. Two transforms: a
/// short one (about 43 ms) for the mids and treble, and one four times longer for the bass, where a
/// short window can't tell 25 Hz from 40 Hz. Both are centred on the moment the measurement carries.
/// </summary>
public sealed class SpectrumAnalyzer
{
    public const double Rate = 120;
    public const double Crossover = 400;

    public int SampleRate { get; }
    private readonly Transform shortT;
    private readonly Transform longT;
    private readonly int hop;
    private readonly (bool Long, (int Lo, int Hi) Bins)[] bandBins;
    private readonly (bool Long, (int Lo, int Hi) Bins)[] fineBins;
    private readonly float[] history;
    private int head;
    private int pending;
    private readonly float[] levels = new float[SpectrumShared.Bands];
    private readonly float[] fine = new float[SpectrumShared.FineBands];
    private double sumL, sumR;
    private float highL, highR;
    private int counted;
    /// <summary>The last hops' left and right levels, so a measurement carries those of its own moment.</summary>
    private readonly float[][] recent;
    private int recentHead;
    private readonly float[] stereoOut = new float[4];

    public SpectrumAnalyzer(int sampleRate)
    {
        SampleRate = sampleRate;
        var shortSize = sampleRate <= 48_000 ? 2048 : sampleRate <= 96_000 ? 4096 : 8192;
        shortT = new Transform(shortSize, sampleRate);
        longT = new Transform(shortSize * 4, sampleRate);
        hop = Math.Max(1, (int)(sampleRate / Rate));
        bandBins = Equalizer.Frequencies.Select(f =>
        {
            var t = f < Crossover ? longT : shortT;
            return (f < Crossover, t.Bins(f / Math.Sqrt(2), f * Math.Sqrt(2)));
        }).ToArray();
        var ratio = Math.Pow(1000, 0.5 / SpectrumShared.FineBands);
        fineBins = SpectrumShared.FineCentres.Select(f =>
        {
            var t = f < Crossover ? longT : shortT;
            return (f < Crossover, t.Bins(f / ratio, f * ratio));
        }).ToArray();
        history = new float[longT.Size];
        recent = Enumerable.Range(0, (int)(longT.Size / 2.0 / hop) + 1).Select(_ => new[] { -120f, -120f, -120f, -120f }).ToArray();
    }

    /// <summary>Adds interleaved frames (−1…1) and measures every 1/120 s. <paramref name="end"/>: track time at the end of the block.</summary>
    public void Process(float[] samples, int channels, int frames, double end, SpectrumShared shared)
    {
        for (var f = 0; f < frames;)
        {
            var b = f * channels;
            var l = samples[b];
            var r = channels > 1 ? samples[b + 1] : l;
            sumL += l * l;
            sumR += r * r;
            highL = Math.Max(highL, Math.Abs(l));
            highR = Math.Max(highR, Math.Abs(r));
            counted++;
            history[head] = (l + r) * 0.5f;
            head = (head + 1) % history.Length;
            f++;
            pending++;
            if (pending < hop) continue;
            pending = 0;
            var slot = recent[recentHead];
            slot[0] = Decibels((float)Math.Sqrt(sumL / Math.Max(counted, 1)));
            slot[1] = Decibels((float)Math.Sqrt(sumR / Math.Max(counted, 1)));
            slot[2] = Decibels(highL);
            slot[3] = Decibels(highR);
            recentHead = (recentHead + 1) % recent.Length;
            sumL = 0; sumR = 0; highL = 0; highR = 0; counted = 0;
            Measure();
            // Centred half a long window back; recentHead is now the oldest hop kept, from then.
            var time = end - (double)(frames - f) / SampleRate - longT.Size / 2.0 / SampleRate;
            Array.Copy(recent[recentHead], stereoOut, 4);
            shared.Write(time, levels, fine, stereoOut);
        }
    }

    private void Measure()
    {
        longT.Run(history, head);
        shortT.Run(history, (head - longT.Size / 2 + shortT.Size / 2 + history.Length) % history.Length);
        for (var b = 0; b < bandBins.Length; b++) levels[b] = (bandBins[b].Long ? longT : shortT).Level(bandBins[b].Bins);
        for (var b = 0; b < fineBins.Length; b++) fine[b] = (fineBins[b].Long ? longT : shortT).Level(fineBins[b].Bins);
    }

    private static float Decibels(float amplitude) => 20 * MathF.Log10(Math.Max(amplitude, 1e-6f));
}

/// <summary>One FFT size, with its Hann window and buffers (radix-2, in place).</summary>
internal sealed class Transform
{
    public int Size { get; }
    private readonly float[] window;
    private readonly double binWidth;
    /// <summary>Power of a full-scale sine summed over its bins, with this window.</summary>
    private readonly float fullScale;
    private readonly float[] real, imag, power, cosTable, sinTable;
    private readonly int[] reversed;

    public Transform(int size, int sampleRate)
    {
        Size = size;
        window = Enumerable.Range(0, size).Select(i => (float)(0.5 - 0.5 * Math.Cos(2 * Math.PI * i / size))).ToArray();
        binWidth = (double)sampleRate / size;
        fullScale = (float)(0.375 * size * size / 4);
        real = new float[size];
        imag = new float[size];
        power = new float[size / 2];
        cosTable = Enumerable.Range(0, size / 2).Select(k => (float)Math.Cos(2 * Math.PI * k / size)).ToArray();
        sinTable = Enumerable.Range(0, size / 2).Select(k => (float)Math.Sin(2 * Math.PI * k / size)).ToArray();
        var bits = (int)Math.Round(Math.Log2(size));
        reversed = Enumerable.Range(0, size).Select(x =>
        {
            int v = x, r = 0;
            for (var i = 0; i < bits; i++) { r = (r << 1) | (v & 1); v >>= 1; }
            return r;
        }).ToArray();
    }

    /// <summary>The bins covering <paramref name="low"/> to <paramref name="high"/> Hz, at least one (bin 0 is DC: never used).</summary>
    public (int Lo, int Hi) Bins(double low, double high)
    {
        var lo = Math.Max(1, (int)(low / binWidth));
        var hi = Math.Min(Size / 2, Math.Max(lo + 1, (int)Math.Ceiling(high / binWidth)));
        return (lo, hi);
    }

    /// <summary>Power spectrum of the <see cref="Size"/> samples of the ring that end just before <paramref name="end"/>.</summary>
    public void Run(float[] history, int end)
    {
        var start = (end - Size + history.Length) % history.Length;
        for (var i = 0; i < Size; i++)
        {
            var j = reversed[i];
            real[j] = history[(start + i) % history.Length] * window[i];
            imag[j] = 0;
        }
        for (var len = 2; len <= Size; len *= 2)
        {
            var half = len / 2;
            var step = Size / len;
            for (var i = 0; i < Size; i += len)
            {
                for (var k = 0; k < half; k++)
                {
                    var c = cosTable[k * step];
                    var s = -sinTable[k * step];
                    var a = i + k;
                    var b = a + half;
                    var tr = real[b] * c - imag[b] * s;
                    var ti = real[b] * s + imag[b] * c;
                    real[b] = real[a] - tr;
                    imag[b] = imag[a] - ti;
                    real[a] += tr;
                    imag[a] += ti;
                }
            }
        }
        for (var k = 0; k < Size / 2; k++) power[k] = real[k] * real[k] + imag[k] * imag[k];
    }

    /// <summary>dBFS of the last run's power over the bins.</summary>
    public float Level((int Lo, int Hi) bins)
    {
        var sum = 0f;
        for (var k = bins.Lo; k < bins.Hi; k++) sum += power[k];
        return 10 * MathF.Log10(Math.Max(sum / fullScale, 1e-12f));
    }
}
