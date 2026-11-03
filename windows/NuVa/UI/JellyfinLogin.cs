using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using NuVa.Core;
using NuVa.Core.Library;

namespace NuVa.UI;

/// <summary>Adds a Jellyfin server: address, user and password (port of JellyfinLoginView.swift).</summary>
public sealed class JellyfinLogin : Window
{
    private readonly AppModel model;
    private readonly TextBox address = new();
    private readonly TextBox username = new();
    private readonly PasswordBox password = new();
    private readonly TextBlock error = Text.Make("", TextStyle.Caption, Token.Danger);
    private readonly KeyButton signIn;
    private bool busy;

    public JellyfinLogin(AppModel model, Window owner)
    {
        this.model = model;
        Owner = owner;
        Title = L.T("Adicionar Jellyfin");
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.Height;
        ShowInTaskbar = false;
        Width = 360;
        Background = Theme.Brush(Token.Surface1);
        var stack = new StackPanel { Margin = new Thickness(Space.S4) };
        stack.Children.Add(Text.Make(L.T("Adicionar Jellyfin"), TextStyle.Title, Token.Ink));
        stack.Children.Add(Field(L.T("Endereço"), address));
        address.ToolTip = "https://jellyfin.exemplo.pt";
        stack.Children.Add(Field(L.T("Utilizador"), username));
        stack.Children.Add(Field(L.T("Palavra-passe"), password));
        error.TextWrapping = TextWrapping.Wrap;
        error.TextTrimming = TextTrimming.None;
        error.Margin = new Thickness(0, Space.S3, 0, 0);
        error.Visibility = Visibility.Collapsed;
        stack.Children.Add(error);
        var keys = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, Space.S4, 0, 0) };
        keys.Children.Add(new KeyButton(L.T("Cancelar"), null, Close));
        signIn = new KeyButton(L.T("Entrar"), null, Submit) { Margin = new Thickness(Space.S2, 0, 0, 0) };
        keys.Children.Add(signIn);
        stack.Children.Add(keys);
        Content = stack;
        address.TextChanged += (_, _) => Validate();
        username.TextChanged += (_, _) => Validate();
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape) { Close(); e.Handled = true; }
            if (e.Key == Key.Enter) { Submit(); e.Handled = true; }
        };
        Loaded += (_, _) => address.Focus();
        Validate();
    }

    private static UIElement Field(string label, Control input)
    {
        var stack = new StackPanel { Margin = new Thickness(0, Space.S3, 0, 0) };
        var text = Text.Make(label, TextStyle.Label, Token.InkMuted);
        text.Margin = new Thickness(0, 0, 0, Space.S1);
        stack.Children.Add(text);
        input.FontFamily = TextStyle.Body.Family;
        input.FontSize = TextStyle.Body.Size;
        System.Windows.Automation.AutomationProperties.SetName(input, label);
        stack.Children.Add(input);
        return stack;
    }

    private void Validate()
    {
        signIn.Available = !busy && JellyfinSource.ServerUrl(address.Text) != null && username.Text.Trim().Length > 0;
        signIn.InvalidateVisual();
    }

    private async void Submit()
    {
        if (!signIn.Available || JellyfinSource.ServerUrl(address.Text) is not { } server) return;
        busy = true;
        Validate();
        address.IsEnabled = username.IsEnabled = password.IsEnabled = false;
        error.Visibility = Visibility.Collapsed;
        var user = username.Text.Trim();
        try
        {
            await JellyfinSource.Login(server, user, password.Password, model.Sources.DeviceId);
            var source = model.Sources.AddJellyfin($"Jellyfin · {server.Host}", server.AbsoluteUri, user, password.Password);
            if (source != null) model.Browser.Open(new BrowserLocation(source.Id, ""));
            Close();
        }
        catch (Exception e)
        {
            error.Text = e is SourceException or JellyfinSource.HttpStatusException ? e.Message : L.T("Servidor offline");
            error.Visibility = Visibility.Visible;
            Log.Write($"jellyfin: sign-in failed: {e.Message}");
        }
        busy = false;
        address.IsEnabled = username.IsEnabled = password.IsEnabled = true;
        Validate();
    }
}
