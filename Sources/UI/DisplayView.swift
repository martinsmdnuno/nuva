import SwiftUI

/// The device's screen, recessed into the chassis. Always dark, in both themes.
/// The position bar lives here, below the time. With artwork on, the folder's image sits
/// at the left, the height of the title, folder and time rows, so the display doesn't grow.
struct DisplayView: View {
    /// Off in Compact mode; the mini player and the other modes show it.
    var allowsArtwork = true
    /// Clicking online or user artwork opens "Wrong artwork…" (main window only).
    var opensArtworkFix = false
    @Environment(AppModel.self) private var model
    @AppStorage("showsRemaining") private var showsRemaining = false

    var body: some View {
        let player = model.player
        let entry = player.current?.entry

        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                LED(isOn: player.isPlaying, size: 6)
                Text(player.formatLabel)
                    .contentTransition(.opacity)
                    .motion(Motion.state, value: player.formatLabel)
                Spacer(minLength: Space.s2)
                Text(model.currentSourceLabel)
            }
            .font(.dsDisplayMeta)
            .foregroundStyle(Color.displayMuted)
            .frame(height: 14)

            HStack(alignment: .top, spacing: Space.s3) {
                if allowsArtwork, let artwork = model.currentArtwork {
                    ArtworkTile(image: artwork)
                        .transition(.opacity)
                        .onTapGesture {
                            if opensArtworkFix, model.canFixArtwork { model.fixingArtwork = entry }
                        }
                        .help(opensArtworkFix && model.canFixArtwork ? String(localized: "Capa errada?") : "")
                }
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(entry?.title ?? (model.sources.sources.isEmpty ? String(localized: "Sem música") : String(localized: "Sem faixa")))
                        .font(.dsTitle)
                        .foregroundStyle(entry == nil ? Color.displayMuted : Color.displayInk)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(entry?.name ?? "")
                        .frame(height: 20)
                        .contentTransition(.opacity)
                        .motion(Motion.state, value: entry?.id)

                    HStack(spacing: Space.s2) {
                        Text(entry?.folderName ?? (model.sources.sources.isEmpty
                            ? String(localized: "Adicionar uma pasta ou um servidor Jellyfin")
                            : String(localized: "Escolher uma pasta para tocar")))
                            .font(.dsCaption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(entry?.parentPath ?? "")
                            .layoutPriority(1)
                            .contentTransition(.opacity)
                            .motion(Motion.state, value: entry?.parentPath)
                        Spacer(minLength: 0)
                        Text(model.output.label)
                            .font(.dsDisplayMeta)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(model.output.detail)
                    }
                    .foregroundStyle(Color.displayMuted)

                    Text(TimeFormat.display(player.currentTime))
                        .font(.dsDisplayTime)
                        .foregroundStyle(Color.displayInk)
                        .padding(.top, Space.s1)
                }
            }
            // A folder's artwork arriving or leaving moves the text aside in place.
            .motion(Motion.state, value: allowsArtwork && model.currentArtwork != nil)

            if model.showsSpectrum {
                // Room above and below, so the meter reads as its own zone of the display.
                SpectrumView()
                    .padding(.top, Space.s3)
                    .padding(.bottom, Space.s3)
            }

            // Position, between the elapsed time and the duration. Clicking the duration
            // switches it to the time left, and back.
            HStack(spacing: Space.s2) {
                Text(TimeFormat.display(player.currentTime))
                    .foregroundStyle(Color.displayMuted)
                ProgressBar()
                Text(endText(player))
                    .foregroundStyle(Color.displayMuted)
                    .contentShape(Rectangle())
                    .onTapGesture { showsRemaining.toggle() }
                    .help(showsRemaining ? String(localized: "Mostrar duração") : String(localized: "Mostrar tempo restante"))
            }
            .font(.dsDisplayMeta)
            .monospacedDigit()
        }
        .padding([.horizontal, .top], Space.s3)
        .padding(.bottom, Space.s1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            // shadow-display: recessed into the chassis.
            shape.fill(Color.display)
                .overlay(alignment: .top) { Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1) }
                .clipShape(shape)
        }
    }

    /// Duration, or the time left ("-03:10") after a click.
    private func endText(_ player: PlayerController) -> String {
        guard showsRemaining, player.duration > 0 else { return TimeFormat.display(player.duration) }
        return "-" + TimeFormat.display(player.duration - player.currentTime)
    }
}

/// The folder's image on the display: aspect-fit, never cropped or tinted.
private struct ArtworkTile: View {
    let image: NSImage
    static let size: CGFloat = 76

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: Self.size, height: Self.size)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .accessibilityLabel(Text("Capa da pasta"))
    }
}
