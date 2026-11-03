using System.Windows;
using System.Windows.Controls;
using NuVa.Core;
using NuVa.UI;

namespace NuVa;

public sealed class MainWindow : Window
{
    public MainWindow()
    {
        Title = "NuVa";
        Width = 380;
        Height = 600;
        MinWidth = 360;
        MaxWidth = 480;
        Background = Theme.Brush(Token.Surface0);
        var time = new TextBlock { Text = "00:00", Foreground = Theme.Brush(Token.DisplayInk), Margin = new Thickness(12) };
        TextStyle.DisplayTime.Apply(time);
        Content = new Border
        {
            Background = Theme.Brush(Token.Display),
            CornerRadius = new CornerRadius(3),
            Margin = new Thickness(16),
            VerticalAlignment = VerticalAlignment.Top,
            Child = time,
        };
    }
}
