import AppKit
import Foundation
import Observation

/// App state: sources, player and queue durations.
@MainActor
@Observable
final class AppModel {
    let sources: SourceStore
    let player: PlayerController
    let durations: TrackDurations
    let browser: Browser
    let output: OutputRoute
    let artwork: ArtworkStore
    let artworkResolver: ArtworkResolver

    /// What sits below the keys. The window is the same device in every mode: 360 to 640 wide.
    enum WindowMode: String {
        /// The queue, 480 or taller.
        case player
        /// The folders, in place of the queue (the raw value is from when they were a drawer).
        case browser
        /// Compact: display, keys and volume only, height from content.
        case compact
    }

    /// "Add Jellyfin" sheet open.
    var showingJellyfinLogin = false

    /// Main window open. NuVa's menu bar icon shows only while it is closed: with the window open,
    /// macOS's own Now Playing item is already there.
    var isMainWindowOpen = true

    var windowMode: WindowMode {
        didSet { defaults.set(windowMode.rawValue, forKey: "windowMode") }
    }

    /// Folder artwork in the display, the mini player and Now Playing. Off by default.
    var showsArtwork: Bool {
        didSet { defaults.set(showsArtwork, forKey: "showsArtwork") }
    }

    /// Spectrum meter on the display (View ▸ Show Spectrum). On by default.
    var showsSpectrum: Bool {
        didSet { defaults.set(showsSpectrum, forKey: "showsSpectrum") }
    }

    /// Artwork of the current track's folder, when artwork is on.
    var currentArtwork: NSImage? { currentLoadedArtwork?.image }

    var currentLoadedArtwork: ArtworkStore.Loaded? {
        guard showsArtwork, let entry = player.current?.entry else { return nil }
        return artwork.artwork(for: entry)
    }

    /// "Wrong artwork…" applies to online or user artwork, and to a finished lookup that found none.
    /// An image in the folder is the user's own and always wins.
    var canFixArtwork: Bool {
        guard showsArtwork, let entry = player.current?.entry, artwork.isResolved(entry) else { return false }
        return currentLoadedArtwork?.origin != .folder
    }

    /// Folder whose artwork is being fixed (sheet open).
    var fixingArtwork: Entry?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var nowPlaying: NowPlaying?
    @ObservationIgnored private let drive = DiscDrive()
    @ObservationIgnored private let discLookup = DiscLookup.standard
    /// Volumes of discs being read (lookup under way), so a mount seen twice plays once.
    @ObservationIgnored private var inserting: Set<URL> = []

    /// `systemIntegration`: media keys and Now Playing (off in snapshots).
    init(defaults: UserDefaults = .standard, systemIntegration: Bool = false) {
        let sources = SourceStore(defaults: defaults)
        let resolve: PlayerController.Resolver = { entry in try await sources.resolve(entry) }
        self.sources = sources
        self.player = PlayerController(resolve: resolve, equalizer: Equalizer(defaults: defaults))
        self.durations = TrackDurations(resolve: resolve)
        self.browser = Browser(sources: sources)
        self.output = OutputRoute(player: systemIntegration ? self.player.avPlayer : nil)
        let resolver = ArtworkResolver(sources: sources)
        self.artwork = ArtworkStore { entry in await resolver.resolve(entry) }
        self.artworkResolver = resolver
        self.defaults = defaults
        self.windowMode = WindowMode(rawValue: defaults.string(forKey: "windowMode") ?? "") ?? .player
        self.showsArtwork = defaults.bool(forKey: "showsArtwork")
        self.showsSpectrum = defaults.object(forKey: "showsSpectrum") as? Bool ?? true
        if systemIntegration { nowPlaying = NowPlaying(player: player, artwork: { [unowned self] in currentArtwork }) }
        if sources.sources.count == 1, let only = sources.sources.first {
            browser.open(BrowserLocation(sourceID: only.id, path: ""))
        }
        // Not under tests: the test host would start playing a CD left in the drive.
        if systemIntegration, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            drive.onInsert = { [unowned self] volume in Task { await insertDisc(volume) } }
            drive.onRemove = { [unowned self] volume in releaseDisc(volume) }
            drive.start()
        }
    }

    /// Source label of the current track ("Local", "Servidor").
    var currentSourceLabel: String {
        guard let entry = player.current?.entry else { return "" }
        return sources.source(entry.sourceID)?.kind.label ?? ""
    }

    /// Swaps the queue and the folders below the keys.
    func toggleBrowser() {
        windowMode = windowMode == .browser ? .player : .browser
    }

    /// Shows or hides the queue: toggles between the player and compact mode.
    func toggleQueue() {
        windowMode = windowMode == .compact ? .player : .compact
    }

    /// Play with no queue opens the folder browser.
    func playOrBrowse() {
        if player.queue.isEmpty {
            windowMode = .browser
        } else {
            player.togglePlayPause()
        }
    }

    /// Adds a Local source and opens it in the browser.
    func addFolder() {
        windowMode = .browser
        guard let source = sources.addLocal() else { return }
        browser.open(BrowserLocation(sourceID: source.id, path: ""))
    }

    /// Opens the sheet to add a Jellyfin server.
    func addJellyfin() {
        windowMode = .browser
        showingJellyfinLogin = true
    }

    /// Plays a folder (with subfolders), starting at a track if given.
    func playFolder(_ folder: BrowserLocation, startingAt track: Entry? = nil) async {
        let tracks = await browser.tracks(in: folder)
        guard !tracks.isEmpty else { return }
        player.setQueue(tracks, startAt: track.flatMap { t in tracks.firstIndex { $0.id == t.id } } ?? 0)
        // The folders give way to the queue, now holding what was chosen.
        if windowMode == .browser { windowMode = .player }
    }

    /// Appends a track or a whole folder to the end of the queue.
    func enqueue(_ entry: Entry) async {
        switch entry.kind {
        case .track:
            player.append([entry])
        case .folder:
            player.append(await browser.tracks(in: BrowserLocation(sourceID: entry.sourceID, path: entry.path)))
        }
    }

    // MARK: CDs

    /// The CD that ⌘E ejects: the one playing, else the one in the drive.
    var ejectableDisc: DiscSource? {
        let discs = sources.discs
        if let entry = player.current?.entry, let playing = discs.first(where: { $0.id == entry.sourceID }) {
            return playing
        }
        return discs.first
    }

    /// A CD went in: look up its names, add it as a source and play it, like a CD player.
    func insertDisc(_ volume: URL) async {
        guard !sources.discs.contains(where: { $0.volume == volume }), inserting.insert(volume).inserted else { return }
        defer { inserting.remove(volume) }
        let toc = DiscTOC(volume: volume)
        let info: DiscInfo? = if let toc { await discLookup.info(for: toc) } else { nil }
        // Ejected while MusicBrainz was answering.
        guard DiscSource.isAudioCD(volume) else { return }
        let disc = DiscSource(volume: volume, toc: toc, info: info, lookup: discLookup)
        sources.addDisc(disc)
        await playFolder(BrowserLocation(sourceID: disc.id, path: disc.folder))
    }

    /// Ejects the CD after letting go of its files.
    func ejectDisc(_ disc: DiscSource? = nil) {
        guard let disc = disc ?? ejectableDisc else { return }
        let volume = disc.volume
        releaseDisc(volume)
        Task {
            do {
                try await drive.eject(volume)
            } catch {
                // AVFoundation can take a moment to close the file: one more try.
                try? await Task.sleep(for: .seconds(1))
                try? await drive.eject(volume)
            }
        }
    }

    /// The CD is going away: its tracks leave the queue and it leaves the sources.
    func releaseDisc(_ volume: URL) {
        for disc in sources.discs where disc.volume == volume {
            player.removeAll { $0.sourceID == disc.id }
            if browser.location?.sourceID == disc.id { browser.open(nil) }
            sources.remove(disc.id)
        }
    }
}
