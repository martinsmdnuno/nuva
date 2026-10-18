import Foundation
import Testing
@testable import NuVa

@MainActor
struct OnlineArtworkTests {
    private func guess(_ path: String, root: String? = nil) -> String? {
        AlbumGuess.from(path: path, root: root).map { "\($0.artist) / \($0.album)" }
    }

    @Test func guessesArtistAndAlbumFromFolders() {
        #expect(guess("Fleetwood Mac/Rumours (1977)") == "Fleetwood Mac / Rumours")
        #expect(guess("Radiohead/2007 - In Rainbows [FLAC 24-96]") == "Radiohead / In Rainbows")
        #expect(guess("Rock/Massive Attack/Mezzanine (Deluxe)/CD 02") == "Massive Attack / Mezzanine")
        #expect(guess("Björk/Björk - Homogenic") == "Björk / Homogenic")
        #expect(guess("Música/Daft Punk - Discovery") == "Daft Punk / Discovery")
        #expect(guess("Daft Punk - Discovery") == "Daft Punk / Discovery")
        // A source added at the artist level: the source folder is the artist.
        #expect(guess("Tusk (1979)/Disc 1", root: "Fleetwood Mac") == "Fleetwood Mac / Tusk")
    }

    @Test func noGuessWithoutArtistAndAlbum() {
        #expect(guess("Rumours (1977)") == nil)
        #expect(guess("Sigur Rós/( )") == nil)
        #expect(guess("") == nil)
    }

    @Test func normalisesForComparison() {
        #expect(AlbumGuess.normalize("The Beatles") == "beatles")
        #expect(AlbumGuess.normalize("Simon & Garfunkel") == "simon and garfunkel")
        #expect(AlbumGuess.normalize("Sigur Rós") == AlbumGuess.normalize("sigur ros"))
    }

    private func group(_ title: String, _ artist: String, score: Int = 100) -> CoverArtArchive.ReleaseGroup {
        let json = """
        {"id": "x", "score": \(score), "title": "\(title)", "artist-credit": [{"name": "\(artist)"}]}
        """
        return try! JSONDecoder().decode(CoverArtArchive.ReleaseGroup.self, from: Data(json.utf8))
    }

    @Test func onlyConfidentMatchesCount() {
        let q = AlbumQuery(artist: "Fleetwood Mac", album: "Rumours")
        #expect(CoverArtArchive.matches(group("Rumours", "Fleetwood Mac"), q))
        #expect(CoverArtArchive.matches(group("Rumours (Super Deluxe)", "Fleetwood Mac"), q))
        #expect(!CoverArtArchive.matches(group("Rumours", "Fleetwood Mac", score: 80), q))
        #expect(!CoverArtArchive.matches(group("Rumours", "Tribute Band"), q))
        #expect(!CoverArtArchive.matches(group("Rumours Live", "Fleetwood Mac"), q))
    }

    @Test func cacheRemembersImagesMissesAndUserChoices() throws {
        let cache = ArtworkCache(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let q = AlbumQuery(artist: "A", album: "B")
        #expect(cache.online(q) == .unknown)
        cache.saveOnline(nil, for: q)
        #expect(cache.online(q) == .none)
        let url = try #require(cache.saveOnline(Data([1, 2, 3]), for: q))
        #expect(cache.online(q) == .image(url))
        // Same artist and album from another folder: same cached cover.
        #expect(cache.online(AlbumQuery(artist: "a", album: "b")) == .image(url))

        #expect(cache.user(folder: "src/Folder") == .unknown)
        cache.saveUser(nil, folder: "src/Folder")
        #expect(cache.user(folder: "src/Folder") == .none)
        #expect(cache.user(folder: "src/Other") == .unknown)
    }

    @Test func discFoldersShareTheAlbumKey() {
        let id = UUID()
        let a = Entry(sourceID: id, path: "Artist/Album/CD 01/01.flac", name: "01.flac", kind: .track)
        let b = Entry(sourceID: id, path: "Artist/Album/CD 02/01.flac", name: "01.flac", kind: .track)
        #expect(ArtworkResolver.folderKey(a) == ArtworkResolver.folderKey(b))
    }
}

@MainActor
struct UpdateAndTermsTests {
    @Test func comparesVersions() {
        #expect(UpdateChecker.isNewer("1.1", than: "1.0"))
        #expect(UpdateChecker.isNewer("1.10", than: "1.9"))
        #expect(UpdateChecker.isNewer("2", than: "1.9.9"))
        #expect(!UpdateChecker.isNewer("1.1", than: "1.1.0"))
        #expect(!UpdateChecker.isNewer("1.0", than: "1.1"))
    }

    @Test func releaseTagBecomesVersion() throws {
        let json = #"{"tag_name": "v1.1", "html_url": "https://github.com/martinsmdnuno/nuva/releases/tag/v1.1"}"#
        let release = try JSONDecoder().decode(UpdateChecker.Release.self, from: Data(json.utf8))
        #expect(release.version == "1.1")
    }

    @Test func termsAreBundledInBothLanguages() {
        let en = TermsView.blocks(language: "en"), pt = TermsView.blocks(language: "pt-PT")
        guard case .title(let enTitle) = en.first, case .title(let ptTitle) = pt.first else {
            Issue.record("TERMS.md missing from the bundle or without a title")
            return
        }
        #expect(enTitle == "Terms and privacy")
        #expect(ptTitle == "Termos e privacidade")
    }
}
