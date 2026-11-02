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
                ZStack {
                    if !isSnapshot, ambient.isResting(at: now) {
                        AmbientRest(size: geometry.size, unit: unit, now: now)
                    } else {
                        Group {
                            switch face ?? ambient.face {
                            case .display: AmbientDisplayFace(unit: unit)
                            case .clock: AmbientClockFace(unit: unit, now: now)
                            case .spectrum: AmbientSpectrumFace(unit: unit)
                            case .meters: AmbientMetersFace(unit: unit)
                            }
                        }
                        .environment(\.ambientStaticOpacity, protects ? 0.55 : 1)
                        .environment(\.ambientBlinks, protects && !isSnapshot)
                        .padding(.horizontal, unit * 7)
                        .padding(.vertical, unit * 6)
                        .frame(width: geometry.size.width * area, height: geometry.size.height * area)
                        .offset(isSnapshot ? .zero : Self.drift(at: now, in: geometry.size, protects: protects))
                        .animation(reduceMotion ? nil : protects ? .linear(duration: 1) : .easeInOut(duration: 2),
                                   value: protects ? Int(now.timeIntervalSinceReferenceDate) : Self.minute(of: now))
                        .opacity(opacity(now: now))
                    }

                    if let lastMove, now.timeIntervalSince(lastMove) < 3 {
                        AmbientStrip()
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, unit * 1.5)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.display)
        .foregroundStyle(Color.displayInk)
        .animation(.easeOut(duration: 0.3), value: lastMove == nil)
        .onContinuousHover { phase in
            guard case .active = phase else { return }
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
        let moved = lastMove
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard lastMove == moved else { return }
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
    /// Parts that hardly change (format, folder, date, position bar) at this opacity: lower with OLED protection.
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
        let t = now.timeIntervalSinceReferenceDate
        LED(isOn: model.player.isPlaying, size: unit)
            .opacity(0.6)
            .offset(x: sin(t / 97) * size.width * 0.4, y: sin(t / 131 + 1) * size.height * 0.4)
            .animation(.linear(duration: 1), value: Int(t))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The window's display, at the scale of the room: format and output, title and folder, time, position.
private struct AmbientDisplayFace: View {
    let unit: CGFloat
    @Environment(AppModel.self) private var model
    @Environment(\.ambientStaticOpacity) private var staticOpacity

    var body: some View {
        let player = model.player
        let entry = player.current?.entry
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: unit * 1.4) {
                LED(isOn: player.isPlaying, size: unit)
                Text(player.formatLabel)
                Spacer(minLength: unit * 2)
                Text(model.output.label)
            }
            .font(.dsAmbientMeta(unit * 1.7))
            .foregroundStyle(Color.displayMuted)
            .lineLimit(1)
            .opacity(staticOpacity)

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
                        .opacity(staticOpacity)
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
    @Environment(\.ambientStaticOpacity) private var staticOpacity
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
                .opacity(staticOpacity)
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
                .help("Anterior")
            Button { player.togglePlayPause() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill") }
                .buttonStyle(.key(.play))
                .help(player.isPlaying ? String(localized: "Pausa") : String(localized: "Tocar"))
            Button { player.next() } label: { Image(systemName: "forward.end") }
                .buttonStyle(.key(.transport))
                .help("Seguinte")
            Button { ambient.face = ambient.face.moved(by: 1) } label: {
                Text(verbatim: "← \(ambient.face.name.lowercased()) →")
                    .font(.dsHint)
                    .foregroundStyle(Color.inkMuted)
                    .frame(minWidth: 110)
            }
            .buttonStyle(.plain)
            .help("Mudar de mostrador")
            Button { ambient.close() } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                .buttonStyle(.key(.mode))
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
    @Environment(\.ambientStaticOpacity) private var staticOpacity

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
                    .opacity(staticOpacity)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer()
            Text(TimeFormat.display(player.currentTime))
                .font(.dsAmbientTime(unit * 4.4))
        }
    }
}

/// Feeds a meter from the tap at 30 frames a second while music plays, and a moment after a
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
        TimelineView(.animation(minimumInterval: 1 / 30, paused: isSnapshot || !(player.isPlaying || settling))) { context in
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

/// The equalizer's 10 bands, as on the window's display but filling the screen: lit segments in
/// `led`, the held peak in `display-ink`, unlit in `display-track`. Band frequencies printed below.
private struct AmbientSpectrumFace: View {
    let unit: CGFloat
    @State private var meter = SpectrumMeter()
    @Environment(AppModel.self) private var model
    @Environment(\.ambientStaticOpacity) private var staticOpacity

    static let segments = 24
    static let still: [Float] = [0.55, 0.8, 0.7, 0.6, 0.65, 0.5, 0.45, 0.35, 0.25, 0.1]

    var body: some View {
        let player = model.player
        VStack(spacing: unit * 1.2) {
            HStack(spacing: unit * 1.4) {
                LED(isOn: player.isPlaying, size: unit)
                Text(player.formatLabel)
                Spacer()
                Text(verbatim: "dBFS")
            }
            .font(.dsAmbientMeta(unit * 1.7))
            .foregroundStyle(Color.displayMuted)
            .opacity(staticOpacity)

            AmbientMeterTimeline(meter: meter, measure: { $0.equalizer.spectrum.levels(at: $1) }, still: Self.still) { levels, peaks in
                Canvas { gc, size in
                    let columns = levels.count
                    let gap = unit * 0.8
                    let width = (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
                    let step = size.height / CGFloat(Self.segments)
                    for c in 0..<columns {
                        let lit = Int((levels[c] * Float(Self.segments)).rounded())
                        let peak = Int((peaks[c] * Float(Self.segments)).rounded()) - 1
                        for s in 0..<Self.segments {
                            let rect = CGRect(x: CGFloat(c) * (width + gap), y: size.height - CGFloat(s + 1) * step,
                                              width: width, height: step * 0.72)
                            let color: Color = s < lit ? .led : (s == peak && peak >= lit ? .displayInk : .displayTrack)
                            gc.fill(Path(rect), with: .color(color))
                        }
                    }
                }
            }

            HStack(spacing: unit * 0.8) {
                ForEach(Equalizer.frequencies, id: \.self) { f in
                    Text(verbatim: f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))")
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.dsAmbientMeta(unit * 1.4))
            .foregroundStyle(Color.displayMuted)
            .opacity(staticOpacity)
            .padding(.bottom, unit * 1.6)

            AmbientTrackFoot(unit: unit)
        }
    }
}

/// Left and right levels as two ladders of segments, like a deck's record meters: RMS lit in `led`,
/// the held peak in `display-ink`, a dBFS scale below.
private struct AmbientMetersFace: View {
    let unit: CGFloat
    @State private var meter = SpectrumMeter(count: 2, floor: -48, ceiling: 0)
    @Environment(AppModel.self) private var model
    @Environment(\.ambientStaticOpacity) private var staticOpacity

    static let segments = 40
    static let marks: [Float] = [-48, -36, -24, -18, -12, -6, -3, 0]

    var body: some View {
        let player = model.player
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: unit * 1.4) {
                LED(isOn: player.isPlaying, size: unit)
                Text(player.formatLabel)
                Spacer()
                Text(model.output.label)
            }
            .font(.dsAmbientMeta(unit * 1.7))
            .foregroundStyle(Color.displayMuted)
            .lineLimit(1)
            .opacity(staticOpacity)

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
            let lit = Int((level * Float(Self.segments)).rounded())
            let held = Int((peak * Float(Self.segments)).rounded()) - 1
            for s in 0..<Self.segments {
                let rect = CGRect(x: CGFloat(s) * (width + gap), y: 0, width: width, height: size.height)
                let color: Color = s < lit ? .led : (s == held && held >= lit ? .displayInk : .displayTrack)
                gc.fill(Path(roundedRect: rect, cornerRadius: unit * 0.15), with: .color(color))
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
        .opacity(staticOpacity)
    }
}
