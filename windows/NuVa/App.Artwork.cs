using System;
using System.IO;
using NuVa.Core;
using NuVa.Core.Library;
using NuVa.UI;

namespace NuVa;

// Album artwork (View ▸ Show Artwork): the folder's image, the user's choice, then online by the folder names.
public sealed partial class App
{
    private ArtworkStore? artwork;

    public ArtworkStore Artwork => artwork ??= MakeArtwork();

    private ArtworkStore MakeArtwork()
    {
        CoverArtArchive.UserAgent = $"NuVa/{Version} ( https://github.com/martinsmdnuno/nuva )";
        var store = new ArtworkStore(new ArtworkResolver(Model.Sources, new ArtworkCache(Path.Combine(LocalFolder, "Artwork")), CoverArtArchive.Shared));
        store.Changed += () =>
        {
            ApplyArtwork(MainWindow?.Display);
            mediaControls?.Update();
            ArtworkChanged?.Invoke();
        };
        return store;
    }

    /// <summary>The current folder's artwork arrived or changed (the mini player and ambient listen).</summary>
    public event Action? ArtworkChanged;

    /// <summary>The current track's artwork, when artwork is on.</summary>
    public ArtworkStore.Loaded? CurrentArtwork =>
        Model.ShowsArtwork && Model.Player.Current?.Entry is { } entry ? Artwork.Get(entry) : null;

    public string? CurrentArtworkFile => CurrentArtwork?.File;

    /// <summary>"Wrong artwork…" applies to online or user artwork, and to a finished lookup that found none. An image in the folder always wins.</summary>
    public bool CanFixArtwork =>
        Model.ShowsArtwork && Model.Player.Current?.Entry is { } entry && Artwork.IsResolved(entry) && CurrentArtwork?.Origin != ArtworkOrigin.Folder;

    public void ApplyArtwork(DisplayView? display) => display?.SetArtwork(CurrentArtwork?.Image, CanFixArtwork);

    public void FixArtwork()
    {
        if (!CanFixArtwork || Model.Player.Current?.Entry is not { } entry) return;
        ShowMainWindow();
        new ArtworkFix(Artwork, entry, MainWindow).ShowDialog();
    }
}
