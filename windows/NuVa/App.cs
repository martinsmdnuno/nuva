using System;
using System.Windows;
using NuVa.UI;

namespace NuVa;

public sealed class App : Application
{
    private readonly string[] args;

    public App(string[] args)
    {
        this.args = args;
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var window = new MainWindow();
        window.Closed += (_, _) => Shutdown();
        window.Show();
    }
}
