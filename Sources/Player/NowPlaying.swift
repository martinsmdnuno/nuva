import AppKit
import MediaPlayer

/// Media keys, Control Centre and macOS Now Playing.
@MainActor
final class NowPlaying {
    private let player: PlayerController
    /// The folder's artwork when the user turned artwork on; nil otherwise.
    private let folderArtwork: @MainActor () -> NSImage?
    /// Never from tags (folders, not metadata): without folder artwork, the NuVa folder.
    private let defaultArtwork = MPMediaItemArtwork(boundsSize: CGSize(width: 1024, height: 1024)) { _ in
        NSImage(named: "NowPlayingArtwork") ?? NSImage()
    }

    init(player: PlayerController, artwork: @escaping @MainActor () -> NSImage?) {
        self.player = player
        self.folderArtwork = artwork
        registerCommands()
        player.onSeek = { [weak self] in self?.update() }
        observe()
    }

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.player.isPlaying == false { self?.player.togglePlayPause() } }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.togglePlayPause() }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.stop() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.player.seek(to: position) }
            return .success
        }
    }

    /// Updates when the track, state or duration changes.
    private func observe() {
        withObservationTracking {
            _ = player.currentID
            _ = player.isPlaying
            _ = player.duration
            _ = folderArtwork()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
    }

    /// MediaPlayer asks for the image on its own queue: the closure must not be main-actor isolated
    /// (Swift 6 traps when it runs elsewhere), so it is built outside the class's isolation.
    nonisolated static func artwork(for image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }

    private func update() {
        let center = MPNowPlayingInfoCenter.default()
        guard let entry = player.current?.entry else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        let artwork = folderArtwork().map(Self.artwork(for:)) ?? defaultArtwork
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: entry.title,
            MPMediaItemPropertyAlbumTitle: entry.folderName,
            MPMediaItemPropertyArtwork: artwork,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        center.playbackState = player.isPlaying ? .playing : .paused
    }
}
