using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using NuVa.Core;
using NuVa.Core.Library;

namespace NuVa.UI;

/// <summary>
/// The one fallback for online artwork: it was wrong or not found. Search again with the artist and album
/// corrected, pick an image file, or say the folder has no artwork. Kept by NuVa for this folder; the
/// folder itself is never written to (port of ArtworkFixView.swift).
/// </summary>
public sealed class ArtworkFix : Window
{
    private readonly ArtworkStore store;
    private readonly Entry entry;
    private readonly TextBox artist = new();
    private readonly TextBox album = new();
    private readonly TextBlock error = Text.Make("", TextStyle.Caption, Token.Danger);
    private readonly KeyButton search;
    private bool busy;

    public ArtworkFix(ArtworkStore store, Entry entry, Window owner)
    {
        this.store = store;
        this.entry = entry;
        Owner = owner;
        Title = L.T("Capa errada ou em falta");
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.Height;
        ShowInTaskbar = false;
        Width = 380;
        Background = Theme.Brush(Token.Surface1);
        var guess = store.Resolver.Query(entry);
        artist.Text = guess?.Artist ?? "";
        album.Text = guess?.Album ?? "";

        var stack = new StackPanel { Margin = new Thickness(Space.S4) };
        stack.Children.Add(Text.Make(L.T("Capa errada ou em falta"), TextStyle.Title, Token.Ink));
        var note = Text.Make(L.T("A NuVa procura a capa pelo nome das pastas. Corrige o artista ou o álbum e procura outra vez, ou escolhe uma imagem."), TextStyle.Caption, Token.InkMuted);
        note.TextWrapping = TextWrapping.Wrap;
        note.TextTrimming = TextTrimming.None;
        note.Margin = new Thickness(0, Space.S3, 0, 0);
        stack.Children.Add(note);
        stack.Children.Add(Field(L.T("Artista"), artist));
        stack.Children.Add(Field(L.T("Álbum"), album));
        error.TextWrapping = TextWrapping.Wrap;
        error.TextTrimming = TextTrimming.None;
        error.Margin = new Thickness(0, Space.S3, 0, 0);
        error.Visibility = Visibility.Collapsed;
        stack.Children.Add(error);
        var choices = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, Space.S4, 0, 0) };
        choices.Children.Add(new KeyButton(L.T("Escolher imagem…"), null, ChooseImage));
        choices.Children.Add(new KeyButton(L.T("Sem capa"), null, () => Save(null)) { Margin = new Thickness(Space.S2, 0, 0, 0) });
        stack.Children.Add(choices);
        var keys = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, Space.S3, 0, 0) };
        keys.Children.Add(new KeyButton(L.T("Cancelar"), null, Close));
        search = new KeyButton(L.T("Procurar"), null, Search) { Margin = new Thickness(Space.S2, 0, 0, 0) };
        keys.Children.Add(search);
        stack.Children.Add(keys);
        Content = stack;
        artist.TextChanged += (_, _) => Validate();
        album.TextChanged += (_, _) => Validate();
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape) { Close(); e.Handled = true; }
            if (e.Key == Key.Enter) { Search(); e.Handled = true; }
        };
        Loaded += (_, _) => artist.Focus();
        Validate();
    }

    private static UIElement Field(string label, TextBox input)
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

    private AlbumQuery? Query()
    {
        var a = artist.Text.Trim();
        var b = album.Text.Trim();
        return a.Length == 0 || b.Length == 0 ? null : new AlbumQuery(a, b);
    }

    private void Validate()
    {
        search.Available = !busy && Query() != null;
        search.InvalidateVisual();
    }

    private void Fail(string message)
    {
        error.Text = message;
        error.Visibility = Visibility.Visible;
    }

    private async void Search()
    {
        if (busy || Query() is not { } query) return;
        busy = true;
        Validate();
        error.Visibility = Visibility.Collapsed;
        try
        {
            if (await store.Resolver.Online.Cover(query) is { } data) Save(data);
            else Fail(L.T("Não encontrei esta capa. Confirma os nomes ou escolhe uma imagem."));
        }
        catch (Exception)
        {
            Fail(L.T("Sem ligação ao MusicBrainz. Tenta mais tarde."));
        }
        busy = false;
        Validate();
    }

    private void ChooseImage()
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = L.T("Escolher a imagem da capa"),
            Filter = $"{L.T("Imagens")}|*.jpg;*.jpeg;*.png;*.bmp;*.gif;*.tif;*.tiff;*.webp",
        };
        if (dialog.ShowDialog(this) != true) return;
        if (ArtworkStore.Jpeg(dialog.FileName) is not { } data)
        {
            Fail(L.T("Não consegui abrir esta imagem."));
            return;
        }
        Save(data);
    }

    /// <summary>Null: this folder has no artwork.</summary>
    private void Save(byte[]? data)
    {
        store.Resolver.Cache.SaveUser(data, ArtworkResolver.FolderKey(entry));
        store.Invalidate(entry);
        Close();
    }
}
