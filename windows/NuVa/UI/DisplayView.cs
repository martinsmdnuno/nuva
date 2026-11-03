using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using NuVa.Core;

namespace NuVa.UI;

/// <summary>
/// The device's screen (Display.md), recessed into the chassis and always dark. Format and source;
/// title; folder (or the error) and the output readout; the elapsed time and the EQ readout; the
/// spectrum; the position row. With artwork on, the folder's image sits at the left.
/// </summary>
public sealed class DisplayView : Border
{
    private readonly AppModel model;
    private readonly bool allowsArtwork;
    private readonly bool isMain;
    private readonly Led led = new(6) { OffToken = Token.LedOff, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock format = Text.Make("", TextStyle.DisplayMeta, Token.DisplayMuted, 14);
    private readonly TextBlock sourceLabel = Text.Make("", TextStyle.DisplayMeta, Token.DisplayMuted, 14);
    private readonly TextBlock title = Text.Make("", TextStyle.Title, Token.DisplayInk, 20);
    private readonly TextBlock folder = Text.Make("", TextStyle.Caption, Token.DisplayMuted);
    private readonly TextBlock time = Text.Make("00:00", TextStyle.DisplayTime, Token.DisplayInk);
    private readonly TextBlock elapsed = Text.Make("00:00", TextStyle.DisplayMeta, Token.DisplayMuted);
    private readonly TextBlock end = Text.Make("00:00", TextStyle.DisplayMeta, Token.DisplayMuted);
    private readonly Readout output = new(Token.DisplayMuted, Token.DisplayInk) { VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock outputName = Text.Make("", TextStyle.DisplayMeta, Token.DisplayMuted);
    private readonly Readout eq = new(Token.DisplayMuted, Token.DisplayInk) { VerticalAlignment = VerticalAlignment.Bottom };
    private readonly Led eqLed = new() { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, Space.S1 + 2, 0) };
    private readonly TextBlock eqLabel = Text.Make("EQ", TextStyle.DisplayMeta, Token.DisplayMuted);
    private readonly BarSlider position = new() { VerticalAlignment = VerticalAlignment.Center };
    private readonly Image artwork = new() { Width = 76, Height = 76, Stretch = Stretch.Uniform, Margin = new Thickness(0, 0, Space.S3, 0), VerticalAlignment = VerticalAlignment.Top };
    private readonly SpectrumView? spectrum;
    private string? lastTitleKey;

    public event Action? EqualizerClicked;
    public event Action<FrameworkElement>? OutputClicked;
    public event Action? ArtworkClicked;

    public DisplayView(AppModel model, bool allowsArtwork, bool isMain)
    {
        this.model = model;
        this.allowsArtwork = allowsArtwork;
        this.isMain = isMain;
        Background = Theme.Brush(Token.Display);
        CornerRadius = new CornerRadius(Space.RadiusSm);
        Padding = new Thickness(Space.S3, Space.S3, Space.S3, Space.S1);
        ClipToBounds = true;
        RenderOptions.SetBitmapScalingMode(artwork, BitmapScalingMode.HighQuality);
        artwork.Clip = new RectangleGeometry(new Rect(0, 0, 76, 76), Space.RadiusSm, Space.RadiusSm);
        artwork.MouseLeftButtonUp += (_, _) => ArtworkClicked?.Invoke();
        title.TextTrimming = TextTrimming.CharacterEllipsis;
        folder.TextTrimming = TextTrimming.CharacterEllipsis;
        outputName.TextTrimming = TextTrimming.CharacterEllipsis;

        // Row 1: LED · format · source.
        var row1 = new DockPanel { Height = 14, LastChildFill = true };
        DockPanel.SetDock(led, Dock.Left);
        led.Margin = new Thickness(0, 0, Space.S2, 0);
        row1.Children.Add(led);
        DockPanel.SetDock(sourceLabel, Dock.Right);
        sourceLabel.Margin = new Thickness(Space.S2, 0, 0, 0);
        row1.Children.Add(sourceLabel);
        row1.Children.Add(format);

        // Folder (or error) · output.
        output.Children.Add(new IconView(Icon.Speaker, 11) { Margin = new Thickness(0, 0, Space.S1, 0), VerticalAlignment = VerticalAlignment.Center });
        output.Children.Add(outputName);
        output.Click += () => OutputClicked?.Invoke(output);
        output.ToolTip = L.T("Escolher a saída");
        var folderRow = new DockPanel { LastChildFill = true };
        DockPanel.SetDock(output, Dock.Right);
        output.Margin = new Thickness(Space.S2, 0, 0, 0);
        folderRow.Children.Add(output);
        folderRow.Children.Add(folder);

        // Time · EQ, on the time's baseline.
        eq.Children.Add(eqLed);
        eq.Children.Add(eqLabel);
        eq.Click += () => EqualizerClicked?.Invoke();
        eq.Margin = new Thickness(Space.S2, 0, 0, 6);
        var timeRow = new DockPanel { LastChildFill = true, Margin = new Thickness(0, Space.S1, 0, 0) };
        DockPanel.SetDock(eq, Dock.Right);
        timeRow.Children.Add(eq);
        timeRow.Children.Add(time);

        var textColumn = new StackPanel();
        textColumn.Children.Add(title);
        folderRow.Margin = new Thickness(0, Space.S1, 0, 0);
        textColumn.Children.Add(folderRow);
        textColumn.Children.Add(timeRow);

        var middle = new DockPanel { LastChildFill = true, Margin = new Thickness(0, Space.S1, 0, 0) };
        DockPanel.SetDock(artwork, Dock.Left);
        middle.Children.Add(artwork);
        middle.Children.Add(textColumn);

        // Position row: elapsed · bar · duration (or the time left, after a click).
        var positionRow = new DockPanel { LastChildFill = true, Margin = new Thickness(0, Space.S1, 0, 0) };
        DockPanel.SetDock(elapsed, Dock.Left);
        elapsed.Margin = new Thickness(0, 0, Space.S2, 0);
        elapsed.VerticalAlignment = VerticalAlignment.Center;
        DockPanel.SetDock(end, Dock.Right);
        end.Margin = new Thickness(Space.S2, 0, 0, 0);
        end.VerticalAlignment = VerticalAlignment.Center;
        end.Background = Brushes.Transparent;
        end.Cursor = Cursors.Hand;
        end.MouseLeftButtonUp += (_, _) => model.ShowsRemaining = !model.ShowsRemaining;
        positionRow.Children.Add(elapsed);
        positionRow.Children.Add(end);
        positionRow.Children.Add(position);
        position.Changed = v => { if (model.Player.Duration > 0) model.Player.Seek(v * model.Player.Duration); };
        position.Step = d => model.Player.Skip(d * 5);
        position.HoverText = v => model.Player.Duration > 0 ? TimeFormat.Display(v * model.Player.Duration) : null;
        System.Windows.Automation.AutomationProperties.SetName(position, L.T("Posição"));

        var stack = new StackPanel();
        stack.Children.Add(row1);
        stack.Children.Add(middle);
        if (model.ShowsSpectrum)
        {
            spectrum = new SpectrumView(model.Spectrum, () => (model.Player.IsPlaying, model.Player.CurrentTime)) { Margin = new Thickness(0, Space.S3, 0, Space.S3) };
            stack.Children.Add(spectrum);
        }
        stack.Children.Add(positionRow);

        // shadow-display: recessed into the chassis, a 1px dark line at the top.
        var grid = new Grid();
        grid.Children.Add(stack);
        Child = grid;
        var shade = new Border { Height = 1, Background = new SolidColorBrush(Color.FromArgb(128, 0, 0, 0)), VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(-Space.S3, -Space.S3, -Space.S3, 0) };
        grid.Children.Add(shade);
        Refresh();
    }

    public SpectrumView? Spectrum => spectrum;

    /// <summary>Everything but the time, which <see cref="Tick"/> keeps current.</summary>
    public void Refresh()
    {
        var player = model.Player;
        var entry = player.Current?.Entry;
        led.IsOn = player.IsPlaying;
        format.Text = player.IsLoading ? L.T("A carregar…") : player.FormatLabel;
        sourceLabel.Text = model.CurrentSourceLabel;
        var titleText = entry?.Title ?? (model.Sources.Sources.Count == 0 ? L.T("Sem música") : L.T("Sem faixa"));
        title.Text = titleText;
        title.Foreground = Theme.Brush(entry == null ? Token.DisplayMuted : Token.DisplayInk);
        title.ToolTip = entry?.Name;
        if (lastTitleKey != entry?.Id)
        {
            lastTitleKey = entry?.Id;
            Motion.FadeIn(title);
        }
        if (player.ErrorMessage is { } error)
        {
            folder.Text = error;
            // The display is dark in both themes: the dark theme's red reads on it.
            folder.Foreground = Theme.Hex(Theme.Skin.Color(Token.Danger, true));
            folder.ToolTip = player.ErrorDetail ?? error;
        }
        else
        {
            folder.Text = entry?.FolderName ?? (model.Sources.Sources.Count == 0
                ? L.T("Adicionar uma pasta ou um servidor Jellyfin")
                : L.T("Escolher uma pasta para tocar"));
            folder.Foreground = Theme.Brush(Token.DisplayMuted);
            folder.ToolTip = entry?.ParentPath;
        }
        outputName.Text = OutputText();
        output.ToolTip = (model.Output.DeviceRate > 0 ? $"{model.Output.DeviceName} · {Core.Player.PlayerController.KHz(model.Output.DeviceRate)} kHz\n" : "") + L.T("Escolher a saída");
        var eqOn = model.Equalizer.Enabled;
        eqLed.IsOn = eqOn;
        eqLabel.Text = eqOn ? $"EQ · {Core.Audio.Equalizer.DisplayName(model.Equalizer.Preset)}" : "EQ";
        eq.ToolTip = (eqOn ? L.F("Equalizador: {0}", Core.Audio.Equalizer.DisplayName(model.Equalizer.Preset)) : L.T("Equalizador desligado")) + " Ctrl+Shift+E";
        output.Paint();
        eq.Paint();
        spectrum?.PlayingChanged(player.IsPlaying);
        Tick();
    }

    /// <summary>The output readout: "Speakers · 48 kHz".</summary>
    private string OutputText()
    {
        var name = model.Output.DeviceName;
        if (string.IsNullOrEmpty(name)) return L.T("Saída");
        return model.Output.DeviceRate > 0 ? $"{name} · {Core.Player.PlayerController.KHz(model.Output.DeviceRate)} kHz" : name;
    }

    /// <summary>The artwork beside the text, or none.</summary>
    public void SetArtwork(BitmapSource? image, bool canFix)
    {
        var show = allowsArtwork && image != null;
        if (show) artwork.Source = image;
        artwork.Visibility = show ? Visibility.Visible : Visibility.Collapsed;
        artwork.Cursor = isMain && canFix ? Cursors.Hand : null;
        artwork.ToolTip = isMain && canFix ? L.T("Capa errada?") : null;
    }

    /// <summary>The time and the position, many times a second.</summary>
    public void Tick()
    {
        var player = model.Player;
        var t = player.CurrentTime;
        var d = player.Duration;
        time.Text = TimeFormat.Display(t);
        elapsed.Text = TimeFormat.Display(t);
        end.Text = model.ShowsRemaining && d > 0 ? "-" + TimeFormat.Display(d - t) : TimeFormat.Display(d);
        end.ToolTip = model.ShowsRemaining ? L.T("Mostrar duração") : L.T("Mostrar tempo restante");
        position.Value = d > 0 ? t / d : 0;
    }
}
