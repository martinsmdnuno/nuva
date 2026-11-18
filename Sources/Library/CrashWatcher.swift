import Foundation
import MetricKit

/// Crashes and hangs, from macOS itself (MetricKit): no crash handler of NuVa's own, no library.
/// macOS hands them over at a later launch, so a crash is reported the next time the app runs.
/// They go to `Reports`, which keeps them only if the user said yes.
final class CrashWatcher: NSObject, MXMetricManagerSubscriber, Sendable {
    private let reports: Reports

    init(reports: Reports) {
        self.reports = reports
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                let stack = crash.callStackTree.jsonRepresentation()
                let signature = Self.signature(
                    exceptionType: crash.exceptionType?.intValue, signal: crash.signal?.intValue, callStack: stack)
                reports.crash(signature: signature, report: Self.report(
                    exceptionType: crash.exceptionType?.intValue, exceptionCode: crash.exceptionCode?.intValue,
                    signal: crash.signal?.intValue, reason: crash.terminationReason, callStack: stack))
            }
            for _ in payload.hangDiagnostics ?? [] {
                reports.failure(area: "app", code: "hang")
            }
        }
    }

    /// Names a crash by its kind and where in NuVa it happened, so the same crash counts as one:
    /// "crash exc1 sig11 NuVa+74565".
    static func signature(exceptionType: Int?, signal: Int?, callStack: Data) -> String {
        var parts = ["crash"]
        if let exceptionType { parts.append("exc\(exceptionType)") }
        if let signal { parts.append("sig\(signal)") }
        if let frame = crashingFrame(in: callStack) { parts.append(frame) }
        return parts.joined(separator: " ")
    }

    /// The first frame inside NuVa on the thread that crashed ("NuVa+74565"), else that thread's first frame.
    static func crashingFrame(in callStack: Data) -> String? {
        guard let tree = try? JSONSerialization.jsonObject(with: callStack) as? [String: Any],
              let stacks = tree["callStacks"] as? [[String: Any]] else { return nil }
        let thread = stacks.first { $0["threadAttributed"] as? Bool == true } ?? stacks.first
        var frame = (thread?["callStackRootFrames"] as? [[String: Any]])?.first
        var first: String?
        var depth = 0
        while let current = frame, depth < 512 {
            if let name = current["binaryName"] as? String, let offset = current["offsetIntoBinaryTextSegment"] as? Int {
                let label = "\(name)+\(offset)"
                if name == "NuVa" { return label }
                if first == nil { first = label }
            }
            frame = (current["subFrames"] as? [[String: Any]])?.first
            depth += 1
        }
        return first
    }

    /// The crash as text: its numbers and the call stack (binaries and offsets, nothing of the user's).
    static func report(exceptionType: Int?, exceptionCode: Int?, signal: Int?, reason: String?, callStack: Data) -> String {
        var lines: [String] = []
        if let exceptionType { lines.append("exceptionType: \(exceptionType)") }
        if let exceptionCode { lines.append("exceptionCode: \(exceptionCode)") }
        if let signal { lines.append("signal: \(signal)") }
        if let reason { lines.append("reason: \(reason)") }
        lines.append(String(decoding: callStack, as: UTF8.self))
        return lines.joined(separator: "\n")
    }
}
