using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using NuVa.Core;
using NuVa.Core.Library;
using NuVa.UI;

namespace NuVa;

public sealed partial class App : Application
{
    private readonly string[] args;
    private Mutex? single;
    private EventWaitHandle? showSignal;

    public static new App Current => (App)Application.Current;
    public AppModel Model { get; private set; } = null!;
    public new MainWindow MainWindow { get; private set; } = null!;
    public bool Quitting { get; private set; }

    /// <summary>%APPDATA%\NuVa: settings. %LOCALAPPDATA%\NuVa: covers, caches and the log.</summary>
    public static string RoamingFolder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "NuVa");
    public static string LocalFolder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "NuVa");
    public static string Version => typeof(App).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0] ?? "0";

    public App(string[] args)
    {
        this.args = args;
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        Log.Start(Path.Combine(LocalFolder, "nuva.log"));
        Log.Write($"NuVa {Version} on Windows {Environment.OSVersion.Version}, {System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture}, {System.Globalization.CultureInfo.CurrentUICulture.Name}");
        DispatcherUnhandledException += (_, ex) =>
        {
            Log.Write($"unhandled: {ex.Exception}");
            ex.Handled = true;
        };
        AppDomain.CurrentDomain.UnhandledException += (_, ex) => Log.Write($"fatal: {ex.ExceptionObject}");

        if (args.Contains("--selftest"))
        {
            SelfTest.Run(args);
            Shutdown();
            return;
        }

        // One NuVa: a second launch brings the first one's window back.
        single = new Mutex(true, "NuVa.SingleInstance." + Environment.UserName, out var first);
        showSignal = new EventWaitHandle(false, EventResetMode.AutoReset, "NuVa.Show." + Environment.UserName);
        if (!first)
        {
            showSignal.Set();
            Shutdown();
            return;
        }
        new Thread(() =>
        {
            while (showSignal.WaitOne()) Dispatcher.BeginInvoke(ShowMainWindow);
        }) { IsBackground = true }.Start();

        L.Portuguese = System.Globalization.CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "pt";
        Settings.Shared = new Settings(Path.Combine(RoamingFolder, "settings.json"));
        Theme.Set(Skin.With(Settings.Shared.Get<string?>("skin", null)), FontSets.FromId(Settings.Shared.Get<string?>("fontSet", null)));
        ApplyControlTheme();

        Model = new AppModel(Settings.Shared, Dispatcher);
        if (Settings.Shared.Get<string?>("outputDevice", null) is { } device) Model.Output.SelectDevice(device);
        StartFeatures();
        Model.Start();

        MainWindow = new MainWindow(this);
        base.MainWindow = MainWindow;
        MainWindow.Show();
        AfterLaunch();
    }

    /// <summary>The standard controls (menus, fields, scroll bars) in Windows 11's own style, light or dark with the skin.</summary>
    private void ApplyControlTheme()
    {
#pragma warning disable WPF0001
        try
        {
            ThemeMode = Theme.Dark ? ThemeMode.Dark : ThemeMode.Light;
        }
        catch (Exception e)
        {
            Log.Write($"theme: {e.Message}");
        }
#pragma warning restore WPF0001
    }

    public void ShowMainWindow()
    {
        if (MainWindow == null) return;
        MainWindow.Show();
        if (MainWindow.WindowState == WindowState.Minimized) MainWindow.WindowState = WindowState.Normal;
        MainWindow.Activate();
        WindowShown();
    }

    public void Quit()
    {
        Quitting = true;
        try
        {
            BeforeQuit();
            Model?.SaveState();
            Model?.Pipeline.Dispose();
        }
        catch (Exception e)
        {
            Log.Write($"quit: {e.Message}");
        }
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        Settings.Shared.Save();
        base.OnExit(e);
    }

    public void ShowAbout()
    {
        Notice.Show(MainWindow, $"NuVa {Version}", L.T("Pastas, som nativo, nada a mais.") + "\n\nnuva.martinsnuno.com");
    }

    // MARK: Skins and fonts

    public void SetSkin(Skin skin)
    {
        Settings.Shared.Set("skin", skin.Id);
        Theme.Set(skin, Theme.FontChoice);
        ApplyControlTheme();
    }

    public void SetFonts(FontSet? set)
    {
        Settings.Shared.Set("fontSet", set == null ? "skin" : FontSets.Id(set.Value));
        Theme.Set(Theme.Skin, set);
    }

    // MARK: Output

    public void SelectOutput(string? id)
    {
        Settings.Shared.Set("outputDevice", id);
        Model.Output.SelectDevice(id);
    }

    /// <summary>The output readout on the display: the system's output devices (the Mac's AirPlay picker).</summary>
    public async void ShowOutputMenu(FrameworkElement anchor)
    {
        var menu = new ContextMenu { PlacementTarget = anchor, Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom };
        foreach (var device in await Audio.GraphOutput.Devices())
            menu.Items.Add(QueueView.Item(device.Name, () => SelectOutput(device.Id), check: device.Id == Model.Output.SelectedDevice));
        menu.IsOpen = true;
    }

    public void RevealCurrentTrack() => MainWindow.RevealCurrentTrack();

    /// <summary>The sheet to add a Jellyfin server.</summary>
    public void AddJellyfin()
    {
        ShowMainWindow();
        Model.WindowMode = WindowMode.Browser;
        new JellyfinLogin(Model, MainWindow).ShowDialog();
    }

    /// <summary>The equalizer, under the display's EQ readout (Ctrl+Shift+E or a click on it).</summary>
    public void ShowEqualizer()
    {
        ShowMainWindow();
        if (MainWindow.Display?.EqualizerAnchor is { } anchor) EqualizerPanel.Open(Model.Equalizer, anchor);
    }
}
