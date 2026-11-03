using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using NuVa.Core;
using NuVa.Core.Player;

namespace NuVa.UI;

/// <summary>
/// The Mac's menu bar (NuVa, File, View, Controls) as one menu: Alt, F10, a right-click on the window or
/// the title bar's icon opens it. Every item also has its shortcut, which works without it.
/// </summary>
public static class AppMenu
{
    private static MenuItem Item(string header, Action action, bool enabled = true, bool? check = null) => QueueView.Item(header, action, enabled, check);

    private static MenuItem Sub(string header, params object[] items)
    {
        var menu = new MenuItem { Header = header };
        foreach (var item in items) menu.Items.Add(item);
        return menu;
    }

    public static ContextMenu Build(App app)
    {
        var model = app.Model;
        var player = model.Player;
        var menu = new ContextMenu();

        menu.Items.Add(Sub("NuVa",
            Item(L.T("Acerca da NuVa"), app.ShowAbout),
            Item(L.T("Procurar atualizações…"), app.CheckForUpdates),
            Item(L.T("Termos e privacidade"), app.ShowTerms),
            new Separator(),
            Item(L.T("Sair da NuVa") + "\tCtrl+Q", app.Quit)));

        menu.Items.Add(Sub(L.T("Ficheiro"),
            Item(L.T("Adicionar pasta…") + "\tCtrl+O", () => model.AddFolder(app.MainWindow)),
            Item(L.T("Adicionar Jellyfin…") + "\tCtrl+Shift+O", app.AddJellyfin),
            new Separator(),
            Item(L.T("Ejetar CD") + "\tCtrl+E", () => app.EjectDisc(null), app.EjectableDisc != null)));

        var view = Sub(L.T("Visualização"),
            Item(L.T("Player com fila") + "\tCtrl+1", () => model.WindowMode = WindowMode.Player, check: model.WindowMode == WindowMode.Player),
            Item(L.T("Player com pastas") + "\tCtrl+2", () => model.WindowMode = WindowMode.Browser, check: model.WindowMode == WindowMode.Browser),
            Item(L.T("Compacto") + "\tCtrl+3", () => model.WindowMode = WindowMode.Compact, check: model.WindowMode == WindowMode.Compact),
            new Separator(),
            Item((app.AmbientOpen ? L.T("Sair do Ambiente") : L.T("Ambiente")) + "\tCtrl+4", app.ToggleAmbient),
            AmbientOptions(app),
            new Separator(),
            Item((model.WindowMode == WindowMode.Browser ? L.T("Mostrar fila") : L.T("Mostrar pastas")) + "\tCtrl+B", model.ToggleBrowser),
            Item(L.T("Mostrar capas") + "\tCtrl+Shift+A", () => model.ShowsArtwork = !model.ShowsArtwork, check: model.ShowsArtwork),
            Item(L.T("Capa errada ou em falta…"), app.FixArtwork, app.CanFixArtwork),
            Item(L.T("Mostrar espectro") + "\tCtrl+Shift+V", () => model.ShowsSpectrum = !model.ShowsSpectrum, check: model.ShowsSpectrum),
            new Separator(),
            SkinMenu(app),
            FontMenu(app));
        menu.Items.Add(view);

        var output = Sub(L.T("Saída"));
        output.SubmenuOpened += async (_, _) =>
        {
            if (output.Items.Count > 1) return;
            output.Items.Clear();
            foreach (var device in await NuVa.Audio.GraphOutput.Devices())
                output.Items.Add(Item(device.Name, () => app.SelectOutput(device.Id), check: device.Id == model.Output.SelectedDevice));
        };
        output.Items.Add(new MenuItem { Header = "…", IsEnabled = false });

        menu.Items.Add(Sub(L.T("Controlos"),
            Item((player.IsPlaying ? L.T("Pausa") : L.T("Tocar")) + "\t" + L.T("Espaço"), model.PlayOrBrowse),
            Item(L.T("Parar") + "\tCtrl+.", player.Stop),
            Item(L.T("Seguinte") + "\tCtrl+→", player.Next),
            Item(L.T("Anterior") + "\tCtrl+←", player.Previous),
            Item(L.T("Avançar 10 s") + "\tCtrl+Shift+→", () => player.Skip(10)),
            Item(L.T("Recuar 10 s") + "\tCtrl+Shift+←", () => player.Skip(-10)),
            new Separator(),
            Item(L.T("Aumentar volume") + "\tCtrl+↑", () => player.ChangeVolume(0.05f)),
            Item(L.T("Baixar volume") + "\tCtrl+↓", () => player.ChangeVolume(-0.05f)),
            output,
            Item(L.T("Equalizador…") + "\tCtrl+Shift+E", app.ShowEqualizer),
            new Separator(),
            Item(L.T("Repetir") + "\tCtrl+R", () => player.RepeatMode = player.RepeatMode switch { RepeatMode.Off => RepeatMode.All, RepeatMode.All => RepeatMode.One, _ => RepeatMode.Off }, check: player.RepeatMode != RepeatMode.Off),
            Item((player.Shuffle ? L.T("Desligar aleatório") : L.T("Aleatório")) + "\tCtrl+Shift+S", () => player.Shuffle = !player.Shuffle, check: player.Shuffle),
            new Separator(),
            Item(L.T("Ir para a faixa atual") + "\tCtrl+L", app.RevealCurrentTrack, player.CurrentId != null),
            Item(L.T("Limpar fila") + "\tCtrl+Shift+Delete", player.Clear, player.Queue.Count > 0)));
        return menu;
    }

    public static MenuItem SkinMenu(App app)
    {
        var menu = new MenuItem { Header = "Skin" };
        foreach (var item in SkinItems(app)) menu.Items.Add(item);
        return menu;
    }

    public static MenuItem[] SkinItems(App app) => Skin.All
        .Select((skin, i) => Item($"{skin.Name}\tCtrl+Shift+{i + 1}", () => app.SetSkin(skin), check: Theme.Skin == skin))
        .ToArray();

    public static MenuItem FontMenu(App app)
    {
        var menu = new MenuItem { Header = L.T("Fonte") };
        menu.Items.Add(Item(L.F("Predefinição da skin ({0})", FontSets.Name(Theme.Skin.FontSet)), () => app.SetFonts(null), check: Theme.FontChoice == null));
        menu.Items.Add(new Separator());
        foreach (var set in FontSets.All)
            menu.Items.Add(Item(FontSets.Name(set), () => app.SetFonts(set), check: Theme.FontChoice == set));
        return menu;
    }

    public static MenuItem AmbientOptions(App app)
    {
        var options = new MenuItem { Header = L.T("Opções do Ambiente") };
        app.FillAmbientOptions(options);
        return options;
    }
}
