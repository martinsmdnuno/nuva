import SwiftUI

/// Spectrum meter on the display: the equalizer's 10 bands as columns of LED segments, like the
/// level meters of a hi-fi deck. Lit segments in `led`, unlit in `display-track`, and a peak segment
/// in `display-ink` that holds, then falls. Moves only with the music; at rest it is dark.
struct SpectrumView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var meter = SpectrumMeter()
    /// Keeps the meter running a moment after pausing, so the columns fall instead of freezing.
    @State private var settling = false

    static let segments = 8
    static let segmentHeight: CGFloat = 2
    static let segmentGap: CGFloat = 1
    static let columnGap: CGFloat = 3
    static let height = CGFloat(segments) * (segmentHeight + segmentGap) - segmentGap

    var body: some View {
        let player = model.player
        let spectrum = player.equalizer.spectrum
        TimelineView(.animation(minimumInterval: 1 / 30, paused: isSnapshot || !(player.isPlaying || settling))) { context in
            Canvas { gc, size in
                let levels: [Float]
                let peaks: [Float]
                if isSnapshot {
                    // Snapshots show a still moment, dark when nothing is loaded.
                    let still = player.current == nil ? Array(repeating: Float(0), count: Self.sample.count) : Self.sample
                    levels = still
                    peaks = still.map { $0 > 0 ? min(1, $0 + 0.2) : 0 }
                } else {
                    let measured = player.isPlaying
                        ? spectrum.levels(at: player.avPlayer.currentTime().seconds) : nil
                    meter.update(at: context.date, measured: measured)
                    levels = meter.levels
                    peaks = meter.peaks
                }
                draw(in: &gc, size: size, levels: levels, peaks: peaks)
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
        .help("Espectro ⌥⌘V")
        .onAppear { if !isSnapshot { spectrum.watch(true) } }
        .onDisappear { if !isSnapshot { spectrum.watch(false) } }
        .onChange(of: player.isPlaying) { _, playing in
            guard !playing else { return }
            settling = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                settling = false
            }
        }
    }

    private func draw(in gc: inout GraphicsContext, size: CGSize, levels: [Float], peaks: [Float]) {
        let columns = levels.count
        let width = (size.width - Self.columnGap * CGFloat(columns - 1)) / CGFloat(columns)
        for c in 0..<columns {
            let x = CGFloat(c) * (width + Self.columnGap)
            let lit = Self.litSegments(levels[c])
            let peak = Self.litSegments(peaks[c]) - 1
            for s in 0..<Self.segments {
                let y = size.height - CGFloat(s + 1) * (Self.segmentHeight + Self.segmentGap) + Self.segmentGap
                let color: Color = s < lit ? .led : (s == peak && peak >= lit ? .displayInk : .displayTrack)
                gc.fill(Path(CGRect(x: x, y: y, width: width, height: Self.segmentHeight)), with: .color(color))
            }
        }
    }

    private static func litSegments(_ level: Float) -> Int {
        Int((level * Float(segments)).rounded())
    }

    /// For snapshots (README images): a plausible album moment.
    private static let sample: [Float] = [0.55, 0.8, 0.7, 0.6, 0.65, 0.5, 0.45, 0.35, 0.25, 0.1]
}

/// Ballistics, like a hardware meter: a column jumps up to the level and falls back at a steady
/// rate; the peak segment holds for a moment, then falls too. Lives across frames, not observed.
final class SpectrumMeter {
    /// dBFS shown as an empty and as a full column. Music sits between -50 and -10 in most bands.
    static let floor: Float = -54
    static let ceiling: Float = -6
    /// Full scale per second.
    static let fall: Float = 1.6
    static let peakFall: Float = 0.6
    static let peakHold: TimeInterval = 0.8

    private(set) var levels = Array(repeating: Float(0), count: SpectrumShared.bands)
    private(set) var peaks = Array(repeating: Float(0), count: SpectrumShared.bands)
    private var peakTimes = Array(repeating: Date.distantPast, count: SpectrumShared.bands)
    private var last: Date?

    /// `measured` in dBFS per band, or nil when nothing is playing (the columns fall).
    func update(at date: Date, measured: [Float]?) {
        let dt = Float(min(max(date.timeIntervalSince(last ?? date), 0), 0.1))
        last = date
        for b in levels.indices {
            let target = measured.map { min(max(($0[b] - Self.floor) / (Self.ceiling - Self.floor), 0), 1) } ?? 0
            levels[b] = max(target, levels[b] - Self.fall * dt)
            if levels[b] >= peaks[b] {
                peaks[b] = levels[b]
                peakTimes[b] = date
            } else if date.timeIntervalSince(peakTimes[b]) > Self.peakHold {
                peaks[b] = max(levels[b], peaks[b] - Self.peakFall * dt)
            }
        }
    }
}
