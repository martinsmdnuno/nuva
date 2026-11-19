import AVFoundation
import CoreAudio
import Observation
import os

/// Where the sound is going: device name and actual output sample rate.
/// Over AirPlay macOS doesn't expose the stream format, so there's only a name.
@MainActor
@Observable
final class OutputRoute {
    /// Short text for the display: "→ Colunas (MacBook Neo) · 48 kHz", "→ AirPlay Sala".
    private(set) var label = ""
    /// Tooltip with the details.
    private(set) var detail = ""

    /// The label without its arrow, where an icon or the context already says "output".
    var name: String { label.replacingOccurrences(of: "→ ", with: "") }

    @ObservationIgnored private let player: AVPlayer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var playback: NSKeyValueObservation?
    @ObservationIgnored private var pollsFast = false
    @ObservationIgnored private let log = Logger(subsystem: "pt.nunomartins.nuva", category: "output")

    init(player: AVPlayer?) {
        self.player = player
        guard player != nil else { return }
        refresh()
        schedule(fast: false)
        playback = player?.observe(\.timeControlStatus) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in self?.schedule(fast: playing) }
        }
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

    private func refresh() {
        guard let player else { return }
        let external = player.isExternalPlaybackActive
        let uid = player.audioOutputDeviceUniqueID
        let device = uid.flatMap(CoreAudioDevice.init(uid:)) ?? CoreAudioDevice.defaultOutput()

        let routed = Self.routedDeviceNames()
        let newLabel: String
        let newDetail: String
        if let routed, !routed.isEmpty, !routed.contains(where: { $0 == device?.name }) {
            // The app's AirPlay picker: the destination lives in AVOutputContext, not CoreAudio.
            newLabel = "→ AirPlay \(routed.joined(separator: " + "))"
            newDetail = String(localized: "Saída AirPlay: \(routed.joined(separator: ", ")). O formato do stream não é exposto pelo macOS")
        } else if external {
            newLabel = "→ AirPlay"
            newDetail = String(localized: "Saída AirPlay. O formato do stream não é exposto pelo macOS")
        } else if let device {
            if device.isAirPlay {
                newLabel = "→ AirPlay \(device.shortName)"
                newDetail = String(localized: "Saída AirPlay: \(device.name). O formato do stream não é exposto pelo macOS")
            } else {
                let rate = device.sampleRate > 0 ? " · \(AudioFormat.kHz(device.sampleRate)) kHz" : ""
                newLabel = "→ \(device.shortName)\(rate)"
                newDetail = String(localized: "Saída: \(device.name)\(device.isBluetooth ? " (Bluetooth)" : "")\(rate)")
            }
        } else {
            newLabel = ""
            newDetail = ""
        }

        guard newLabel != label else { return }
        label = newLabel
        detail = newDetail
        #if DEBUG
        let dump = "\(Date()) label=\(newLabel) routed=\(routed ?? ["nil"]) external=\(external) uid=\(uid ?? "nil") default=\(device?.name ?? "nil")/\(device?.transport ?? "")\n"
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("output.log")
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile(); h.write(Data(dump.utf8)); try? h.close()
        } else {
            try? dump.write(to: file, atomically: true, encoding: .utf8)
        }
        #endif
        log.notice("saída: \(newLabel, privacy: .public) external=\(external) uid=\(uid ?? "nil", privacy: .public) transport=\(device?.transport ?? "?", privacy: .public)")
    }

    /// Names of the destinations of the app's shared AVOutputContext (private API on macOS,
    /// public on iOS). nil if the class or methods don't exist.
    private static func routedDeviceNames() -> [String]? {
        guard let cls = NSClassFromString("AVOutputContext") as? NSObject.Type else { return nil }
        let shared = NSSelectorFromString("defaultSharedOutputContext")
        guard cls.responds(to: shared),
              let context = cls.perform(shared)?.takeUnretainedValue() as? NSObject else { return nil }
        if context.responds(to: NSSelectorFromString("outputDevices")),
           let devices = context.value(forKey: "outputDevices") as? [NSObject] {
            return devices.compactMap { $0.value(forKey: "name") as? String }
        }
        if context.responds(to: NSSelectorFromString("deviceName")) {
            return (context.value(forKey: "deviceName") as? String).map { [$0] }
        }
        return nil
    }

    #if DEBUG
    func debugSet(_ label: String) { self.label = label }
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

    private static func name(_ object: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
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
