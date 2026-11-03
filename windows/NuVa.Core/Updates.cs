using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

namespace NuVa.Core;

/// <summary>
/// Asks GitHub for the latest release (port of UpdateChecker.swift). Never downloads anything: the
/// notice opens the release page. A release counts for Windows only when it carries the Windows zip
/// (NuVa-Windows-&lt;version&gt;.zip), so a Mac-only release doesn't call.
/// </summary>
public static class Updates
{
    public const string ReleasesApi = "https://api.github.com/repos/martinsmdnuno/nuva/releases/latest";

    public sealed class Release
    {
        public sealed class Asset { [JsonPropertyName("name")] public string Name { get; set; } = ""; }
        [JsonPropertyName("tag_name")] public string TagName { get; set; } = "";
        [JsonPropertyName("html_url")] public string HtmlUrl { get; set; } = "";
        [JsonPropertyName("assets")] public List<Asset>? Assets { get; set; }

        /// <summary>"v1.1" → "1.1".</summary>
        public string Version => TagName.StartsWith('v') ? TagName[1..] : TagName;

        public bool HasWindows => (Assets ?? []).Any(a => a.Name == $"NuVa-Windows-{Version}.zip");
    }

    /// <summary>"1.10" &gt; "1.9"; missing parts count as 0 ("1.1" == "1.1.0").</summary>
    public static bool IsNewer(string candidate, string installed)
    {
        var a = candidate.Split('.').Select(p => int.TryParse(p, out var n) ? n : 0).ToArray();
        var b = installed.Split('.').Select(p => int.TryParse(p, out var n) ? n : 0).ToArray();
        for (var i = 0; i < Math.Max(a.Length, b.Length); i++)
        {
            int x = i < a.Length ? a[i] : 0, y = i < b.Length ? b[i] : 0;
            if (x != y) return x > y;
        }
        return false;
    }

    public static Release Parse(string json) => JsonSerializer.Deserialize<Release>(json) ?? throw new FormatException("No release");

    public static async Task<Release> Latest(string installed, HttpClient? http = null)
    {
        http ??= new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        using var request = new HttpRequestMessage(HttpMethod.Get, ReleasesApi);
        request.Headers.TryAddWithoutValidation("Accept", "application/vnd.github+json");
        request.Headers.TryAddWithoutValidation("User-Agent", $"NuVa/{installed}");
        using var response = await http.SendAsync(request);
        response.EnsureSuccessStatusCode();
        return Parse(await response.Content.ReadAsStringAsync());
    }
}

/// <summary>TERMS.md as blocks, in the interface's language (the English half, or the Portuguese one after "---").</summary>
public static class Terms
{
    public enum Kind { Title, Heading, Paragraph, Bullet }

    public static List<(Kind Kind, string Text)> Blocks(string markdown, bool portuguese)
    {
        var halves = markdown.Replace("\r\n", "\n").Split("\n---\n");
        var half = portuguese ? halves[^1] : halves[0];
        var blocks = new List<(Kind, string)>();
        var paragraph = new List<string>();
        void Flush()
        {
            if (paragraph.Count > 0) blocks.Add((Kind.Paragraph, string.Join(" ", paragraph)));
            paragraph.Clear();
        }
        foreach (var raw in half.Split('\n'))
        {
            var line = raw.Trim();
            if (line.Length == 0) { Flush(); continue; }
            if (line.StartsWith("# ")) { Flush(); blocks.Add((Kind.Title, line[2..])); }
            else if (line.StartsWith("## ")) { Flush(); blocks.Add((Kind.Heading, line[3..])); }
            else if (line.StartsWith("- ")) { Flush(); blocks.Add((Kind.Bullet, line[2..])); }
            else paragraph.Add(line);
        }
        Flush();
        return blocks;
    }
}
