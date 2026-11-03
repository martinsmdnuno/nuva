using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using NuVa.Core;

namespace NuVa.UI;

/// <summary>A notice in NuVa's own look: a title, a line, and keys (the first is the default).</summary>
public sealed class Notice : Window
{
    public int Choice { get; private set; } = -1;

    private Notice(Window? owner, string title, string text, string[] keys)
    {
        if (owner is { IsVisible: true }) { Owner = owner; WindowStartupLocation = WindowStartupLocation.CenterOwner; }
        else WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Title = "NuVa";
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.Height;
        Width = 380;
        Background = Theme.Brush(Token.Surface1);
        var stack = new StackPanel { Margin = new Thickness(Space.S4) };
        stack.Children.Add(Text.Make(title, TextStyle.Title, Token.Ink));
        var body = Text.Make(text, TextStyle.Body, Token.InkMuted);
        body.TextWrapping = TextWrapping.Wrap;
        body.TextTrimming = TextTrimming.None;
        body.Margin = new Thickness(0, Space.S2, 0, 0);
        stack.Children.Add(body);
        var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, Space.S4, 0, 0) };
        for (var i = keys.Length - 1; i >= 0; i--)
        {
            var index = i;
            row.Children.Add(new KeyButton(keys[i], null, () => { Choice = index; Close(); }) { Margin = new Thickness(Space.S2, 0, 0, 0) });
        }
        stack.Children.Add(row);
        Content = stack;
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape) { Close(); e.Handled = true; }
            if (e.Key == Key.Enter) { Choice = 0; Close(); e.Handled = true; }
        };
    }

    /// <summary>Shows the notice; returns the key pressed (0 is the first), or -1 for Esc.</summary>
    public static int Show(Window? owner, string title, string text, params string[] keys)
    {
        var notice = new Notice(owner, title, text, keys.Length == 0 ? ["OK"] : keys);
        notice.ShowDialog();
        return notice.Choice;
    }
}

/// <summary>NuVa ▸ Terms and Privacy: TERMS.md from the app, in the interface's language.</summary>
public sealed class TermsWindow : Window
{
    public TermsWindow()
    {
        Title = L.T("Termos e privacidade");
        Width = 540;
        Height = 640;
        MinWidth = 420;
        MinHeight = 360;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Theme.Brush(Token.Surface0);
        var markdown = "";
        using (var stream = typeof(TermsWindow).Assembly.GetManifestResourceStream("NuVa.TERMS.md"))
            if (stream != null) markdown = new StreamReader(stream).ReadToEnd();
        var document = new FlowDocument
        {
            PagePadding = new Thickness(Space.S6),
            Background = Theme.Brush(Token.Surface0),
            Foreground = Theme.Brush(Token.Ink),
            FontFamily = TextStyle.Body.Family,
            FontSize = TextStyle.Body.Size,
        };
        foreach (var (kind, text) in Terms.Blocks(markdown, L.Portuguese))
        {
            var paragraph = new Paragraph { Margin = new Thickness(0, kind == Terms.Kind.Heading ? Space.S4 : 0, 0, Space.S2) };
            switch (kind)
            {
                case Terms.Kind.Title:
                    paragraph.FontSize = 20;
                    paragraph.FontWeight = FontWeights.SemiBold;
                    break;
                case Terms.Kind.Heading:
                    paragraph.FontSize = TextStyle.Title.Size;
                    paragraph.FontWeight = TextStyle.Title.FontWeight;
                    break;
                case Terms.Kind.Bullet:
                    paragraph.Inlines.Add(new Run("·  ") { Foreground = Theme.Brush(Token.InkMuted) });
                    break;
            }
            Inline(paragraph, text);
            document.Blocks.Add(paragraph);
        }
        Content = new FlowDocumentScrollViewer { Document = document, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) Close(); };
    }

    private static readonly Regex inline = new(@"\*\*(.+?)\*\*|\*(.+?)\*|\[(.+?)\]\((.+?)\)");

    /// <summary>**bold**, *italic* and [links](url), the inline markdown TERMS.md uses.</summary>
    private static void Inline(Paragraph paragraph, string text)
    {
        var at = 0;
        foreach (Match m in inline.Matches(text))
        {
            if (m.Index > at) paragraph.Inlines.Add(new Run(text[at..m.Index]));
            if (m.Groups[1].Success) paragraph.Inlines.Add(new Bold(new Run(m.Groups[1].Value)));
            else if (m.Groups[2].Success) paragraph.Inlines.Add(new Italic(new Run(m.Groups[2].Value)));
            else
            {
                var link = new Hyperlink(new Run(m.Groups[3].Value)) { NavigateUri = new Uri(m.Groups[4].Value), Foreground = Theme.Brush(Token.Focus) };
                link.RequestNavigate += (_, e) => App.OpenInBrowser(e.Uri.AbsoluteUri);
                paragraph.Inlines.Add(link);
            }
            at = m.Index + m.Length;
        }
        if (at < text.Length) paragraph.Inlines.Add(new Run(text[at..]));
    }
}
