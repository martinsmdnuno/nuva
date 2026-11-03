using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using NuVa.Core;

namespace NuVa.UI;

/// <summary>Spacing, radius and size tokens (tokens.json).</summary>
public static class Space
{
    public const double S1 = 4, S2 = 8, S3 = 12, S4 = 16, S6 = 24;
    public const double RadiusSm = 3, RadiusMd = 6, RadiusLg = 10;
    public const double Key = 36, KeySm = 32, KeyMd = 40, KeyLg = 56, KeyText = 28, Led = 4, Row = 28, Bar = 2;
}

/// <summary>Motion tokens (Motion.swift). Everything snaps when Windows' animation effects are off.</summary>
public static class Motion
{
    public static bool Reduced => !SystemParameters.ClientAreaAnimation;

    public static Duration Press => D(60);
    public static Duration Release => D(180);
    public static Duration LedOn => D(80);
    public static Duration LedOff => D(350);
    public static Duration Hover => D(120);
    public static Duration State => D(200);
    public static Duration Fader => D(300);

    private static Duration D(int ms) => new(TimeSpan.FromMilliseconds(Reduced ? 0 : ms));

    /// <summary>Animates a double property to a value, from wherever it is.</summary>
    public static void To(UIElement element, DependencyProperty property, double value, Duration duration)
    {
        element.BeginAnimation(property, new DoubleAnimation(value, duration) { EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut } });
    }

    /// <summary>Cross-fades an element in place after a state change (200 ms).</summary>
    public static void FadeIn(UIElement element)
    {
        if (Reduced) return;
        element.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0.2, 1, State));
    }
}

/// <summary>Indicator light: on state, playback, the track playing. Lights in 80 ms, fades in 350 ms.</summary>
public sealed class Led : FrameworkElement
{
    private bool isOn;

    public static readonly DependencyProperty GlowProperty = DependencyProperty.Register(
        nameof(Glow), typeof(double), typeof(Led), new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsRender));

    public double Glow
    {
        get => (double)GetValue(GlowProperty);
        set => SetValue(GlowProperty, value);
    }

    public Led(double size = Space.Led)
    {
        Width = size;
        Height = size;
        IsHitTestVisible = false;
    }

    public bool IsOn
    {
        get => isOn;
        set
        {
            if (isOn == value) return;
            isOn = value;
            Motion.To(this, GlowProperty, value ? 1 : 0, value ? Motion.LedOn : Motion.LedOff);
        }
    }

    /// <summary>Sets the state without the fade (first layout).</summary>
    public void Set(bool on)
    {
        isOn = on;
        BeginAnimation(GlowProperty, null);
        Glow = on ? 1 : 0;
    }

    /// <summary>The "off" colour; the display's LED sits on the display, not the chassis.</summary>
    public Token OffToken { get; set; } = Token.LedOff;

    protected override void OnRender(DrawingContext dc)
    {
        var r = ActualWidth / 2;
        var c = new Point(r, r);
        dc.DrawEllipse(Theme.Brush(OffToken), null, c, r, r);
        if (Glow > 0) dc.DrawEllipse(Theme.Brush(Token.Led, Glow), null, c, r, r);
    }
}

public enum Tone { Play, Transport, Mode }

/// <summary>
/// The device's flat key, as on a Braun calculator: no outline, the face is the edge. Pressed, the face
/// darkens 15% and travels 1px; with keyboard focus, a 2px ring 4px away. An icon key (36 high, width by
/// tone) or a text key (28 high, in the mode tone).
/// </summary>
public class KeyButton : FrameworkElement
{
    private bool pressed;
    private Icon icon;
    private readonly string? text;

    public static readonly DependencyProperty PressProperty = DependencyProperty.Register(
        nameof(Press), typeof(double), typeof(KeyButton), new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsRender));

    public double Press
    {
        get => (double)GetValue(PressProperty);
        set => SetValue(PressProperty, value);
    }

    public Tone Tone { get; }
    public event Action? Click;
    /// <summary>A text key that can't be used yet (a sheet's key before its fields are filled): the legend at 40%.</summary>
    public bool Available { get; set; } = true;

    public KeyButton(Tone tone, Icon icon, string help, Action? click = null)
    {
        Tone = tone;
        this.icon = icon;
        Width = tone switch { Tone.Play => Space.KeyLg, Tone.Transport => Space.KeyMd, _ => Space.KeySm };
        Height = Space.Key;
        Init(help, click);
    }

    public KeyButton(string text, string? help = null, Action? click = null)
    {
        Tone = Tone.Mode;
        this.text = text;
        Height = Space.KeyText;
        Init(help, click);
    }

    private void Init(string? help, Action? click)
    {
        if (click != null) Click += click;
        Focusable = true;
        FocusVisualStyle = null;
        Cursor = Cursors.Arrow;
        Help = help;
        AutomationProperties_SetName(help ?? text ?? "");
    }

    private void AutomationProperties_SetName(string name) =>
        System.Windows.Automation.AutomationProperties.SetName(this, Spoken(name));

    /// <summary>A tooltip without its shortcut: "Anterior Ctrl+←" → "Anterior".</summary>
    public static string Spoken(string help)
    {
        var at = help.IndexOf("Ctrl+", StringComparison.Ordinal);
        if (at < 0) at = help.IndexOf("Alt+", StringComparison.Ordinal);
        return (at > 0 ? help[..at] : help).Trim();
    }

    public string? Help
    {
        get => ToolTip as string;
        set => ToolTip = string.IsNullOrEmpty(value) ? null : value;
    }

    public Icon Icon
    {
        get => icon;
        set
        {
            if (icon == value) return;
            icon = value;
            InvalidateVisual();
        }
    }

    protected override Size MeasureOverride(Size available)
    {
        if (text == null) return new Size(Width, Height);
        var formatted = TextStyle.Label.Format(text, Brushes.Black, VisualTreeHelper.GetDpi(this).PixelsPerDip);
        return new Size(Math.Ceiling(formatted.WidthIncludingTrailingWhitespace) + 2 * Space.S3, Space.KeyText);
    }

    protected override void OnRender(DrawingContext dc)
    {
        var face = Tone switch { Tone.Play => Token.KeyPlay, Tone.Transport => Token.KeyFace, _ => Token.KeyMode };
        var ink = Tone == Tone.Mode ? Token.KeyModeInk : Token.KeyInk;
        var rect = new Rect(0, Press, ActualWidth, ActualHeight);
        dc.DrawRoundedRectangle(Theme.Brush(face), null, rect, Space.RadiusSm, Space.RadiusSm);
        if (Press > 0) dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb((byte)(0.15 * 255 * Press), 0, 0, 0)), null, rect, Space.RadiusSm, Space.RadiusSm);
        var brush = Available ? Theme.Brush(ink) : Theme.Brush(ink, 0.4);
        var centre = new Point(ActualWidth / 2, ActualHeight / 2 + Press);
        if (text != null)
        {
            var formatted = TextStyle.Label.Format(text, brush, VisualTreeHelper.GetDpi(this).PixelsPerDip);
            dc.DrawText(formatted, new Point(centre.X - formatted.Width / 2, centre.Y - formatted.Height / 2));
        }
        else
        {
            var size = Tone switch { Tone.Play => 18.0, Tone.Transport => 16.0, _ => 14.0 };
            Icons.Draw(dc, icon, centre, size + 4, brush);
        }
        if (IsKeyboardFocused && InputManager.Current.MostRecentInputDevice is KeyboardDevice)
        {
            var ring = new Rect(-4, -4, ActualWidth + 8, ActualHeight + 8);
            dc.DrawRoundedRectangle(null, new Pen(Theme.Brush(Token.Focus), 2), ring, Space.RadiusSm + 4, Space.RadiusSm + 4);
        }
    }

    protected override void OnGotKeyboardFocus(KeyboardFocusChangedEventArgs e) { base.OnGotKeyboardFocus(e); InvalidateVisual(); }
    protected override void OnLostKeyboardFocus(KeyboardFocusChangedEventArgs e) { base.OnLostKeyboardFocus(e); InvalidateVisual(); }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        pressed = true;
        CaptureMouse();
        Motion.To(this, PressProperty, 1, Motion.Press);
        e.Handled = true;
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        var inside = IsMouseOver;
        Up();
        if (inside) Activate();
        e.Handled = true;
    }

    protected override void OnLostMouseCapture(MouseEventArgs e)
    {
        base.OnLostMouseCapture(e);
        if (pressed) Up();
    }

    private void Up()
    {
        pressed = false;
        ReleaseMouseCapture();
        BeginAnimation(PressProperty, new DoubleAnimation(0, Motion.Release) { EasingFunction = new BackEase { Amplitude = 0.4, EasingMode = EasingMode.EaseOut } });
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (e.Key is Key.Space or Key.Enter && Keyboard.Modifiers == ModifierKeys.None)
        {
            Activate();
            e.Handled = true;
        }
    }

    protected virtual void Activate()
    {
        if (Available) Click?.Invoke();
    }

    // Accessibility: a button to screen readers.
    protected override System.Windows.Automation.Peers.AutomationPeer OnCreateAutomationPeer() => new KeyPeer(this);

    private sealed class KeyPeer(KeyButton key) : System.Windows.Automation.Peers.FrameworkElementAutomationPeer(key),
        System.Windows.Automation.Provider.IInvokeProvider
    {
        protected override System.Windows.Automation.Peers.AutomationControlType GetAutomationControlTypeCore() =>
            System.Windows.Automation.Peers.AutomationControlType.Button;
        public override object? GetPattern(System.Windows.Automation.Peers.PatternInterface pattern) =>
            pattern == System.Windows.Automation.Peers.PatternInterface.Invoke ? this : base.GetPattern(pattern);
        public void Invoke() => key.Activate();
    }
}

/// <summary>Builders for the chassis' printed text.</summary>
public static class Text
{
    public static TextBlock Make(string text, TextStyle style, Token color, double? height = null)
    {
        var block = new TextBlock { Text = text, Foreground = Theme.Brush(color), TextTrimming = TextTrimming.CharacterEllipsis };
        style.Apply(block);
        if (height is { } h) { block.Height = h; block.LineHeight = h; block.LineStackingStrategy = LineStackingStrategy.BlockLineHeight; }
        return block;
    }

    /// <summary>Legend printed on the chassis below a group of keys or in front of an area.</summary>
    public static TextBlock Legend(string text) => Make(text, TextStyle.Legend, Token.InkMuted);
}

/// <summary>A key with its LED above (or the empty space where one would be, so faces line up).</summary>
public sealed class KeyWithLed : StackPanel
{
    public Led? Led { get; }
    public KeyButton Key { get; }

    public KeyWithLed(KeyButton key, bool hasLed)
    {
        Key = key;
        Orientation = Orientation.Vertical;
        if (hasLed)
        {
            Led = new Led { HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, Space.S1) };
            Children.Add(Led);
        }
        else
        {
            Children.Add(new FrameworkElement { Height = Space.Led, Margin = new Thickness(0, 0, 0, Space.S1) });
        }
        Children.Add(key);
    }
}

/// <summary>
/// A readout that is also a control (the output and the equalizer on the display, the queue's legend):
/// text in a resting colour that goes to its hover colour in 120 ms. No background, no underline.
/// </summary>
public sealed class Readout : StackPanel
{
    private readonly Token rest;
    private readonly Token hover;
    private bool lit;
    public event Action? Click;

    public Readout(Token rest, Token hover)
    {
        this.rest = rest;
        this.hover = hover;
        Orientation = Orientation.Horizontal;
        Background = Brushes.Transparent;
        Cursor = Cursors.Hand;
        Focusable = true;
        FocusVisualStyle = null;
        MouseEnter += (_, _) => Paint();
        MouseLeave += (_, _) => Paint();
        MouseLeftButtonUp += (_, e) => { Click?.Invoke(); e.Handled = true; };
        KeyDown += (_, e) => { if (e.Key is Key.Enter or Key.Space) { Click?.Invoke(); e.Handled = true; } };
    }

    /// <summary>Shown as if hovered (a legend that is on).</summary>
    public bool Lit
    {
        get => lit;
        set { lit = value; Paint(); }
    }

    public void Paint()
    {
        var brush = Theme.Brush(IsMouseOver || lit ? hover : rest);
        foreach (var child in Children)
        {
            if (child is TextBlock text) text.Foreground = brush;
            if (child is IconView icon) icon.Brush = brush;
        }
    }
}

/// <summary>
/// Thin bar (position on the display): 2px track and filled part, a 16px hit area, and a 2 × 10px tick
/// only on hover or while dragging, with the time at that point in a tooltip. Arrow keys step.
/// </summary>
public sealed class BarSlider : FrameworkElement
{
    private double value;
    private double? hover;
    private bool dragging;
    private readonly ToolTip tip = new() { Placement = System.Windows.Controls.Primitives.PlacementMode.Relative };

    public Token TrackToken { get; set; } = Token.DisplayTrack;
    public Token FillToken { get; set; } = Token.DisplayInk;
    public Action<double>? Changed { get; set; }
    public Action<int>? Step { get; set; }
    public Func<double, string?>? HoverText { get; set; }

    public BarSlider()
    {
        Height = 16;
        Focusable = true;
        FocusVisualStyle = null;
        Cursor = Cursors.Hand;
        ToolTip = tip;
        ToolTipService.SetInitialShowDelay(this, 0);
        tip.Opened += (_, _) => tip.IsOpen = HoverText?.Invoke(hover ?? 0) != null;
    }

    public double Value
    {
        get => value;
        set
        {
            var v = Math.Clamp(double.IsFinite(value) ? value : 0, 0, 1);
            if (Math.Abs(v - this.value) < 1e-5) return;
            this.value = v;
            InvalidateVisual();
        }
    }

    protected override void OnRender(DrawingContext dc)
    {
        var w = ActualWidth;
        var y = ActualHeight / 2 - Space.Bar / 2;
        dc.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, w, ActualHeight));
        dc.DrawRectangle(Theme.Brush(TrackToken), null, new Rect(0, y, w, Space.Bar));
        dc.DrawRectangle(Theme.Brush(FillToken), null, new Rect(0, y, w * value, Space.Bar));
        if (hover != null || dragging)
        {
            var x = Math.Clamp(w * value - 1, 0, Math.Max(0, w - 2));
            dc.DrawRectangle(Theme.Brush(FillToken), null, new Rect(x, ActualHeight / 2 - 5, 2, 10));
        }
        if (IsKeyboardFocused)
            dc.DrawRoundedRectangle(null, new Pen(Theme.Brush(Token.Focus), 2), new Rect(-2, 0, w + 4, ActualHeight), Space.RadiusSm + 2, Space.RadiusSm + 2);
    }

    private double At(MouseEventArgs e) => Math.Clamp(e.GetPosition(this).X / Math.Max(1, ActualWidth), 0, 1);

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        hover = At(e);
        if (dragging) Changed?.Invoke(hover.Value);
        var text = HoverText?.Invoke(hover.Value);
        tip.Content = text;
        tip.HorizontalOffset = e.GetPosition(this).X - 20;
        tip.VerticalOffset = -26;
        tip.IsOpen = text != null;
        InvalidateVisual();
    }

    protected override void OnMouseLeave(MouseEventArgs e)
    {
        base.OnMouseLeave(e);
        hover = null;
        tip.IsOpen = false;
        InvalidateVisual();
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        dragging = true;
        CaptureMouse();
        Changed?.Invoke(At(e));
        e.Handled = true;
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        dragging = false;
        ReleaseMouseCapture();
        InvalidateVisual();
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (Keyboard.Modifiers != ModifierKeys.None) return;
        if (e.Key == Key.Left) { Step?.Invoke(-1); e.Handled = true; }
        if (e.Key == Key.Right) { Step?.Invoke(1); e.Handled = true; }
    }

    protected override void OnGotKeyboardFocus(KeyboardFocusChangedEventArgs e) { base.OnGotKeyboardFocus(e); InvalidateVisual(); }
    protected override void OnLostKeyboardFocus(KeyboardFocusChangedEventArgs e) { base.OnLostKeyboardFocus(e); InvalidateVisual(); }
}

/// <summary>
/// The volume knob (Volume.md): the height of a key, a 26px disc in key-mode with a 2 × 9 pointer, a
/// printed 0–10 scale over 270°. Drag up or down (160 px for the whole range), the wheel, or the arrows.
/// </summary>
public sealed class VolumeKnob : FrameworkElement
{
    private const double Sweep = 270;
    private const double Travel = 160;
    private double value = 1;
    private double? dragStart;
    private Point dragOrigin;

    public Action<double>? Changed { get; set; }

    public VolumeKnob()
    {
        Width = Space.Key;
        Height = Space.Key;
        Focusable = true;
        FocusVisualStyle = null;
        Cursor = Cursors.SizeNS;
        System.Windows.Automation.AutomationProperties.SetName(this, "Volume");
    }

    public double Value
    {
        get => value;
        set
        {
            this.value = Math.Clamp(value, 0, 1);
            ToolTip = $"Volume {Math.Round(this.value * 100)}% Ctrl+↑ Ctrl+↓";
            InvalidateVisual();
        }
    }

    /// <summary>Volume as a scale reading, 0 to 10.</summary>
    public static string Reading(double volume) => $"{(int)Math.Round(volume * 100) / 10}";

    private static double Angle(double v) => -Sweep / 2 + Sweep * Math.Clamp(v, 0, 1);

    private static Point At(Point c, double degrees, double r)
    {
        var a = degrees * Math.PI / 180;
        return new Point(c.X + r * Math.Sin(a), c.Y - r * Math.Cos(a));
    }

    protected override void OnRender(DrawingContext dc)
    {
        var c = new Point(ActualWidth / 2, ActualHeight / 2);
        dc.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, ActualWidth, ActualHeight));
        for (var i = 0; i <= 10; i++)
        {
            var major = i % 5 == 0;
            var a = Angle(i / 10.0);
            dc.DrawLine(new Pen(Theme.Brush(major ? Token.InkMuted : Token.Line), 1), At(c, a, 15.5), At(c, a, major ? 18 : 17));
        }
        dc.DrawEllipse(Theme.Brush(Token.KeyMode), null, c, 13, 13);
        dc.PushTransform(new RotateTransform(Angle(value), c.X, c.Y));
        dc.DrawRectangle(Theme.Brush(Token.KeyModeInk), null, new Rect(c.X - Space.Bar / 2, c.Y - 11, Space.Bar, 9));
        dc.Pop();
        if (IsKeyboardFocused) dc.DrawEllipse(null, new Pen(Theme.Brush(Token.Focus), 2), c, 15, 15);
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        dragStart = value;
        dragOrigin = e.GetPosition(this);
        CaptureMouse();
        Focus();
        e.Handled = true;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (dragStart is not { } start || !IsMouseCaptured) return;
        var dy = e.GetPosition(this).Y - dragOrigin.Y;
        Changed?.Invoke(Math.Clamp(start - dy / Travel, 0, 1));
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        dragStart = null;
        ReleaseMouseCapture();
    }

    protected override void OnMouseWheel(MouseWheelEventArgs e)
    {
        base.OnMouseWheel(e);
        Changed?.Invoke(Math.Clamp(value + (e.Delta > 0 ? 0.05 : -0.05), 0, 1));
        e.Handled = true;
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (Keyboard.Modifiers != ModifierKeys.None) return;
        double? step = e.Key switch { Key.Up or Key.Right => 0.05, Key.Down or Key.Left => -0.05, _ => null };
        if (step is { } s)
        {
            Changed?.Invoke(Math.Clamp(value + s, 0, 1));
            e.Handled = true;
        }
    }

    protected override void OnGotKeyboardFocus(KeyboardFocusChangedEventArgs e) { base.OnGotKeyboardFocus(e); InvalidateVisual(); }
    protected override void OnLostKeyboardFocus(KeyboardFocusChangedEventArgs e) { base.OnLostKeyboardFocus(e); InvalidateVisual(); }
}

public static class TimeFormat
{
    /// <summary>Display: "03:07", "1:02:03".</summary>
    public static string Display(double seconds)
    {
        var (h, m, s) = Parts(seconds);
        return h > 0 ? $"{h}:{m:00}:{s:00}" : $"{m:00}:{s:00}";
    }

    /// <summary>List: "4:05", "1:02:03".</summary>
    public static string Short(double seconds)
    {
        var (h, m, s) = Parts(seconds);
        return h > 0 ? $"{h}:{m:00}:{s:00}" : $"{m}:{s:00}";
    }

    private static (int, int, int) Parts(double seconds)
    {
        var t = Math.Max(0, (int)(double.IsFinite(seconds) ? seconds : 0));
        return (t / 3600, t % 3600 / 60, t % 60);
    }
}
