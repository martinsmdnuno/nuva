import AppKit
import ImageIO
import Observation

/// Folder artwork, downsampled and kept in memory per folder.
/// Off by default: only loads while the user has artwork turned on.
@MainActor
@Observable
final class ArtworkStore {
    /// Longest side kept in memory: enough for the display at 2x and for Now Playing.
    nonisolated static let maxPixels = 600

    /// Per folder: the image, or nil when the folder has none.
    private var images: [String: NSImage?] = [:]
    @ObservationIgnored private var loading: Set<String> = []
    @ObservationIgnored private let find: @MainActor (Entry) async -> URL?

    init(find: @escaping @MainActor (Entry) async -> URL?) {
        self.find = find
    }

    /// The artwork of the folder holding `entry`. Starts loading it the first time; the view updates when it arrives.
    func image(for entry: Entry) -> NSImage? {
        let key = Self.key(entry)
        if let cached = images[key] { return cached }
        load(entry, key: key)
        return nil
    }

    private func load(_ entry: Entry, key: String) {
        guard loading.insert(key).inserted else { return }
        Task {
            let url = await find(entry)
            let image = await Task.detached(priority: .utility) { url.flatMap(Self.downsample) }.value
            images[key] = .some(image)
            loading.remove(key)
        }
    }

    /// Decodes at most `maxPixels` on the longest side, so a 3000 px JPEG doesn't stay in memory.
    nonisolated static func downsample(_ url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private static func key(_ entry: Entry) -> String { "\(entry.sourceID.uuidString)/\(entry.parentPath)" }

    #if DEBUG
    func debugSet(_ image: NSImage?, for entry: Entry) {
        images[Self.key(entry)] = .some(image)
    }
    #endif
}
