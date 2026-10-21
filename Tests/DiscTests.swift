import Foundation
import Testing
@testable import NuVa

struct DiscTests {
    /// MusicBrainz's documented example: TOC "1 6 95462 150 15363 32314 46592 63414 80489".
    private let example = DiscTOC(
        firstTrack: 1, lastTrack: 6,
        starts: [1: 0, 2: 15213, 3: 32164, 4: 46442, 5: 63264, 6: 80339],
        leadout: 95312)

    @Test func musicBrainzDiscID() {
        #expect(example.musicBrainzID == "49HHV7Eb8UKF3aQiNmu1GR8vKTY-")
        #expect(example.musicBrainzTOC == "1 6 95462 150 15363 32314 46592 63414 80489")
    }

    @Test func durationsFromTheTOC() {
        #expect(example.duration(of: 1) == 15213.0 / 75)
        #expect(example.duration(of: 6) == (95312.0 - 80339) / 75)
        #expect(example.duration(of: 7) == nil)
    }

    @Test func readsTheCddafsPlist() throws {
        let plist: [String: Any] = ["Sessions": [[
            "First Track": 1, "Last Track": 3, "Leadout Block": 30000, "Session Number": 1,
            "Track Array": [
                ["Point": 1, "Start Block": 0, "Data": false],
                ["Point": 2, "Start Block": 10000, "Data": false],
                ["Point": 3, "Start Block": 20000, "Data": false],
            ],
        ]]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let toc = try #require(DiscTOC(plist: data))
        #expect(toc == DiscTOC(firstTrack: 1, lastTrack: 3, starts: [1: 0, 2: 10000, 3: 20000], leadout: 30000))
    }

    @Test func enhancedCDEndsAudioBeforeTheDataTrack() throws {
        let plist: [String: Any] = ["Sessions": [
            ["Leadout Block": 20000, "Track Array": [
                ["Point": 1, "Start Block": 0, "Data": false],
                ["Point": 2, "Start Block": 10000, "Data": false],
            ]],
            ["Leadout Block": 60000, "Track Array": [["Point": 3, "Start Block": 31400, "Data": true]]],
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let toc = try #require(DiscTOC(plist: data))
        #expect(toc.lastTrack == 2)
        #expect(toc.leadout == 31400 - DiscTOC.dataSessionGap)
    }

    @Test func picksTheMediumWithThisDisc() {
        typealias R = CoverArtArchive.Release
        let six = (1...6).map { R.Medium.Track(title: "T\($0)") }
        let releases = [
            R(id: "other", title: "Wrong", artistCredit: nil,
              media: [R.Medium(discs: [], tracks: six)]),
            R(id: "right", title: "Album", artistCredit: [.init(name: "A", joinphrase: " & "), .init(name: "B", joinphrase: nil)],
              media: [R.Medium(discs: [.init(id: example.musicBrainzID)], tracks: six)]),
        ]
        let info = CoverArtArchive.pick(releases, for: example)
        #expect(info == DiscInfo(artist: "A & B", album: "Album", titles: six.map(\.title), releaseID: "right"))
        // No exact disc: the first medium with the same number of tracks.
        #expect(CoverArtArchive.pick(Array(releases.prefix(1)), for: example)?.releaseID == "other")
        #expect(CoverArtArchive.pick([R(id: "x", title: "x", artistCredit: nil,
                                        media: [R.Medium(discs: nil, tracks: Array(six.prefix(5)))])], for: example) == nil)
    }

    @Test func namesTracksFromMusicBrainz() async throws {
        let volume = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: volume, withIntermediateDirectories: true)
        for name in ["1 Audio Track.aiff", "2 Audio Track.aiff", "10 Audio Track.aiff", ".TOC.plist"] {
            FileManager.default.createFile(atPath: volume.appendingPathComponent(name).path, contents: Data())
        }
        defer { try? FileManager.default.removeItem(at: volume) }
        let toc = DiscTOC(firstTrack: 1, lastTrack: 10, starts: Dictionary(uniqueKeysWithValues: (1...10).map { ($0, ($0 - 1) * 750) }), leadout: 7500)
        let info = DiscInfo(artist: "AC/DC", album: "Back in Black", titles: (1...10).map { "Song \($0)" }, releaseID: "r")

        let disc = DiscSource(volume: volume, toc: toc, info: info)
        #expect(disc.folder == "AC∕DC – Back in Black")
        #expect(try await disc.list("").map(\.name) == [disc.folder])
        let tracks = try await disc.list(disc.folder)
        #expect(tracks.map(\.name) == ["01 Song 1.aiff", "02 Song 2.aiff", "10 Song 10.aiff"])
        #expect(tracks.map(\.title) == ["Song 1", "Song 2", "Song 10"])
        #expect(tracks[0].folderName == disc.folder)
        #expect(tracks[0].duration == 10)
        #expect(try await disc.url(for: tracks[2]).lastPathComponent == "10 Audio Track.aiff")
        // Same disc, same id: its artwork choice sticks.
        #expect(DiscSource(volume: volume, toc: toc, info: nil).id == disc.id)

        let unknown = DiscSource(volume: volume, toc: toc, info: nil)
        #expect(unknown.folder == volume.lastPathComponent)
        #expect(try await unknown.list(unknown.folder).map(\.listName) == ["1 Audio Track", "2 Audio Track", "10 Audio Track"])
    }
}
