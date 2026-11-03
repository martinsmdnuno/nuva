using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace NuVa.Core.Library;

/// <summary>
/// A folder on this computer, a mapped drive or a network share (\\server\share). Windows needs no
/// bookmark: the path is enough.
/// </summary>
public sealed class LocalSource(Guid id, string name, string root) : IMusicSource
{
    public Guid Id { get; } = id;
    public string Name { get; } = name;
    public SourceKind Kind => SourceKind.Local;
    /// <summary>Full path of the folder.</summary>
    public string Root { get; } = root;

    public string? RootFolderName => System.IO.Path.GetFileName(Root.TrimEnd('\\', '/'));

    private string Full(string path) =>
        path.Length == 0 ? Root : System.IO.Path.Combine(Root, path.Replace('/', System.IO.Path.DirectorySeparatorChar));

    public Task<IReadOnlyList<Entry>> List(string path) => Task.Run<IReadOnlyList<Entry>>(() =>
    {
        var dir = new DirectoryInfo(Full(path));
        FileSystemInfo[] items;
        try
        {
            items = dir.GetFileSystemInfos();
        }
        catch (Exception)
        {
            throw SourceException.MissingFolder(path.Length == 0 ? Name : Paths.LastComponent(path));
        }
        var entries = new List<Entry>();
        foreach (var item in items)
        {
            // Hidden and system files, as the Mac skips hidden ones (desktop.ini, Thumbs.db, ._ files).
            if ((item.Attributes & (FileAttributes.Hidden | FileAttributes.System)) != 0 || item.Name.StartsWith('.')) continue;
            var rel = Paths.Join(path, item.Name);
            if ((item.Attributes & FileAttributes.Directory) != 0)
                entries.Add(new Entry(Id, rel, item.Name, EntryKind.Folder));
            else if (Playable.IsPlayable(item.Name))
                entries.Add(new Entry(Id, rel, item.Name, EntryKind.Track));
        }
        return entries.NaturallySorted();
    });

    public Task<string?> Artwork(string folderPath) => Task.Run(() =>
    {
        try
        {
            var dir = Full(folderPath);
            var file = ArtworkFiles.Pick(Directory.EnumerateFiles(dir).Select(f => System.IO.Path.GetFileName(f)));
            return file == null ? null : System.IO.Path.Combine(dir, file);
        }
        catch (Exception)
        {
            return (string?)null;
        }
    });

    public Task<string> Url(Entry track)
    {
        var file = Full(track.Path);
        if (!File.Exists(file)) throw SourceException.MissingFolder(track.FolderName);
        return Task.FromResult(file);
    }

    /// <summary>The folder can be read now (a network share may be offline).</summary>
    public bool IsReachable => Directory.Exists(Root);
}
