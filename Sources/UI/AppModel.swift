import Foundation
import Observation

/// Estado da app: fontes, player e durações da fila.
@MainActor
@Observable
final class AppModel {
    let sources: SourceStore
    let player: PlayerController
    let durations: TrackDurations
    let browser: Browser
    let output: OutputRoute

    enum WindowMode: String {
        /// Player com playlist, 360 × 480.
        case player
        /// Com navegador, 720 × 480.
        case browser
    }

    /// Folha "Adicionar Jellyfin" aberta.
    var showingJellyfinLogin = false

    var windowMode: WindowMode {
        didSet { defaults.set(windowMode.rawValue, forKey: "windowMode") }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var nowPlaying: NowPlaying?

    /// `systemIntegration`: media keys e Now Playing (desligado em capturas).
    init(defaults: UserDefaults = .standard, systemIntegration: Bool = false) {
        let sources = SourceStore(defaults: defaults)
        let resolve: PlayerController.Resolver = { entry in try await sources.resolve(entry) }
        self.sources = sources
        self.player = PlayerController(resolve: resolve)
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

    /// Rótulo da fonte da faixa atual ("Local", "Servidor").
    var currentSourceLabel: String {
        guard let entry = player.current?.entry else { return "" }
        return sources.source(entry.sourceID)?.kind.label ?? ""
    }

    /// Play sem fila abre o navegador de pastas.
    func playOrBrowse() {
        if player.queue.isEmpty {
            windowMode = .browser
        } else {
            player.togglePlayPause()
        }
    }

    /// Adiciona uma fonte Local e abre-a no navegador.
    func addFolder() {
        windowMode = .browser
        guard let source = sources.addLocal() else { return }
        browser.open(BrowserLocation(sourceID: source.id, path: ""))
    }

    /// Abre a folha para juntar um servidor Jellyfin.
    func addJellyfin() {
        windowMode = .browser
        showingJellyfinLogin = true
    }

    /// Toca uma pasta (com subpastas), a começar numa faixa se indicada.
    func playFolder(_ folder: BrowserLocation, startingAt track: Entry? = nil) async {
        let tracks = await browser.tracks(in: folder)
        guard !tracks.isEmpty else { return }
        player.setQueue(tracks, startAt: track.flatMap { t in tracks.firstIndex { $0.id == t.id } } ?? 0)
    }

    /// Junta ao fim da fila uma faixa ou uma pasta inteira.
    func enqueue(_ entry: Entry) async {
        switch entry.kind {
        case .track:
            player.append([entry])
        case .folder:
            player.append(await browser.tracks(in: BrowserLocation(sourceID: entry.sourceID, path: entry.path)))
        }
    }
}
