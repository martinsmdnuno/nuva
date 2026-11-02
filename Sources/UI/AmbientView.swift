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
            let unit = geometry.size.width / 100
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let now = isSnapshot ? Self.snapshotDate : context.date
                ZStack {
                    Group {
                        switch face ?? ambient.face {
                        case .display: AmbientDisplayFace(unit: unit)
                        case .clock: AmbientClockFace(unit: unit, now: now)
                        }
                    }
                    .padding(.horizontal, unit * 7)
                    .padding(.vertical, unit * 6)
                    .offset(isSnapshot ? .zero : Self.shift(at: now, unit: unit))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 2), value: Self.minute(of: now))
                    .opacity(opacity(now: now))

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

    /// A few points each minute, along a slow loop, so nothing stays on the same pixels (OLED, plasma).
    private static func shift(at date: Date, unit: CGFloat) -> CGSize {
        let angle = Double(minute(of: date) % 24) / 24 * 2 * .pi
        return CGSize(width: cos(angle) * unit * 1.2, height: sin(angle) * unit * 0.8)
    }

    /// Fixed for the README snapshots.
    static let snapshotDate = Calendar.current.date(
        from: DateComponents(year: 2026, month: 11, day: 2, hour: 21, minute: 24)) ?? .now
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
                Text(model.output.label)
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

    var body: some View {
        let player = model.player
        VStack(spacing: unit * 1.4) {
            Spacer()
            Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
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
