using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Windows;
using NuVa.Audio;
using NuVa.Core;
using NuVa.Core.Audio;

namespace NuVa;

/// <summary>
/// NuVa.exe --selftest [music file]: checks each stage of the sound on this machine, with no window:
/// Media Foundation, the decoder (a file given, or a WAV of silence made here), AudioGraph and the
/// output devices. Writes the result to the log and shows it.
/// </summary>
internal static class SelfTest
{
    public static void Run(string[] args)
    {
        var report = new StringBuilder();
        void Line(string text)
        {
            report.AppendLine(text);
            Log.Write("selftest: " + text);
        }
        Line($"NuVa {App.Version}, Windows {Environment.OSVersion.Version}, {System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture}");
        var file = args.SkipWhile(a => a != "--selftest").Skip(1).FirstOrDefault(a => !a.StartsWith("--"));
        if (file == null)
        {
            file = Path.Combine(Path.GetTempPath(), "nuva-selftest.wav");
            WriteSilence(file, 44100, 2);
        }
        Line($"file: {file}");
        try
        {
            using var decoder = new DecoderFactory().Open(Path.GetFullPath(file));
            Line($"decoder: ok, {decoder.Format}, {decoder.Duration:F2} s, {decoder.SourceBits} bits");
            var buffer = new float[4096 * decoder.Format.Channels];
            var frames = decoder.Read(buffer, 4096);
            Line($"read: {frames} frames, peak {buffer.Take(frames * decoder.Format.Channels).Select(Math.Abs).DefaultIfEmpty(0).Max():F3}");
            decoder.Seek(decoder.Duration / 2);
            Line($"seek: ok, then {decoder.Read(buffer, 4096)} frames");
        }
        catch (Exception e)
        {
            Line($"decoder: FAILED {e.Message}");
        }
        try
        {
            var devices = GraphOutput.Devices().GetAwaiter().GetResult();
            Line($"devices: {string.Join(", ", devices.Select(d => d.Name))}");
            using var output = new GraphOutput();
            var calls = 0;
            output.Render = (buffer, frames, format) =>
            {
                Array.Clear(buffer, 0, frames * format.Channels);
                Interlocked.Increment(ref calls);
            };
            output.Configure(new AudioFormat(44100, 2));
            output.Start();
            Thread.Sleep(1000);
            output.Stop();
            Line($"output: {output.DeviceName}, {output.DeviceRate} Hz, latency {output.Latency * 1000:F0} ms, {calls} blocks in 1 s (about 100 expected)");
        }
        catch (Exception e)
        {
            Line($"output: FAILED {e.Message}");
        }
        Line($"log: {Log.File}");
        MessageBox.Show(report.ToString(), "NuVa self-test");
    }

    private static void WriteSilence(string path, int rate, int channels)
    {
        using var stream = File.Create(path);
        using var writer = new BinaryWriter(stream);
        var frames = rate * 2;
        var bytes = frames * channels * 2;
        writer.Write("RIFF"u8);
        writer.Write(36 + bytes);
        writer.Write("WAVEfmt "u8);
        writer.Write(16);
        writer.Write((short)1);
        writer.Write((short)channels);
        writer.Write(rate);
        writer.Write(rate * channels * 2);
        writer.Write((short)(channels * 2));
        writer.Write((short)16);
        writer.Write("data"u8);
        writer.Write(bytes);
        writer.Write(new byte[bytes]);
    }
}
