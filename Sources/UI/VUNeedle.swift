import Foundation

/// A VU meter's movement: a needle on a damped spring, driven by the signal's voltage. Tuned to
/// the standard (IEC 60268-17): a steady tone reaches 99% of its reading in 300 ms and overshoots
/// it by about 1.2%. The needle rests on a pin left of the scale and bounces softly off the pins.
struct VUNeedle {
    /// Deflection, proportional to voltage: 0 is the rest pin, 1 is +3 VU (so -20 VU is at 0.07).
    private(set) var position: Double = 0
    private var velocity: Double = 0

    /// Natural frequency (rad/s) and damping ratio of the movement.
    static let frequency = 13.5
    static let damping = 0.81
    /// The pin past +3 VU; the rest pin is at 0.
    static let endStop = 1.08
    /// Share of its speed the needle keeps when it hits a pin.
    static let bounce = 0.2

    /// Deflection for a level in VU (0 VU = full reading at +3 VU / 1.41).
    static func deflection(vu: Double) -> Double {
        pow(10, (vu - 3) / 20)
    }

    /// Moves the needle `dt` seconds towards `target` (a deflection), in 1 ms steps so it stays
    /// stable at any frame rate.
    mutating func step(towards target: Double, dt: Double) {
        let w = Self.frequency, z = Self.damping
        var remaining = min(max(dt, 0), 0.25)
        while remaining > 0 {
            let h = min(remaining, 0.001)
            velocity += (w * w * (target - position) - 2 * z * w * velocity) * h
            position += velocity * h
            if position < 0 {
                position = 0
                velocity = -velocity * Self.bounce
            } else if position > Self.endStop {
                position = Self.endStop
                velocity = -velocity * Self.bounce
            }
            remaining -= h
        }
    }
}

/// Left and right needles fed from the tap's RMS levels, plus each channel's highest peak over
/// the last half second (for the peak light).
final class NeedleMeter: StereoMeter {
    /// 0 VU in dBFS RMS.
    static let reference: Float = -14
    private var needles = [VUNeedle(), VUNeedle()]
    private(set) var peaks: [Float] = [-120, -120]
    private var peakTimes: [Date] = [.distantPast, .distantPast]
    private var last: Date?

    var levels: [Float] { needles.map { Float($0.position) } }

    /// `measured`: per channel, RMS and peak in dBFS; nil when nothing plays (the needles fall to rest).
    func update(at date: Date, measured: [(level: Float, peak: Float)]?) {
        let dt = date.timeIntervalSince(last ?? date)
        last = date
        for c in needles.indices {
            let target = measured.map { VUNeedle.deflection(vu: Double($0[c].level - Self.reference)) } ?? 0
            needles[c].step(towards: target, dt: dt)
            if let peak = measured?[c].peak, peak >= peaks[c] {
                peaks[c] = peak
                peakTimes[c] = date
            } else if date.timeIntervalSince(peakTimes[c]) > 0.5 {
                peaks[c] = measured?[c].peak ?? -120
            }
        }
    }
}
