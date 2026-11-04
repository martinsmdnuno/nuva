import AppKit
import SwiftUI

/// The ambient screen: one face at a time on the `display` token, sized from the screen's width
/// (`unit` = 1% of it), so every skin and every screen gets the same proportions.
struct AmbientView: View {
    /// Fixed face for the snapshots; otherwise View ▸ Ambient's choice.
    var face: AmbientFace?
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the mouse last moved: the key strip shows for 3 s after.
    @State private var lastMove: Date?
    @State private var hideStrip: Task<Void, Never>?
    /// The pointer is on the strip: it stays.
    @State private var stripHovered = false
    /// Paused for 10 minutes, the content dims.
    @State private var pausedSince: Date?

    var body: some View {
        let ambient = Ambient.shared
        let player = model.player
        GeometryReader { geometry in
            let protects = ambient.protectsOLED
            // With OLED protection the content is smaller, so it can wander over the screen.
            let area = protects ? 0.84 : 1.0
            let unit = geometry.size.width * area / 100
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = isSnapshot ? Self.snapshotDate : context.date
                // With artwork on, the cover's hue lights the screen from behind (not while resting).
                let glow = model.currentArtwork.flatMap(ArtworkGlow.field(for:))
                let shownFace = face ?? ambient.face
                ZStack {
                    if !isSnapshot, ambient.isResting(at: now) {
                        AmbientRest(size: geometry.size, unit: unit, now: now)
                    } else {
                        if let glow {
                            // The Display face's glow breathes with the bass.
                            AmbientGlow(field: glow, pulses: shownFace == .display && !reduceMotion)
                                .opacity(opacity(now: now))
                                .transition(.opacity)
                        }
                        Group {
                            switch shownFace {
                            case .display: AmbientDisplayFace(unit: unit)
                            case .clock: AmbientClockFace(unit: unit, now: now)
                            case .spectrum: AmbientSpectrumFace(unit: unit)
                            case .meters: AmbientMetersFace(unit: unit)
                            case .needles: AmbientNeedlesFace(unit: unit)
                            case .valves: AmbientValvesFace(unit: unit)
                            }
                        }
                        .environment(\.ambientStaticOpacity, protects ? 0.55 : 1)
                        .environment(\.ambientBlinks, protects && !isSnapshot)
                        .padding(.horizontal, unit * 7)
                        .padding(.vertical, unit * 6)
                        .frame(width: geometry.size.width * area, height: geometry.size.height * area)
                        .offset(isSnapshot ? .zero : Self.drift(at: now, in: geometry.size, protects: protects))
                        // The OLED drift moves about half a point a second: stepping once a second is
                        // invisible, and an animation there would redraw the screen at its refresh rate
                        // all the time. Only the small shift once a minute is animated.
                        .animation(reduceMotion || protects ? nil : .easeInOut(duration: 2), value: Self.minute(of: now))
                        .opacity(opacity(now: now))
                    }

                    if let lastMove, now.timeIntervalSince(lastMove) < 3 {
                        AmbientStrip()
                            .onHover { stripHovered = $0 }
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, unit * 1.5)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // A new album's glow fades in over the old one.
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.5), value: glow)
            }
        }
        .background(Color.display)
        .foregroundStyle(Color.displayInk)
        // All display, and the display is always dark: the skin's dark colours whatever the Mac's
        // appearance (in Aluminium the amber is darker and `ink` is near black, for a light chassis).
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: lastMove == nil)
        // ← → show the strip, with the new face's name, for a moment.
        .onChange(of: ambient.changesByHand) {
            lastMove = .now
            hideStripLater()
        }
        .onContinuousHover { phase in
            guard case .active = phase else { return }
            // Mouse events come many times a second; four updates a second are plenty.
            if let lastMove, Date.now.timeIntervalSince(lastMove) < 0.25 { return }
            ambient.noteInteraction()
            lastMove = .now
            hideStripLater()
        }
        .onChange(of: player.isPlaying, initial: true) { _, playing in
            pausedSince = playing ? nil : .now
            if !isSnapshot { ambient.keepAwake(playing) }
        }
        .onDisappear { ambient.keepAwake(false) }
        .id(SkinStore.shared.renderID)
    }

    private func opacity(now: Date) -> Double {
        let idle = pausedSince.map { now.timeIntervalSince($0) > 600 } ?? false
        return idle ? 0.3 : Ambient.shared.dims ? 0.4 : 1
    }

    private func hideStripLater() {
        hideStrip?.cancel()
        hideStrip = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if stripHovered {
                // Still pointing at the keys: keep them a little longer.
                lastMove = .now
                hideStripLater()
                return
            }
            lastMove = nil
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private static func minute(of date: Date) -> Int { Int(date.timeIntervalSinceReferenceDate / 60) }

    /// Where the content sits. Without OLED protection, a few points each minute along a 24-minute loop.
    /// With it, a slow wander over 8% of the screen each way, from two waves per axis whose periods
    /// don't divide each other, so the path doesn't repeat for days.
    static func drift(at date: Date, in size: CGSize, protects: Bool) -> CGSize {
        guard protects else {
            let unit = size.width / 100
            let angle = Double(minute(of: date) % 24) / 24 * 2 * .pi
            return CGSize(width: cos(angle) * unit * 1.2, height: sin(angle) * unit * 0.8)
        }
        let t = date.timeIntervalSinceReferenceDate
        func wave(_ slow: Double, _ fast: Double, _ phase: Double) -> Double {
            0.65 * sin(2 * .pi * t / slow + phase) + 0.35 * sin(2 * .pi * t / fast + phase * 2.3)
        }
        return CGSize(width: wave(3187, 1279, 0) * size.width * 0.08,
                      height: wave(4253, 1531, 1.7) * size.height * 0.08)
    }

    /// Fixed for the README snapshots.
    static let snapshotDate = Calendar.current.date(
        from: DateComponents(year: 2026, month: 11, day: 2, hour: 21, minute: 24)) ?? .now
}

extension EnvironmentValues {
    /// Lit areas that hardly change and aren't text (position bar, VU lamp) at this opacity: lower with
    /// OLED protection. Text keeps its full contrast (the display's muted ink is dim already).
    @Entry var ambientStaticOpacity: Double = 1
    /// The clock's colon blinks each second (OLED protection), like a bedside radio.
    @Entry var ambientBlinks = false
}

/// After an hour untouched (OLED protection): an almost black screen, only the LED wandering.
/// A key or the mouse brings the face back.
private struct AmbientRest: View {
    let size: CGSize
    let unit: CGFloat
    let now: Date
    @Environment(AppModel.self) private var model

    var body: some View {
        // Slow enough (a couple of points a second) to step once a second without animating.
        let t = now.timeIntervalSinceReferenceDate
        LED(isOn: model.player.isPlaying, size: unit)
            .opacity(0.6)
            .offset(x: sin(t / 571) * size.width * 0.4, y: sin(t / 787 + 1) * size.height * 0.4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The window's display, at the scale of the room: format and output, title and folder, time, position.
private struct AmbientDisplayFace: View {
    let unit: CGFloat
    @Environment(AppModel.self) private var model

    var body: some View {
        let player = model.player
        let entry = player.current?.entry
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: unit * 1.4) {
                LED(isOn: player.isPlaying, size: unit)
                Text(player.formatLabel)
                Spacer(minLength: unit * 2)
                Text(model.output.name)
            }
            .font(.dsAmbientMeta(unit * 1.7))
            .foregroundStyle(Color.displayMuted)
            .lineLimit(1)

            Spacer(minLength: unit * 2)

            HStack(spacing: unit * 2.4) {
                if model.showsArtwork, let artwork = model.currentArtwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: unit * 10, height: unit * 10)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                VStack(alignment: .leading, spacing: unit * 1.2) {
                    Text(entry?.title ?? String(localized: "Sem faixa"))
                        .font(.dsAmbientTitle(unit * 5.6))
                        .foregroundStyle(entry == nil ? Color.displayMuted : Color.displayInk)
                    Text(entry?.folderName ?? String(localized: "Escolher uma pasta para tocar"))
                        .font(.dsAmbientCaption(unit * 2.3))
                        .foregroundStyle(Color.displayMuted)
                }
                .lineLimit(1)
                .truncationMode(.tail)
            }

            Spacer(minLength: unit * 2)

            HStack(alignment: .lastTextBaseline) {
                Text(TimeFormat.display(player.currentTime))
                    .font(.dsAmbientTime(unit * 13))
                Spacer()
                Text(TimeFormat.display(player.duration))
                    .font(.dsAmbientMeta(unit * 2.2))
                    .foregroundStyle(Color.displayMuted)
            }
            .padding(.bottom, unit * 2)

            AmbientPosition(unit: unit)
        }
    }
}

/// The time of day as the subject, the playing track on one line below.
private struct AmbientClockFace: View {
    let unit: CGFloat
    let now: Date
    @Environment(AppModel.self) private var model
    @Environment(\.ambientBlinks) private var blinks

    var body: some View {
        let player = model.player
        VStack(spacing: unit * 1.4) {
            Spacer()
            // Hours and minutes apart, so the colon can blink.
            HStack(spacing: 0) {
                Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                Text(verbatim: ":")
                    .opacity(blinks && Int(now.timeIntervalSinceReferenceDate) % 2 == 1 ? 0 : 1)
                Text(now, format: .dateTime.minute(.twoDigits))
            }
            .font(.dsAmbientTime(unit * 20))
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)).lowercased())
                .font(.dsAmbientMeta(unit * 1.9))
                .foregroundStyle(Color.displayMuted)
            Spacer()
            if let entry = player.current?.entry {
                HStack(spacing: unit * 1.4) {
                    LED(isOn: player.isPlaying, size: unit)
                    Text(entry.title)
                    Text(verbatim: "· \(entry.folderName)")
                        .foregroundStyle(Color.displayMuted)
                }
                .font(.dsAmbientCaption(unit * 2.1))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.bottom, unit * 1.4)
                AmbientPosition(unit: unit)
                    .frame(maxWidth: unit * 30)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The position bar, read-only: nothing on the ambient screen is operated by pointing.
private struct AmbientPosition: View {
    let unit: CGFloat
    @Environment(AppModel.self) private var model
    @Environment(\.ambientStaticOpacity) private var staticOpacity

    var body: some View {
        let player = model.player
        let fraction = player.duration > 0 ? min(1, player.currentTime / player.duration) : 0
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.displayTrack)
                Rectangle().fill(Color.displayInk).frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: max(Size.bar, unit * 0.35))
        .opacity(staticOpacity)
    }
}

/// Shown for 3 s when the mouse moves: playback keys, the face's name and a key to leave.
private struct AmbientStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let player = model.player
        let ambient = Ambient.shared
        HStack(spacing: Space.s1) {
            Button { player.previous() } label: { Image(systemName: "backward.end") }
                .buttonStyle(.key(.transport))
                .keyFocus()
                .help("Anterior")
            Button { player.togglePlayPause() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }
                .buttonStyle(.key(.play))
                .keyFocus()
                .help(player.isPlaying ? String(localized: "Pausa") : String(localized: "Tocar"))
            Button { player.next() } label: { Image(systemName: "forward.end") }
                .buttonStyle(.key(.transport))
                .keyFocus()
                .help("Seguinte")
            Button { ambient.changeFace(by: 1) } label: {
                Text(verbatim: "← \(ambient.face.name.lowercased()) →")
                    .font(.dsHint)
                    .foregroundStyle(Color.inkMuted)
                    .frame(minWidth: 110)
            }
            .buttonStyle(.plain)
            .help("Mudar de mostrador")
            Button { ambient.close() } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                .buttonStyle(.key(.mode))
                .keyFocus()
                .help("Sair do Ambiente")
        }
        .padding(Space.s2)
        .background(Color.surface0, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

/// The track at the foot of the animated faces: title and folder on the left, elapsed time on the right.
private struct AmbientTrackFoot: View {
    let unit: CGFloat
    @Environment(AppModel.self) private var model

    var body: some View {
        let player = model.player
        let entry = player.current?.entry
        HStack(alignment: .lastTextBaseline, spacing: unit * 2) {
            VStack(alignment: .leading, spacing: unit * 0.6) {
                Text(entry?.title ?? String(localized: "Sem faixa"))
                    .font(.dsAmbientTitle(unit * 2.8))
                    .foregroundStyle(entry == nil ? Color.displayMuted : Color.displayInk)
                Text(entry?.folderName ?? "")
                    .font(.dsAmbientCaption(unit * 1.9))
                    .foregroundStyle(Color.displayMuted)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer()
            Text(TimeFormat.display(player.currentTime))
                .font(.dsAmbientTime(unit * 4.4))
        }
    }
}

/// Feeds a meter from the tap at the screen's own rate (120 Hz on a screen that has it) while music plays, and a moment after a
/// pause so the segments fall instead of freezing. Snapshots get a still moment instead.
private struct AmbientMeterTimeline<Content: View>: View {
    let meter: SpectrumMeter
    let measure: (PlayerController, Double) -> [Float]?
    let still: [Float]
    @ViewBuilder let content: (_ levels: [Float], _ peaks: [Float]) -> Content
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var settling = false

    var body: some View {
        let player = model.player
        let spectrum = player.equalizer.spectrum
        TimelineView(.animation(minimumInterval: nil, paused: isSnapshot || !(player.isPlaying || settling))) { context in
            if isSnapshot {
                let levels = player.current == nil ? still.map { _ in Float(0) } : still
                content(levels, levels.map { $0 > 0 ? min(1, $0 + 0.12) : 0 })
            } else {
                let _ = meter.update(
                    at: context.date,
                    measured: player.isPlaying ? measure(player, player.avPlayer.currentTime().seconds) : nil)
                content(meter.levels, meter.peaks)
            }
        }
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
}

/// 28 bands from 20 Hz to 20 kHz as solid bars in `display-ink`, each with its held peak as a thin
/// cap in `led`, the position bar below and the track at the foot. Finer than the window's 10-band
/// meter, which follows the equalizer's bands.
private struct AmbientSpectrumFace: View {
    let unit: CGFloat
    /// Narrower bands carry less energy than the equalizer's octaves, so the range sits lower.
    /// Like a hi-fi analyser: bars rise in a couple of frames and fall at about 45 dB a second; the
    /// peak caps hold, then drop faster and faster.
    @State private var meter = SpectrumMeter(
        count: SpectrumShared.fineBands, floor: -62, ceiling: -12, fall: 0.9, attack: 0.025, gravity: 2.4)
    @Environment(AppModel.self) private var model

    /// For snapshots: a plausible moment, falling from the bass to the treble.
    static let still: [Float] = (0..<SpectrumShared.fineBands).map { i in
        let x = Float(i) / Float(SpectrumShared.fineBands - 1)
        return max(0.08, 0.82 - 0.5 * x + 0.12 * sin(Float(i) * 1.7))
    }

    var body: some View {
        let player = model.player
        VStack(spacing: 0) {
            HStack(spacing: unit * 1.4) {
                LED(isOn: player.isPlaying, size: unit)
                Text(player.formatLabel)
                Spacer()
                Text(verbatim: "20 Hz – 20 kHz")
            }
            .font(.dsAmbientMeta(unit * 1.7))
            .foregroundStyle(Color.displayMuted)
            .lineLimit(1)
            .padding(.bottom, unit * 3)

            AmbientMeterTimeline(meter: meter, measure: { $0.equalizer.spectrum.fineLevels(at: $1) }, still: Self.still) { levels, peaks in
                Canvas { gc, size in
                    let columns = levels.count
                    let gap = unit * 0.75
                    let width = (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
                    let cap = max(2, unit * 0.35)
                    for c in 0..<columns {
                        let x = CGFloat(c) * (width + gap)
                        let bar = CGFloat(levels[c]) * (size.height - cap * 2)
                        if bar > 0 {
                            gc.fill(Path(CGRect(x: x, y: size.height - bar, width: width, height: bar)), with: .color(.displayInk))
                        }
                        let peak = CGFloat(peaks[c]) * (size.height - cap * 2)
                        if peaks[c] > 0 {
                            gc.fill(Path(CGRect(x: x, y: size.height - peak - cap * 1.6, width: width, height: cap)), with: .color(.led))
                        }
                    }
                }
            }

            AmbientPosition(unit: unit)
                .padding(.top, unit * 1.6)
                .padding(.bottom, unit * 3)

            AmbientTrackFoot(unit: unit)
        }
    }
}

/// Left and right levels as two ladders of segments, like a deck's record meters: RMS lit in `led`,
/// the held peak in `display-ink`, a dBFS scale below.
private struct AmbientMetersFace: View {
    let unit: CGFloat
    @State private var meter = SpectrumMeter(count: 2, floor: -48, ceiling: 0, fall: 1.3, attack: 0.02, gravity: 1.8)
    @Environment(AppModel.self) private var model

    static let segments = 40
    static let marks: [Float] = [-48, -36, -24, -18, -12, -6, -3, 0]

    var body: some View {
        let player = model.player
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: unit * 1.4) {
                LED(isOn: player.isPlaying, size: unit)
                Text(player.formatLabel)
                Spacer()
                Text(model.output.name)
            }
            .font(.dsAmbientMeta(unit * 1.7))
            .foregroundStyle(Color.displayMuted)
            .lineLimit(1)

            Spacer(minLength: unit * 2)

            AmbientMeterTimeline(meter: meter, measure: { player, time in
                player.equalizer.spectrum.stereo(at: time).map { [$0[0], $0[1]] }
            }, still: [0.78, 0.72]) { levels, peaks in
                VStack(alignment: .leading, spacing: unit * 2.6) {
                    ForEach(0..<2, id: \.self) { channel in
                        HStack(spacing: unit * 2) {
                            Text(verbatim: channel == 0 ? "L" : "R")
                                .font(.dsAmbientMeta(unit * 2))
                                .foregroundStyle(Color.displayMuted)
                                .frame(width: unit * 2.5, alignment: .leading)
                            ladder(level: levels[channel], peak: peaks[channel])
                                .frame(height: unit * 4.2)
                        }
                    }
                    scale
                }
            }

            Spacer(minLength: unit * 2)

            AmbientTrackFoot(unit: unit)
        }
    }

    private func ladder(level: Float, peak: Float) -> some View {
        Canvas { gc, size in
            let gap = unit * 0.45
            let width = (size.width - gap * CGFloat(Self.segments - 1)) / CGFloat(Self.segments)
            // The segment at the level's edge lights in part, so the bar glides instead of stepping.
            let exact = level * Float(Self.segments)
            let lit = Int(exact)
            let held = Int((peak * Float(Self.segments)).rounded()) - 1
            for s in 0..<Self.segments {
                let rect = CGRect(x: CGFloat(s) * (width + gap), y: 0, width: width, height: size.height)
                let segment = Path(roundedRect: rect, cornerRadius: unit * 0.15)
                gc.fill(segment, with: .color(s < lit ? .led : (s == held && held >= lit ? .displayInk : .displayTrack)))
                if s == lit, s != held, exact > Float(lit) {
                    gc.fill(segment, with: .color(Color.led.opacity(Double(exact - Float(lit)))))
                }
            }
        }
    }

    /// dBFS marks placed on the same scale as the segments.
    private var scale: some View {
        HStack(spacing: unit * 2) {
            Color.clear.frame(width: unit * 2.5, height: 1)
            GeometryReader { geometry in
                ForEach(Self.marks, id: \.self) { mark in
                    let x = CGFloat((mark - meter.floor) / (meter.ceiling - meter.floor)) * geometry.size.width
                    Text(verbatim: mark == 0 ? "0" : "\(Int(mark))")
                        .fixedSize()
                        .position(x: min(max(x, unit), geometry.size.width - unit), y: geometry.size.height / 2)
                }
            }
            .frame(height: unit * 2)
        }
        .font(.dsAmbientMeta(unit * 1.5))
        .foregroundStyle(Color.displayMuted)
    }
}

/// Left and right levels with their own ballistics, fed by `AmbientStereoTimeline`.
protocol StereoMeter: AnyObject {
    /// Per channel, what the face draws (0…1 for a slow meter, a deflection for a needle).
    var levels: [Float] { get }
    /// Per channel, the highest peak in dBFS over the last half second.
    var peaks: [Float] { get }
    /// `measured`: per channel, RMS and peak in dBFS; nil when nothing plays.
    func update(at date: Date, measured: [(level: Float, peak: Float)]?)
}

/// Slow ballistics for the filaments: they rise and fall over a fraction of a second, like a
/// heater, instead of jumping like the LED segments.
final class SlowMeter: StereoMeter {
    let floor: Float
    let ceiling: Float
    let rise: Float
    let fall: Float
    private(set) var levels: [Float]
    /// The highest peak of each channel, in dBFS, over the last half second (for the clip light).
    private(set) var peaks: [Float]
    private var peakTimes: [Date]
    private var last: Date?

    init(count: Int = 2, floor: Float, ceiling: Float, rise: Float, fall: Float) {
        self.floor = floor
        self.ceiling = ceiling
        self.rise = rise
        self.fall = fall
        levels = Array(repeating: 0, count: count)
        peaks = Array(repeating: -120, count: count)
        peakTimes = Array(repeating: .distantPast, count: count)
    }

    /// `measured`: per channel, a level in dBFS and a peak in dBFS; nil when nothing plays.
    func update(at date: Date, measured: [(level: Float, peak: Float)]?) {
        let dt = Float(min(max(date.timeIntervalSince(last ?? date), 0), 0.1))
        last = date
        for c in levels.indices {
            let target = measured.map { min(max(($0[c].level - floor) / (ceiling - floor), 0), 1) } ?? 0
            let rate = target > levels[c] ? rise : fall
            levels[c] += (target - levels[c]) * min(1, rate * dt)
            if let peak = measured?[c].peak, peak >= peaks[c] {
                peaks[c] = peak
                peakTimes[c] = date
            } else if date.timeIntervalSince(peakTimes[c]) > 0.5 {
                peaks[c] = measured?[c].peak ?? -120
            }
        }
    }
}

/// Runs a stereo meter on the tap's left and right levels at the screen's own rate (120 Hz on a
/// screen that has it) while music plays, and for 2 s after a pause so needles and filaments
/// settle. Snapshots get a still moment.
private struct AmbientStereoTimeline<Content: View>: View {
    let meter: any StereoMeter
    let still: [Float]
    @ViewBuilder let content: (_ levels: [Float], _ peaks: [Float]) -> Content
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var settling = false

    var body: some View {
        let player = model.player
        let spectrum = player.equalizer.spectrum
        TimelineView(.animation(minimumInterval: nil, paused: isSnapshot || !(player.isPlaying || settling))) { context in
            if isSnapshot {
                content(player.current == nil ? still.map { _ in 0 } : still, still.map { _ in -12 })
            } else {
                let measured = player.isPlaying
                    ? spectrum.stereo(at: player.avPlayer.currentTime().seconds).map { [($0[0], $0[2]), ($0[1], $0[3])] }
                    : nil
                let _ = meter.update(at: context.date, measured: measured)
                content(meter.levels, meter.peaks)
            }
        }
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
}

/// Two backlit VU meters, as on a hi-fi amplifier's front: a lit panel set into the chassis under
/// glass, a printed arc from -20 to +3 VU with the 0 to +3 zone in a heavier band, a tapered needle
/// casting its shadow on the dial, and a peak light that shows when a channel comes within 1 dB of
/// full scale. The needles move like the real thing (`VUNeedle`); 0 VU is -14 dBFS RMS.
/// The lamp is the skin's ink warmed by its accent: amber in Rams, pale green in Phosphor.
private struct AmbientNeedlesFace: View {
    let unit: CGFloat
    @State private var meter = NeedleMeter()
    @Environment(AppModel.self) private var model
    @Environment(\.ambientStaticOpacity) private var staticOpacity

    /// VU marks printed on the arc.
    static let marks: [Float] = [-20, -10, -7, -5, -3, -1, 0, 1, 2, 3]
    static let labelled: Set<Float> = [-20, -10, -7, -5, -3, 0, 3]

    var body: some View {
        let player = model.player
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: unit * 1.4) {
                LED(isOn: player.isPlaying, size: unit)
                Text(player.formatLabel)
                Spacer()
                Text(model.output.name)
            }
            .font(.dsAmbientMeta(unit * 1.7))
            .foregroundStyle(Color.displayMuted)
            .lineLimit(1)

            Spacer(minLength: unit * 2)

            AmbientStereoTimeline(meter: meter, still: [Float(Self.position(vu: -6)), Float(Self.position(vu: -7.5))]) { levels, peaks in
                HStack(spacing: unit * 4) {
                    ForEach(0..<2, id: \.self) { channel in
                        panel(deflection: CGFloat(levels[channel]), clipping: peaks[channel] > -1, channel: channel)
                            .aspectRatio(1.9, contentMode: .fit)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: unit * 2)

            AmbientTrackFoot(unit: unit)
        }
    }

    /// Deflection of a VU value, 0 (the rest pin) to 1 (+3 VU): a VU meter moves with voltage, not
    /// decibels, so -20 sits just right of the pin and 0 VU at about 70%.
    nonisolated static func position(vu: Float) -> CGFloat {
        CGFloat(VUNeedle.deflection(vu: Double(vu)))
    }

    private func panel(deflection: CGFloat, clipping: Bool, channel: Int) -> some View {
        Canvas { gc, size in
            let w = size.width, h = size.height
            let shape = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: unit * 0.4)
            // The lamp: the display's ink with the accent's warmth, dimmer with OLED protection.
            // The skin's paper-white ink under the accent: warm amber in Rams, pale green in Phosphor.
            gc.fill(shape, with: .color(.ink))
            gc.fill(shape, with: .color(Color.led.opacity(0.5)))
            // Lit from behind by one bulb: brighter just below the middle, darker towards the corners.
            gc.fill(shape, with: .radialGradient(
                Gradient(colors: [Color.display.opacity(0), Color.display.opacity(0.4)]),
                center: CGPoint(x: w / 2, y: h * 0.6), startRadius: h * 0.15, endRadius: w * 0.62))
            // OLED protection: a dimmer lamp (staticOpacity 0.55 leaves it at about 75%).
            gc.fill(shape, with: .color(Color.display.opacity((1 - staticOpacity) * 0.55)))

            let ink = GraphicsContext.Shading.color(Color.display.opacity(0.85))
            let pivot = CGPoint(x: w / 2, y: h * 1.18)
            let radius = h * 0.95
            let sweep = 0.78  // radians each side of vertical, from the rest pin to +3
            func angle(_ p: CGFloat) -> Double { -Double.pi / 2 - sweep + 2 * sweep * Double(p) }
            func point(_ p: CGFloat, _ r: CGFloat) -> CGPoint {
                CGPoint(x: pivot.x + CGFloat(cos(angle(p))) * r, y: pivot.y + CGFloat(sin(angle(p))) * r)
            }

            // The arc from -20 to +3, with a heavier band over 0 to +3.
            var arc = Path()
            arc.addArc(center: pivot, radius: radius, startAngle: .radians(angle(Self.position(vu: -20))),
                       endAngle: .radians(angle(1)), clockwise: false)
            gc.stroke(arc, with: ink, lineWidth: max(1, unit * 0.12))
            var over = Path()
            over.addArc(center: pivot, radius: radius + unit * 0.35,
                        startAngle: .radians(angle(Self.position(vu: 0))), endAngle: .radians(angle(1)), clockwise: false)
            gc.stroke(over, with: ink, lineWidth: unit * 0.6)

            for mark in Self.marks {
                let p = Self.position(vu: mark)
                var tick = Path()
                tick.move(to: point(p, radius))
                tick.addLine(to: point(p, radius + unit * (Self.labelled.contains(mark) ? 1.1 : 0.7)))
                gc.stroke(tick, with: ink, lineWidth: max(1, unit * 0.14))
                if Self.labelled.contains(mark) {
                    let text = Text(verbatim: mark > 0 ? "+\(Int(mark))" : "\(Int(mark))")
                        .font(.dsAmbientMeta(unit * 1.25))
                        .foregroundStyle(Color.display.opacity(0.85))
                    gc.draw(text, at: point(p, radius + unit * 2.2))
                }
            }
            gc.draw(Text(verbatim: "VU").font(.dsAmbientMeta(unit * 1.6)).foregroundStyle(Color.display.opacity(0.85)),
                    at: CGPoint(x: w / 2, y: h * 0.62))
            gc.draw(Text(verbatim: channel == 0 ? "L" : "R").font(.dsAmbientMeta(unit * 1.3)).foregroundStyle(Color.display.opacity(0.6)),
                    at: CGPoint(x: unit * 1.6, y: h - unit * 1.4))

            // The needle, tapered from its hidden pivot below the panel to a fine tip past the arc.
            let base = radius * 0.19, tip = radius + unit * 1.2
            let a = angle(deflection)
            let along = CGVector(dx: cos(a), dy: sin(a)), across = CGVector(dx: -sin(a), dy: cos(a))
            func needle(offset: CGSize) -> Path {
                let wide = max(1.2, unit * 0.13), fine = max(0.6, unit * 0.045)
                func at(_ r: CGFloat, _ side: CGFloat) -> CGPoint {
                    CGPoint(x: pivot.x + along.dx * r + across.dx * side + offset.width,
                            y: pivot.y + along.dy * r + across.dy * side + offset.height)
                }
                var path = Path()
                path.move(to: at(base, -wide))
                path.addLine(to: at(tip, -fine))
                path.addLine(to: at(tip, fine))
                path.addLine(to: at(base, wide))
                path.closeSubpath()
                return path
            }
            // Its shadow on the dial: the needle sits a little above it, lit from above.
            gc.drawLayer { layer in
                layer.clip(to: shape)
                layer.addFilter(.blur(radius: unit * 0.18))
                layer.fill(needle(offset: CGSize(width: unit * 0.22, height: unit * 0.4)), with: .color(Color.display.opacity(0.28)))
            }
            gc.fill(needle(offset: .zero), with: .color(Color.display))

            // Peak light, top right: on within 1 dB of full scale, with its glow on the panel.
            let light = CGRect(x: w - unit * 2, y: unit * 1, width: unit * 0.9, height: unit * 0.9)
            if clipping {
                gc.drawLayer { layer in
                    layer.addFilter(.blur(radius: unit * 0.5))
                    layer.fill(Path(ellipseIn: light.insetBy(dx: -unit * 0.3, dy: -unit * 0.3)), with: .color(Color.led.opacity(0.8)))
                }
            }
            gc.fill(Path(ellipseIn: light), with: .color(clipping ? .led : Color.display.opacity(0.35)))

            // Under glass, set into the chassis: a faint sheen across the top and a shadow along
            // the inside of the opening.
            gc.drawLayer { layer in
                layer.clip(to: shape)
                layer.fill(shape, with: .linearGradient(
                    Gradient(colors: [Color.displayInk.opacity(0.07), Color.displayInk.opacity(0)]),
                    startPoint: CGPoint(x: w * 0.3, y: 0), endPoint: CGPoint(x: w * 0.45, y: h * 0.5)))
                layer.addFilter(.blur(radius: unit * 0.6))
                layer.stroke(shape, with: .color(Color.display.opacity(0.55)), lineWidth: unit * 1.2)
            }
        }
    }
}

/// Two valves in a cage, after a valve phono stage: a glass envelope with its dome, the plate and the
/// filament inside, three rings and two posts around it. Each filament glows with its channel's level
/// (in `led`), and keeps a faint warm glow while paused, as a valve stays heated.
private struct AmbientValvesFace: View {
    let unit: CGFloat
    @State private var meter = SlowMeter(floor: -40, ceiling: -8, rise: 4, fall: 1.5)
    @Environment(AppModel.self) private var model

    var body: some View {
        let player = model.player
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: unit * 1.4) {
                LED(isOn: player.isPlaying, size: unit)
                Text(player.formatLabel)
                Spacer()
                Text(model.output.name)
            }
            .font(.dsAmbientMeta(unit * 1.7))
            .foregroundStyle(Color.displayMuted)
            .lineLimit(1)

            Spacer(minLength: unit * 2)

            AmbientStereoTimeline(meter: meter, still: [0.7, 0.62]) { levels, _ in
                HStack(spacing: unit * 10) {
                    ForEach(0..<2, id: \.self) { channel in
                        valve(glow: levels[channel], heated: player.current != nil, channel: channel)
                            .aspectRatio(0.62, contentMode: .fit)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: unit * 2)

            AmbientTrackFoot(unit: unit)
        }
    }

    private func valve(glow: Float, heated: Bool, channel: Int) -> some View {
        Canvas { gc, size in
            let w = size.width, h = size.height
            let line = max(1, unit * 0.14)
            let metal = GraphicsContext.Shading.color(Color.displayTrack)
            let glass = GraphicsContext.Shading.color(Color.displayMuted.opacity(0.8))
            let level = CGFloat(heated ? 0.2 + 0.8 * glow : 0)

            // Glass envelope: straight sides and a dome, on a base.
            let left = w * 0.24, right = w * 0.76, top = h * 0.16, shoulder = h * 0.3, bottom = h * 0.86
            var envelope = Path()
            envelope.move(to: CGPoint(x: left, y: bottom))
            envelope.addLine(to: CGPoint(x: left, y: shoulder))
            envelope.addQuadCurve(to: CGPoint(x: right, y: shoulder), control: CGPoint(x: w / 2, y: top - h * 0.1))
            envelope.addLine(to: CGPoint(x: right, y: bottom))

            // The glow spills past the glass as a soft halo, and fills the inside, strongest around the filament.
            let centre = CGPoint(x: w / 2, y: h * 0.57)
            if level > 0 {
                gc.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                    Gradient(colors: [Color.led.opacity(Double(0.35 * level)), Color.led.opacity(0)]),
                    center: centre, startRadius: 0, endRadius: w * (0.35 + 0.25 * level)))
                var inside = envelope
                inside.closeSubpath()
                gc.drawLayer { layer in
                    layer.clip(to: inside)
                    layer.fill(inside, with: .radialGradient(
                        Gradient(colors: [Color.led.opacity(Double(level)), Color.led.opacity(Double(0.3 * level))]),
                        center: centre, startRadius: 0, endRadius: h * (0.18 + 0.35 * level)))
                }
            }
            gc.stroke(envelope, with: glass, lineWidth: line)
            // The getter's silvering in the dome.
            var getter = Path()
            getter.addEllipse(in: CGRect(x: w * 0.38, y: h * 0.2, width: w * 0.24, height: h * 0.07))
            gc.fill(getter, with: .color(Color.displayTrack))

            // Plate and filament.
            // The plate is opaque metal: the filament shows through its open middle.
            let plate = CGRect(x: w * 0.36, y: h * 0.42, width: w * 0.28, height: h * 0.3)
            gc.stroke(Path(roundedRect: plate, cornerRadius: unit * 0.3), with: metal, lineWidth: w * 0.035)
            var filament = Path()
            filament.move(to: CGPoint(x: w / 2, y: h * 0.44))
            filament.addLine(to: CGPoint(x: w / 2, y: h * 0.7))
            gc.stroke(filament, with: .color(level > 0 ? Color.led.opacity(Double(0.5 + 0.5 * level)) : Color.displayTrack),
                      lineWidth: line * 1.4)
            // White-hot at its core when the channel is loud.
            if level > 0.4 {
                gc.stroke(filament, with: .color(Color.displayInk.opacity(Double(level - 0.4) * 1.4)), lineWidth: line * 0.6)
            }

            // Base and pins.
            gc.fill(Path(roundedRect: CGRect(x: w * 0.2, y: bottom, width: w * 0.6, height: h * 0.08), cornerRadius: unit * 0.2),
                    with: metal)

            // The cage: two posts and three rings, in front of the glass.
            for x in [w * 0.13, w * 0.87] {
                gc.fill(Path(roundedRect: CGRect(x: x - w * 0.025, y: h * 0.08, width: w * 0.05, height: h * 0.8),
                             cornerRadius: unit * 0.3), with: metal)
            }
            for y in [h * 0.09, h * 0.36, h * 0.66] {
                gc.fill(Path(roundedRect: CGRect(x: w * 0.08, y: y, width: w * 0.84, height: h * 0.028),
                             cornerRadius: unit * 0.3), with: metal)
            }

            gc.draw(Text(verbatim: channel == 0 ? "L" : "R").font(.dsAmbientMeta(unit * 1.5)).foregroundStyle(Color.displayMuted),
                    at: CGPoint(x: w / 2, y: h * 0.98))
        }
    }
}

/// The VU scale's shape, for the tests (the face itself is private).
enum AmbientNeedlesFaceTestHook {
    static func position(_ vu: Float) -> CGFloat { AmbientNeedlesFace.position(vu: vu) }
}
