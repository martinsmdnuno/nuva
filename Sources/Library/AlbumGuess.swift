import Foundation

/// Artist and album to look up online, read from folder names (never from tags).
struct AlbumQuery: Hashable, Codable, Sendable {
    var artist: String
    var album: String

    /// Key shared by every folder with the same artist and album.
    var key: String { "\(AlbumGuess.normalize(artist))|\(AlbumGuess.normalize(album))" }
}

enum AlbumGuess {
    /// "Artist/Album (1977)/CD 01" → Fleetwood Mac, Rumours. `root` is the source folder's own name
    /// (for a source added at the artist level); `path` is the folder, relative to the source.
    static func from(path: String, root: String? = nil) -> AlbumQuery? {
        var parts = path.split(separator: "/").map(String.init)
        if let root, !root.isEmpty { parts.insert(root, at: 0) }
        // Disc folders belong to the album above them.
        while let last = parts.last, isDiscFolder(last) { parts.removeLast() }
        guard let folder = parts.last else { return nil }

        // "Artist - Album" in a single folder name.
        if parts.count == 1 || isGeneric(parts[parts.count - 2]) {
            let pieces = folder.components(separatedBy: " - ")
            if pieces.count >= 2 {
                let artist = clean(pieces[0]), album = clean(pieces.dropFirst().joined(separator: " - "))
                return valid(artist, album)
            }
            return nil
        }
        var album = clean(folder)
        let artist = clean(parts[parts.count - 2])
        // "Artist - Album" inside the artist folder: drop the repeated artist.
        if let range = album.range(of: artist + " - ", options: [.caseInsensitive, .anchored]) {
            album = String(album[range.upperBound...])
        }
        return valid(artist, album)
    }

    private static func valid(_ artist: String, _ album: String) -> AlbumQuery? {
        artist.isEmpty || album.isEmpty ? nil : AlbumQuery(artist: artist, album: album)
    }

    static func isDiscFolder(_ name: String) -> Bool {
        name.range(of: #"^(cd|disc|disk|disco)[\s._-]*\d+\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Library-level folders that are not an artist.
    private static func isGeneric(_ name: String) -> Bool {
        ["music", "música", "musica", "flac", "mp3", "albums", "álbuns", "albuns", "library", "biblioteca"]
            .contains(name.lowercased())
    }

    /// Removes years, formats and editions: "1977 - Rumours (Remastered) [FLAC 24-96]" → "Rumours".
    static func clean(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "_", with: " ")
        // Bracketed chunks: (1977), [FLAC], {24-96}, (Deluxe Edition)…
        s = s.replacingOccurrences(of: #"\s*[\(\[\{][^\)\]\}]*[\)\]\}]"#, with: "", options: .regularExpression)
        // Leading year or catalogue order: "1977 - ", "1977. "
        s = s.replacingOccurrences(of: #"^\s*(19|20)\d{2}\s*[-–.]\s*"#, with: "", options: .regularExpression)
        // Trailing year or format: " - 1977", " FLAC", " 24bit"
        s = s.replacingOccurrences(
            of: #"(\s*[-–]?\s*((19|20)\d{2}|flac|mp3|alac|wav|hi-?res|24[\s-]?bit|\d{2}[-/]\d{2,3}))+\s*$"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        return s.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "-–.")))
    }

    /// For comparing names: lowercase, no accents or punctuation, "&" as "and", no leading "the".
    static func normalize(_ s: String) -> String {
        var t = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        t = t.replacingOccurrences(of: "&", with: " and ")
        t = t.replacingOccurrences(of: #"[^a-z0-9 ]"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("the ") { t.removeFirst(4) }
        return t
    }
}
