using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace NuVa.Core.Tests;

public static class StringTests
{
    /// <summary>Every Portuguese key in the code has its English translation in Strings.json.</summary>
    [Test]
    public static void EveryKeyHasEnglish()
    {
        var root = Path.GetFullPath(Path.Combine(System.AppContext.BaseDirectory, "../../../.."));
        var files = Directory.GetFiles(root, "*.cs", SearchOption.AllDirectories)
            .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}") && !f.Contains("Tests"));
        var missing = files.SelectMany(f => Regex.Matches(File.ReadAllText(f), "L\\.[TF]\\(\"((?:[^\"\\\\]|\\\\.)*)\"").Select(m => m.Groups[1].Value))
            .Distinct().Where(k => !L.English.ContainsKey(k)).ToList();
        Assert.True(missing.Count == 0, "no English for: " + string.Join(" | ", missing));
        foreach (var preset in Audio.Equalizer.Presets) Assert.True(L.English.ContainsKey(preset.Key), preset.Key);
    }

    [Test]
    public static void PlaceholdersMatch()
    {
        foreach (var (pt, en) in L.English)
        {
            var a = Regex.Matches(pt, @"\{\d\}").Count;
            var b = Regex.Matches(en, @"\{\d\}").Count;
            Assert.Equal(a, b, pt);
        }
    }
}
