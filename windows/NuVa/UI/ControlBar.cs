using System;
using System.Windows;
using System.Windows.Controls;
using NuVa.Core;
using NuVa.Core.Player;

namespace NuVa.UI;

/// <summary>
/// Keys in three groups with a legend, as on the Braun TG 60, play on the centre line:
/// mode (shuffle, repeat) · playback (previous, play/pause, next) · volume (the knob).
/// </summary>
public sealed class ControlBar : Grid
{
    private readonly AppModel model;
    private readonly KeyWithLed shuffle;
    private readonly KeyWithLed repeat;
    private readonly KeyButton play;
    private readonly VolumeKnob knob = new();
    private readonly TextBlock reading = Text.Make("10", TextStyle.Hint, Token.InkMuted);

    public ControlBar(AppModel model)
    {
        this.model = model;
        var player = model.Player;
        // Equal flexible sides keep the play key on the window's centre line.
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        shuffle = new KeyWithLed(new KeyButton(Tone.Mode, Icon.Shuffle, "", () => player.Shuffle = !player.Shuffle), true);
        repeat = new KeyWithLed(new KeyButton(Tone.Mode, Icon.Repeat, "", () => player.RepeatMode = Next(player.RepeatMode)), true);
        var mode = Group(L.T("modo"), shuffle, repeat);
        mode.HorizontalAlignment = HorizontalAlignment.Left;
        Add(mode, 0);

        var previous = new KeyWithLed(new KeyButton(Tone.Transport, Icon.Previous, L.T("Anterior") + " Ctrl+←", player.Previous), false);
        play = new KeyButton(Tone.Play, Icon.Play, "", model.PlayOrBrowse);
        var next = new KeyWithLed(new KeyButton(Tone.Transport, Icon.Next, L.T("Seguinte") + " Ctrl+→", player.Next), false);
        var playback = Group(L.T("leitura"), previous, new KeyWithLed(play, false), next);
        playback.Margin = new Thickness(Space.S4, 0, Space.S4, 0);
        Add(playback, 1);

        knob.Changed = v => player.Volume = (float)v;
        var volume = new StackPanel { HorizontalAlignment = HorizontalAlignment.Right };
        var knobSlot = new StackPanel();
        knobSlot.Children.Add(new FrameworkElement { Height = Space.Led, Margin = new Thickness(0, 0, 0, Space.S1) });
        knobSlot.Children.Add(knob);
        knobSlot.HorizontalAlignment = HorizontalAlignment.Right;
        volume.Children.Add(knobSlot);
        var legend = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, Space.S1 + 2, 0, 0) };
        legend.Children.Add(Text.Legend("volume"));
        reading.Margin = new Thickness(Space.S1 + 2, 0, 0, 0);
        legend.Children.Add(reading);
        volume.Children.Add(legend);
        Add(volume, 2);
        Refresh();
    }

    private static RepeatMode Next(RepeatMode mode) => mode switch { RepeatMode.Off => RepeatMode.All, RepeatMode.All => RepeatMode.One, _ => RepeatMode.Off };

    private void Add(UIElement element, int column)
    {
        SetColumn(element, column);
        Children.Add(element);
    }

    private static StackPanel Group(string legend, params UIElement[] keys)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        for (var i = 0; i < keys.Length; i++)
        {
            if (keys[i] is FrameworkElement f) f.Margin = new Thickness(i == 0 ? 0 : Space.S1, 0, 0, 0);
            row.Children.Add(keys[i]);
        }
        var group = new StackPanel();
        group.Children.Add(row);
        var text = Text.Legend(legend);
        text.Margin = new Thickness(0, Space.S1 + 2, 0, 0);
        group.Children.Add(text);
        return group;
    }

    public void Refresh()
    {
        var player = model.Player;
        shuffle.Led!.IsOn = player.Shuffle;
        shuffle.Key.Help = (player.Shuffle ? L.T("Aleatório ligado") : L.T("Aleatório")) + " Ctrl+Shift+S";
        repeat.Led!.IsOn = player.RepeatMode != RepeatMode.Off;
        repeat.Key.Icon = player.RepeatMode == RepeatMode.One ? Icon.RepeatOne : Icon.Repeat;
        repeat.Key.Help = player.RepeatMode switch { RepeatMode.Off => L.T("Repetir"), RepeatMode.All => L.T("Repetir tudo"), _ => L.T("Repetir uma") } + " Ctrl+R";
        play.Icon = player.IsPlaying ? Icon.Pause : Icon.Play;
        play.Help = (player.IsPlaying ? L.T("Pausa") : L.T("Tocar")) + " " + L.T("Espaço");
        knob.Value = player.Volume;
        reading.Text = VolumeKnob.Reading(player.Volume);
    }
}
