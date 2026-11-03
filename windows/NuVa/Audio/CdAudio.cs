using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using NuVa.Core;
using NuVa.Core.Audio;
using NuVa.Core.Library;

namespace NuVa.Audio;

/// <summary>
/// The CD drive, read directly (Windows shows an audio CD only as .cda stubs): the table of contents with
/// IOCTL_CDROM_READ_TOC, the audio with IOCTL_CDROM_RAW_READ (2352-byte sectors of 16-bit stereo at
/// 44.1 kHz), and the tray with IOCTL_STORAGE_EJECT_MEDIA. No library involved.
/// </summary>
internal static class CdDrive
{
    private const uint ReadToc = 0x00024000;
    private const uint RawRead = 0x0002403E;
    private const uint EjectMedia = 0x002D4808;
    private const uint GenericRead = 0x80000000;
    public const int SectorBytes = 2352;
    public const int FramesPerSector = SectorBytes / 4;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(SafeFileHandle device, uint code, byte[]? input, int inputSize, byte[]? output, int outputSize, out int returned, IntPtr overlapped);

    public static SafeFileHandle Open(char drive)
    {
        var handle = CreateFile($@"\\.\{drive}:", GenericRead, 3 /* read | write sharing */, IntPtr.Zero, 3 /* OPEN_EXISTING */, 0, IntPtr.Zero);
        if (handle.IsInvalid) throw new IOException($"CD drive {drive}: can't be opened ({Marshal.GetLastWin32Error()})");
        return handle;
    }

    /// <summary>The audio tracks of the disc in the drive, or null (no disc, a data disc, no drive).</summary>
    public static DiscToc? Toc(char drive)
    {
        try
        {
            using var device = Open(drive);
            var toc = new byte[804];
            if (!DeviceIoControl(device, ReadToc, null, 0, toc, toc.Length, out var returned, IntPtr.Zero) || returned < 12) return null;
            int first = toc[2], last = toc[3];
            var tracks = new List<(int, int, bool)>();
            var leadout = 0;
            for (var i = 0; i <= last - first + 1; i++)
            {
                var at = 4 + i * 8;
                if (at + 8 > returned) break;
                // TRACK_DATA's first bit field (Control) is the byte's low nibble; 0x4 marks a data track.
                var control = toc[at + 1] & 0x0F;
                var number = toc[at + 2];
                // Address as MSF (minutes, seconds, frames) from the disc's start, pregap included.
                var start = (toc[at + 5] * 60 + toc[at + 6]) * 75 + toc[at + 7];
                if (number == 0xAA) leadout = start;
                else tracks.Add((number, start, (control & 0x4) != 0));
            }
            return leadout > 0 ? DiscToc.From(tracks, leadout) : null;
        }
        catch (Exception e)
        {
            Log.Write($"cd: no TOC on {drive}: ({e.Message})");
            return null;
        }
    }

    /// <summary>Reads whole sectors of audio into <paramref name="buffer"/>; returns the sectors read.</summary>
    public static int Read(SafeFileHandle device, int sector, int count, byte[] buffer)
    {
        // RAW_READ_INFO: the disk offset (in 2048-byte units, as the driver wants), the count, the mode (CDDA = 2).
        var info = new byte[16];
        BitConverter.TryWriteBytes(info.AsSpan(0, 8), (long)sector * 2048);
        BitConverter.TryWriteBytes(info.AsSpan(8, 4), count);
        BitConverter.TryWriteBytes(info.AsSpan(12, 4), 2);
        for (var attempt = 0; attempt < 3; attempt++)
        {
            if (DeviceIoControl(device, RawRead, info, info.Length, buffer, count * SectorBytes, out var returned, IntPtr.Zero))
                return returned / SectorBytes;
        }
        throw new IOException($"CD read failed at sector {sector} ({Marshal.GetLastWin32Error()})");
    }

    public static bool Eject(char drive)
    {
        try
        {
            using var device = Open(drive);
            return DeviceIoControl(device, EjectMedia, null, 0, null, 0, out _, IntPtr.Zero);
        }
        catch (Exception e)
        {
            Log.Write($"cd: eject failed: {e.Message}");
            return false;
        }
    }

    /// <summary>The CD drives with a disc in them.</summary>
    public static IEnumerable<char> Drives() =>
        DriveInfo.GetDrives().Where(d => d.DriveType == DriveType.CDRom).Select(d => char.ToUpperInvariant(d.Name[0]));
}

/// <summary>One track of the CD as interleaved floats: 588 frames a sector, read 25 sectors at a time.</summary>
internal sealed class CdDecoder : IDecoder
{
    private const int Batch = 25;
    private readonly SafeFileHandle device;
    private readonly int start;
    private readonly int end;
    private int sector;
    private readonly byte[] raw = new byte[Batch * CdDrive.SectorBytes];
    private int rawFrames;
    private int rawOffset;

    public AudioFormat Format { get; } = new(44100, 2);
    public double Duration => (end - start) / 75.0;
    public int SourceBits => 16;

    public CdDecoder(char drive, int track)
    {
        var toc = CdDrive.Toc(drive) ?? throw new IOException("No audio CD in the drive");
        var span = toc.Span(track) ?? throw new IOException($"No track {track} on the CD");
        // The TOC's sectors start after the pregap; the drive counts from the end of it too.
        (start, end) = span;
        sector = start;
        device = CdDrive.Open(drive);
    }

    public int Read(float[] buffer, int maxFrames)
    {
        var written = 0;
        while (written < maxFrames)
        {
            if (rawOffset >= rawFrames)
            {
                if (sector >= end) break;
                var count = Math.Min(Batch, end - sector);
                var read = CdDrive.Read(device, sector, count, raw);
                if (read == 0) break;
                sector += read;
                rawFrames = read * CdDrive.FramesPerSector;
                rawOffset = 0;
            }
            var n = Math.Min(maxFrames - written, rawFrames - rawOffset);
            for (var i = 0; i < n * 2; i++)
                buffer[written * 2 + i] = BitConverter.ToInt16(raw, (rawOffset * 2 + i) * 2) / 32768f;
            rawOffset += n;
            written += n;
        }
        return written;
    }

    public void Seek(double seconds)
    {
        var frames = (long)(Math.Max(0, seconds) * 44100);
        sector = Math.Min(end, start + (int)(frames / CdDrive.FramesPerSector));
        rawFrames = 0;
        rawOffset = 0;
        // Into the sector: read it now and skip the frames before the target.
        var skip = (int)(frames % CdDrive.FramesPerSector);
        if (skip > 0 && sector < end)
        {
            var read = CdDrive.Read(device, sector, 1, raw);
            sector += read;
            rawFrames = read * CdDrive.FramesPerSector;
            rawOffset = Math.Min(skip, rawFrames);
        }
    }

    public void Dispose() => device.Dispose();
}

/// <summary>Opens cdda://D/3 locations (drive letter, track number).</summary>
internal static class CdDecoderFactory
{
    public static IDecoder Open(string location)
    {
        var parts = location["cdda://".Length..].Split('/');
        return new CdDecoder(parts[0][0], int.Parse(parts[1]));
    }
}
