import CryptoKit
import Foundation

/// Table of contents of an audio CD, read from the `.TOC.plist` that macOS (cddafs)
/// puts at the root of the disc's volume. Only the audio tracks count.
struct DiscTOC: Equatable, Sendable {
    let firstTrack: Int
    let lastTrack: Int
    /// Start of each audio track in sectors (LBA, 75 per second), by track number.
    let starts: [Int: Int]
    /// End of the last audio track (LBA).
    let leadout: Int

    /// Sectors before the first track (the 2 s pregap); MusicBrainz offsets include it.
    static let pregap = 150
    /// Gap between the audio session and a data session on an enhanced CD.
    static let dataSessionGap = 11_400

    init(firstTrack: Int, lastTrack: Int, starts: [Int: Int], leadout: Int) {
        self.firstTrack = firstTrack
        self.lastTrack = lastTrack
        self.starts = starts
        self.leadout = leadout
    }

    init?(volume: URL) {
        let url = volume.appendingPathComponent(".TOC.plist", isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(plist: data)
    }

    /// Sessions › Track Array › Point / Start Block / Data, and each session's Leadout Block.
    init?(plist data: Data) {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let sessions = root["Sessions"] as? [[String: Any]] else { return nil }
        struct Track { let number: Int; let start: Int; let isData: Bool }
        var tracks: [Track] = []
        var leadouts: [Int] = []
        for session in sessions {
            if let leadout = session["Leadout Block"] as? Int { leadouts.append(leadout) }
            for track in session["Track Array"] as? [[String: Any]] ?? [] {
                guard let point = track["Point"] as? Int, let start = track["Start Block"] as? Int,
                      (1...99).contains(point) else { continue }
                tracks.append(Track(number: point, start: start, isData: track["Data"] as? Bool ?? false))
            }
        }
        tracks.sort { $0.number < $1.number }
        let audio = tracks.filter { !$0.isData }
        guard let first = audio.first, let last = audio.last, let discEnd = leadouts.first else { return nil }
        // Enhanced CD: a data track after the audio ends the audio early.
        let leadout = tracks.first { $0.isData && $0.number > last.number }
            .map { $0.start - Self.dataSessionGap } ?? discEnd
        self.init(
            firstTrack: first.number, lastTrack: last.number,
            starts: Dictionary(audio.map { ($0.number, $0.start) }, uniquingKeysWith: { a, _ in a }),
            leadout: leadout)
    }

    /// Length of a track in seconds, or nil if it isn't on the disc.
    func duration(of track: Int) -> Double? {
        guard let start = starts[track] else { return nil }
        let end = starts.filter { $0.key > track }.map(\.value).min() ?? leadout
        return Double(end - start) / 75
    }

    /// MusicBrainz disc ID: SHA-1 of the first and last track and 100 offsets, in a URL-safe Base64.
    var musicBrainzID: String {
        var text = String(format: "%02X%02X", firstTrack, lastTrack)
        text += String(format: "%08X", leadout + Self.pregap)
        for number in 1...99 {
            text += String(format: "%08X", starts[number].map { $0 + Self.pregap } ?? 0)
        }
        return Data(Insecure.SHA1.hash(data: Data(text.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: ".")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "-")
    }

    /// The TOC as MusicBrainz takes it for a fuzzy lookup: first, last, leadout, then each offset.
    var musicBrainzTOC: String {
        let offsets = (firstTrack...lastTrack).compactMap { starts[$0] }.map { $0 + Self.pregap }
        return ([firstTrack, lastTrack, leadout + Self.pregap] + offsets).map(String.init).joined(separator: " ")
    }
}
