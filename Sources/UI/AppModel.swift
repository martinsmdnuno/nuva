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

    /// What sits below the keys. The window is the same device in every mode: 360 to 480 wide.
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
        didSet {
            defaults.set(windowMode.rawValue, forKey: "windowMode")
            if windowMode != oldValue { count("mode.\(windowMode.rawValue)") }
        }
    }

    /// Folder artwork in the display, the mini player and Now Playing. Off by default.
    var showsArtwork: Bool {
        didSet {
            defaults.set(showsArtwork, forKey: "showsArtwork")
            if showsArtwork, !oldValue { count("artwork.on") }
        }
    }

    /// Spectrum meter on the display (View ▸ Show Spectrum). On by default.
    var showsSpectrum: Bool {
        didSet { defaults.set(showsSpectrum, forKey: "showsSpectrum") }
    }

    /// Controls ▸ Match Output to Track: a wired output is set to each track's sample rate, and
    /// put back when this is turned off or NuVa quits. On by default.
    var matchesOutputRate: Bool {
        didSet {
            guard matchesOutputRate != oldValue else { return }
            defaults.set(matchesOutputRate, forKey: "matchesOutputRate")
            if matchesOutputRate {
                matchOutputRate()
            } else {
                outputRate.restore()
            }
        }
    }

    /// Artwork of the current track's folder, when artwork is on.
    var currentArtwork: NSImage? { currentLoadedArtwork?.image }

    var currentLoadedArtwork: ArtworkStore.Loaded? {
        guard showsArtwork, let entry = player.current?.entry else { return nil }
        return artwork.artwork(for: entry)
    }

    /// Artwork is on and there is none to show: nothing playing, or a folder known to have no cover
    /// (not one still being looked up). Ambient mode then glows in the skin's own light.
    var lacksArtwork: Bool {
        guard showsArtwork else { return false }
        guard let entry = player.current?.entry else { return true }
        return artwork.isResolved(entry) && currentLoadedArtwork == nil
    }

    /// "Wrong artwork…" applies to online or user artwork, and to a finished lookup that found none.
    /// An image in the folder is the user's own and always wins.
    var canFixArtwork: Bool {
        guard showsArtwork, let entry = player.current?.entry, artwork.isResolved(entry) else { return false }
        return currentLoadedArtwork?.origin != .folder
    }

    /// Something the user asked for that didn't happen (a folder that wouldn't open), with the reason.
    struct Notice: Equatable {
        let message: String
        let detail: String?
    }

    /// On the display for a few seconds, where a failed track's message goes.
    private(set) var notice: Notice?
    @ObservationIgnored private var noticeToken = 0

    /// Folder whose artwork is being fixed (sheet open).
    var fixingArtwork: Entry?
    /// The equalizer panel, open from the display or Controls ▸ Equalizer… (⌥⌘E).
    var showsEqualizer = false {
        didSet { if showsEqualizer, !oldValue { count("eq.open") } }
    }

    /// NuVa ▸ Send Anonymous Use and Failures: the user's yes to `Reports`. Off until they say so.
    var sendsReports: Bool {
        didSet {
            guard sendsReports != oldValue else { return }
            reports?.setConsent(sendsReports)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let outputRate = OutputRate()
    @ObservationIgnored private var nowPlaying: NowPlaying?
    @ObservationIgnored private var memory: PlayerMemory?
    /// Only the real app reports: nil in tests and snapshots.
    @ObservationIgnored private let reports: Reports?
    @ObservationIgnored private var crashes: CrashWatcher?
    @ObservationIgnored private let drive = DiscDrive()
    @ObservationIgnored private let discLookup = DiscLookup.standard
    /// Volumes of discs being read (lookup under way), so a mount seen twice plays once.
    @ObservationIgnored private var inserting: Set<URL> = []

    /// `systemIntegration`: media keys and Now Playing (off in snapshots).
    init(defaults: UserDefaults = .standard, systemIntegration: Bool = false, reports: Reports? = nil) {
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let reports = reports ?? (systemIntegration && !underTest ? Reports.shared : nil)
        self.reports = reports
        self.sendsReports = reports?.consent == true
        let sources = SourceStore(defaults: defaults)
        let resolve: PlayerController.Resolver = { entry in try await sources.resolve(entry) }
        self.sources = sources
        self.player = PlayerController(resolve: resolve, equalizer: Equalizer(defaults: defaults))
        self.player.onStreamFailure = { entry in await sources.streamFailed(for: entry) }
        self.durations = TrackDurations(resolve: resolve)
        self.browser = Browser(sources: sources)
        let player = self.player
        self.output = OutputRoute(player: systemIntegration ? player.avPlayer : nil) { player.trackSampleRate }
        let resolver = ArtworkResolver(sources: sources)
        self.artwork = ArtworkStore { entry in await resolver.resolve(entry) }
        self.artworkResolver = resolver
        self.defaults = defaults
        self.windowMode = WindowMode(rawValue: defaults.string(forKey: "windowMode") ?? "") ?? .player
        self.showsArtwork = defaults.bool(forKey: "showsArtwork")
        self.showsSpectrum = defaults.object(forKey: "showsSpectrum") as? Bool ?? true
        self.matchesOutputRate = defaults.object(forKey: "matchesOutputRate") as? Bool ?? true
        // Before Now Playing, so it starts with the track of the last session.
        if systemIntegration {
            memory = PlayerMemory(player: player, defaults: defaults) { sources.remembers($0) }
        }
        player.onTrackStarted = { [unowned self] entry in
            let kind = self.sources.source(entry.sourceID)?.kind.rawValue ?? "unknown"
            count("played.\(kind).\(entry.format.lowercased())")
        }
        // Only the real app has an output to set: `output` has no device in tests and snapshots.
        player.onTrackRate = { [unowned self] _ in matchOutputRate() }
        output.onDeviceChange = { [unowned self] in if player.isPlaying { matchOutputRate() } }
        if systemIntegration, !underTest {
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.outputRate.restore() }
            }
        }
        if systemIntegration, !underTest, let reports {
            count("launch")
            let watcher = CrashWatcher(reports: reports)
            watcher.start()
            crashes = watcher
            // About once a day while the app is open, and at launch if a day has passed.
            Task { [unowned self] in
                while !Task.isCancelled {
                    await reports.sendIfDue(settings: usageSettings)
                    try? await Task.sleep(for: .seconds(3600))
                }
            }
        }
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

    // MARK: Output rate

    /// Sets the device the sound goes to at the current track's sample rate, when the setting is
    /// on and that device is a wired one. A device that refuses is only written down: the music
    /// plays on, resampled by macOS. Plan in docs/plans/dac-sample-rate.md.
    private func matchOutputRate() {
        guard matchesOutputRate, let track = player.trackSampleRate, let device = output.localDevice() else { return }
        switch outputRate.match(track: track, on: device) {
        case .asked:
            count("output-rate.set")
        case .refused(let rate, let status):
            Log.shared.error(.player, "output-rate", detail: "\(AudioFormat.kHz(rate)) kHz, status \(status)")
        case .leftAlone, .unchanged:
            break
        }
    }

    // MARK: Reports

    /// Counts a use of a feature, when the user agreed to report them. `event` is a fixed word.
    func count(_ event: String) {
        reports?.count(event)
    }

    /// How the app is set, counted once per report: settings chosen long ago are use too.
    var usageSettings: [String] {
        let skins = SkinStore.shared
        var settings = [
            "state.skin.\(skins.current.id)", "state.font.\(skins.fontSet.rawValue)",
            "state.mode.\(windowMode.rawValue)", "state.repeat.\(player.repeatMode.rawValue)",
        ]
        if showsArtwork { settings.append("state.artwork") }
        if showsSpectrum { settings.append("state.spectrum") }
        if matchesOutputRate { settings.append("state.output-rate") }
        if player.equalizer.enabled { settings.append("state.eq") }
        if player.shuffle { settings.append("state.shuffle") }
        settings += Set(sources.sources.map(\.kind.rawValue)).map { "state.source.\($0)" }
        return settings
    }

    /// Asks once, the first time the window shows, whether NuVa may report use and failures.
    /// The answer that needs no thought (Return) is no.
    func askAboutReports() {
        guard let reports, reports.consent == nil else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Ajudar a melhorar a NuVa?")
        alert.informativeText = String(localized: "A NuVa pode enviar ao autor, cerca de uma vez por dia, contagens anónimas: que funções são usadas e que tipos de falha acontecem. Nunca nomes de pastas, ficheiros ou servidores, nem nada que te identifique. Podes mudar de ideias no menu NuVa; os detalhes estão em Termos e privacidade.")
        alert.addButton(withTitle: String(localized: "Não enviar"))
        alert.addButton(withTitle: String(localized: "Enviar"))
        NSApp.activate()
        let yes = alert.runModal() == .alertSecondButtonReturn
        reports.setConsent(yes)
        sendsReports = yes
        if yes { count("launch") }
    }

    /// Shows a failure on the display for a few seconds.
    func report(_ message: String, detail: String? = nil) {
        notice = Notice(message: message, detail: detail)
        noticeToken += 1
        let token = noticeToken
        Task {
            try? await Task.sleep(for: .seconds(8))
            if token == noticeToken { notice = nil }
        }
    }

    /// Says what a folder didn't give: nothing at all, or less than it holds.
    private func report(_ found: FolderTracks) {
        if found.tracks.isEmpty {
            if let error = found.error {
                report(String(localized: "Não foi possível abrir a pasta"), detail: error.localizedDescription)
            } else {
                report(String(localized: "Sem música nesta pasta"))
            }
        } else if found.unreadable > 0 {
            report(String(localized: "Algumas pastas não abriram"), detail: found.error?.localizedDescription)
        }
    }

    /// Adds a Local source and opens it in the browser.
    func addFolder() {
        windowMode = .browser
        do {
            guard let source = try sources.addLocal() else { return }
            count("source.add.local")
            browser.open(BrowserLocation(sourceID: source.id, path: ""))
        } catch {
            report(String(localized: "Não foi possível adicionar a pasta"), detail: error.localizedDescription)
        }
    }

    /// Opens the sheet to add a Jellyfin server.
    func addJellyfin() {
        windowMode = .browser
        showingJellyfinLogin = true
    }

    /// Plays a folder (with subfolders), starting at a track if given.
    func playFolder(_ folder: BrowserLocation, startingAt track: Entry? = nil) async {
        count("play-folder")
        let found = await browser.collect(in: folder)
        report(found)
        let tracks = found.tracks
        guard !tracks.isEmpty else { return }
        player.setQueue(tracks, startAt: track.flatMap { t in tracks.firstIndex { $0.id == t.id } } ?? 0)
        // The folders give way to the queue, now holding what was chosen.
        if windowMode == .browser { windowMode = .player }
    }

    /// Appends a track or a whole folder to the end of the queue.
    func enqueue(_ entry: Entry) async {
        count("enqueue")
        switch entry.kind {
        case .track:
            player.append([entry])
        case .folder:
            let found = await browser.collect(in: BrowserLocation(sourceID: entry.sourceID, path: entry.path))
            report(found)
            player.append(found.tracks)
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
    func insertDisc(_ volume: URL, plays: Bool = true) async {
        guard !sources.discs.contains(where: { $0.volume == volume }), inserting.insert(volume).inserted else { return }
        defer { inserting.remove(volume) }
        let toc = DiscTOC(volume: volume)
        let info: DiscInfo? = if let toc { await discLookup.info(for: toc) } else { nil }
        // Ejected while MusicBrainz was answering.
        guard DiscSource.isAudioCD(volume) else { return }
        let disc = DiscSource(volume: volume, toc: toc, info: info, lookup: discLookup)
        sources.addDisc(disc)
        count("cd.inserted")
        if plays { await playFolder(BrowserLocation(sourceID: disc.id, path: disc.folder)) }
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
                do {
                    try await drive.eject(volume)
                } catch {
                    // macOS kept the disc: bring it back as a source, so it can be played or ejected again.
                    NSSound.beep()
                    await insertDisc(volume, plays: false)
                }
            }
        }
    }

    /// The CD is going away: its tracks leave the queue and it leaves the sources.
    func releaseDisc(_ volume: URL) {
        for disc in sources.discs where disc.volume == volume {
            removeSource(disc.id)
        }
    }

    /// A source goes: its tracks leave the queue (playback moves on or stops), the browser
    /// leaves it, and then it is forgotten. Every removal goes through here.
    func removeSource(_ id: UUID) {
        player.removeAll { $0.sourceID == id }
        if browser.location?.sourceID == id { browser.open(nil) }
        sources.remove(id)
    }
}
