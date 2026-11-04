using System;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using NuVa.Core;
using NuVa.Core.Audio;

namespace NuVa.UI;

/// <summary>
/// The equalizer (Equalizer.md), a popover of the display's EQ readout: "equalizer" and the power switch;
/// presets in a grid of 4 with their LEDs; ten bands from −12 to +12 dB over a printed scale.
/// </summary>
public sealed class EqualizerPanel : Border
{
    private const double BandHeight = 120;
    private static readonly float[] marks = [12, 6, 0, -6, -12];
    private readonly Equalizer eq;
    private readonly Led power = new() { VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock powerText = Text.Legend("");
    private readonly SwitchView slide = new();
    private readonly Grid presets = new();
    private readonly BandSlider[] bands;
    private readonly Readout powerSwitch = new(Token.InkMuted, Token.InkMuted);

    public EqualizerPanel(Equalizer eq)
    {
        this.eq = eq;
        Background = Theme.Brush(Token.Surface1);
        CornerRadius = new CornerRadius(Space.RadiusLg);
        BorderBrush = Theme.Brush(Token.Line);
        BorderThickness = new Thickness(1);
        Padding = new Thickness(Space.S4);
        Width = 380;
        var stack = new StackPanel();

        var header = new DockPanel { LastChildFill = true };
        powerSwitch.Children.Add(power);
        powerText.Margin = new Thickness(Space.S1 + 2, 0, Space.S1 + 2, 0);
        powerText.VerticalAlignment = VerticalAlignment.Center;
        powerSwitch.Children.Add(powerText);
        powerSwitch.Children.Add(slide);
        powerSwitch.Click += () => eq.SetEnabled(!eq.Enabled);
        DockPanel.SetDock(powerSwitch, Dock.Right);
        header.Children.Add(powerSwitch);
        header.Children.Add(Text.Make(L.T("equalizador"), TextStyle.Label, Token.Ink));
        stack.Children.Add(header);

        for (var c = 0; c < 4; c++) presets.ColumnDefinitions.Add(new ColumnDefinition());
        for (var r = 0; r < (Equalizer.Presets.Length + 3) / 4; r++) presets.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        presets.Margin = new Thickness(0, Space.S3, 0, 0);
        stack.Children.Add(presets);

        var bandsRow = new Grid { Margin = new Thickness(0, Space.S3, 0, 0) };
        bandsRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(28) });
        var scale = new Canvas { Height = BandHeight, Width = 28, VerticalAlignment = VerticalAlignment.Top };
        foreach (var mark in marks)
        {
            var label = Text.Make(mark > 0 ? $"+{mark}" : $"{mark}", TextStyle.DisplayMeta, Token.InkMuted);
            label.Width = 24;
            label.TextAlignment = TextAlignment.Right;
            Canvas.SetTop(label, Y(mark) - 7);
            scale.Children.Add(label);
        }
        bandsRow.Children.Add(scale);
        bands = new BandSlider[Equalizer.Labels.Length];
        for (var b = 0; b < bands.Length; b++)
        {
            bandsRow.ColumnDefinitions.Add(new ColumnDefinition());
            var band = b;
            bands[b] = new BandSlider(Equalizer.Labels[b], v => eq.Set(band, v)) { Margin = new Thickness(Space.S1, 0, 0, 0) };
            Grid.SetColumn(bands[b], b + 1);
            bandsRow.Children.Add(bands[b]);
        }
        stack.Children.Add(bandsRow);
        Child = stack;
        Refresh(animated: false);
        eq.Changed += OnChanged;
        Unloaded += (_, _) => eq.Changed -= OnChanged;
    }

    private string? lastPreset;

    private void OnChanged() => Refresh(animated: eq.Preset != lastPreset && eq.Preset != Equalizer.Custom);

    public static double Y(float gain) => BandHeight * (Equalizer.Max - gain) / (Equalizer.Max - Equalizer.Min);

    private void Refresh(bool animated)
    {
        lastPreset = eq.Preset;
        power.IsOn = eq.Enabled;
        powerText.Text = eq.Enabled ? L.T("ligado") : L.T("desligado");
        slide.IsOn = eq.Enabled;
        powerSwitch.ToolTip = eq.Enabled ? L.T("Desligar o equalizador") : L.T("Ligar o equalizador");
        presets.Children.Clear();
        for (var i = 0; i < Equalizer.Presets.Length; i++)
        {
            var preset = Equalizer.Presets[i];
            var active = eq.Enabled && eq.Preset == preset.Key;
            var button = new Readout(active ? Token.Ink : Token.InkMuted, Token.Ink) { Margin = new Thickness(0, 0, 0, Space.S2), HorizontalAlignment = HorizontalAlignment.Left };
            var led = new Led { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, Space.S1 + 2, 0) };
            led.Set(active);
            button.Children.Add(led);
            button.Children.Add(Text.Make(Equalizer.DisplayName(preset.Key).ToLower(CultureInfo.CurrentCulture), TextStyle.Caption, Token.InkMuted));
            button.Lit = active;
            button.ToolTip = L.F("Preset {0}", Equalizer.DisplayName(preset.Key));
            button.Click += () => eq.Apply(preset);
            Grid.SetColumn(button, i % 4);
            Grid.SetRow(button, i / 4);
            presets.Children.Add(button);
        }
        for (var b = 0; b < bands.Length; b++) bands[b].Show(eq.Gains[b], eq.Enabled, animated);
    }

    /// <summary>Opens the panel under an element (the EQ readout), closing on a click elsewhere or Esc.</summary>
    public static void Open(Equalizer eq, UIElement anchor)
    {
        var popup = new Popup
        {
            Child = new EqualizerPanel(eq),
            PlacementTarget = anchor,
            Placement = PlacementMode.Bottom,
            StaysOpen = false,
            AllowsTransparency = true,
            PopupAnimation = Motion.Reduced ? PopupAnimation.None : PopupAnimation.Fade,
            VerticalOffset = 6,
        };
        popup.Child.KeyDown += (_, e) => { if (e.Key == Key.Escape) popup.IsOpen = false; };
        popup.Opened += (_, _) => (popup.Child as EqualizerPanel)?.bands[0].Focus();
        popup.IsOpen = true;
    }
}

/// <summary>The power switch: a 26 × 14 slot with a 10px key-face slider.</summary>
internal sealed class SwitchView : FrameworkElement
{
    private bool isOn;

    public static readonly DependencyProperty PositionProperty = DependencyProperty.Register(
        nameof(Position), typeof(double), typeof(SwitchView), new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsRender));

    public double Position
    {
        get => (double)GetValue(PositionProperty);
        set => SetValue(PositionProperty, value);
    }

    public SwitchView()
    {
        Width = 26;
        Height = 14;
        VerticalAlignment = VerticalAlignment.Center;
    }

    public bool IsOn
    {
        get => isOn;
        set
        {
            isOn = value;
            Motion.To(this, PositionProperty, value ? 1 : 0, Motion.State);
        }
    }

    protected override void OnRender(DrawingContext dc)
    {
        dc.DrawRoundedRectangle(Theme.Brush(Token.Surface0), null, new Rect(0, 0, 26, 14), 2, 2);
        dc.DrawRoundedRectangle(Theme.Brush(Token.KeyFace), null, new Rect(2 + Position * 12, 2, 10, 10), 1, 1);
    }
}

/// <summary>One band: printed scale behind, a 2px track and a 16 × 8 fader cap. Double-click resets to 0 dB; ↑ ↓ half a decibel.</summary>
internal sealed class BandSlider : FrameworkElement
{
    private readonly string label;
    private readonly Action<float> changed;
    private float value;
    private bool isOn = true;
    private bool active;

    public static readonly DependencyProperty ShownProperty = DependencyProperty.Register(
        nameof(Shown), typeof(double), typeof(BandSlider), new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsRender));

    /// <summary>The cap's gain as drawn: moves to a preset like a motorised fader.</summary>
    public double Shown
    {
        get => (double)GetValue(ShownProperty);
        set => SetValue(ShownProperty, value);
    }

    public BandSlider(string label, Action<float> changed)
    {
        this.label = label;
        this.changed = changed;
        Height = 120 + Space.S1 + 14;
        Focusable = true;
        FocusVisualStyle = null;
        Cursor = Cursors.SizeNS;
        System.Windows.Automation.AutomationProperties.SetName(this, $"{label} Hz");
    }

    public void Show(float gain, bool on, bool animated)
    {
        value = gain;
        isOn = on;
        ToolTip = $"{label} Hz {(gain > 0 ? "+" : "")}{gain.ToString("0.#", CultureInfo.CurrentCulture)} dB";
        if (animated) BeginAnimation(ShownProperty, new DoubleAnimation(gain, Motion.Fader) { EasingFunction = new SineEase { EasingMode = EasingMode.EaseInOut } });
        else
        {
            BeginAnimation(ShownProperty, null);
            Shown = gain;
        }
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext dc)
    {
        var w = ActualWidth;
        var cx = Math.Round(w / 2);
        dc.DrawRectangle(Brushes.Transparent, null, new Rect(0, 0, w, 120));
        var opacity = isOn ? 1 : 0.5;
        dc.PushOpacity(opacity);
        foreach (var mark in new float[] { 12, 6, 0, -6, -12 })
            // A printed scale: the 0 line in full, the others fainter.
            dc.DrawRectangle(mark == 0 ? Theme.Brush(Token.Line) : Theme.Brush(Token.Line, 0.5), null, new Rect(0, EqualizerPanel.Y(mark), w, 1));
        dc.DrawRectangle(Theme.Brush(Token.Surface0), null, new Rect(cx - 1, 0, Space.Bar, 120));
        var y = EqualizerPanel.Y((float)Shown) - 4;
        var cap = new Rect(cx - 8, y, 16, 8);
        dc.DrawRoundedRectangle(Theme.Brush(Token.KeyFace), null, cap, 1, 1);
        if (active) dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(16, 255, 255, 255)), null, cap, 1, 1);
        dc.DrawRectangle(Theme.Brush(Token.KeyInk, 0.5), null, new Rect(cap.X + 2, cap.Y + 3.5, 12, 1));
        dc.Pop();
        var text = TextStyle.DisplayMeta.Format(label, Theme.Brush(Token.InkMuted), VisualTreeHelper.GetDpi(this).PixelsPerDip);
        dc.DrawText(text, new Point(cx - text.Width / 2, 120 + Space.S1));
        if (IsKeyboardFocused) dc.DrawRoundedRectangle(null, new Pen(Theme.Brush(Token.Focus), 2), new Rect(-1, -2, w + 2, 124), Space.RadiusSm, Space.RadiusSm);
    }

    private float At(MouseEventArgs e)
    {
        var t = (float)Math.Clamp(e.GetPosition(this).Y / 120, 0, 1);
        return Equalizer.Max - t * (Equalizer.Max - Equalizer.Min);
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        Focus();
        if (e.ClickCount == 2)
        {
            changed(0);
            e.Handled = true;
            return;
        }
        active = true;
        CaptureMouse();
        changed(At(e));
        e.Handled = true;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (active && IsMouseCaptured) changed(At(e));
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonUp(e);
        active = false;
        ReleaseMouseCapture();
        InvalidateVisual();
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (Keyboard.Modifiers != ModifierKeys.None) return;
        switch (e.Key)
        {
            case Key.Up:
                changed(value + 0.5f);
                e.Handled = true;
                break;
            case Key.Down:
                changed(value - 0.5f);
                e.Handled = true;
                break;
            case Key.Right:
                MoveFocus(new TraversalRequest(FocusNavigationDirection.Next));
                e.Handled = true;
                break;
            case Key.Left:
                MoveFocus(new TraversalRequest(FocusNavigationDirection.Previous));
                e.Handled = true;
                break;
        }
    }

    protected override void OnGotKeyboardFocus(KeyboardFocusChangedEventArgs e) { base.OnGotKeyboardFocus(e); InvalidateVisual(); }
    protected override void OnLostKeyboardFocus(KeyboardFocusChangedEventArgs e) { base.OnLostKeyboardFocus(e); InvalidateVisual(); }
}
