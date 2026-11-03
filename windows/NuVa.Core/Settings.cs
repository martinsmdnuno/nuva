using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;

namespace NuVa.Core;

/// <summary>
/// The app's settings, the Windows counterpart of the Mac's UserDefaults: one JSON file in
/// %APPDATA%\NuVa, written a moment after the last change (and on exit).
/// </summary>
public sealed class Settings
{
    private readonly string? file;
    private readonly Dictionary<string, JsonNode?> values = new();
    private readonly object gate = new();
    private Timer? pending;

    /// <summary>The app's settings. Tests make their own, in memory.</summary>
    public static Settings Shared { get; set; } = new(null);

    /// <param name="file">The JSON file, or null to keep the settings in memory only.</param>
    public Settings(string? file)
    {
        this.file = file;
        if (file == null || !File.Exists(file)) return;
        try
        {
            if (JsonNode.Parse(File.ReadAllText(file)) is JsonObject root)
                foreach (var (key, value) in root) values[key] = value?.DeepClone();
        }
        catch (Exception e)
        {
            Log.Write($"settings: unreadable, starting afresh ({e.Message})");
        }
    }

    public T Get<T>(string key, T fallback)
    {
        lock (gate)
        {
            if (!values.TryGetValue(key, out var node) || node == null) return fallback;
            try
            {
                return node.Deserialize<T>() ?? fallback;
            }
            catch (Exception)
            {
                return fallback;
            }
        }
    }

    public bool Has(string key)
    {
        lock (gate) return values.ContainsKey(key);
    }

    public void Set<T>(string key, T value)
    {
        lock (gate)
        {
            values[key] = JsonSerializer.SerializeToNode(value);
            if (file == null) return;
            pending ??= new Timer(_ => Save(), null, Timeout.Infinite, Timeout.Infinite);
            pending.Change(400, Timeout.Infinite);
        }
    }

    public void Remove(string key)
    {
        lock (gate) values.Remove(key);
        if (file != null) Save();
    }

    /// <summary>Writes the file now (atomically: a temporary file, then a replace).</summary>
    public void Save()
    {
        if (file == null) return;
        string json;
        lock (gate)
        {
            var root = new JsonObject();
            foreach (var (key, value) in values) root[key] = value?.DeepClone();
            json = root.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
        }
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(file)!);
            var temp = file + ".tmp";
            File.WriteAllText(temp, json);
            File.Move(temp, file, true);
        }
        catch (Exception e)
        {
            Log.Write($"settings: not saved ({e.Message})");
        }
    }
}

/// <summary>
/// A plain log in %LOCALAPPDATA%\NuVa\nuva.log, for what only a Windows machine can tell (audio, devices,
/// the CD drive). Kept short: the last run and the one before.
/// </summary>
public static class Log
{
    private static readonly object gate = new();
    public static string? File { get; private set; }

    public static void Start(string file)
    {
        lock (gate)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(file)!);
                if (System.IO.File.Exists(file)) System.IO.File.Copy(file, file + ".1", true);
                System.IO.File.WriteAllText(file, "");
                File = file;
            }
            catch (Exception)
            {
                File = null;
            }
        }
    }

    public static void Write(string line)
    {
        var text = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} {line}{Environment.NewLine}";
        lock (gate)
        {
            if (File == null)
            {
                System.Diagnostics.Debug.Write(text);
                return;
            }
            try
            {
                System.IO.File.AppendAllText(File, text);
            }
            catch (Exception)
            {
                // Never let logging stop the music.
            }
        }
    }
}
