import Foundation
import Observation

/// Remembers the player between launches: volume, shuffle, repeat, the queue, its track and
/// where it was. NuVa reopens on that track, stopped; play picks it up there.
@MainActor
final class PlayerMemory {
    private let player: PlayerController
    private let defaults: UserDefaults
    private var savedQueue: [QueueItem.ID] = []
    private var savedPosition: Double = -1
    private var savedPlaying = false
    private var savedCurrent: QueueItem.ID?
    private var terminationObserver: NSObjectProtocol?

    /// The position is written this often while playing, and whenever playback stops or the track changes.
    static let positionInterval: Double = 5

    private enum Key {
        static let volume = "player.volume"
        static let shuffle = "player.shuffle"
        static let repeatMode = "player.repeat"
        static let queue = "player.queue"
        static let current = "player.current"
        static let position = "player.position"
        static let duration = "player.duration"
    }

    /// `keeps`: whether a source is still one of the app's (a removed source's tracks don't come
    /// back, nor a CD's: it left with the disc).
    init(player: PlayerController, defaults: UserDefaults, keeps: (UUID) -> Bool) {
        self.player = player
        self.defaults = defaults
        restore(keeps: keeps)
        observe()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("NSApplicationWillTerminateNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.save(force: true) }
        }
    }

    private func restore(keeps: (UUID) -> Bool) {
        if let volume = defaults.object(forKey: Key.volume) as? Float { player.volume = volume }
        player.shuffle = defaults.bool(forKey: Key.shuffle)
        player.repeatMode = RepeatMode(rawValue: defaults.string(forKey: Key.repeatMode) ?? "") ?? .off
        guard let data = defaults.data(forKey: Key.queue),
              let saved = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        let index = defaults.object(forKey: Key.current) as? Int
        let currentEntry = index.flatMap { saved.indices.contains($0) ? saved[$0] : nil }
        let entries = saved.filter { keeps($0.sourceID) }
        // The track it was on, if it is still there; its place among the ones that stayed.
        var current: Int?
        if let index, let currentEntry, keeps(currentEntry.sourceID) {
            current = saved[..<index].count { keeps($0.sourceID) }
        }
        player.restore(
            entries, current: current,
            position: current == nil ? 0 : defaults.double(forKey: Key.position),
            duration: current == nil ? 0 : defaults.double(forKey: Key.duration))
    }

    private func observe() {
        withObservationTracking {
            _ = player.queue
            _ = player.currentID
            _ = player.isPlaying
            _ = player.currentTime
            _ = player.volume
            _ = player.shuffle
            _ = player.repeatMode
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.save()
                self?.observe()
            }
        }
    }

    /// Writes what changed. The queue is only encoded when its entries change, the position at intervals.
    func save(force: Bool = false) {
        defaults.set(player.volume, forKey: Key.volume)
        defaults.set(player.shuffle, forKey: Key.shuffle)
        defaults.set(player.repeatMode.rawValue, forKey: Key.repeatMode)

        let ids = player.queue.map(\.id)
        if ids != savedQueue {
            savedQueue = ids
            if let data = try? JSONEncoder().encode(player.queue.map(\.entry)) {
                defaults.set(data, forKey: Key.queue)
            }
        }
        let moved = abs(player.currentTime - savedPosition) >= Self.positionInterval
        guard force || moved || player.currentID != savedCurrent || player.isPlaying != savedPlaying else { return }
        savedCurrent = player.currentID
        savedPlaying = player.isPlaying
        savedPosition = player.currentTime
        if let index = player.queue.firstIndex(where: { $0.id == player.currentID }) {
            defaults.set(index, forKey: Key.current)
        } else {
            defaults.removeObject(forKey: Key.current)
        }
        defaults.set(player.currentTime, forKey: Key.position)
        defaults.set(player.duration, forKey: Key.duration)
    }
}
