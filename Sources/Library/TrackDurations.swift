import AVFoundation
import Observation

/// Durações das faixas para a lista, carregadas a pedido e guardadas em memória.
@MainActor
@Observable
final class TrackDurations {
    private(set) var values: [Entry.ID: Double] = [:]
    @ObservationIgnored private var pending: Set<Entry.ID> = []
    @ObservationIgnored private let resolve: PlayerController.Resolver

    init(resolve: @escaping PlayerController.Resolver) {
        self.resolve = resolve
    }

    func load(_ entry: Entry) async {
        guard values[entry.id] == nil, !pending.contains(entry.id) else { return }
        pending.insert(entry.id)
        defer { pending.remove(entry.id) }
        guard let url = try? await resolve(entry),
              let duration = try? await AVURLAsset(url: url).load(.duration),
              duration.seconds.isFinite else { return }
        values[entry.id] = duration.seconds
    }

    #if DEBUG
    func debugSet(_ entry: Entry, _ seconds: Double) { values[entry.id] = seconds }
    #endif
}
