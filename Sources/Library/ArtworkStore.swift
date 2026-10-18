import AppKit
import ImageIO
import Observation

/// Album artwork, downsampled and kept in memory per folder. Off by default: only loads
/// while the user has artwork turned on. Where it comes from is `ArtworkResolver`'s business.
@MainActor
@Observable
final class ArtworkStore {
    /// Longest side kept in memory: enough for the display at 2x and for Now Playing.
    nonisolated static let maxPixels = 600

    struct Loaded {
        let image: NSImage
        let origin: ArtworkOrigin
    }

    /// Per folder: the artwork, or nil once it is known there is none.
    private var images: [String: Loaded?] = [:]
    @ObservationIgnored private var loading: Set<String> = []
    @ObservationIgnored private let find: @MainActor (Entry) async -> ResolvedArtwork?

    init(find: @escaping @MainActor (Entry) async -> ResolvedArtwork?) {
        self.find = find
    }

    /// The artwork of the folder holding `entry`. Starts loading it the first time; the view updates when it arrives.
    func artwork(for entry: Entry) -> Loaded? {
        let key = Self.key(entry)
        if let cached = images[key] { return cached }
        load(entry, key: key)
        return nil
    }

    /// Whether the lookup for `entry`'s folder has finished (with or without artwork).
    func isResolved(_ entry: Entry) -> Bool { images[Self.key(entry)] != nil }

    /// Forgets the folder's artwork, so it is looked up again (after the user fixes it).
    func invalidate(_ entry: Entry) {
        images[Self.key(entry)] = nil
        load(entry, key: Self.key(entry))
    }

    private func load(_ entry: Entry, key: String) {
        guard loading.insert(key).inserted else { return }
        Task {
            let found = await find(entry)
            let image = await Task.detached(priority: .utility) { found.flatMap { Self.downsample($0.url) } }.value
            if let image, let found {
                images[key] = .some(Loaded(image: image, origin: found.origin))
            } else {
                images[key] = .some(nil)
            }
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

    private static func key(_ entry: Entry) -> String { ArtworkResolver.folderKey(entry) }

    /// JPEG for the cache, from any image file the user picks.
    nonisolated static func jpeg(from url: URL) -> Data? {
        guard let image = downsample(url), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    #if DEBUG
    func debugSet(_ image: NSImage?, origin: ArtworkOrigin = .folder, for entry: Entry) {
        images[Self.key(entry)] = .some(image.map { Loaded(image: $0, origin: origin) })
    }
    #endif
}
