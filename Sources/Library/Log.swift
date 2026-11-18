import AppKit
import Foundation
import os

/// What went wrong, written down on this Mac: `Application Support/NuVa/Logs/nuva.log`.
/// Nothing leaves the Mac from here. Each line has a `code` that names the kind of failure
/// without naming anything of the user's (no folder, file or server names), and a `detail`
/// that may name them and is for the person reading the file on their own Mac.
final class Log: Sendable {
    enum Area: String, Sendable {
        case player, source, jellyfin, artwork, disc, app
    }

    static let shared = Log(directory: URL.applicationSupportDirectory
        .appendingPathComponent("NuVa/Logs", isDirectory: true), reports: .shared)

    /// The file is started again past this size; the one before it is kept as `nuva.old.log`.
    static let maxBytes = 256 * 1024

    let file: URL
    private let old: URL
    private let queue = DispatchQueue(label: "pt.nunomartins.nuva.log", qos: .utility)
    private let system = Logger(subsystem: "pt.nunomartins.nuva", category: "errors")

    /// Counts each failure's kind (its code, never its detail) for the user who agreed to report them.
    private let reports: Reports?

    init(directory: URL, reports: Reports? = nil) {
        self.reports = reports
        file = directory.appendingPathComponent("nuva.log")
        old = directory.appendingPathComponent("nuva.old.log")
    }

    /// Writes one failure. `code` is a fixed word for the kind of failure ("track-skipped").
    func error(_ area: Area, _ code: String, _ error: Error? = nil, detail: String? = nil) {
        let reason = error.map(Self.code(for:))
        let text = [detail, error?.localizedDescription].compactMap { $0 }.joined(separator: ": ")
        let kind = [code, reason].compactMap { $0 }.joined(separator: " ")
        let line = Self.line(area: area, code: kind, detail: text)
        reports?.failure(area: area.rawValue, code: kind)
        system.error("\(line, privacy: .private)")
        queue.async { [file, old] in Self.append(line, to: file, old: old) }
    }

    /// Waits for the lines written so far (tests, and before showing the file).
    func flush() {
        queue.sync {}
    }

    /// Shows the file in the Finder (NuVa ▸ Show Error Log), empty if nothing has gone wrong yet.
    @MainActor
    func reveal() {
        flush()
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: file.path) { fm.createFile(atPath: file.path, contents: nil) }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    /// The kind of an error without its words: "SourceError.serverUnavailable", "NSURLErrorDomain -1009".
    static func code(for error: Error) -> String {
        if let error = error as? SourceError {
            // The case's name only: its associated value is a folder name.
            let name = String(describing: error)
            return "SourceError." + (name.split(separator: "(").first.map(String.init) ?? name)
        }
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }

    static func line(area: Area, code: String, detail: String, at date: Date = Date()) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let stamp = date.formatted(.iso8601)
        // One failure, one line.
        let flat = detail.replacingOccurrences(of: "\n", with: " ")
        return "\(stamp) \(version) \(area.rawValue) \(code)" + (flat.isEmpty ? "" : " | \(flat)")
    }

    private static func append(_ line: String, to file: URL, old: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = try? fm.attributesOfItem(atPath: file.path)[.size] as? Int, size > maxBytes {
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: file, to: old)
        }
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }
}
