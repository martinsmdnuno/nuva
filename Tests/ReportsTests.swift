import Foundation
import Testing
@testable import NuVa

/// Stands in for the author's server: remembers what was posted and answers with `status`.
final class FakeReportsServer: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var posts: [(path: String, body: [String: Any])] = []
    nonisolated(unsafe) static var status = 204

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        // URLSession hands the body to a URLProtocol as a stream.
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
        }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        Self.posts.append((request.url!.path, body))
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized)
struct ReportsTests {
    private func reports() -> (Reports, UserDefaults, String) {
        FakeReportsServer.posts = []
        FakeReportsServer.status = 204
        let suite = "reports-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeReportsServer.self]
        return (Reports(defaults: defaults, session: URLSession(configuration: config)), defaults, suite)
    }

    @Test func nothingIsCountedOrSentWithoutAYes() async {
        let (reports, defaults, suite) = reports()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Not asked yet.
        reports.count("play-folder")
        reports.failure(area: "player", code: "track-skipped")
        reports.crash(signature: "crash sig11", report: "stack")
        #expect(await reports.send(settings: ["state.skin.rave"]) == false)

        // Asked, and the answer was no.
        reports.setConsent(false)
        reports.count("play-folder")
        #expect(await reports.sendIfDue() == false)
        #expect(FakeReportsServer.posts.isEmpty)
        #expect(defaults.dictionary(forKey: "reports.usage") == nil)
    }

    @Test func sendsCountsOnceADayAndForgetsWhatWasSent() async throws {
        let (reports, defaults, suite) = reports()
        defer { defaults.removePersistentDomain(forName: suite) }
        reports.setConsent(true)
        reports.count("play-folder")
        reports.count("play-folder")
        reports.failure(area: "player", code: "track-skipped NSURLErrorDomain -1009")
        reports.crash(signature: "crash exc1 sig11 NuVa+74565", report: "stack")

        let now = Date()
        #expect(await reports.sendIfDue(settings: ["state.skin.rave"], now: now))
        #expect(FakeReportsServer.posts.map(\.path) == ["/api/usage", "/api/errors"])
        let usage = FakeReportsServer.posts[0].body
        #expect(usage["app"] as? String == "mac")
        #expect(usage["events"] as? [String: Int] == ["play-folder": 2, "state.skin.rave": 1])
        // Nothing that could tell one Mac from another.
        #expect(Set(usage.keys) == ["app", "version", "os", "events"])
        let errors = FakeReportsServer.posts[1].body
        let failure = try #require((errors["errors"] as? [[String: Any]])?.first)
        #expect(failure["area"] as? String == "player")
        #expect(failure["code"] as? String == "track-skipped NSURLErrorDomain -1009")
        #expect(failure["count"] as? Int == 1)
        #expect((errors["crashes"] as? [[String: String]])?.first?["signature"] == "crash exc1 sig11 NuVa+74565")
        #expect(Set(errors.keys) == ["app", "version", "os", "errors", "crashes"])

        // Not again within the day; and what was sent is gone, also for the next launch.
        reports.count("enqueue")
        #expect(await reports.sendIfDue(now: now.addingTimeInterval(3600)) == false)
        #expect(defaults.dictionary(forKey: "reports.usage") as? [String: Int] == ["enqueue": 1])
        #expect(await reports.sendIfDue(now: now.addingTimeInterval(Reports.interval + 1)))
        #expect(FakeReportsServer.posts.last?.body["events"] as? [String: Int] == ["enqueue": 1])
    }

    @Test func countsAreKeptWhenTheServerIsDown() async {
        let (reports, defaults, suite) = reports()
        defer { defaults.removePersistentDomain(forName: suite) }
        reports.setConsent(true)
        reports.count("play-folder")

        FakeReportsServer.status = 503
        #expect(await reports.send() == false)
        FakeReportsServer.status = 204
        #expect(await reports.sendIfDue())
        #expect(FakeReportsServer.posts.last?.body["events"] as? [String: Int] == ["play-folder": 1])
    }

    @Test func aNoForgetsWhatWasCounted() async {
        let (reports, defaults, suite) = reports()
        defer { defaults.removePersistentDomain(forName: suite) }
        reports.setConsent(true)
        reports.count("play-folder")
        reports.setConsent(false)
        #expect(defaults.dictionary(forKey: "reports.usage") == nil)
        reports.setConsent(true)
        #expect(await reports.send() == true)
        #expect(FakeReportsServer.posts.isEmpty)
    }

    /// Whatever reaches these, a name or a path can't get through to the server.
    @Test func namesAreReducedToWhatTheServerTakes() {
        #expect(Reports.eventName("played.local.FLAC") == "played.local.flac")
        #expect(Reports.eventName("Fleetwood Mac/Rumours") == "fleetwood-mac-rumours")
        #expect(Reports.failureCode("track-skipped SourceError.missingFolder") == "track-skipped SourceError.missingFolder")
        #expect(Reports.failureCode("/Users/nuno/Música/01.flac") == "UsersnunoMsica01.flac")
        #expect(Reports.failureCode("…") == "unknown")
    }

    @Test func theLogReportsOnlyTheKindOfAFailure() async throws {
        let (reports, defaults, suite) = reports()
        defer { defaults.removePersistentDomain(forName: suite) }
        reports.setConsent(true)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = Log(directory: dir, reports: reports)

        log.error(.player, "track-skipped", SourceError.missingFolder("Rumours"), detail: "Fleetwood Mac/Rumours/01.flac")
        log.flush()
        #expect(await reports.send())
        let sent = try #require((FakeReportsServer.posts.last?.body["errors"] as? [[String: Any]])?.first)
        #expect(sent["code"] as? String == "track-skipped SourceError.missingFolder")
        #expect(!"\(FakeReportsServer.posts)".contains("Rumours"))
    }

    @Test func aCrashIsNamedByWhereInNuVaItHappened() {
        let stack = Data("""
        {"callStackPerThread": true, "callStacks": [
          {"threadAttributed": false, "callStackRootFrames": [{"binaryName": "libsystem_kernel.dylib", "offsetIntoBinaryTextSegment": 1}]},
          {"threadAttributed": true, "callStackRootFrames": [
            {"binaryName": "libswiftCore.dylib", "offsetIntoBinaryTextSegment": 220,
             "subFrames": [{"binaryName": "NuVa", "offsetIntoBinaryTextSegment": 74565,
               "subFrames": [{"binaryName": "NuVa", "offsetIntoBinaryTextSegment": 100}]}]}]}]}
        """.utf8)
        #expect(CrashWatcher.signature(exceptionType: 1, signal: 11, callStack: stack) == "crash exc1 sig11 NuVa+74565")
        #expect(CrashWatcher.signature(exceptionType: nil, signal: 6, callStack: Data("{}".utf8)) == "crash sig6")
        #expect(Reports.crashSignature("crash exc1 sig11 NuVa+74565") == "crash exc1 sig11 NuVa+74565")
    }
}
