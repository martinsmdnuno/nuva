using System;
using System.Buffers.Binary;
using System.IO;
using System.Text;
using NuVa.Core.Audio;

namespace NuVa.Core.Tests;

public static class AiffTests
{
    /// <summary>A 16-bit stereo AIFF at 44.1 kHz with a ramp.</summary>
    private static MemoryStream Make(int frames, string kind = "AIFF", string compression = "NONE")
    {
        var data = new MemoryStream();
        void Id(string s) => data.Write(Encoding.ASCII.GetBytes(s));
        void U32(uint v) { Span<byte> b = stackalloc byte[4]; BinaryPrimitives.WriteUInt32BigEndian(b, v); data.Write(b); }
        void I16(short v) { Span<byte> b = stackalloc byte[2]; BinaryPrimitives.WriteInt16BigEndian(b, v); data.Write(b); }
        var comm = kind == "AIFC" ? 22 + 2 : 18;
        Id("FORM"); U32((uint)(4 + 8 + comm + 8 + 8 + frames * 4)); Id(kind);
        Id("COMM"); U32((uint)comm); I16(2); U32((uint)frames); I16(16);
        // 44100 as an 80-bit extended number.
        data.Write([0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]);
        if (kind == "AIFC") { Id(compression); data.Write([0, 0]); }
        Id("SSND"); U32((uint)(8 + frames * 4)); U32(0); U32(0);
        for (var i = 0; i < frames; i++)
        {
            short l = (short)(i * 100), r = (short)(-i * 100);
            if (compression == "sowt") { data.Write(BitConverter.GetBytes(l)); data.Write(BitConverter.GetBytes(r)); }
            else { I16(l); I16(r); }
        }
        data.Position = 0;
        return data;
    }

    [Test]
    public static void ReadsBigEndianPcm()
    {
        using var decoder = new AiffDecoder(Make(100));
        Assert.Equal(new AudioFormat(44100, 2), decoder.Format);
        Assert.Equal(16, decoder.SourceBits);
        var buffer = new float[400];
        Assert.Equal(100, decoder.Read(buffer, 200));
        Assert.Near(500 / 32768.0, buffer[10], 1e-6);
        Assert.Near(-500 / 32768.0, buffer[11], 1e-6);
        decoder.Seek(50 / 44100.0);
        decoder.Read(buffer, 1);
        Assert.Near(5000 / 32768.0, buffer[0], 1e-6);
    }

    [Test]
    public static void ReadsLittleEndianAifc()
    {
        using var decoder = new AiffDecoder(Make(10, "AIFC", "sowt"));
        var buffer = new float[40];
        Assert.Equal(10, decoder.Read(buffer, 20));
        Assert.Near(300 / 32768.0, buffer[6], 1e-6);
    }
}
