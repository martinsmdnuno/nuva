using System;
using System.Linq;
using System.Windows.Controls;
using NuVa.Core;
using NuVa.UI;

namespace NuVa;

// Ambient mode (View ▸ Ambient, Ctrl+4 or F11).
public sealed partial class App
{
    private AmbientWindow? ambient;
    private AmbientOptions? ambientOptions;
    private AmbientOptions Ambient => ambientOptions ??= new AmbientOptions(Settings.Shared);

    public bool AmbientOpen => ambient != null;

    public void ToggleAmbient()
    {
        if (ambient != null) ambient.Close();
        else OpenAmbient(Ambient.Screen);
    }

    private void OpenAmbient(int screenIndex)
    {
        ambient?.Close();
        var screens = System.Windows.Forms.Screen.AllScreens;
        var screen = screenIndex >= 0 && screenIndex < screens.Length
            ? screens[screenIndex]
            : MainWindow.IsVisible ? System.Windows.Forms.Screen.FromHandle(new System.Windows.Interop.WindowInteropHelper(MainWindow).Handle) : System.Windows.Forms.Screen.PrimaryScreen!;
        ambient = new AmbientWindow(this, Ambient, screen);
        ambient.Closed += (_, _) => ambient = null;
        ambient.Show();
        ambient.Activate();
    }

    public void FillAmbientOptions(MenuItem options)
    {
        var settings = Ambient;
        foreach (var face in Enum.GetValues<AmbientFace>())
            options.Items.Add(QueueView.Item(AmbientOptions.Name(face), () => { settings.Face = face; ambient?.Canvas.FaceChanged(false); }, check: settings.Face == face));
        options.Items.Add(new Separator());
        options.Items.Add(QueueView.Item(L.T("Escurecer"), () => settings.Dims = !settings.Dims, check: settings.Dims));
        options.Items.Add(QueueView.Item(L.T("Proteção OLED"), () => settings.ProtectsOled = !settings.ProtectsOled, check: settings.ProtectsOled));
        var screens = System.Windows.Forms.Screen.AllScreens;
        if (screens.Length > 1)
        {
            options.Items.Add(new Separator());
            for (var i = 0; i < screens.Length; i++)
            {
                var index = i;
                var name = screens[i].Primary ? L.F("Ecrã {0} (principal)", i + 1) : L.F("Ecrã {0}", i + 1);
                options.Items.Add(QueueView.Item(L.F("Abrir em {0}", name), () => { settings.Screen = index; OpenAmbient(index); }, check: settings.Screen == index));
            }
        }
    }
}
