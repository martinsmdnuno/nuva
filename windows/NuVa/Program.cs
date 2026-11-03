using System;
using System.Windows;

namespace NuVa;

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        var app = new App(args);
        return app.Run();
    }
}
