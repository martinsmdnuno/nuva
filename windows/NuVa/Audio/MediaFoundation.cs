using System;
using System.Runtime.InteropServices;
using NuVa.Core;
using NuVa.Core.Audio;

namespace NuVa.Audio;

/// <summary>
/// Media Foundation's Source Reader, called through its COM vtables (no wrapper library): it opens a file
/// or an http(s) URL with Windows' own media sources and decoders (FLAC, ALAC, MP3, AAC, WAV) and hands
/// back float PCM. Slot numbers are the methods' positions in the SDK headers (mfreadwrite.h,
/// mfobjects.h), after IUnknown's three.
/// </summary>
internal static unsafe class MF
{
    private const uint Version = 0x00020070; // MF_SDK_VERSION << 16 | MF_API_VERSION
    public const uint FirstAudioStream = 0xFFFFFFFD;
    public const uint AllStreams = 0xFFFFFFFE;
    public const uint MediaSource = 0xFFFFFFFF;
    public const uint EndOfStream = 0x2;
    public const uint CurrentMediaTypeChanged = 0x20;
    public const uint ErrorFlag = 0x1;

    public static readonly Guid MajorType = new("48eba18e-f8c9-4687-bf11-0a74c9f96a8f");
    public static readonly Guid Subtype = new("f7e34c9a-42e8-4714-b74b-cb29d72c35e5");
    public static readonly Guid Audio = new("73647561-0000-0010-8000-00AA00389B71");
    public static readonly Guid Float = new("00000003-0000-0010-8000-00AA00389B71");
    public static readonly Guid Pcm = new("00000001-0000-0010-8000-00AA00389B71");
    public static readonly Guid Channels = new("37e48bf5-645e-4c5b-89de-ada9e29b696a");
    public static readonly Guid SamplesPerSecond = new("5faeeae7-0290-4c31-9e8a-c534f68d9dba");
    public static readonly Guid BitsPerSample = new("f2deb57f-40fa-4764-aa33-ed4f2d1ff669");
    public static readonly Guid BlockAlignment = new("322de230-9eeb-43bd-ab7a-ff412251541d");
    public static readonly Guid PdDuration = new("6c990d33-bb8e-477a-8598-0d5d96fcd88a");

    [DllImport("mfplat.dll", ExactSpelling = true)]
    private static extern int MFStartup(uint version, uint flags);

    [DllImport("mfplat.dll", ExactSpelling = true)]
    public static extern int MFCreateMediaType(out IntPtr type);

    [DllImport("mfreadwrite.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
    public static extern int MFCreateSourceReaderFromURL(string url, IntPtr attributes, out IntPtr reader);

    [DllImport("mfreadwrite.dll", ExactSpelling = true)]
    public static extern int MFCreateSourceReaderFromByteStream(IntPtr byteStream, IntPtr attributes, out IntPtr reader);

    [DllImport("mfplat.dll", ExactSpelling = true)]
    public static extern int MFCreateMFByteStreamOnStream(IntPtr stream, out IntPtr byteStream);

    public static readonly Guid ByteStreamContentType = new("fc358289-3cb6-460c-a424-b6681260375a");
    public static readonly Guid ByteStreamOriginName = new("fc358288-3cb6-460c-a424-b6681260375a");
    private static readonly Guid attributesId = new("2cd2d921-c447-44a7-a13c-4adabfc247e3");

    /// <summary>A source reader on a byte stream of NuVa's own (an IStream), with the type and name hints MF resolves by.</summary>
    public static IntPtr ReaderOnStream(System.Runtime.InteropServices.ComTypes.IStream stream, string? contentType, string name)
    {
        var unknown = Marshal.GetComInterfaceForObject(stream, typeof(System.Runtime.InteropServices.ComTypes.IStream));
        try
        {
            Check(MFCreateMFByteStreamOnStream(unknown, out var byteStream), "MFCreateMFByteStreamOnStream");
            try
            {
                var iid = attributesId;
                if (Marshal.QueryInterface(byteStream, in iid, out var attributes) >= 0)
                {
                    if (contentType != null) SetString(attributes, ByteStreamContentType, contentType);
                    SetString(attributes, ByteStreamOriginName, name);
                    Release(attributes);
                }
                Check(MFCreateSourceReaderFromByteStream(byteStream, IntPtr.Zero, out var reader), "MFCreateSourceReaderFromByteStream");
                return reader;
            }
            finally
            {
                Release(byteStream);
            }
        }
        finally
        {
            Marshal.Release(unknown);
        }
    }

    public static int SetString(IntPtr attributes, Guid key, string value)
    {
        fixed (char* text = value)
            return ((delegate* unmanaged[Stdcall]<IntPtr, Guid*, char*, int>)Slot(attributes, 25))(attributes, &key, text);
    }

    private static readonly object gate = new();
    private static bool started;

    public static void Startup()
    {
        lock (gate)
        {
            if (started) return;
            Check(MFStartup(Version, 0), "MFStartup");
            started = true;
        }
    }

    public static void Check(int hr, string what)
    {
        if (hr < 0) throw new COMException($"{what} failed (0x{hr:X8})", hr);
    }

    private static void* Slot(IntPtr obj, int index) => (*(void***)obj)[index];

    public static void Release(IntPtr obj)
    {
        if (obj != IntPtr.Zero) ((delegate* unmanaged[Stdcall]<IntPtr, uint>)Slot(obj, 2))(obj);
    }

    // IMFAttributes (also the first 30 methods of IMFMediaType and IMFSample).
    public static int GetUInt32(IntPtr attributes, Guid key, out uint value)
    {
        uint v = 0;
        var hr = ((delegate* unmanaged[Stdcall]<IntPtr, Guid*, uint*, int>)Slot(attributes, 7))(attributes, &key, &v);
        value = v;
        return hr;
    }

    public static int GetGuid(IntPtr attributes, Guid key, out Guid value)
    {
        Guid v;
        var hr = ((delegate* unmanaged[Stdcall]<IntPtr, Guid*, Guid*, int>)Slot(attributes, 10))(attributes, &key, &v);
        value = v;
        return hr;
    }

    public static int SetUInt32(IntPtr attributes, Guid key, uint value) =>
        ((delegate* unmanaged[Stdcall]<IntPtr, Guid*, uint, int>)Slot(attributes, 21))(attributes, &key, value);

    public static int SetGuid(IntPtr attributes, Guid key, Guid value) =>
        ((delegate* unmanaged[Stdcall]<IntPtr, Guid*, Guid*, int>)Slot(attributes, 24))(attributes, &key, &value);

    // IMFSourceReader
    public static int SetStreamSelection(IntPtr reader, uint stream, bool selected) =>
        ((delegate* unmanaged[Stdcall]<IntPtr, uint, int, int>)Slot(reader, 4))(reader, stream, selected ? 1 : 0);

    public static int GetNativeMediaType(IntPtr reader, uint stream, uint index, out IntPtr type)
    {
        IntPtr t;
        var hr = ((delegate* unmanaged[Stdcall]<IntPtr, uint, uint, IntPtr*, int>)Slot(reader, 5))(reader, stream, index, &t);
        type = t;
        return hr;
    }

    public static int GetCurrentMediaType(IntPtr reader, uint stream, out IntPtr type)
    {
        IntPtr t;
        var hr = ((delegate* unmanaged[Stdcall]<IntPtr, uint, IntPtr*, int>)Slot(reader, 6))(reader, stream, &t);
        type = t;
        return hr;
    }

    public static int SetCurrentMediaType(IntPtr reader, uint stream, IntPtr type) =>
        ((delegate* unmanaged[Stdcall]<IntPtr, uint, IntPtr, IntPtr, int>)Slot(reader, 7))(reader, stream, IntPtr.Zero, type);

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    public struct PropVariant
    {
        [FieldOffset(0)] public ushort Type;
        [FieldOffset(8)] public long Value;
    }

    private const ushort VT_I8 = 20;
    private const ushort VT_UI8 = 21;

    public static int SetCurrentPosition(IntPtr reader, long hundredNanoseconds)
    {
        var format = Guid.Empty;
        var position = new PropVariant { Type = VT_I8, Value = hundredNanoseconds };
        return ((delegate* unmanaged[Stdcall]<IntPtr, Guid*, PropVariant*, int>)Slot(reader, 8))(reader, &format, &position);
    }

    public static int ReadSample(IntPtr reader, out uint flags, out long time, out IntPtr sample)
    {
        uint actual, f;
        long t;
        IntPtr s;
        var hr = ((delegate* unmanaged[Stdcall]<IntPtr, uint, uint, uint*, uint*, long*, IntPtr*, int>)Slot(reader, 9))(
            reader, FirstAudioStream, 0, &actual, &f, &t, &s);
        flags = f;
        time = t;
        sample = s;
        return hr;
    }

    /// <summary>The source's duration in 100 ns units, or 0.</summary>
    public static long Duration(IntPtr reader)
    {
        var key = PdDuration;
        PropVariant value = default;
        var hr = ((delegate* unmanaged[Stdcall]<IntPtr, uint, Guid*, PropVariant*, int>)Slot(reader, 12))(reader, MediaSource, &key, &value);
        return hr >= 0 && (value.Type == VT_UI8 || value.Type == VT_I8) ? value.Value : 0;
    }

    // IMFSample: ConvertToContiguousBuffer is its 9th method, after IMFAttributes' 30.
    public static int ConvertToContiguousBuffer(IntPtr sample, out IntPtr buffer)
    {
        IntPtr b;
        var hr = ((delegate* unmanaged[Stdcall]<IntPtr, IntPtr*, int>)Slot(sample, 3 + 30 + 8))(sample, &b);
        buffer = b;
        return hr;
    }

    // IMFMediaBuffer
    public static int Lock(IntPtr buffer, out byte* data, out uint length)
    {
        byte* d;
        uint max, current;
        var hr = ((delegate* unmanaged[Stdcall]<IntPtr, byte**, uint*, uint*, int>)Slot(buffer, 3))(buffer, &d, &max, &current);
        data = d;
        length = current;
        return hr;
    }

    public static int Unlock(IntPtr buffer) => ((delegate* unmanaged[Stdcall]<IntPtr, int>)Slot(buffer, 4))(buffer);
}

/// <summary>One track through the Source Reader, as interleaved floats.</summary>
internal sealed unsafe class MediaFoundationDecoder : IDecoder
{
    private IntPtr reader;
    private bool isFloat;
    private int bits;
    private int channels;
    private float[] pending = [];
    private int pendingOffset;
    private int pendingFrames;
    private bool ended;
    /// <summary>After a seek: the target, in 100 ns, until the first sample arrives.</summary>
    private long seekTarget = -1;

    public AudioFormat Format { get; private set; }
    public double Duration { get; }
    public int SourceBits { get; }

    public MediaFoundationDecoder(string url)
    {
        MF.Startup();
        var hr = MF.MFCreateSourceReaderFromURL(url, IntPtr.Zero, out reader);
        if (hr < 0 && url.StartsWith("http", StringComparison.OrdinalIgnoreCase))
        {
            // Media Foundation wouldn't open the stream by URL: feed it the file over range requests.
            Log.Write($"decoder: URL refused (0x{hr:X8}), reading it over HTTP ranges");
            var stream = new HttpByteStream(url);
            reader = MF.ReaderOnStream(stream, stream.ContentType, url.Split('?')[0]);
        }
        else
        {
            MF.Check(hr, "MFCreateSourceReaderFromURL");
        }
        try
        {
            MF.SetStreamSelection(reader, MF.AllStreams, false);
            MF.Check(MF.SetStreamSelection(reader, MF.FirstAudioStream, true), "select the audio stream");
            SourceBits = NativeBits();
            if (!Request(MF.Float, 32))
            {
                // Some decoders only give integer PCM: take it at the source's depth and convert here.
                if (!Request(MF.Pcm, SourceBits is 24 or 32 ? SourceBits : 16) && !Request(MF.Pcm, 16) && !Request(MF.Pcm, 0))
                    throw new COMException("No PCM output for this file");
            }
            ReadFormat();
            Duration = MF.Duration(reader) / 1e7;
        }
        catch
        {
            MF.Release(reader);
            reader = IntPtr.Zero;
            throw;
        }
    }

    /// <summary>Bits per sample of the source, from its native media type (24 for a 24-bit FLAC); 0 for lossy.</summary>
    private int NativeBits()
    {
        if (MF.GetNativeMediaType(reader, MF.FirstAudioStream, 0, out var native) < 0) return 0;
        try
        {
            if (MF.GetUInt32(native, MF.BitsPerSample, out var b) >= 0 && b is 8 or 16 or 20 or 24 or 32) return (int)b;
            return 0;
        }
        finally
        {
            MF.Release(native);
        }
    }

    private bool Request(Guid subtype, int bitsPerSample)
    {
        MF.Check(MF.MFCreateMediaType(out var type), "MFCreateMediaType");
        try
        {
            MF.SetGuid(type, MF.MajorType, MF.Audio);
            MF.SetGuid(type, MF.Subtype, subtype);
            // 0 leaves the depth to the decoder.
            if (subtype == MF.Pcm && bitsPerSample > 0) MF.SetUInt32(type, MF.BitsPerSample, (uint)bitsPerSample);
            return MF.SetCurrentMediaType(reader, MF.FirstAudioStream, type) >= 0;
        }
        finally
        {
            MF.Release(type);
        }
    }

    private void ReadFormat()
    {
        MF.Check(MF.GetCurrentMediaType(reader, MF.FirstAudioStream, out var type), "GetCurrentMediaType");
        try
        {
            MF.GetGuid(type, MF.Subtype, out var subtype);
            MF.GetUInt32(type, MF.Channels, out var ch);
            MF.GetUInt32(type, MF.SamplesPerSecond, out var rate);
            MF.GetUInt32(type, MF.BitsPerSample, out var b);
            isFloat = subtype == MF.Float;
            channels = Math.Max(1, (int)ch);
            // Bytes per sample from the block alignment (20-bit PCM travels in 24 bits).
            bits = MF.GetUInt32(type, MF.BlockAlignment, out var align) >= 0 && align > 0 ? (int)(align / channels) * 8 : isFloat ? 32 : (int)b;
            if (bits is not (8 or 16 or 24 or 32)) throw new COMException($"Unsupported sample size {bits}");
            if (rate == 0) throw new COMException("No sample rate");
            Format = new AudioFormat((int)rate, channels);
        }
        finally
        {
            MF.Release(type);
        }
    }

    public int Read(float[] buffer, int maxFrames)
    {
        var written = 0;
        while (written < maxFrames)
        {
            if (pendingFrames > 0)
            {
                var n = Math.Min(maxFrames - written, pendingFrames);
                Array.Copy(pending, pendingOffset * channels, buffer, written * channels, n * channels);
                pendingOffset += n;
                pendingFrames -= n;
                written += n;
                continue;
            }
            if (ended || !Fill()) break;
        }
        return written;
    }

    /// <summary>Reads the next sample into <see cref="pending"/>. False at the end.</summary>
    private bool Fill()
    {
        while (true)
        {
            MF.Check(MF.ReadSample(reader, out var flags, out var time, out var sample), "ReadSample");
            try
            {
                if ((flags & MF.ErrorFlag) != 0) throw new COMException("The stream failed");
                if ((flags & MF.CurrentMediaTypeChanged) != 0) ReadFormat();
                if ((flags & MF.EndOfStream) != 0)
                {
                    ended = true;
                    return false;
                }
                if (sample == IntPtr.Zero) continue;
                if (!Convert(sample)) continue;
                if (seekTarget >= 0)
                {
                    // The source seeks to a frame boundary before the target: drop what comes before it.
                    var skip = (int)Math.Clamp((seekTarget - time) * Format.SampleRate / 1e7, 0, pendingFrames);
                    seekTarget = -1;
                    pendingOffset += skip;
                    pendingFrames -= skip;
                    if (pendingFrames == 0) continue;
                }
                return true;
            }
            finally
            {
                MF.Release(sample);
            }
        }
    }

    private bool Convert(IntPtr sample)
    {
        MF.Check(MF.ConvertToContiguousBuffer(sample, out var buffer), "ConvertToContiguousBuffer");
        try
        {
            MF.Check(MF.Lock(buffer, out var data, out var length), "Lock");
            try
            {
                var bytesPerSample = bits / 8;
                var count = (int)(length / bytesPerSample);
                var frames = count / channels;
                if (frames == 0) return false;
                if (pending.Length < frames * channels) pending = new float[frames * channels];
                var n = frames * channels;
                if (isFloat)
                {
                    new ReadOnlySpan<float>(data, n).CopyTo(pending);
                }
                else if (bits == 16)
                {
                    var s = (short*)data;
                    for (var i = 0; i < n; i++) pending[i] = s[i] / 32768f;
                }
                else if (bits == 24)
                {
                    for (var i = 0; i < n; i++)
                    {
                        var p = data + i * 3;
                        var v = (p[0] << 8 | p[1] << 16 | p[2] << 24) >> 8;
                        pending[i] = v / 8388608f;
                    }
                }
                else if (bits == 32)
                {
                    var s = (int*)data;
                    for (var i = 0; i < n; i++) pending[i] = s[i] / 2147483648f;
                }
                else
                {
                    for (var i = 0; i < n; i++) pending[i] = (data[i] - 128) / 128f;
                }
                pendingOffset = 0;
                pendingFrames = frames;
                return true;
            }
            finally
            {
                MF.Unlock(buffer);
            }
        }
        finally
        {
            MF.Release(buffer);
        }
    }

    public void Seek(double seconds)
    {
        var target = (long)(Math.Max(0, seconds) * 1e7);
        MF.Check(MF.SetCurrentPosition(reader, target), "SetCurrentPosition");
        seekTarget = target;
        pendingFrames = 0;
        ended = false;
    }

    public void Dispose()
    {
        MF.Release(reader);
        reader = IntPtr.Zero;
    }
}

/// <summary>Picks the decoder for a location: AIFF and CDs NuVa reads itself; everything else goes to Media Foundation.</summary>
public sealed class DecoderFactory : IDecoderFactory
{
    public IDecoder Open(string location)
    {
        if (location.StartsWith("cdda://", StringComparison.Ordinal)) return CdDecoderFactory.Open(location);
        if (Core.Library.Locations.IsFile(location))
        {
            var ext = System.IO.Path.GetExtension(location).ToLowerInvariant();
            if (ext is ".aiff" or ".aif") return new AiffDecoder(location);
            return new MediaFoundationDecoder(location);
        }
        return new MediaFoundationDecoder(location);
    }
}
