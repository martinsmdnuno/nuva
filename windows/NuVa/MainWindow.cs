using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Threading;
using NuVa.Core;
using NuVa.Core.Player;
using NuVa.UI;

namespace NuVa;

/// <summary>
/// One device in every mode (PlayerWindow.md): display, keys, the header, and below them the queue or the
/// folders, or neither in compact mode (height from content). The width is free from 360 to 480; with
/// the queue or the folders the height is free too (minimum 540). Both sizes are remembered.
/// </summary>
public sealed class MainWindow : Window
{
    public const double MinContentWidth = 360, MaxContentWidth = 480, MinContentHeight = 540;

    private readonly App app;
    private readonly AppModel model;
    private readonly Grid root = new() { Margin = new Thickness(Space.S4) };
    private readonly DispatcherTimer ticker;
    private DisplayView? display;
    private ControlBar? controls;
    private ContentControl header = new();
    private QueueView? queue;
    private BrowserView? browser;
    private Size chrome = new(16, 39);
    private bool measuredChrome;
    private WindowMode laidOut;
    private int queueCount = -1;

    public MainWindow(App app)
    {
        this.app = app;
        model = app.Model;
        Title = "NuVa";
        Icon = System.Windows.Media.Imaging.BitmapFrame.Create(new Uri("pack://application:,,,/NuVa;component/Assets/icon-256.png"));
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        Content = root;
        var width = model.Settings.Get("playerWidth", MinContentWidth);
        Width = Math.Clamp(width, MinContentWidth, MaxContentWidth) + chrome.Width;
        Height = Math.Max(MinContentHeight, model.Settings.Get("listHeight", MinContentHeight)) + chrome.Height;
        if (model.Settings.Get<double?>("windowLeft", null) is { } left && model.Settings.Get<double?>("windowTop", null) is { } top && OnScreen(left, top))
        {
            WindowStartupLocation = WindowStartupLocation.Manual;
            Left = left;
            Top = top;
        }
        else
        {
            WindowStartupLocation = WindowStartupLocation.CenterScreen;
        }

        Build();
        model.Changed += Build;
        Theme.Changed += Build;
        model.Player.Changed += PlayerChanged;
        model.Durations.Changed += () => { queue?.Refresh(); browser?.RefreshRows(); RebuildHeader(); };
        model.Browser.Changed += () => { if (model.WindowMode == WindowMode.Browser) RebuildHeader(); };
        model.Output.DeviceChanged += () => Dispatcher.BeginInvoke(() => display?.Refresh());
        model.Equalizer.Changed += () => display?.Refresh();

        // The time and the position bar: 10 times a second is plenty for a readout in seconds.
        ticker = new DispatcherTimer(DispatcherPriority.Render) { Interval = TimeSpan.FromMilliseconds(100) };
        ticker.Tick += (_, _) => display?.Tick();
        ticker.Start();

        Loaded += (_, _) => MeasureChrome();
        SizeChanged += (_, _) => Remember();
        LocationChanged += (_, _) => { if (WindowState == WindowState.Normal) { model.Settings.Set("windowLeft", Left); model.Settings.Set("windowTop", Top); } };
        SourceInitialized += (_, _) =>
        {
            var source = HwndSource.FromHwnd(new WindowInteropHelper(this).Handle);
            source.AddHook(Hook);
            PaintTitleBar();
        };
        PreviewKeyDown += OnKey;
        MouseRightButtonUp += (_, e) =>
        {
            if (e.Handled) return;
            OpenMenu(null);
            e.Handled = true;
        };
    }

    private static bool OnScreen(double left, double top) =>
        left >= SystemParameters.VirtualScreenLeft - 50 && top >= SystemParameters.VirtualScreenTop - 10 &&
        left < SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth - 100 &&
        top < SystemParameters.VirtualScreenTop + SystemParameters.VirtualScreenHeight - 100;

    public DisplayView? Display => display;

    /// <summary>Lays the device out again: a new mode, skin, font set or View option.</summary>
    private void Build()
    {
        Background = Theme.Brush(Token.Surface0);
        PaintTitleBar();
        root.Children.Clear();
        var compact = model.WindowMode == WindowMode.Compact;
        display = new DisplayView(model, allowsArtwork: !compact, isMain: true);
        display.EqualizerClicked += app.ShowEqualizer;
        display.OutputClicked += app.ShowOutputMenu;
        display.ArtworkClicked += () => { if (app.CanFixArtwork) app.FixArtwork(); };
        app.ApplyArtwork(display);
        Grid.SetRow(display, 0);
        root.Children.Add(display);

        controls = new ControlBar(model) { Margin = new Thickness(0, Space.S4, 0, 0) };
        Grid.SetRow(controls, 1);
        root.Children.Add(controls);

        header = new ContentControl { Margin = new Thickness(0, Space.S4, 0, 0), Focusable = false };
        Grid.SetRow(header, 2);
        root.Children.Add(header);
        RebuildHeader();

        queue = null;
        browser = null;
        UIElement? below = model.WindowMode switch
        {
            WindowMode.Player => queue = new QueueView(model, this),
            WindowMode.Browser => browser = new BrowserView(model, this),
            _ => null,
        };
        if (below != null)
        {
            if (below is FrameworkElement f) f.Margin = new Thickness(0, Space.S1 + 2, 0, 0);
            Grid.SetRow(below, 3);
            root.Children.Add(below);
            Motion.FadeIn(below);
        }
        queueCount = model.Player.Queue.Count;
        ApplyMode();
    }

    private void RebuildHeader() => header.Content = new QueueHeader(model, id => app.EjectDisc(id));

    private void PlayerChanged()
    {
        display?.Refresh();
        controls?.Refresh();
        app.ApplyArtwork(display);
        if (model.Player.Queue.Count != queueCount)
        {
            // The queue went empty or got its first tracks: the empty state comes or goes.
            var emptiness = queueCount == 0 || model.Player.Queue.Count == 0;
            queueCount = model.Player.Queue.Count;
            if (emptiness && model.WindowMode == WindowMode.Player) { Build(); return; }
            RebuildHeader();
        }
        queue?.Rebuild();
        browser?.RefreshRows();
    }

    public void RevealCurrentTrack()
    {
        if (model.WindowMode != WindowMode.Player) model.WindowMode = WindowMode.Player;
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, () => queue?.RevealCurrent());
    }

    // MARK: Size

    private void MeasureChrome()
    {
        if (measuredChrome || root.ActualWidth <= 0) return;
        measuredChrome = true;
        var content = (FrameworkElement)Content;
        chrome = new Size(Math.Max(0, ActualWidth - content.ActualWidth), Math.Max(0, ActualHeight - content.ActualHeight));
        ApplyMode(force: true);
    }

    private void ApplyMode(bool force = false)
    {
        var mode = model.WindowMode;
        MinWidth = MinContentWidth + chrome.Width;
        MaxWidth = MaxContentWidth + chrome.Width;
        if (!force && mode == laidOut && IsLoaded) return;
        var wasCompact = laidOut == WindowMode.Compact;
        laidOut = mode;
        if (mode == WindowMode.Compact)
        {
            // The height follows the content, no resize.
            MinHeight = 0;
            MaxHeight = double.PositiveInfinity;
            SizeToContent = SizeToContent.Height;
            Dispatcher.BeginInvoke(DispatcherPriority.Loaded, () =>
            {
                if (model.WindowMode != WindowMode.Compact) return;
                MinHeight = ActualHeight;
                MaxHeight = ActualHeight;
            });
        }
        else
        {
            SizeToContent = SizeToContent.Manual;
            MaxHeight = double.PositiveInfinity;
            MinHeight = MinContentHeight + chrome.Height;
            if (wasCompact || force) Height = Math.Max(MinContentHeight, model.Settings.Get("listHeight", MinContentHeight)) + chrome.Height;
        }
    }

    private void Remember()
    {
        if (!measuredChrome || WindowState != WindowState.Normal) return;
        var content = (FrameworkElement)Content;
        if (content.ActualWidth >= MinContentWidth - 0.5) model.Settings.Set("playerWidth", Math.Round(content.ActualWidth));
        if (model.WindowMode != WindowMode.Compact && SizeToContent == SizeToContent.Manual && content.ActualHeight >= MinContentHeight - 0.5)
            model.Settings.Set("listHeight", Math.Round(content.ActualHeight));
    }

    // MARK: Title bar

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    /// <summary>Windows 11: the title bar in the chassis colour, dark or light with the skin.</summary>
    private void PaintTitleBar()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd == IntPtr.Zero) return;
        var dark = Theme.Dark ? 1 : 0;
        DwmSetWindowAttribute(hwnd, 20, ref dark, sizeof(int)); // DWMWA_USE_IMMERSIVE_DARK_MODE
        int Colorref(Token token)
        {
            var hex = Theme.Hex(token);
            return (int)(((hex & 0xFF) << 16) | (hex & 0xFF00) | ((hex >> 16) & 0xFF));
        }
        var caption = Colorref(Token.Surface0);
        var text = Colorref(Token.Ink);
        DwmSetWindowAttribute(hwnd, 35, ref caption, sizeof(int)); // DWMWA_CAPTION_COLOR
        DwmSetWindowAttribute(hwnd, 36, ref text, sizeof(int)); // DWMWA_TEXT_COLOR
    }

    // MARK: Menu and keys

    private const int WM_SYSCOMMAND = 0x0112, WM_SETTINGCHANGE = 0x001A, WM_DEVICECHANGE = 0x0219;
    private const int SC_KEYMENU = 0xF100, SC_MOUSEMENU = 0xF090;

    private IntPtr Hook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WM_SYSCOMMAND)
        {
            var command = (int)wParam & 0xFFF0;
            // Alt or F10 alone (lParam 0), or a click on the title bar's icon: NuVa's menu, not the system's.
            if ((command == SC_KEYMENU && lParam == IntPtr.Zero) || command == SC_MOUSEMENU)
            {
                OpenMenu(new Point(0, 0));
                handled = true;
            }
        }
        else if (msg == WM_SETTINGCHANGE && lParam != IntPtr.Zero && Marshal.PtrToStringUni(lParam) == "ImmersiveColorSet")
        {
            Theme.RefreshSystem();
        }
        else if (msg == WM_DEVICECHANGE)
        {
            app.DeviceChanged((int)wParam, lParam);
        }
        return IntPtr.Zero;
    }

    /// <summary>Opens NuVa's menu at the mouse, or at a point of the window.</summary>
    public void OpenMenu(Point? at)
    {
        var menu = AppMenu.Build(app);
        menu.PlacementTarget = this;
        if (at is { } p)
        {
            menu.Placement = System.Windows.Controls.Primitives.PlacementMode.Relative;
            menu.HorizontalOffset = p.X;
            menu.VerticalOffset = p.Y;
        }
        menu.IsOpen = true;
    }

    private void OnKey(object sender, KeyEventArgs e)
    {
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        var mods = Keyboard.Modifiers;
        var player = model.Player;
        var ctrl = mods == ModifierKeys.Control;
        var ctrlShift = mods == (ModifierKeys.Control | ModifierKeys.Shift);
        Action? action = null;
        if (mods == ModifierKeys.None && key == Key.Space && Keyboard.FocusedElement is not (KeyButton or Readout or TextBox))
            action = model.PlayOrBrowse;
        else if (mods == ModifierKeys.None && key == Key.F11) action = app.ToggleAmbient;
        else if (ctrl) action = key switch
        {
            Key.Right => player.Next,
            Key.Left => player.Previous,
            Key.OemPeriod => player.Stop,
            Key.Up => () => player.ChangeVolume(0.05f),
            Key.Down => () => player.ChangeVolume(-0.05f),
            Key.L => RevealCurrentTrack,
            Key.B => model.ToggleBrowser,
            Key.D1 or Key.NumPad1 => () => model.WindowMode = WindowMode.Player,
            Key.D2 or Key.NumPad2 => () => model.WindowMode = WindowMode.Browser,
            Key.D3 or Key.NumPad3 => () => model.WindowMode = WindowMode.Compact,
            Key.D4 or Key.NumPad4 => app.ToggleAmbient,
            Key.O => () => model.AddFolder(this),
            Key.E => () => app.EjectDisc(null),
            Key.R => () => player.RepeatMode = player.RepeatMode switch { RepeatMode.Off => RepeatMode.All, RepeatMode.All => RepeatMode.One, _ => RepeatMode.Off },
            Key.Q => app.Quit,
            Key.W => Close,
            _ => null,
        };
        else if (ctrlShift) action = key switch
        {
            Key.Right => () => player.Skip(10),
            Key.Left => () => player.Skip(-10),
            Key.E => app.ShowEqualizer,
            Key.Delete or Key.Back => player.Clear,
            Key.O => app.AddJellyfin,
            Key.S => () => player.Shuffle = !player.Shuffle,
            Key.A => () => model.ShowsArtwork = !model.ShowsArtwork,
            Key.V => () => model.ShowsSpectrum = !model.ShowsSpectrum,
            Key.D1 or Key.NumPad1 => () => app.SetSkin(Skin.All[0]),
            Key.D2 or Key.NumPad2 => () => app.SetSkin(Skin.All[1]),
            Key.D3 or Key.NumPad3 => () => app.SetSkin(Skin.All[2]),
            _ => null,
        };
        if (action == null && !app.SystemMediaControls) action = MediaKey(key);
        if (action == null) return;
        action();
        e.Handled = true;
    }

    /// <summary>The keyboard's media keys, when the system media controls aren't there to take them.</summary>
    private Action? MediaKey(Key key) => key switch
    {
        Key.MediaPlayPause => model.PlayOrBrowse,
        Key.MediaNextTrack => model.Player.Next,
        Key.MediaPreviousTrack => model.Player.Previous,
        Key.MediaStop => model.Player.Stop,
        _ => null,
    };

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        base.OnClosing(e);
        if (app.Quitting) return;
        // Closing the window doesn't stop the music: NuVa stays in the notification area.
        e.Cancel = true;
        Hide();
        app.WindowHidden();
    }
}
