using System;
using System.Collections.Generic;
using System.Linq;

namespace NuVa.Core.Audio;

/// <summary>A preset: its key (the Portuguese name, as on the Mac) and the gain in dB of each band.</summary>
public sealed record EqPreset(string Key, float[] Gains)
{
    public string Name => L.T(Key);
}

/// <summary>
/// The 10-band equalizer's state, shared by the screen and the audio thread, saved between launches.
/// Same bands, range and presets as the Mac's Equalizer.swift (by way of the Android port).
/// </summary>
public sealed class Equalizer
{
    public static readonly double[] Frequencies = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
    public static readonly string[] Labels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"];
    public const float Min = -12, Max = 12;
    public const string Custom = "Personalizado";

    public static readonly EqPreset[] Presets =
    [
        new("Plano", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        new("Graves", [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        new("Agudos", [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
        new("Voz", [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1]),
        new("Loudness", [6, 4, 2, 0, -1, -1, 0, 2, 4, 5]),
        new("Rock", [4, 3, 1, -1, -2, -1, 1, 3, 4, 4]),
        new("Clássica", [3, 2, 1, 0, 0, 0, -1, 1, 2, 3]),
        new("Noite", [3, 2, 1, 0, 0, 0, -1, -2, -3, -4]),
    ];

    /// <summary>What the audio thread reads on every block; Version changes with every edit.</summary>
    public sealed record Snapshot(float[] Gains, bool Enabled, int Version);

    private readonly Settings settings;
    private float[] gains;

    public bool Enabled { get; private set; }
    /// <summary>The active preset's key, or "Personalizado" after changing a band.</summary>
    public string Preset { get; private set; }
    public IReadOnlyList<float> Gains => gains;
    public volatile Snapshot Current;
    public event Action? Changed;

    public Equalizer(Settings settings)
    {
        this.settings = settings;
        var saved = settings.Get<float[]?>("eq.gains", null);
        gains = saved?.Length == Frequencies.Length ? saved : (float[])Presets[0].Gains.Clone();
        Enabled = settings.Get("eq.enabled", false);
        Preset = settings.Get("eq.preset", Presets.FirstOrDefault(p => p.Gains.SequenceEqual(gains))?.Key ?? Custom);
        Current = new Snapshot((float[])gains.Clone(), Enabled, 0);
    }

    /// <summary>A preset's name in the interface's language.</summary>
    public static string DisplayName(string key) => L.T(key);

    public void Apply(EqPreset preset)
    {
        gains = (float[])preset.Gains.Clone();
        Preset = preset.Key;
        Enabled = true;
        Push();
    }

    public void SetEnabled(bool on)
    {
        Enabled = on;
        Push();
    }

    /// <summary>Sets a band (dB, rounded to half a decibel, as a fader would).</summary>
    public void Set(int band, float value)
    {
        var clamped = Math.Clamp(MathF.Round(value * 2) / 2, Min, Max);
        if (clamped == gains[band] && Enabled) return;
        gains = (float[])gains.Clone();
        gains[band] = clamped;
        Preset = Presets.FirstOrDefault(p => p.Gains.SequenceEqual(gains))?.Key ?? Custom;
        Enabled = true;
        Push();
    }

    /// <summary>Moves a band by <paramref name="steps"/> half-decibel steps.</summary>
    public void Nudge(int band, int steps) => Set(band, gains[band] + steps * 0.5f);

    private void Push()
    {
        Current = new Snapshot((float[])gains.Clone(), Enabled, Current.Version + 1);
        settings.Set("eq.gains", gains);
        settings.Set("eq.enabled", Enabled);
        settings.Set("eq.preset", Preset);
        Changed?.Invoke();
    }

    /// <summary>Normalised [b0, b1, b2, a1, a2] of a peaking filter (Audio EQ Cookbook, Q 1.41).</summary>
    public static double[] Peaking(double frequency, double gain, double sampleRate)
    {
        if (gain == 0 || frequency >= sampleRate / 2) return [1, 0, 0, 0, 0];
        var a = Math.Pow(10, gain / 40);
        var w0 = 2 * Math.PI * frequency / sampleRate;
        var alpha = Math.Sin(w0) / (2 * 1.41);
        var a0 = 1 + alpha / a;
        return [(1 + alpha * a) / a0, -2 * Math.Cos(w0) / a0, (1 - alpha * a) / a0, -2 * Math.Cos(w0) / a0, (1 - alpha / a) / a0];
    }
}

/// <summary>
/// 10 cascaded peaking filters per channel on interleaved float samples, in double precision, with a
/// negative pre-gain so boosts never clip. Rebuilt only when the gains or the format change.
/// </summary>
public sealed class EqFilter
{
    private int version = -1;
    private int sampleRate;
    private int channels;
    private double[][] coefficients = [];
    /// <summary>Per channel and section: the two state values of a transposed direct form II biquad.</summary>
    private double[] state = [];
    private double preGain = 1;

    public void Reset() => Array.Clear(state);

    /// <summary>Filters in place. False (and untouched) when the equalizer is off.</summary>
    public bool Process(float[] samples, int frames, int channels, int sampleRate, Equalizer.Snapshot eq)
    {
        if (!eq.Enabled) return false;
        if (eq.Version != version || sampleRate != this.sampleRate || channels != this.channels)
        {
            coefficients = Equalizer.Frequencies.Select((f, b) => Equalizer.Peaking(f, eq.Gains[b], sampleRate)).ToArray();
            if (channels != this.channels || sampleRate != this.sampleRate) state = new double[channels * coefficients.Length * 2];
            preGain = Math.Pow(10, -Math.Max(0f, eq.Gains.Max()) / 20.0);
            version = eq.Version;
            this.sampleRate = sampleRate;
            this.channels = channels;
        }
        var sections = coefficients.Length;
        for (var f = 0; f < frames; f++)
        {
            for (var c = 0; c < channels; c++)
            {
                var i = f * channels + c;
                var x = samples[i] * preGain;
                var s = c * sections * 2;
                for (var b = 0; b < sections; b++)
                {
                    var k = coefficients[b];
                    var y = k[0] * x + state[s];
                    state[s] = k[1] * x - k[3] * y + state[s + 1];
                    state[s + 1] = k[2] * x - k[4] * y;
                    x = y;
                    s += 2;
                }
                samples[i] = (float)x;
            }
        }
        return true;
    }
}

/// <summary>The pipeline's tap: the equalizer, then the meters, measuring what is heard.</summary>
public sealed class Tap(Equalizer equalizer, SpectrumShared spectrum) : IAudioTap
{
    private readonly EqFilter filter = new();
    private SpectrumAnalyzer? analyzer;

    public void Process(float[] samples, int frames, AudioFormat format, double endTime)
    {
        filter.Process(samples, frames, format.Channels, format.SampleRate, equalizer.Current);
        if (!spectrum.IsWatched) return;
        if (analyzer?.SampleRate != format.SampleRate) analyzer = new SpectrumAnalyzer(format.SampleRate);
        analyzer.Process(samples, format.Channels, frames, endTime, spectrum);
    }

    public void Reset()
    {
        filter.Reset();
        analyzer = null;
        spectrum.Clear();
    }
}
