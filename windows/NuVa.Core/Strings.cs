using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.Json;

namespace NuVa.Core;

/// <summary>
/// Interface text in European Portuguese and English. As on the Mac, the Portuguese text is the key;
/// Strings.json holds its English translation. The system's display language picks one; anything but
/// Portuguese gets English.
/// </summary>
public static class L
{
    private static readonly Dictionary<string, string> english = Load();

    /// <summary>True when the interface is in Portuguese. Set once at launch from the system language.</summary>
    public static bool Portuguese { get; set; } = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "pt";

    /// <summary>The text for a Portuguese key in the interface's language.</summary>
    public static string T(string key) => Portuguese ? key : english.TryGetValue(key, out var en) ? en : key;

    /// <summary>A formatted text: the key has {0}, {1}… placeholders.</summary>
    public static string F(string key, params object[] args) => string.Format(CultureInfo.CurrentCulture, T(key), args);

    /// <summary>Keys with no English translation (for the tests).</summary>
    public static IReadOnlyDictionary<string, string> English => english;

    private static Dictionary<string, string> Load()
    {
        using var stream = typeof(L).Assembly.GetManifestResourceStream("NuVa.Strings.json");
        if (stream == null) return new();
        return JsonSerializer.Deserialize<Dictionary<string, string>>(stream) ?? new();
    }
}
