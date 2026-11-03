using System;
using System.Windows;
using System.Windows.Controls;
using NuVa.Core;
using NuVa.UI;

namespace NuVa;

// The features that arrive step by step (see docs/plans/windows.md). Each fills in its part here.
public sealed partial class App
{
    public Guid? EjectableDisc => null;

    public void DeviceChanged(int kind, IntPtr data) { }

    public void EjectDisc(Guid? id) { }
    public void CheckForUpdates() { }
    public void ShowTerms() { }

}
