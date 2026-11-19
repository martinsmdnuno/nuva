import AVFoundation
import CoreAudio
import Observation
import os

/// Where the sound is going: device name and actual output sample rate, and the track's own rate
/// beside it when macOS is converting one into the other ("96 → 48 kHz").
/// Over AirPlay macOS doesn't expose the stream format, so there's only a name.
@MainActor
@Observable
final class OutputRoute {
    /// Short text for the display: "→ Colunas · 48 kHz", "→ DAC · 96 → 48 kHz", "→ AirPlay Sala".
    var label: String {
        #if DEBUG
        if let debugLabel { return debugLabel }
        #endif
        switch route {
        case .none: return ""
        case .airPlay(let label, _): return label
        case .device(_, let short, _, let rate):
            let text = Self.rateText(device: rate, track: trackRate())
            return text.isEmpty ? "→ \(short)" : "→ \(short) · \(text)"
        }
    }

    /// Tooltip with the details.
    var detail: String {
        switch route {
        case .none: return ""
        case .airPlay(_, let detail): return detail
        case .device(let name, _, let bluetooth, let rate):
            let own = rate > 0 ? " · \(AudioFormat.kHz(rate)) kHz" : ""
            let output = String(localized: "Saída: \(name)\(bluetooth ? " (Bluetooth)" : "")\(own)")
            guard rate > 0, let track = trackRate() else { return output }
            let conversion = Self.converts(device: rate, track: track)
                ? String(localized: "O macOS converte a faixa de \(AudioFormat.kHz(track)) para \(AudioFormat.kHz(rate)) kHz")
                : String(localized: "A saída está na frequência da faixa")
            return "\(output)\n\(conversion)"
        }
    }

    /// The label without its arrow, where an icon or the context already says "output".
    var name: String { label.replacingOccurrences(of: "→ ", with: "") }

    /// Called when the sound moves to another Core Audio device, or to or from AirPlay.
    @ObservationIgnored var onDeviceChange: (() -> Void)?

    private enum Route: Equatable {
        case none
        case airPlay(label: String, detail: String)
        case device(name: String, short: String, bluetooth: Bool, rate: Double)
    }

    private var route = Route.none
    #if DEBUG
    private var debugLabel: String?
    #endif

    @ObservationIgnored private let player: AVPlayer?
    /// The playing track's sample rate, read each time the text is asked for.
    @ObservationIgnored private let trackRate: () -> Double?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var playback: NSKeyValueObservation?
    @ObservationIgnored private var pollsFast = false
    @ObservationIgnored private var localUID: String?
    /// Tells of a change of the local device's rate at once, whoever made it.
    @ObservationIgnored private var rateObservation: SampleRateObservation?
    @ObservationIgnored private let log = Logger(subsystem: "pt.nunomartins.nuva", category: "output")

    init(player: AVPlayer?, trackRate: @escaping () -> Double? = { nil }) {
        self.player = player
        self.trackRate = trackRate
        guard player != nil else { return }
        refresh()
        schedule(fast: false)
        playback = player?.observe(\.timeControlStatus) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in self?.schedule(fast: playing) }
        }
    }

    /// The device's rate, with the track's before it when they differ: "48 kHz", "96 → 48 kHz".
    nonisolated static func rateText(device: Double, track: Double?) -> String {
        guard device > 0 else { return "" }
        guard let track, converts(device: device, track: track) else { return "\(AudioFormat.kHz(device)) kHz" }
        return "\(AudioFormat.kHz(track)) → \(AudioFormat.kHz(device)) kHz"
    }

    /// Whether macOS resamples a track of this rate for a device at that one.
    nonisolated static func converts(device: Double, track: Double) -> Bool {
        device > 0 && track > 0 && abs(device - track) >= 0.5
    }

    /// Polls the route (a few CoreAudio reads; also catches the AirPlay picker): every second while
    /// music plays, every 10 s otherwise, with a tolerance so macOS can group the wake-ups.
    private func schedule(fast: Bool) {
        guard timer == nil || fast != pollsFast else { return }
        pollsFast = fast
        timer?.invalidate()
        refresh()
        let timer = Timer(timeInterval: fast ? 1 : 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = fast ? 0.25 : 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The Core Audio device the sound really goes to: nil over AirPlay (the app's picker or the
    /// system's) and when there is no player (tests, snapshots).
    func localDevice() -> CoreAudioDevice? {
        guard let player, !player.isExternalPlaybackActive, let device = device(of: player), !device.isAirPlay
        else { return nil }
        if let routed = Self.routedDeviceNames(of: player), !routed.isEmpty, !routed.contains(device.name) { return nil }
        return device
    }

    private func device(of player: AVPlayer) -> CoreAudioDevice? {
        player.audioOutputDeviceUniqueID.flatMap(CoreAudioDevice.init(uid:)) ?? CoreAudioDevice.defaultOutput()
    }

    private func refresh() {
        guard let player else { return }
        let external = player.isExternalPlaybackActive
        let device = device(of: player)
        let routed = Self.routedDeviceNames(of: player)

        let new: Route
        var local: CoreAudioDevice?
        if let routed, !routed.isEmpty, !routed.contains(where: { $0 == device?.name }) {
            // The app's AirPlay picker: the destination lives in AVOutputContext, not CoreAudio.
            new = .airPlay(
                label: "→ AirPlay \(routed.joined(separator: " + "))",
                detail: String(localized: "Saída AirPlay: \(routed.joined(separator: ", ")). O formato do stream não é exposto pelo macOS"))
        } else if external {
            new = .airPlay(label: "→ AirPlay", detail: String(localized: "Saída AirPlay. O formato do stream não é exposto pelo macOS"))
        } else if let device {
            if device.isAirPlay {
                new = .airPlay(
                    label: "→ AirPlay \(device.shortName)",
                    detail: String(localized: "Saída AirPlay: \(device.name). O formato do stream não é exposto pelo macOS"))
            } else {
                new = .device(name: device.name, short: device.shortName, bluetooth: device.isBluetooth, rate: device.sampleRate)
                local = device
            }
        } else {
            new = .none
        }

        let uid = local?.uid
        if uid != localUID {
            localUID = uid
            rateObservation = local?.observeSampleRate { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            onDeviceChange?()
        }

        guard new != route else { return }
        route = new
        #if DEBUG
        let dump = "\(Date()) label=\(label) routed=\(routed ?? ["nil"]) external=\(external) uid=\(player.audioOutputDeviceUniqueID ?? "nil") default=\(device?.name ?? "nil")/\(device?.transport ?? "")\n"
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("output.log")
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile(); h.write(Data(dump.utf8)); try? h.close()
        } else {
            try? dump.write(to: file, atomically: true, encoding: .utf8)
        }
        #endif
        log.notice("saída: \(self.label, privacy: .public) external=\(external) uid=\(player.audioOutputDeviceUniqueID ?? "nil", privacy: .public) transport=\(device?.transport ?? "?", privacy: .public)")
    }

    /// Names of the AirPlay destinations the player is sending to, from its AVOutputContext
    /// (private API on macOS, public on iOS); empty when the sound stays on this Mac, nil if the
    /// classes or methods don't exist. The route picker sets the player's own context
    /// (`AVPlayer.outputContext`): seen on macOS 27, where the app's shared context stays empty
    /// with a WiiM chosen. The shared one is still asked, for the systems where it is the one used.
    private static func routedDeviceNames(of player: AVPlayer) -> [String]? {
        var contexts: [NSObject] = []
        if player.responds(to: NSSelectorFromString("outputContext")),
           let own = player.value(forKey: "outputContext") as? NSObject {
            contexts.append(own)
        }
        let shared = NSSelectorFromString("defaultSharedOutputContext")
        if let cls = NSClassFromString("AVOutputContext") as? NSObject.Type, cls.responds(to: shared),
           let context = cls.perform(shared)?.takeUnretainedValue() as? NSObject {
            contexts.append(context)
        }
        guard !contexts.isEmpty else { return nil }
        return contexts.lazy.compactMap(names(in:)).first { !$0.isEmpty } ?? []
    }

    private static func names(in context: NSObject) -> [String]? {
        if context.responds(to: NSSelectorFromString("outputDevices")),
           let devices = context.value(forKey: "outputDevices") as? [NSObject] {
            return devices.compactMap { $0.value(forKey: "name") as? String }
        }
        if context.responds(to: NSSelectorFromString("deviceName")) {
            return (context.value(forKey: "deviceName") as? String).map { [$0] } ?? []
        }
        return nil
    }

    #if DEBUG
    func debugSet(_ label: String) { debugLabel = label }
    #endif
}

/// Minimal reading of a CoreAudio output device.
struct CoreAudioDevice {
    let id: AudioObjectID
    let name: String
    let sampleRate: Double
    let transport: String

    /// Without the trailing parenthesis: "Colunas (MacBook Neo)" → "Colunas".
    var shortName: String {
        let short = name.replacingOccurrences(of: #"\s*\([^)]*\)$"#, with: "", options: .regularExpression)
        return short.isEmpty ? name : short
    }

    /// Stable across replugging, unlike `id`.
    var uid: String? { Self.string(id, kAudioDevicePropertyDeviceUID) }

    var isAirPlay: Bool { transport == "airp" }
    var isBluetooth: Bool { transport == "blue" || transport == "blea" }

    static func defaultOutput() -> CoreAudioDevice? {
        var id = AudioObjectID(0)
        guard get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, &id), id != 0
        else { return nil }
        return CoreAudioDevice(id: id)
    }

    init?(uid: String) {
        var id = AudioObjectID(0)
        var cfUID = uid as CFString
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { ptr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &addr,
                UInt32(MemoryLayout<CFString>.size), ptr, &size, &id)
        }
        guard status == noErr, id != 0 else { return nil }
        self.init(id: id)
    }

    init?(id: AudioObjectID) {
        guard let name = Self.name(id) else { return nil }
        var rate = Float64(0)
        _ = Self.get(id, kAudioDevicePropertyNominalSampleRate, &rate)
        var transport = UInt32(0)
        _ = Self.get(id, kAudioDevicePropertyTransportType, &transport)
        self.id = id
        self.name = name
        self.sampleRate = rate
        self.transport = String(bytes: [24, 16, 8, 0].map { UInt8((transport >> $0) & 0xff) }, encoding: .ascii) ?? ""
    }

    private static func name(_ object: AudioObjectID) -> String? { string(object, kAudioObjectPropertyName) }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func get<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr
    }
}

// MARK: - Sample rate

extension CoreAudioDevice {
    /// The rates the device offers, as Core Audio gives them: ranges (a single rate is a range of one).
    func availableSampleRates() -> [ClosedRange<Double>] {
        var addr = Self.rateAddress(kAudioDevicePropertyAvailableNominalSampleRates)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let stride = MemoryLayout<AudioValueRange>.stride
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / stride)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &ranges) == noErr else { return [] }
        return ranges.prefix(Int(size) / stride)
            .filter { $0.mMinimum > 0 && $0.mMinimum <= $0.mMaximum }
            .map { $0.mMinimum...$0.mMaximum }
    }

    /// The device's rate now (`sampleRate` is the rate when this value was made).
    func currentSampleRate() -> Double? {
        var rate = Float64(0)
        return Self.get(id, kAudioDevicePropertyNominalSampleRate, &rate) && rate > 0 ? rate : nil
    }

    /// Asks the device for a rate, as Audio MIDI Setup does. The change is not immediate: the
    /// device reports it later, through `observeSampleRate`.
    @discardableResult
    func setSampleRate(_ rate: Double) -> OSStatus {
        var addr = Self.rateAddress(kAudioDevicePropertyNominalSampleRate)
        var value = Float64(rate)
        return AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &value)
    }

    /// Calls `handler` (on the main queue) with the new rate each time the device changes it,
    /// whoever asked. Lasts as long as the returned object.
    func observeSampleRate(_ handler: @escaping @Sendable (Double) -> Void) -> SampleRateObservation {
        SampleRateObservation(device: id, handler: handler)
    }

    fileprivate static func rateAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}

/// A Core Audio listener on one device's sample rate, removed when this object goes away.
final class SampleRateObservation: @unchecked Sendable {
    private let device: AudioObjectID
    private let block: AudioObjectPropertyListenerBlock

    fileprivate init(device: AudioObjectID, handler: @escaping @Sendable (Double) -> Void) {
        self.device = device
        block = { _, _ in
            if let rate = CoreAudioDevice(id: device)?.currentSampleRate() { handler(rate) }
        }
        var addr = CoreAudioDevice.rateAddress(kAudioDevicePropertyNominalSampleRate)
        AudioObjectAddPropertyListenerBlock(device, &addr, .main, block)
    }

    deinit {
        var addr = CoreAudioDevice.rateAddress(kAudioDevicePropertyNominalSampleRate)
        AudioObjectRemovePropertyListenerBlock(device, &addr, .main, block)
    }
}
