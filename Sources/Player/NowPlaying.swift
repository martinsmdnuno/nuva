import AppKit
import MediaPlayer

/// Media keys, Centro de Controlo e Now Playing do macOS.
@MainActor
final class NowPlaying {
    private let player: PlayerController

    init(player: PlayerController) {
        self.player = player
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

    /// Atualiza quando muda a faixa, o estado ou a duração.
    private func observe() {
        withObservationTracking {
            _ = player.currentID
            _ = player.isPlaying
            _ = player.duration
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
    }

    private func update() {
        let center = MPNowPlayingInfoCenter.default()
        guard let entry = player.current?.entry else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: entry.title,
            MPMediaItemPropertyAlbumTitle: entry.folderName,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        center.playbackState = player.isPlaying ? .playing : .paused
    }
}
