import Foundation
import Testing
@testable import NuVa

struct LogTests {
    @Test func writesOneLinePerFailureAndStartsAgainWhenFull() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = Log(directory: dir)

        log.error(.player, "track-skipped", SourceError.missingFolder("Rumours"), detail: "Fleetwood Mac/Rumours/01.flac")
        log.error(.jellyfin, "keychain-save-failed")
        log.flush()
        let lines = try String(contentsOf: log.file, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains(" player track-skipped SourceError.missingFolder | Fleetwood Mac/Rumours/01.flac"))
        #expect(lines[1].hasSuffix(" jellyfin keychain-save-failed"))

        // Past the size limit the file starts again and the old one is kept once.
        let filler = String(repeating: "x", count: Log.maxBytes)
        log.error(.app, "filler", detail: filler)
        log.error(.app, "after")
        log.flush()
        let fresh = try String(contentsOf: log.file, encoding: .utf8)
        #expect(fresh.split(separator: "\n").count == 1)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("nuva.old.log").path))
    }

    /// The code is what could one day leave the Mac: it never carries a folder's name.
    @Test func codesNameTheKindOfFailureOnly() {
        #expect(Log.code(for: SourceError.missingFolder("Rumours")) == "SourceError.missingFolder")
        #expect(Log.code(for: SourceError.serverUnavailable) == "SourceError.serverUnavailable")
        #expect(Log.code(for: URLError(.notConnectedToInternet)) == "NSURLErrorDomain -1009")
    }
}
