using System;
using System.Globalization;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using NuVa.Core;
using NuVa.Core.Audio;
using NuVa.Core.Player;

namespace NuVa.UI;

/// <summary>What the ambient screen shows; ← → cycle through them.</summary>
public enum AmbientFace { Display, Clock, Spectrum, Meters, Needles, Valves }

/// <summary>Ambient mode's options (View ▸ Ambient Options), remembered: the face, dimming, OLED protection, the screen.</summary>
public sealed class AmbientOptions(Settings settings)
{
    public AmbientFace Face
    {
        get => Enum.TryParse<AmbientFace>(settings.Get("ambient.face", "Display"), out var f) ? f : AmbientFace.Display;
        set => settings.Set("ambient.face", value.ToString());
    }

    /// <summary>On by default.</summary>
    public bool ProtectsOled
    {
        get => settings.Get("ambient.oled", true);
        set => settings.Set("ambient.oled", value);
    }

    public bool Dims
    {
        get => settings.Get("ambient.dims", false);
        set => settings.Set("ambient.dims", value);
    }

    /// <summary>Index into the screens; -1: the window's own screen.</summary>
    public int Screen
    {
        get => settings.Get("ambient.screen", -1);
        set => settings.Set("ambient.screen", value);
    }

    public static string Name(AmbientFace face) => face switch
    {
        AmbientFace.Display => L.T("Ecrã"),
        AmbientFace.Clock => L.T("Relógio"),
        AmbientFace.Spectrum => L.T("Espectro"),
        AmbientFace.Meters => L.T("Medidores"),
        AmbientFace.Needles => L.T("Ponteiros"),
        _ => L.T("Válvulas"),
    };
}

/// <summary>
/// Ambient mode (Ambient.md in the plans): a borderless window over a whole screen that is all display,
/// in the skin's dark colours. Esc, Ctrl+4 or F11 leave; ← → change face; Space plays or pauses. Keeps the
/// screen awake while music plays. Moving the mouse shows the playback keys for 3 s.
/// </summary>
public sealed class AmbientWindow : Window
{
    private const double RestAfter = 3600, ChangeFaceAfter = 1200, IdleDim = 600;

    private readonly App app;
    private readonly AmbientOptions options;
    private readonly AmbientCanvas canvas;
    private readonly Border keys;
    private readonly KeyButton play;
    private readonly DispatcherTimer tick;
    private DateTime lastInput = DateTime.UtcNow;
    private DateTime faceShown = DateTime.UtcNow;
    private DateTime keysUntil;
    private Point lastMouse;

    public AmbientWindow(App app, AmbientOptions options, System.Windows.Forms.Screen screen)
    {
        this.app = app;
        this.options = options;
        Title = L.T("Ambiente");
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        Background = Theme.Hex(Theme.Skin.Color(Token.Display, true));
        // Placed on the screen first, then maximised there.
        var b = screen.Bounds;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Left = b.Left;
        Top = b.Top;
        Width = Math.Max(400, b.Width / 2.0);
        Height = Math.Max(300, b.Height / 2.0);
        SourceInitialized += (_, _) =>
        {
            var dpi = VisualTreeHelper.GetDpi(this);
            Left = b.Left / dpi.DpiScaleX;
            Top = b.Top / dpi.DpiScaleY;
            WindowState = WindowState.Maximized;
        };

        canvas = new AmbientCanvas(app, options);
        var grid = new Grid();
        grid.Children.Add(canvas);
        var player = app.Model.Player;
        play = new KeyButton(Tone.Play, NuVa.UI.Icon.Play, "", player.TogglePlayPause);
        var strip = new StackPanel { Orientation = Orientation.Horizontal };
        strip.Children.Add(new KeyButton(Tone.Transport, NuVa.UI.Icon.Previous, L.T("Anterior"), player.Previous));
        play.Margin = new Thickness(Space.S1, 0, Space.S1, 0);
        strip.Children.Add(play);
        strip.Children.Add(new KeyButton(Tone.Transport, NuVa.UI.Icon.Next, L.T("Seguinte"), player.Next));
        strip.Children.Add(new KeyButton(Tone.Mode, NuVa.UI.Icon.Leave, L.T("Sair do Ambiente") + " Esc", Close) { Margin = new Thickness(Space.S4, 0, 0, 0) });
        keys = new Border
        {
            Child = strip,
            Padding = new Thickness(Space.S3),
            CornerRadius = new CornerRadius(Space.RadiusMd),
            Background = Theme.Hex(Theme.Skin.Color(Token.Surface0, true)),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(0, 0, 0, 48),
            Visibility = Visibility.Collapsed,
        };
        grid.Children.Add(keys);
        Content = grid;

        PreviewKeyDown += OnKey;
        MouseMove += (_, e) =>
        {
            var p = e.GetPosition(this);
            if ((p - lastMouse).Length < 3) return;
            lastMouse = p;
            Touched();
            keysUntil = DateTime.UtcNow.AddSeconds(3);
            keys.Visibility = Visibility.Visible;
            Cursor = null;
        };
        MouseDown += (_, _) => Touched();
        Cursor = Cursors.None;

        tick = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
        tick.Tick += (_, _) => Tick();
        tick.Start();
        player.Changed += PlayerChanged;
        Closed += (_, _) =>
        {
            tick.Stop();
            player.Changed -= PlayerChanged;
            canvas.Stop();
            Power.KeepDisplayOn(false);
        };
        PlayerChanged();
    }

    public AmbientCanvas Canvas => canvas;

    private void PlayerChanged()
    {
        var playing = app.Model.Player.IsPlaying;
        play.Icon = playing ? NuVa.UI.Icon.Pause : NuVa.UI.Icon.Play;
        play.Help = (playing ? L.T("Pausa") : L.T("Tocar")) + " " + L.T("Espaço");
        canvas.PlayingChanged(playing);
        // The display stays awake while music plays; paused, Windows may dim and sleep it as usual.
        Power.KeepDisplayOn(playing);
    }

    private void Touched()
    {
        var wasResting = canvas.Resting;
        lastInput = DateTime.UtcNow;
        canvas.Resting = false;
        if (wasResting) canvas.InvalidateVisual();
    }

    private void Tick()
    {
        var now = DateTime.UtcNow;
        if (keys.Visibility == Visibility.Visible && now > keysUntil && !keys.IsMouseOver)
        {
            keys.Visibility = Visibility.Collapsed;
            Cursor = Cursors.None;
        }
        var protects = options.ProtectsOled;
        canvas.Resting = protects && (now - lastInput).TotalSeconds > RestAfter;
        // With OLED protection, a new face every 20 minutes.
        if (protects && !canvas.Resting && (now - faceShown).TotalSeconds > ChangeFaceAfter) ChangeFace(1, byHand: false);
        canvas.Dim = canvas.PausedFor > IdleDim ? 0.3 : options.Dims ? 0.4 : 1;
        canvas.InvalidateVisual();
    }

    public void ChangeFace(int step, bool byHand)
    {
        var count = Enum.GetValues<AmbientFace>().Length;
        options.Face = (AmbientFace)(((int)options.Face + step + count) % count);
        faceShown = DateTime.UtcNow;
        canvas.FaceChanged(byHand);
    }

    private void OnKey(object sender, KeyEventArgs e)
    {
        Touched();
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        var mods = Keyboard.Modifiers;
        var player = app.Model.Player;
        if (key == Key.Escape || key == Key.F11 || (mods == ModifierKeys.Control && key is Key.D4 or Key.NumPad4)) Close();
        else if (mods == ModifierKeys.None && key == Key.Left) ChangeFace(-1, byHand: true);
        else if (mods == ModifierKeys.None && key == Key.Right) ChangeFace(1, byHand: true);
        else if (mods == ModifierKeys.None && key == Key.Space) app.Model.PlayOrBrowse();
        else if (mods == ModifierKeys.Control && key == Key.Right) player.Next();
        else if (mods == ModifierKeys.Control && key == Key.Left) player.Previous();
        else if (mods == ModifierKeys.Control && key == Key.Up) player.ChangeVolume(0.05f);
        else if (mods == ModifierKeys.Control && key == Key.Down) player.ChangeVolume(-0.05f);
        else if (mods == ModifierKeys.Control && key == Key.OemPeriod) player.Stop();
        else return;
        e.Handled = true;
    }
}

/// <summary>Keeping the display on (SetThreadExecutionState), the Mac's IOPMAssertion.</summary>
internal static class Power
{
    [DllImport("kernel32.dll")]
    private static extern uint SetThreadExecutionState(uint flags);

    private const uint Continuous = 0x80000000, DisplayRequired = 0x2, SystemRequired = 0x1;

    public static void KeepDisplayOn(bool on) => SetThreadExecutionState(on ? Continuous | DisplayRequired | SystemRequired : Continuous);
}

/// <summary>
/// The faces, drawn in one element sized from the screen's width (u = 1% of it): Display, Clock,
/// Spectrum, Meters, Needles, Valves; the cover's glow behind; OLED protection (a slow wander, static
/// parts at 55%, a blinking colon, rest). Drawn every frame (at the screen's rate) while a meter moves.
/// </summary>
public sealed class AmbientCanvas : FrameworkElement
{
    private readonly App app;
    private readonly AmbientOptions options;
    private readonly SpectrumMeter fine = new(SpectrumShared.FineBands, floor: -62, ceiling: -12, fall: 0.9f, attack: 0.025f, gravity: 2.4f);
    private readonly SpectrumMeter ladders = new(2, floor: -48, ceiling: 0, fall: 1.3f, attack: 0.02f, gravity: 1.8f);
    private readonly NeedleMeter needles = new();
    private readonly SlowMeter valves = new(floor: -40, ceiling: -8, rise: 4, fall: 1.5f);
    private readonly GlowPulse pulse = new();
    private bool watching;
    private bool framing;
    private DateTime settleUntil;
    private DateTime? pausedSince;
    private DateTime nameUntil;
    private BitmapSource? glow;
    private BitmapSource? glowBefore;
    private DateTime glowChanged;
    private string? glowKey;

    public bool Resting { get; set; }
    public double Dim { get; set; } = 1;
    public double PausedFor => pausedSince is { } since ? (DateTime.UtcNow - since).TotalSeconds : 0;

    public AmbientCanvas(App app, AmbientOptions options)
    {
        this.app = app;
        this.options = options;
        app.Model.Spectrum.Watch(true);
        watching = true;
        app.ArtworkChanged += UpdateGlow;
        UpdateGlow();
        CompositionTarget.Rendering += OnFrame;
        framing = true;
    }

    public void Stop()
    {
        if (framing) CompositionTarget.Rendering -= OnFrame;
        framing = false;
        if (watching) app.Model.Spectrum.Watch(false);
        watching = false;
        app.ArtworkChanged -= UpdateGlow;
    }

    public void PlayingChanged(bool playing)
    {
        if (playing) pausedSince = null;
        else
        {
            pausedSince ??= DateTime.UtcNow;
            settleUntil = DateTime.UtcNow.AddSeconds(2);
        }
        UpdateGlow();
        InvalidateVisual();
    }

    public void FaceChanged(bool byHand)
    {
        if (byHand) nameUntil = DateTime.UtcNow.AddSeconds(3);
        InvalidateVisual();
    }

    private void OnFrame(object? sender, EventArgs e)
    {
        var face = options.Face;
        var moving = app.Model.Player.IsPlaying || DateTime.UtcNow < settleUntil;
        var animated = face is AmbientFace.Spectrum or AmbientFace.Meters or AmbientFace.Needles or AmbientFace.Valves || (face == AmbientFace.Display && glow != null && !Motion.Reduced);
        if ((moving && animated) || DateTime.UtcNow - glowChanged < TimeSpan.FromSeconds(1.6)) InvalidateVisual();
    }

    /// <summary>The field of the cover's colours, crossfading over 1.5 s between albums.</summary>
    private void UpdateGlow()
    {
        var art = app.CurrentArtwork;
        var key = art?.File + Theme.Skin.Id;
        if (key == glowKey) return;
        glowKey = key;
        glowBefore = glow;
        glow = art == null ? null : Field(art.Image);
        glowChanged = DateTime.UtcNow;
    }

    private static BitmapSource? Field(BitmapSource cover)
    {
        try
        {
            var small = new FormatConvertedBitmap(new TransformedBitmap(cover, new ScaleTransform(16.0 / cover.PixelWidth, 16.0 / cover.PixelHeight)), PixelFormats.Bgra32, null, 0);
            var pixels = new int[256];
            small.CopyPixels(pixels, 16 * 4, 0);
            var rgb = pixels.Select(p => (uint)p & 0xFFFFFF).ToArray();
            var skin = Theme.Skin;
            var field = ArtworkGlow.Field(rgb, skin.Color(Token.Display, true), skin.Color(Token.DisplayMuted, true));
            if (field == null) return null;
            var bitmap = BitmapSource.Create(ArtworkGlow.Width, ArtworkGlow.Height, 96, 96, PixelFormats.Bgr32, null,
                field.Select(c => (int)c).ToArray(), ArtworkGlow.Width * 4);
            bitmap.Freeze();
            return bitmap;
        }
        catch (Exception e)
        {
            Log.Write($"ambient: glow: {e.Message}");
            return null;
        }
    }

    // MARK: Drawing

    private Brush C(Token token, double opacity = 1) => Theme.Hex(Theme.Skin.Color(token, true), opacity);
    private static Color Tint(Token token, double opacity) => Theme.Rgb(Theme.Skin.Color(token, true), opacity);
    private double dpi = 1;

    private FormattedText Text(string text, TextStyle style, double size, Brush brush, double maxWidth = 0)
    {
        var t = style.Sized(size).Format(text, brush, dpi, maxWidth);
        return t;
    }

    private void DrawText(DrawingContext dc, FormattedText text, double x, double y, double align = 0) => dc.DrawText(text, new Point(x - text.Width * align, y));

    protected override void OnRender(DrawingContext dc)
    {
        dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var W = ActualWidth;
        var H = ActualHeight;
        dc.DrawRectangle(C(Token.Display), null, new Rect(0, 0, W, H));
        var protects = options.ProtectsOled;
        var area = protects ? 0.84 : 1;
        var u = W * area / 100;
        var now = DateTime.Now;
        var player = app.Model.Player;
        var t = Environment.TickCount64 / 1000.0;
        if (Resting)
        {
            // Only the LED, wandering on black.
            var x = W / 2 + W * 0.4 * Math.Sin(t / 571);
            var y = H / 2 + H * 0.4 * Math.Sin(t / 787 + 1);
            dc.PushOpacity(0.6);
            DrawLed(dc, new Point(x, y), u, player.IsPlaying);
            dc.Pop();
            return;
        }
        // The cover's glow behind the face; on the Display face it breathes with the bass (70% to full).
        var fade = Math.Clamp((DateTime.UtcNow - glowChanged).TotalSeconds / 1.5, 0, 1);
        var breath = 1.0;
        if (options.Face == AmbientFace.Display && glow != null && !Motion.Reduced)
            breath = 0.7 + 0.3 * pulse.Update(t, player.IsPlaying ? app.Model.Spectrum.Levels(player.CurrentTime) : null);
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
        if (glowBefore != null && fade < 1) { dc.PushOpacity((1 - fade) * Dim); dc.DrawImage(glowBefore, new Rect(0, 0, W, H)); dc.Pop(); }
        if (glow != null) { dc.PushOpacity(fade * breath * Dim); dc.DrawImage(glow, new Rect(0, 0, W, H)); dc.Pop(); }

        var (dx, dy) = Drift(protects);
        var box = new Rect(W * (1 - area) / 2 + W * dx + u * 7, H * (1 - area) / 2 + H * dy + u * 6, W * area - u * 14, H * area - u * 12);
        var still = protects ? 0.55 : 1;
        dc.PushOpacity(Dim);
        switch (options.Face)
        {
            case AmbientFace.Display: DisplayFace(dc, box, u, still); break;
            case AmbientFace.Clock: ClockFace(dc, box, u, now, protects, still); break;
            case AmbientFace.Spectrum: SpectrumFace(dc, box, u, still, t); break;
            case AmbientFace.Meters: MetersFace(dc, box, u, t); break;
            case AmbientFace.Needles: NeedlesFace(dc, box, u, still, t); break;
            default: ValvesFace(dc, box, u, t); break;
        }
        dc.Pop();
        if (DateTime.UtcNow < nameUntil)
        {
            var name = Text($"←  {AmbientOptions.Name(options.Face).ToLower(CultureInfo.CurrentCulture)}  →", TextStyle.Hint, u * 1.6, C(Token.InkMuted));
            var r = new Rect(W / 2 - name.Width / 2 - 20, H - u * 2 - name.Height - 20, name.Width + 40, name.Height + 20);
            dc.DrawRoundedRectangle(C(Token.Surface0), null, r, 6, 6);
            DrawText(dc, name, W / 2, r.Y + 10, 0.5);
        }
    }

    /// <summary>With OLED protection a slow wander over 8% of the screen each way, from two waves per axis; without, a few points each minute.</summary>
    private static (double, double) Drift(bool protects)
    {
        var t = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0;
        if (!protects)
        {
            var angle = (long)(t / 60) % 24 / 24.0 * 2 * Math.PI;
            return (Math.Cos(angle) * 0.012, Math.Sin(angle) * 0.008);
        }
        static double Wave(double t, double slow, double fast, double phase) => 0.65 * Math.Sin(2 * Math.PI * t / slow + phase) + 0.35 * Math.Sin(2 * Math.PI * t / fast + phase * 2.3);
        return (Wave(t, 3187, 1279, 0) * 0.08, Wave(t, 4253, 1531, 1.7) * 0.08);
    }

    private void DrawLed(DrawingContext dc, Point centre, double size, bool on) =>
        dc.DrawEllipse(on ? C(Token.Led) : C(Token.LedOff), null, centre, size / 2, size / 2);

    private string Source => app.Model.CurrentSourceLabel;

    /// <summary>LED, format and the source: the line at the top of every face.</summary>
    private void MetaLine(DrawingContext dc, Rect box, double u, string right)
    {
        var player = app.Model.Player;
        var size = u * 1.7;
        DrawLed(dc, new Point(box.X + u / 2, box.Y + size * 0.65), u, player.IsPlaying);
        var format = player.FormatLabel.Length > 0 ? player.FormatLabel : player.Current?.Entry.Format ?? "";
        DrawText(dc, Text(format, TextStyle.DisplayMeta, size, C(Token.DisplayMuted), box.Width * 0.6), box.X + u * 2.4, box.Y);
        DrawText(dc, Text(right, TextStyle.DisplayMeta, size, C(Token.DisplayMuted), box.Width * 0.35), box.Right, box.Y, 1);
    }

    private void Position(DrawingContext dc, double x, double y, double width, double u, double still)
    {
        var player = app.Model.Player;
        var h = Math.Max(2, u * 0.35);
        var v = player.Duration > 0 ? Math.Clamp(player.CurrentTime / player.Duration, 0, 1) : 0;
        dc.PushOpacity(still);
        dc.DrawRectangle(C(Token.DisplayTrack), null, new Rect(x, y, width, h));
        dc.DrawRectangle(C(Token.DisplayInk), null, new Rect(x, y, width * v, h));
        dc.Pop();
    }

    /// <summary>The track at the foot of the animated faces: title and folder on the left, elapsed time on the right.</summary>
    private void TrackFoot(DrawingContext dc, Rect box, double u)
    {
        var player = app.Model.Player;
        var entry = player.Current?.Entry;
        var time = Text(TimeFormat.Display(player.CurrentTime), TextStyle.DisplayTime, u * 4.4, C(Token.DisplayInk));
        DrawText(dc, time, box.Right, box.Bottom - time.Height, 1);
        var width = box.Width - time.Width - u * 2;
        var folder = Text(entry?.FolderLine ?? "", TextStyle.Body, u * 1.9, C(Token.DisplayMuted), width);
        var title = Text(entry?.Title ?? L.T("Sem faixa"), TextStyle.Title, u * 2.8, entry == null ? C(Token.DisplayMuted) : C(Token.DisplayInk), width);
        DrawText(dc, folder, box.X, box.Bottom - folder.Height - u * 0.4);
        DrawText(dc, title, box.X, box.Bottom - folder.Height - u * 1.0 - title.Height);
    }

    /// <summary>The window's display at the scale of the room.</summary>
    private void DisplayFace(DrawingContext dc, Rect box, double u, double still)
    {
        var player = app.Model.Player;
        var entry = player.Current?.Entry;
        MetaLine(dc, box, u, Source);
        var x = box.X;
        var cover = app.CurrentArtwork?.Image;
        var title = Text(entry?.Title ?? L.T("Sem faixa"), TextStyle.Title, u * 5.6, entry == null ? C(Token.DisplayMuted) : C(Token.DisplayInk), box.Width - (cover != null ? u * 12.4 : 0));
        var folder = Text(entry?.FolderLine ?? L.T("Escolher uma pasta para tocar"), TextStyle.Caption, u * 2.3, C(Token.DisplayMuted), box.Width - (cover != null ? u * 12.4 : 0));
        var blockHeight = Math.Max(cover != null ? u * 10 : 0, title.Height + u * 1.2 + folder.Height);
        var top = box.Y + box.Height * 0.36 - blockHeight / 2;
        if (cover != null)
        {
            var tile = new Rect(x, top + (blockHeight - u * 10) / 2, u * 10, u * 10);
            dc.PushClip(new RectangleGeometry(tile, 3, 3));
            dc.DrawImage(cover, tile);
            dc.Pop();
            x += u * 12.4;
        }
        var textTop = top + (blockHeight - title.Height - u * 1.2 - folder.Height) / 2;
        DrawText(dc, title, x, textTop);
        dc.PushOpacity(still);
        DrawText(dc, folder, x, textTop + title.Height + u * 1.2);
        dc.Pop();
        var bar = Math.Max(2, u * 0.35);
        var time = Text(TimeFormat.Display(player.CurrentTime), TextStyle.DisplayTime, u * 13, C(Token.DisplayInk));
        var duration = Text(TimeFormat.Display(player.Duration), TextStyle.DisplayMeta, u * 2.2, C(Token.DisplayMuted));
        DrawText(dc, time, box.X, box.Bottom - bar - u * 2 - time.Height);
        dc.PushOpacity(still);
        DrawText(dc, duration, box.Right, box.Bottom - bar - u * 2 - duration.Height * 1.6, 1);
        dc.Pop();
        Position(dc, box.X, box.Bottom - bar, box.Width, u, still);
    }

    /// <summary>The time of day as the subject, the playing track on one line below; the colon blinks with OLED protection.</summary>
    private void ClockFace(DrawingContext dc, Rect box, double u, DateTime now, bool blinks, double still)
    {
        var player = app.Model.Player;
        var colon = !blinks || now.Second % 2 == 0;
        var ink = C(Token.DisplayInk);
        var hh = Text(now.ToString("HH", CultureInfo.CurrentCulture), TextStyle.DisplayTime, u * 20, ink);
        var mm = Text(now.ToString("mm", CultureInfo.CurrentCulture), TextStyle.DisplayTime, u * 20, ink);
        var sep = Text(":", TextStyle.DisplayTime, u * 20, colon ? ink : Brushes.Transparent);
        var total = hh.WidthIncludingTrailingWhitespace + sep.WidthIncludingTrailingWhitespace + mm.Width;
        var cx = box.X + box.Width / 2;
        var y = box.Y + box.Height * 0.42 - hh.Height / 2;
        var x = cx - total / 2;
        DrawText(dc, hh, x, y);
        DrawText(dc, sep, x + hh.WidthIncludingTrailingWhitespace, y);
        DrawText(dc, mm, x + hh.WidthIncludingTrailingWhitespace + sep.WidthIncludingTrailingWhitespace, y);
        var date = Text(now.ToString(L.Portuguese ? "dddd, d 'de' MMMM" : "dddd, d MMMM", CultureInfo.CurrentCulture).ToLower(CultureInfo.CurrentCulture), TextStyle.DisplayMeta, u * 1.9, C(Token.DisplayMuted));
        dc.PushOpacity(still);
        DrawText(dc, date, cx, y + hh.Height + u * 1.4, 0.5);
        dc.Pop();
        if (player.Current?.Entry is { } entry)
        {
            var line = Text($"{entry.Title}  ·  {entry.FolderLine}", TextStyle.Body, u * 2.1, ink, u * 60);
            var ly = box.Bottom - u * 4 - line.Height;
            DrawLed(dc, new Point(cx - line.Width / 2 - u * 1.4, ly + line.Height / 2), u, player.IsPlaying);
            DrawText(dc, line, cx, ly, 0.5);
            Position(dc, cx - u * 15, ly + line.Height + u * 1.4, u * 30, u, still);
        }
    }

    /// <summary>28 bands from 20 Hz to 20 kHz as solid bars in display-ink, each with its held peak as a thin cap in led.</summary>
    private void SpectrumFace(DrawingContext dc, Rect box, double u, double still, double t)
    {
        var player = app.Model.Player;
        MetaLine(dc, box, u, "20 Hz – 20 kHz");
        fine.Update(t, player.IsPlaying ? app.Model.Spectrum.FineLevels(player.CurrentTime) : null);
        var footHeight = u * 9;
        var bar = Math.Max(2, u * 0.35);
        var top = box.Y + u * 5;
        var bottom = box.Bottom - footHeight - u * 4.6;
        var height = Math.Max(1, bottom - top);
        var columns = fine.Levels.Length;
        var gap = u * 0.75;
        var width = (box.Width - gap * (columns - 1)) / columns;
        var cap = Math.Max(2, u * 0.35);
        for (var c = 0; c < columns; c++)
        {
            var x = box.X + c * (width + gap);
            var level = fine.Levels[c] * (height - cap * 2);
            if (level > 0) dc.DrawRectangle(C(Token.DisplayInk), null, new Rect(x, bottom - level, width, level));
            var peak = fine.Peaks[c] * (height - cap * 2);
            if (fine.Peaks[c] > 0) dc.DrawRectangle(C(Token.Led), null, new Rect(x, bottom - peak - cap * 1.6, width, cap));
        }
        Position(dc, box.X, bottom + u * 1.6, box.Width, u, still);
        TrackFoot(dc, box, u);
    }

    /// <summary>Left and right as two ladders of 40 segments: RMS lit in led, the held peak in display-ink, a dBFS scale below.</summary>
    private void MetersFace(DrawingContext dc, Rect box, double u, double t)
    {
        var player = app.Model.Player;
        MetaLine(dc, box, u, Source);
        var stereo = player.IsPlaying ? app.Model.Spectrum.Stereo(player.CurrentTime) : null;
        ladders.Update(t, stereo == null ? null : [stereo[0], stereo[1]]);
        const int segments = 40;
        var labelWidth = u * 4.5;
        var ladder = box.Width - labelWidth;
        var gap = u * 0.45;
        var width = (ladder - gap * (segments - 1)) / segments;
        var row = u * 4.2;
        var top = box.Y + box.Height * 0.42 - u * 7.75;
        for (var channel = 0; channel < 2; channel++)
        {
            var y = top + channel * (row + u * 2.6);
            var label = Text(channel == 0 ? "L" : "R", TextStyle.DisplayMeta, u * 2, C(Token.DisplayMuted));
            DrawText(dc, label, box.X, y + row / 2 - label.Height / 2);
            var exact = ladders.Levels[channel] * segments;
            var lit = (int)exact;
            var held = (int)Math.Round(ladders.Peaks[channel] * segments) - 1;
            for (var s = 0; s < segments; s++)
            {
                var x = box.X + labelWidth + s * (width + gap);
                var color = s < lit ? C(Token.Led) : s == held && held >= lit ? C(Token.DisplayInk) : C(Token.DisplayTrack);
                var r = new Rect(x, y, width, row);
                dc.DrawRoundedRectangle(color, null, r, u * 0.15, u * 0.15);
                // The segment at the level's edge lights in part, so the bar glides instead of stepping.
                if (s == lit && s != held && exact > lit) dc.DrawRoundedRectangle(C(Token.Led, exact - lit), null, r, u * 0.15, u * 0.15);
            }
        }
        var scaleY = top + 2 * row + u * 2.6 + u * 1.6;
        foreach (var mark in new[] { -48, -36, -24, -18, -12, -6, -3, 0 })
        {
            var x = Math.Clamp(box.X + labelWidth + (mark + 48) / 48.0 * ladder, box.X + labelWidth + u, box.Right - u);
            DrawText(dc, Text(mark.ToString(CultureInfo.InvariantCulture), TextStyle.DisplayMeta, u * 1.5, C(Token.DisplayMuted)), x, scaleY, 0.5);
        }
        TrackFoot(dc, box, u);
    }

    private static double Deflection(double vu) => VUNeedle.Deflection(vu);

    /// <summary>Two backlit VU meters under glass: an arc from −20 to +3 VU, a tapered needle with its shadow, a peak light.</summary>
    private void NeedlesFace(DrawingContext dc, Rect box, double u, double still, double t)
    {
        var player = app.Model.Player;
        MetaLine(dc, box, u, Source);
        needles.Update(t, player.IsPlaying ? app.Model.Spectrum.Stereo(player.CurrentTime) : null);
        var gap = u * 4;
        var w = (box.Width - gap) / 2;
        var h = w / 1.9;
        var top = box.Y + (box.Height - u * 9 - h) / 2;
        for (var channel = 0; channel < 2; channel++)
            VuPanel(dc, new Rect(box.X + channel * (w + gap), top, w, h), needles.Levels[channel], needles.Peaks[channel] > -1, channel, u, still);
        TrackFoot(dc, box, u);
    }

    private void VuPanel(DrawingContext dc, Rect r, double deflection, bool clipping, int channel, double u, double still)
    {
        var corner = u * 0.4;
        var panel = new RectangleGeometry(r, corner, corner);
        // The lamp: the skin's ink warmed by its accent, lit from behind by one bulb.
        dc.DrawGeometry(C(Token.Ink), null, panel);
        dc.DrawGeometry(C(Token.Led, 0.5), null, panel);
        var lamp = new RadialGradientBrush(Tint(Token.Display, 0), Tint(Token.Display, 0.4))
        {
            MappingMode = BrushMappingMode.Absolute,
            Center = new Point(r.X + r.Width / 2, r.Y + r.Height * 0.6),
            GradientOrigin = new Point(r.X + r.Width / 2, r.Y + r.Height * 0.6),
            RadiusX = r.Width * 0.62,
            RadiusY = r.Width * 0.62,
        };
        dc.DrawGeometry(lamp, null, panel);
        dc.DrawGeometry(C(Token.Display, (1 - still) * 0.55), null, panel);

        var printed = C(Token.Display, 0.85);
        var pivot = new Point(r.X + r.Width / 2, r.Y + r.Height * 1.18);
        var radius = r.Height * 0.95;
        const double sweep = 0.78;
        double Angle(double p) => -Math.PI / 2 - sweep + 2 * sweep * p;
        Point At(double p, double rr) => new(pivot.X + Math.Cos(Angle(p)) * rr, pivot.Y + Math.Sin(Angle(p)) * rr);
        void Arc(double from, double to, double rr, double width)
        {
            var figure = new PathFigure { StartPoint = At(from, rr) };
            figure.Segments.Add(new ArcSegment(At(to, rr), new Size(rr, rr), 0, false, SweepDirection.Clockwise, true));
            dc.DrawGeometry(null, new Pen(printed, width), new PathGeometry([figure]));
        }
        dc.PushClip(panel);
        Arc(Deflection(-20), 1, radius, Math.Max(1, u * 0.12));
        Arc(Deflection(0), 1, radius + u * 0.35, u * 0.6);
        int[] labelled = [-20, -10, -7, -5, -3, 0, 3];
        foreach (var mark in new[] { -20, -10, -7, -5, -3, -1, 0, 1, 2, 3 })
        {
            var p = Deflection(mark);
            var isLabelled = labelled.Contains(mark);
            dc.DrawLine(new Pen(printed, Math.Max(1, u * 0.14)), At(p, radius), At(p, radius + u * (isLabelled ? 1.1 : 0.7)));
            if (isLabelled)
            {
                var label = Text(mark > 0 ? $"+{mark}" : $"{mark}", TextStyle.DisplayMeta, u * 1.25, printed);
                var at = At(p, radius + u * 2.2);
                DrawText(dc, label, at.X, at.Y - label.Height / 2, 0.5);
            }
        }
        var vu = Text("VU", TextStyle.DisplayMeta, u * 1.6, printed);
        DrawText(dc, vu, r.X + r.Width / 2, r.Y + r.Height * 0.62 - vu.Height / 2, 0.5);
        var ch = Text(channel == 0 ? "L" : "R", TextStyle.DisplayMeta, u * 1.3, C(Token.Display, 0.6));
        DrawText(dc, ch, r.X + u * 1.6, r.Bottom - u * 1.4 - ch.Height / 2, 0.5);

        // The needle, tapered from its hidden pivot to a fine tip past the arc, with its shadow.
        var a = Angle(deflection);
        var along = new Vector(Math.Cos(a), Math.Sin(a));
        var across = new Vector(-Math.Sin(a), Math.Cos(a));
        Geometry Needle(Vector shift)
        {
            var wide = Math.Max(1.2, u * 0.13);
            var fineW = Math.Max(0.6, u * 0.045);
            var b = radius * 0.19;
            var tip = radius + u * 1.2;
            Point P(double rr, double side) => pivot + along * rr + across * side + shift;
            var f = new PathFigure { StartPoint = P(b, -wide), IsClosed = true, IsFilled = true };
            f.Segments.Add(new PolyLineSegment([P(tip, -fineW), P(tip, fineW), P(b, wide)], true));
            return new PathGeometry([f]);
        }
        dc.DrawGeometry(C(Token.Display, 0.22), null, Needle(new Vector(u * 0.22, u * 0.4)));
        dc.DrawGeometry(C(Token.Display), null, Needle(new Vector()));
        // Under glass: a faint sheen across the top and a shadow inside the opening.
        dc.DrawRectangle(new LinearGradientBrush(Tint(Token.DisplayInk, 0.07), Tint(Token.DisplayInk, 0), new Point(0.3, 0), new Point(0.45, 0.5)), null, r);
        dc.DrawGeometry(null, new Pen(C(Token.Display, 0.35), u * 1.2), panel);
        dc.Pop();
        var light = new Point(r.Right - u * 1.55, r.Y + u * 1.45);
        if (clipping)
        {
            dc.DrawEllipse(new RadialGradientBrush(Tint(Token.Led, 0.8), Tint(Token.Led, 0)), null, light, u * 1.2, u * 1.2);
        }
        dc.DrawEllipse(clipping ? C(Token.Led) : C(Token.Display, 0.35), null, light, u * 0.45, u * 0.45);
    }

    /// <summary>Two valves in their cage, the filaments glowing with each channel (in led), warm while paused.</summary>
    private void ValvesFace(DrawingContext dc, Rect box, double u, double t)
    {
        var player = app.Model.Player;
        MetaLine(dc, box, u, Source);
        valves.Update(t, player.IsPlaying ? app.Model.Spectrum.Stereo(player.CurrentTime) : null);
        var available = box.Height - u * 9 - u * 6;
        var h = available * 0.8;
        var w = h * 0.62;
        var gap = u * 10;
        var left = box.X + box.Width / 2 - w - gap / 2;
        var top = box.Y + u * 3 + (available - h) / 2;
        for (var channel = 0; channel < 2; channel++)
            Valve(dc, new Rect(left + channel * (w + gap), top, w, h), valves.Levels[channel], player.Current != null, channel, u);
        TrackFoot(dc, box, u);
    }

    private void Valve(DrawingContext dc, Rect r, double glowLevel, bool heated, int channel, double u)
    {
        double w = r.Width, h = r.Height, ox = r.X, oy = r.Y;
        var metal = C(Token.DisplayTrack);
        var line = Math.Max(1, u * 0.14);
        var level = heated ? 0.2 + 0.8 * glowLevel : 0;
        double left = ox + w * 0.24, right = ox + w * 0.76, top = oy + h * 0.16, shoulder = oy + h * 0.3, bottom = oy + h * 0.86;
        var envelope = new PathFigure { StartPoint = new Point(left, bottom) };
        envelope.Segments.Add(new LineSegment(new Point(left, shoulder), true));
        envelope.Segments.Add(new QuadraticBezierSegment(new Point(ox + w / 2, top - h * 0.1), new Point(right, shoulder), true));
        envelope.Segments.Add(new LineSegment(new Point(right, bottom), true));
        var outline = new PathGeometry([envelope]);
        var centre = new Point(ox + w / 2, oy + h * 0.57);
        Color Led(double alpha) => Tint(Token.Led, alpha);
        RadialGradientBrush Radial(Color inner, Color outer, double radius) => new(inner, outer)
        {
            MappingMode = BrushMappingMode.Absolute, Center = centre, GradientOrigin = centre, RadiusX = radius, RadiusY = radius,
        };
        if (level > 0)
        {
            var outer = w * (0.35 + 0.25 * level);
            dc.DrawRectangle(Radial(Led(0.35 * level), Led(0), outer), null, new Rect(centre.X - outer, centre.Y - outer, outer * 2, outer * 2));
            var inside = new PathFigure { StartPoint = envelope.StartPoint, IsClosed = true, IsFilled = true };
            foreach (var s in envelope.Segments) inside.Segments.Add(s.Clone());
            dc.DrawGeometry(Radial(Led(level), Led(0.3 * level), h * (0.18 + 0.35 * level)), null, new PathGeometry([inside]));
        }
        dc.DrawGeometry(null, new Pen(C(Token.DisplayMuted, 0.8), line), outline);
        dc.DrawEllipse(metal, null, new Point(ox + w * 0.5, oy + h * 0.235), w * 0.12, h * 0.035);
        dc.DrawRoundedRectangle(null, new Pen(metal, w * 0.035), new Rect(ox + w * 0.36, oy + h * 0.42, w * 0.28, h * 0.3), u * 0.3, u * 0.3);
        var filamentTop = new Point(ox + w / 2, oy + h * 0.44);
        var filamentBottom = new Point(ox + w / 2, oy + h * 0.7);
        dc.DrawLine(new Pen(level > 0 ? new SolidColorBrush(Led(0.5 + 0.5 * level)) : metal, line * 1.4) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, filamentTop, filamentBottom);
        if (level > 0.4) dc.DrawLine(new Pen(C(Token.DisplayInk, Math.Min(1, (level - 0.4) * 1.4)), line * 0.6) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, filamentTop, filamentBottom);
        dc.DrawRoundedRectangle(metal, null, new Rect(ox + w * 0.2, bottom, w * 0.6, h * 0.08), u * 0.2, u * 0.2);
        foreach (var x in new[] { w * 0.13, w * 0.87 }) dc.DrawRoundedRectangle(metal, null, new Rect(ox + x - w * 0.025, oy + h * 0.08, w * 0.05, h * 0.8), u * 0.3, u * 0.3);
        foreach (var y in new[] { h * 0.09, h * 0.36, h * 0.66 }) dc.DrawRoundedRectangle(metal, null, new Rect(ox + w * 0.08, oy + y, w * 0.84, h * 0.028), u * 0.3, u * 0.3);
        var label = Text(channel == 0 ? "L" : "R", TextStyle.DisplayMeta, u * 1.5, C(Token.DisplayMuted));
        DrawText(dc, label, ox + w / 2, oy + h * 0.98 - label.Height / 2, 0.5);
    }
}
