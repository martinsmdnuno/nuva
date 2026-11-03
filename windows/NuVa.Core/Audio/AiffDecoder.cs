using System;
using System.Buffers.Binary;
using System.IO;
using System.Text;

namespace NuVa.Core.Audio;

/// <summary>
/// AIFF and AIFF-C, which Windows can't decode: plain PCM in chunks, so NuVa reads it itself (big-endian
/// integers, or little-endian "sowt", or 32/64-bit float). No decoding library involved.
/// </summary>
public sealed class AiffDecoder : IDecoder
{
    private readonly Stream stream;
    private readonly long dataStart;
    private readonly long frameCount;
    private readonly int bytesPerSample;
    private readonly bool littleEndian;
    private readonly bool isFloat;
    private long position;
    private byte[] raw = [];

    public AudioFormat Format { get; }
    public double Duration => (double)frameCount / Format.SampleRate;
    public int SourceBits { get; }

    public AiffDecoder(string path) : this(File.OpenRead(path)) { }

    public AiffDecoder(Stream stream)
    {
        this.stream = stream;
        try
        {
            Span<byte> header = stackalloc byte[12];
            stream.ReadExactly(header);
            var form = Encoding.ASCII.GetString(header[..4]);
            var kind = Encoding.ASCII.GetString(header[8..12]);
            if (form != "FORM" || kind is not ("AIFF" or "AIFC")) throw new InvalidDataException("Not an AIFF file");
            int channels = 0, bits = 0;
            double rate = 0;
            var compression = "NONE";
            long data = -1;
            Span<byte> chunk = stackalloc byte[8];
            while (stream.Position + 8 <= stream.Length)
            {
                stream.ReadExactly(chunk);
                var id = Encoding.ASCII.GetString(chunk[..4]);
                var size = BinaryPrimitives.ReadUInt32BigEndian(chunk[4..]);
                var start = stream.Position;
                if (id == "COMM")
                {
                    var comm = new byte[size];
                    stream.ReadExactly(comm);
                    channels = BinaryPrimitives.ReadInt16BigEndian(comm.AsSpan(0));
                    frameCount = BinaryPrimitives.ReadUInt32BigEndian(comm.AsSpan(2));
                    bits = BinaryPrimitives.ReadInt16BigEndian(comm.AsSpan(6));
                    rate = Extended(comm.AsSpan(8, 10));
                    if (kind == "AIFC" && size >= 22) compression = Encoding.ASCII.GetString(comm, 18, 4);
                }
                else if (id == "SSND")
                {
                    Span<byte> ssnd = stackalloc byte[8];
                    stream.ReadExactly(ssnd);
                    data = start + 8 + BinaryPrimitives.ReadUInt32BigEndian(ssnd);
                }
                stream.Position = start + size + (size & 1);
            }
            if (channels <= 0 || rate <= 0 || data < 0) throw new InvalidDataException("AIFF without sound");
            switch (compression)
            {
                case "NONE" or "twos": break;
                case "sowt": littleEndian = true; break;
                case "fl32" or "FL32": isFloat = true; bits = 32; break;
                case "fl64" or "FL64": isFloat = true; bits = 64; break;
                default: throw new InvalidDataException($"AIFF-C compression {compression} isn't supported");
            }
            bytesPerSample = (bits + 7) / 8;
            SourceBits = isFloat ? 0 : bits;
            dataStart = data;
            Format = new AudioFormat((int)Math.Round(rate), channels);
            stream.Position = dataStart;
        }
        catch
        {
            stream.Dispose();
            throw;
        }
    }

    /// <summary>An 80-bit IEEE 754 extended number (the sample rate).</summary>
    private static double Extended(ReadOnlySpan<byte> b)
    {
        var exponent = ((b[0] & 0x7F) << 8) | b[1];
        var mantissa = BinaryPrimitives.ReadUInt64BigEndian(b[2..]);
        if (exponent == 0 && mantissa == 0) return 0;
        var value = mantissa * Math.Pow(2, exponent - 16383 - 63);
        return (b[0] & 0x80) != 0 ? -value : value;
    }

    public int Read(float[] buffer, int maxFrames)
    {
        var channels = Format.Channels;
        var frames = (int)Math.Min(maxFrames, frameCount - position);
        if (frames <= 0) return 0;
        var bytes = frames * channels * bytesPerSample;
        if (raw.Length < bytes) raw = new byte[bytes];
        var read = stream.ReadAtLeast(raw.AsSpan(0, bytes), bytes, throwOnEndOfStream: false);
        frames = read / (channels * bytesPerSample);
        var n = frames * channels;
        for (var i = 0; i < n; i++)
        {
            var s = raw.AsSpan(i * bytesPerSample, bytesPerSample);
            buffer[i] = isFloat
                ? bytesPerSample == 4 ? BinaryPrimitives.ReadSingleBigEndian(s) : (float)BinaryPrimitives.ReadDoubleBigEndian(s)
                : Integer(s);
        }
        position += frames;
        return frames;
    }

    private float Integer(ReadOnlySpan<byte> s)
    {
        // Sign-extend from the top byte down; bytes in file order, big-endian unless "sowt".
        long v = 0;
        for (var k = 0; k < s.Length; k++) v = (v << 8) | s[littleEndian ? s.Length - 1 - k : k];
        var bitsTotal = s.Length * 8;
        v = (v << (64 - bitsTotal)) >> (64 - bitsTotal);
        return (float)(v / Math.Pow(2, bitsTotal - 1));
    }

    public void Seek(double seconds)
    {
        position = Math.Clamp((long)(seconds * Format.SampleRate), 0, frameCount);
        stream.Position = dataStart + position * Format.Channels * bytesPerSample;
    }

    public void Dispose() => stream.Dispose();
}
