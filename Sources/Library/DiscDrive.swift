import AppKit

/// Tells the app when an audio CD goes in or out, and ejects it.
@MainActor
final class DiscDrive {
    /// An audio CD was mounted (also called for discs already in the drive at launch).
    var onInsert: ((URL) -> Void)?
    /// An audio CD is about to go away, or already went: let go of its files.
    var onRemove: ((URL) -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let url = Self.volume(note), DiscSource.isAudioCD(url) else { return }
            MainActor.assumeIsolated { self?.onInsert?(url) }
        })
        // Not checked for cddafs: once unmounted, the volume can't be asked any more.
        for name in [NSWorkspace.willUnmountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let url = Self.volume(note) else { return }
                MainActor.assumeIsolated { self?.onRemove?(url) }
            })
        }
        let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        for url in mounted where DiscSource.isAudioCD(url) {
            onInsert?(url)
        }
    }

    /// Unmounts and ejects the disc. Throws when macOS refuses (a file still in use).
    func eject(_ volume: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
        }.value
    }

    private nonisolated static func volume(_ note: Notification) -> URL? {
        note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
    }
}
