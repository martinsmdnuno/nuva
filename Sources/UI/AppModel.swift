import Foundation
import Observation

/// Estado da app: fontes, player e durações da fila.
@MainActor
@Observable
final class AppModel {
    let sources: SourceStore
    let player: PlayerController
    let durations: TrackDurations

    init(defaults: UserDefaults = .standard) {
        let sources = SourceStore(defaults: defaults)
        let resolve: PlayerController.Resolver = { entry in try await sources.resolve(entry) }
        self.sources = sources
        self.player = PlayerController(resolve: resolve)
        self.durations = TrackDurations(resolve: resolve)
    }

    /// Rótulo da fonte da faixa atual ("Local", "Servidor").
    var currentSourceLabel: String {
        guard let entry = player.current?.entry else { return "" }
        return sources.source(entry.sourceID)?.kind.label ?? ""
    }

    /// Play sem fila: por agora pede uma fonte se não houver nenhuma.
    func playOrBrowse() {
        if player.queue.isEmpty {
            if sources.sources.isEmpty { sources.addLocal() }
        } else {
            player.togglePlayPause()
        }
    }
}
