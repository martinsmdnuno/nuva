import AudioToolbox
import Foundation

/// Formato e taxa para o display: "FLAC 24/96", "MP3 44.1".
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

        let rate = kHz(asbd.mSampleRate)
        // Profundidades negativas indicam formato com perdas (MP3, AAC).
        return depth > 0 ? "\(ext) \(depth)/\(rate)" : "\(ext) \(rate)"
    }

    /// 44100 → "44.1", 48000 → "48".
    static func kHz(_ rate: Double) -> String {
        let k = rate / 1000
        return k.rounded() == k ? String(Int(k)) : String(format: "%.1f", k)
    }
}
