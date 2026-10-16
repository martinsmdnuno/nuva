import AudioToolbox
import Foundation

/// Formato, taxa e bitrate para o display: "FLAC 24/96 · 4608 kbps", "MP3 44.1 · 320 kbps".
enum AudioFormat {
    static func label(for url: URL) -> String {
        let ext = url.pathExtension.uppercased()
        guard url.isFileURL else { return ext }
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else { return ext }
        defer { AudioFileClose(file) }

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &asbd) == noErr else { return ext }

        var depth: Int32 = 0
        size = UInt32(MemoryLayout<Int32>.size)
        AudioFileGetProperty(file, kAudioFilePropertySourceBitDepth, &size, &depth)
        if depth == 0 { depth = Int32(asbd.mBitsPerChannel) }

        // Bitrate médio do ficheiro (FLAC e MP3 VBR variam ao longo da faixa).
        var bitRate: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        AudioFileGetProperty(file, kAudioFilePropertyBitRate, &size, &bitRate)

        let rate = kHz(asbd.mSampleRate)
        // Profundidades negativas indicam formato com perdas (MP3, AAC).
        let base = depth > 0 ? "\(ext) \(depth)/\(rate)" : "\(ext) \(rate)"
        return bitRate > 0 ? "\(base) · \(kbps(bitRate)) kbps" : base
    }

    /// 1668595 → "1669".
    static func kbps(_ bitsPerSecond: UInt32) -> String {
        String(Int((Double(bitsPerSecond) / 1000).rounded()))
    }

    /// 44100 → "44.1", 48000 → "48".
    static func kHz(_ rate: Double) -> String {
        let k = rate / 1000
        return k.rounded() == k ? String(Int(k)) : String(format: "%.1f", k)
    }
}
