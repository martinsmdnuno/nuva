import Foundation
import os

/// What NuVa tells its author, and only when the user said yes: how many times each feature was
/// used and which kinds of failure happened, as counts. Never a folder, file or server name, and
/// nothing that identifies the Mac or the person: no ID is made or sent. Without a yes nothing is
/// counted at all. About once a day the counts go to the author's own server (`deploy/site/reports.py`).
final class Reports: Sendable {
    static let shared = Reports(defaults: .standard)

    static let server = URL(string: "https://nuva.martinsnuno.com/api/")!
    /// At most this often.
    static let interval: TimeInterval = 20 * 3600
    static let maxCrashes = 5
    static let maxReport = 30_000

    struct Crash: Codable, Equatable, Sendable {
        let signature: String
        let report: String
    }

    private struct State {
        /// nil until the user is asked.
        var consent: Bool?
        var usage: [String: Int] = [:]
        /// By "area code".
        var failures: [String: Int] = [:]
        var crashes: [Crash] = []
    }

    private enum Key {
        static let consent = "reports.consent"
        static let usage = "reports.usage"
        static let failures = "reports.failures"
        static let crashes = "reports.crashes"
        static let lastSent = "reports.lastSent"
    }

    private let state: OSAllocatedUnfairLock<State>
    // UserDefaults is safe to use from any thread; it just isn't marked Sendable.
    private nonisolated(unsafe) let defaults: UserDefaults
    private let session: URLSession
    private let server: URL

    init(defaults: UserDefaults, session: URLSession = .shared, server: URL = Reports.server) {
        self.defaults = defaults
        self.session = session
        self.server = server
        var saved = State()
        saved.consent = defaults.object(forKey: Key.consent) as? Bool
        if saved.consent == true {
            saved.usage = defaults.dictionary(forKey: Key.usage) as? [String: Int] ?? [:]
            saved.failures = defaults.dictionary(forKey: Key.failures) as? [String: Int] ?? [:]
            saved.crashes = defaults.data(forKey: Key.crashes)
                .flatMap { try? JSONDecoder().decode([Crash].self, from: $0) } ?? []
        }
        state = OSAllocatedUnfairLock(initialState: saved)
    }

    /// The user's answer; nil while they haven't been asked.
    var consent: Bool? {
        state.withLock { $0.consent }
    }

    /// A no forgets everything counted so far.
    func setConsent(_ yes: Bool) {
        state.withLock {
            $0.consent = yes
            if !yes {
                $0.usage = [:]
                $0.failures = [:]
                $0.crashes = []
            }
        }
        defaults.set(yes, forKey: Key.consent)
        if !yes {
            for key in [Key.usage, Key.failures, Key.crashes, Key.lastSent] { defaults.removeObject(forKey: key) }
        }
    }

    // MARK: Counting

    /// A feature was used. `event` is a fixed word from the code ("play-folder"), never the user's text.
    func count(_ event: String) {
        let name = Self.eventName(event)
        let usage = state.withLock { state -> [String: Int]? in
            guard state.consent == true, !name.isEmpty else { return nil }
            state.usage[name, default: 0] += 1
            return state.usage
        }
        if let usage { defaults.set(usage, forKey: Key.usage) }
    }

    /// A failure was written to the log: only its kind is kept.
    func failure(area: String, code: String) {
        let name = Self.eventName(area) + " " + Self.failureCode(code)
        let failures = state.withLock { state -> [String: Int]? in
            guard state.consent == true else { return nil }
            state.failures[name, default: 0] += 1
            return state.failures
        }
        if let failures { defaults.set(failures, forKey: Key.failures) }
    }

    /// The app crashed in an earlier run (from MetricKit).
    func crash(signature: String, report: String) {
        let crashes = state.withLock { state -> [Crash]? in
            guard state.consent == true, state.crashes.count < Self.maxCrashes else { return nil }
            state.crashes.append(Crash(signature: Self.crashSignature(signature), report: String(report.prefix(Self.maxReport))))
            return state.crashes
        }
        if let crashes, let data = try? JSONEncoder().encode(crashes) { defaults.set(data, forKey: Key.crashes) }
    }

    /// Lowercase letters, digits, "." and "-", 40 at most: what the server takes as a feature's name.
    static func eventName(_ text: String) -> String {
        let kept = text.lowercased().unicodeScalars.map { scalar -> Character in
            let ok = ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "." || scalar == "-"
            return ok ? Character(scalar) : "-"
        }
        return String(String(kept).drop { $0 == "." || $0 == "-" }.prefix(40))
    }

    /// Letters, digits, space, ".", "_" and "-", 120 at most: no path survives it.
    static func failureCode(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._-")
        let kept = String(String.UnicodeScalarView(text.unicodeScalars.filter(allowed.contains)))
        let trimmed = kept.drop { !($0.isLetter || $0.isNumber) }.prefix(120)
        return trimmed.isEmpty ? "unknown" : String(trimmed)
    }

    static func crashSignature(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ._:()<>,+-")
        let kept = String(String.UnicodeScalarView(text.unicodeScalars.filter(allowed.contains)))
        let trimmed = kept.drop { !($0.isLetter || $0.isNumber) }.prefix(200)
        return trimmed.isEmpty ? "crash" : String(trimmed)
    }

    // MARK: Sending

    /// Sends what was counted, if the user said yes and a day has about passed. `settings`: how the
    /// app is set right now ("state.skin.rave"), counted once per report.
    @discardableResult
    func sendIfDue(settings: [String] = [], now: Date = Date()) async -> Bool {
        guard consent == true else { return false }
        let last = defaults.object(forKey: Key.lastSent) as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= Self.interval else { return false }
        return await send(settings: settings, now: now)
    }

    /// True when the server took everything there was to send.
    @discardableResult
    func send(settings: [String] = [], now: Date = Date()) async -> Bool {
        guard consent == true else { return false }
        let (usage, failures, crashes) = state.withLock { ($0.usage, $0.failures, $0.crashes) }
        var events = usage
        for name in settings.map(Self.eventName) where !name.isEmpty { events[name, default: 0] += 1 }

        var ok = true
        if !events.isEmpty {
            let done = await post("usage", ["events": events])
            if done { forget(usage: usage) }
            ok = ok && done
        }
        if !failures.isEmpty || !crashes.isEmpty {
            let errors: [[String: Any]] = failures.compactMap { name, n in
                guard let space = name.firstIndex(of: " ") else { return nil }
                return ["area": String(name[..<space]), "code": String(name[name.index(after: space)...]), "count": n]
            }
            let done = await post("errors", [
                "errors": errors,
                "crashes": crashes.map { ["signature": $0.signature, "report": $0.report] },
            ])
            if done { forget(failures: failures, crashes: crashes) }
            ok = ok && done
        }
        if ok { defaults.set(now, forKey: Key.lastSent) }
        return ok
    }

    /// True when the report is off our hands: taken (2xx) or refused as malformed (400, 413), which
    /// sending again wouldn't fix. Offline, flooded or a server error: kept for the next time.
    private func post(_ path: String, _ fields: [String: Any]) async -> Bool {
        var body = fields
        body["app"] = "mac"
        body["version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let system = ProcessInfo.processInfo.operatingSystemVersion
        body["os"] = "\(system.majorVersion).\(system.minorVersion)"
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return true }
        var request = URLRequest(url: server.appending(path: path), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        guard let (_, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return false }
        return (200..<300).contains(status) || status == 400 || status == 413
    }

    /// Takes what was sent off the counts, keeping what was counted meanwhile.
    private func forget(usage sent: [String: Int] = [:], failures: [String: Int] = [:], crashes: [Crash] = []) {
        let (usage, left, pending) = state.withLock { state in
            for (name, n) in sent { state.usage[name] = Self.minus(state.usage[name], n) }
            for (name, n) in failures { state.failures[name] = Self.minus(state.failures[name], n) }
            state.crashes.removeAll { crashes.contains($0) }
            return (state.usage, state.failures, state.crashes)
        }
        defaults.set(usage, forKey: Key.usage)
        defaults.set(left, forKey: Key.failures)
        defaults.set(try? JSONEncoder().encode(pending), forKey: Key.crashes)
    }

    private static func minus(_ value: Int?, _ sent: Int) -> Int? {
        let left = (value ?? 0) - sent
        return left > 0 ? left : nil
    }
}
