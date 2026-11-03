using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Media.Imaging;
using NuVa.Core;
using NuVa.Core.Library;

namespace NuVa;

/// <summary>
/// Album artwork, downsampled and kept in memory per folder (port of ArtworkStore.swift). Only loads
/// while artwork is on. Where it comes from is the ArtworkResolver's business.
/// </summary>
public sealed class ArtworkStore(ArtworkResolver resolver)
{
    /// <summary>Longest side kept in memory: enough for the display at 2x and the media controls.</summary>
    public const int MaxPixels = 600;

    public sealed record Loaded(BitmapSource Image, ArtworkOrigin Origin, string File);

    private readonly Dictionary<string, Loaded?> images = new();
    private readonly HashSet<string> loading = [];

    public ArtworkResolver Resolver => resolver;
    public event Action? Changed;

    /// <summary>The artwork of the folder holding the entry. Starts loading it the first time.</summary>
    public Loaded? Get(Entry entry)
    {
        var key = ArtworkResolver.FolderKey(entry);
        if (images.TryGetValue(key, out var cached)) return cached;
        Load(entry, key);
        return null;
    }

    /// <summary>Whether the lookup for the entry's folder has finished (with or without artwork).</summary>
    public bool IsResolved(Entry entry) => images.ContainsKey(ArtworkResolver.FolderKey(entry));

    /// <summary>Forgets the folder's artwork, so it is looked up again (after the user fixes it).</summary>
    public void Invalidate(Entry entry)
    {
        var key = ArtworkResolver.FolderKey(entry);
        images.Remove(key);
        Load(entry, key);
    }

    private async void Load(Entry entry, string key)
    {
        if (!loading.Add(key)) return;
        ResolvedArtwork? found = null;
        try
        {
            found = await resolver.Resolve(entry);
        }
        catch (Exception e)
        {
            Log.Write($"artwork: {e.Message}");
        }
        var image = found == null ? null : await Task.Run(() => Downsample(found.File));
        images[key] = image != null && found != null ? new Loaded(image, found.Origin, found.File) : null;
        loading.Remove(key);
        Changed?.Invoke();
    }

    /// <summary>Decodes at most MaxPixels across, so a 3000 px JPEG doesn't stay in memory.</summary>
    public static BitmapSource? Downsample(string file)
    {
        try
        {
            using var stream = File.OpenRead(file);
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.CreateOptions = BitmapCreateOptions.IgnoreColorProfile;
            image.DecodePixelWidth = MaxPixels;
            image.StreamSource = stream;
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch (Exception e)
        {
            Log.Write($"artwork: can't read {file}: {e.Message}");
            return null;
        }
    }

    /// <summary>JPEG for the cache, from any image file the user picks.</summary>
    public static byte[]? Jpeg(string file)
    {
        if (Downsample(file) is not { } image) return null;
        var encoder = new JpegBitmapEncoder { QualityLevel = 85 };
        encoder.Frames.Add(BitmapFrame.Create(image));
        using var output = new MemoryStream();
        encoder.Save(output);
        return output.ToArray();
    }
}
