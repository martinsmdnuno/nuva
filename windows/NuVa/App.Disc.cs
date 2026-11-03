using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using NuVa.Audio;
using NuVa.Core;
using NuVa.Core.Library;

namespace NuVa;

// Audio CDs: a disc going in (or in the drive at launch) becomes a source and plays, like a CD player.
public sealed partial class App
{
    private DiscLookup? discLookup;
    private readonly HashSet<char> inserting = [];

    private DiscLookup Discs => discLookup ??= new DiscLookup(Path.Combine(LocalFolder, "Discs"), CoverArtArchive.Shared);

    private IEnumerable<DiscSource> DiscSources => Model.Sources.Sources.OfType<DiscSource>();

    /// <summary>The CD that Ctrl+E ejects: the one playing, else the one in the drive.</summary>
    public Guid? EjectableDisc
    {
        get
        {
            var discs = DiscSources.ToList();
            if (Model.Player.Current?.Entry is { } entry && discs.FirstOrDefault(d => d.Id == entry.SourceId) is { } playing) return playing.Id;
            return discs.FirstOrDefault()?.Id;
        }
    }

    /// <summary>At launch: a disc already in the drive plays.</summary>
    private void ScanDrives()
    {
        foreach (var drive in CdDrive.Drives()) _ = InsertDisc(drive, plays: true);
    }

    /// <summary>WM_DEVICECHANGE: a disc went in or came out.</summary>
    public void DeviceChanged(int kind, IntPtr data)
    {
        const int arrival = 0x8000, removed = 0x8004;
        if ((kind != arrival && kind != removed) || data == IntPtr.Zero) return;
        if (Marshal.ReadInt32(data, 4) != 2 /* DBT_DEVTYP_VOLUME */) return;
        var mask = (uint)Marshal.ReadInt32(data, 12);
        for (var i = 0; i < 26; i++)
        {
            if ((mask & (1u << i)) == 0) continue;
            var drive = (char)('A' + i);
            if (kind == arrival) _ = InsertDisc(drive, plays: true);
            else ReleaseDisc(drive);
        }
    }

    /// <summary>A CD went in: look up its names, add it as a source and play it.</summary>
    private async Task InsertDisc(char drive, bool plays)
    {
        if (DiscSources.Any(d => d.Drive == drive) || !inserting.Add(drive)) return;
        try
        {
            var toc = await Task.Run(() => CdDrive.Toc(drive));
            if (toc == null) return;
            Log.Write($"cd: {drive}: {toc.Starts.Count} tracks, disc ID {toc.MusicBrainzId}");
            var info = await Discs.Info(toc);
            var disc = new DiscSource(drive, toc, info, Discs);
            Model.Sources.AddTransient(disc);
            Model.Notify();
            if (plays) await Model.PlayFolder(new BrowserLocation(disc.Id, disc.Folder));
        }
        catch (Exception e)
        {
            Log.Write($"cd: {e.Message}");
        }
        finally
        {
            inserting.Remove(drive);
        }
    }

    /// <summary>Ejects the CD (the one playing, or the one given) after letting go of it.</summary>
    public async void EjectDisc(Guid? id)
    {
        var target = id ?? EjectableDisc;
        if (DiscSources.FirstOrDefault(d => d.Id == target) is not { } disc) return;
        ReleaseDisc(disc.Drive);
        // The decoder lets go of the drive a moment after the queue does.
        await Task.Delay(300);
        if (!await Task.Run(() => CdDrive.Eject(disc.Drive)))
        {
            await Task.Delay(1000);
            if (!await Task.Run(() => CdDrive.Eject(disc.Drive)))
            {
                // Windows kept the disc: bring it back, so it can be played or ejected again.
                System.Media.SystemSounds.Beep.Play();
                await InsertDisc(disc.Drive, plays: false);
            }
        }
    }

    /// <summary>The CD is going away: its tracks leave the queue and it leaves the sources.</summary>
    private void ReleaseDisc(char drive)
    {
        foreach (var disc in DiscSources.Where(d => d.Drive == drive).ToList()) Model.RemoveSource(disc.Id);
    }
}
