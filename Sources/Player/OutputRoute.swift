import AVFoundation
import CoreAudio
import Observation
import os

/// Para onde está a sair o som: nome do dispositivo e taxa real da saída.
/// Por AirPlay o macOS não expõe o formato do stream, por isso só há nome.
@MainActor
@Observable
final class OutputRoute {
    /// Texto curto para o display: "→ Colunas (MacBook Neo) · 48 kHz", "→ AirPlay Sala".
    private(set) var label = ""
    /// Tooltip com o detalhe.
    private(set) var detail = ""

    @ObservationIgnored private let player: AVPlayer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let log = Logger(subsystem: "pt.nunomartins.nuva", category: "output")

    init(player: AVPlayer?) {
        self.player = player
        guard player != nil else { return }
        refresh()
        // Barato (algumas leituras CoreAudio); apanha também as mudanças do seletor AirPlay.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
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
            // Seletor AirPlay da app: o destino vive no AVOutputContext, não no CoreAudio.
            newLabel = "→ AirPlay \(routed.joined(separator: " + "))"
            newDetail = "Saída AirPlay: \(routed.joined(separator: ", ")). O formato do stream não é exposto pelo macOS"
        } else if external {
            newLabel = "→ AirPlay"
            newDetail = "Saída AirPlay. O formato do stream não é exposto pelo macOS"
        } else if let device {
            if device.isAirPlay {
                newLabel = "→ AirPlay \(device.shortName)"
                newDetail = "Saída AirPlay: \(device.name). O formato do stream não é exposto pelo macOS"
            } else {
                let rate = device.sampleRate > 0 ? " · \(AudioFormat.kHz(device.sampleRate)) kHz" : ""
                newLabel = "→ \(device.shortName)\(rate)"
                newDetail = "Saída: \(device.name)\(device.isBluetooth ? " (Bluetooth)" : "")\(rate)"
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

    /// Nomes dos destinos do AVOutputContext partilhado da app (API privada no macOS,
    /// pública no iOS). nil se a classe ou os métodos não existirem.
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

/// Leitura mínima de um dispositivo de saída CoreAudio.
struct CoreAudioDevice {
    let id: AudioObjectID
    let name: String
    let sampleRate: Double
    let transport: String

    /// Sem o parêntese final: "Colunas (MacBook Neo)" → "Colunas".
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
