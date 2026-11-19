#if DEBUG
import AppKit
import AVFoundation
import CoreAudio
import os

/// Step 1 of docs/plans/dac-sample-rate.md: a trial with no interface, in Debug builds only and
/// only when launched with `--match-rate`. On each new track it sets a wired output to the track's
/// sample rate when the device offers exactly that rate, and writes what happened (the status of
/// the call, how long the device took, what the player was doing) to `rate.log` in the app's
/// temporary folder. On quit it puts each device back. To be replaced by `OutputRate` in step 2.
@MainActor
final class OutputRateSpike {
    static var isRequested: Bool { CommandLine.arguments.contains("--match-rate") }

    private let player: AVPlayer
    private var itemObservation: NSKeyValueObservation?
    private var rateObservation: SampleRateObservation?
    private var quitObserver: NSObjectProtocol?
    private weak var lastItem: AVPlayerItem?
    /// The rate each device had before the first change, to restore on quit.
    private var original: [AudioObjectID: Double] = [:]
    private var askedAt: Date?
    private let log = Logger(subsystem: "pt.nunomartins.nuva", category: "output")

    init(player: AVPlayer) {
        self.player = player
        itemObservation = player.observe(\.currentItem) { [weak self] _, _ in
            Task { @MainActor in self?.itemChanged() }
        }
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restore() }
        }
        note("trial on")
    }

    private func itemChanged() {
        guard let item = player.currentItem, item !== lastItem else { return }
        lastItem = item
        let asset = item.asset
        Task {
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let description = try? await track.load(.formatDescriptions).first,
                  let rate = description.audioStreamBasicDescription?.mSampleRate, rate > 0
            else { return note("track rate unknown") }
            guard player.currentItem === item else { return }
            match(rate)
        }
    }

    private func match(_ trackRate: Double) {
        let uid = player.audioOutputDeviceUniqueID
        guard let device = uid.flatMap(CoreAudioDevice.init(uid:)) ?? CoreAudioDevice.defaultOutput()
        else { return note("no output device") }
        let offered = device.availableSampleRates()
        let now = device.currentSampleRate() ?? 0
        let summary = "track=\(trackRate) device=\(now) transport=\(device.transport) offered=\(offered)"
        guard !device.isAirPlay, !device.isBluetooth, !player.isExternalPlaybackActive
        else { return note("left alone (AirPlay or Bluetooth) \(summary)") }
        guard now != trackRate else { return note("already matches \(summary)") }
        guard offered.contains(where: { $0.contains(trackRate) })
        else { return note("rate not offered \(summary)") }

        if original[device.id] == nil { original[device.id] = now }
        let asked = Date()
        askedAt = asked
        rateObservation = device.observeSampleRate { [weak self] rate in
            MainActor.assumeIsolated { self?.changed(to: rate) }
        }
        let status = device.setSampleRate(trackRate)
        note("set status=\(status) playerStatus=\(player.timeControlStatus.rawValue) \(summary)")
    }

    private func changed(to rate: Double) {
        let ms = askedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
        note("device now \(rate) after \(ms) ms playerStatus=\(player.timeControlStatus.rawValue) time=\(player.currentTime().seconds)")
    }

    private func restore() {
        rateObservation = nil
        for (id, rate) in original {
            let status = CoreAudioDevice(id: id)?.setSampleRate(rate)
            note("restore \(rate) status=\(status.map(String.init) ?? "device gone")")
        }
        original = [:]
    }

    private func note(_ text: String) {
        log.notice("rate trial: \(text, privacy: .public)")
        let line = "\(Date()) \(text)\n"
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rate.log")
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }
}
#endif
