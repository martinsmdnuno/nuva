using System;
using System.Windows;
using System.Windows.Controls;
using NuVa.Core;
using NuVa.UI;

namespace NuVa;

// The features that arrive step by step (see docs/plans/windows.md). Each fills in its part here.
public sealed partial class App
{
    /// <summary>The system media controls took the media keys.</summary>
    public bool SystemMediaControls { get; private set; }
    public bool AmbientOpen => false;
    public bool CanFixArtwork => false;
    public Guid? EjectableDisc => null;

    private void StartFeatures() { }
    private void AfterLaunch() { }
    private void BeforeQuit() { }
    public void WindowHidden() { }
    public void WindowShown() { }
    public void DeviceChanged(int kind, IntPtr data) { }

    public void ShowEqualizer() { }
    public void AddJellyfin() { }
    public void EjectDisc(Guid? id) { }
    public void CheckForUpdates() { }
    public void ShowTerms() { }
    public void ToggleAmbient() { }
    public void FillAmbientOptions(MenuItem options) => options.IsEnabled = false;
    public void FixArtwork() { }
    public void ApplyArtwork(DisplayView? display) => display?.SetArtwork(null, false);
}
