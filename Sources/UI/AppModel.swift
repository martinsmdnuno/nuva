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

    enum WindowMode: String {
        /// Player with playlist, 360 × 480.
        case player
        /// With browser, 720 × 480.
        case browser
        /// Compact: display, keys and volume only (360 wide, height from content).
        case compact
    }

    /// "Add Jellyfin" sheet open.
    var showingJellyfinLogin = false

    var windowMode: WindowMode {
        didSet { defaults.set(windowMode.rawValue, forKey: "windowMode") }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var nowPlaying: NowPlaying?

    /// `systemIntegration`: media keys and Now Playing (off in snapshots).
    init(defaults: UserDefaults = .standard, systemIntegration: Bool = false) {
        let sources = SourceStore(defaults: defaults)
        let resolve: PlayerController.Resolver = { entry in try await sources.resolve(entry) }
        self.sources = sources
        self.player = PlayerController(resolve: resolve, equalizer: Equalizer(defaults: defaults))
        self.durations = TrackDurations(resolve: resolve)
        self.browser = Browser(sources: sources)
        self.output = OutputRoute(player: systemIntegration ? self.player.avPlayer : nil)
        self.defaults = defaults
        self.windowMode = WindowMode(rawValue: defaults.string(forKey: "windowMode") ?? "") ?? .player
        if systemIntegration { nowPlaying = NowPlaying(player: player) }
        if sources.sources.count == 1, let only = sources.sources.first {
            browser.open(BrowserLocation(sourceID: only.id, path: ""))
        }
    }

    /// Source label of the current track ("Local", "Servidor").
    var currentSourceLabel: String {
        guard let entry = player.current?.entry else { return "" }
        return sources.source(entry.sourceID)?.kind.label ?? ""
    }

    /// Opens or closes the folders drawer.
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
}
