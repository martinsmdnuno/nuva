import Foundation

enum TimeFormat {
    /// Display: "03:07", "1:02:03".
    static func display(_ seconds: Double) -> String {
        let (h, m, s) = parts(seconds)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// List: "4:05", "1:02:03".
    static func short(_ seconds: Double) -> String {
        let (h, m, s) = parts(seconds)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private static func parts(_ seconds: Double) -> (Int, Int, Int) {
        let t = max(0, Int(seconds.isFinite ? seconds : 0))
        return (t / 3600, (t % 3600) / 60, t % 60)
    }
}
