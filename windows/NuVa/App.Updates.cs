using System;
using System.Diagnostics;
using System.Threading.Tasks;
using NuVa.Core;
using NuVa.UI;

namespace NuVa;

// The update check (GitHub releases/latest, a notice only, never a download) and Terms and Privacy.
public sealed partial class App
{
    private TermsWindow? terms;

    /// <summary>At launch: at most once a day, quietly. A notice only for a newer Windows version the user hasn't skipped.</summary>
    private async void CheckAtLaunch()
    {
        var last = Settings.Shared.Get("lastUpdateCheck", DateTime.MinValue);
        if (DateTime.UtcNow - last < TimeSpan.FromHours(24)) return;
        try
        {
            var release = await Updates.Latest(Version);
            Settings.Shared.Set("lastUpdateCheck", DateTime.UtcNow);
            if (!release.HasWindows || !Updates.IsNewer(release.Version, Version) || Settings.Shared.Get<string?>("skippedVersion", null) == release.Version) return;
            ShowUpdate(release, allowSkip: true);
        }
        catch (Exception e)
        {
            Log.Write($"updates: {e.Message}");
        }
    }

    /// <summary>NuVa ▸ Check for Updates…: always answers, also when up to date or offline.</summary>
    public async void CheckForUpdates()
    {
        try
        {
            var release = await Updates.Latest(Version);
            Settings.Shared.Set("lastUpdateCheck", DateTime.UtcNow);
            if (release.HasWindows && Updates.IsNewer(release.Version, Version)) ShowUpdate(release, allowSkip: false);
            else Notice.Show(MainWindow, L.T("A NuVa está atualizada"), L.F("Tens a versão mais recente ({0}).", Version));
        }
        catch (Exception)
        {
            Notice.Show(MainWindow, L.T("Não foi possível procurar atualizações"), L.T("Sem ligação ao GitHub. Tenta mais tarde."));
        }
    }

    private void ShowUpdate(Updates.Release release, bool allowSkip)
    {
        string[] keys = allowSkip ? [L.T("Descarregar"), L.T("Mais tarde"), L.T("Ignorar esta versão")] : [L.T("Descarregar"), L.T("Mais tarde")];
        var choice = Notice.Show(MainWindow, L.F("NuVa {0} disponível", release.Version),
            L.F("Tens a {0}. A nova versão está no GitHub; a NuVa não descarrega nada sozinha.", Version), keys);
        if (choice == 0) OpenInBrowser(release.HtmlUrl);
        if (choice == 2) Settings.Shared.Set("skippedVersion", release.Version);
    }

    public static void OpenInBrowser(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch (Exception e)
        {
            Log.Write($"browser: {e.Message}");
        }
    }

    public void ShowTerms()
    {
        if (terms != null) { terms.Activate(); return; }
        terms = new TermsWindow();
        terms.Closed += (_, _) => terms = null;
        terms.Show();
    }
}
