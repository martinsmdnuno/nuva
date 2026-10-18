import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The one fallback for online artwork: it was wrong or not found. Search again with the
/// artist and album corrected, pick an image file, or say the folder has no artwork.
/// The choice is kept by NuVa for this folder; the folder itself is never written to.
struct ArtworkFixView: View {
    let entry: Entry
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var artist: String
    @State private var album: String
    @State private var error: String?
    @State private var busy = false

    /// `guess`: artist and album read from the folders, to start from.
    init(entry: Entry, guess: AlbumQuery?) {
        self.entry = entry
        _artist = State(initialValue: guess?.artist ?? "")
        _album = State(initialValue: guess?.album ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Capa errada ou em falta")
                .font(.dsTitle)
                .foregroundStyle(Color.ink)
            Text("A NuVa procura a capa pelo nome das pastas. Corrige o artista ou o álbum e procura outra vez, ou escolhe uma imagem.")
                .font(.dsCaption)
                .foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            field("Artista") { TextField("", text: $artist) }
            field("Álbum") { TextField("", text: $album) }
            if let error {
                Text(error)
                    .font(.dsCaption)
                    .foregroundStyle(Color.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.s2) {
                Button("Escolher imagem…") { chooseImage() }
                    .buttonStyle(.keyText)
                Button("Sem capa") { save(nil) }
                    .buttonStyle(.keyText)
                Spacer()
            }
            .disabled(busy)
            .padding(.top, Space.s2)
            HStack(spacing: Space.s2) {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .buttonStyle(.keyText)
                    .keyboardShortcut(.cancelAction)
                Button(busy ? String(localized: "A procurar…") : String(localized: "Procurar")) { search() }
                    .buttonStyle(.keyText)
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || query == nil)
            }
        }
        .padding(Space.s4)
        .frame(width: 360)
        .background(Color.surface1)
    }

    private var query: AlbumQuery? {
        let a = artist.trimmingCharacters(in: .whitespaces), b = album.trimmingCharacters(in: .whitespaces)
        return a.isEmpty || b.isEmpty ? nil : AlbumQuery(artist: a, album: b)
    }

    private func field(_ label: LocalizedStringKey, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(.dsLabel)
                .foregroundStyle(Color.inkMuted)
            content()
                .textFieldStyle(.roundedBorder)
                .font(.dsBody)
                .disabled(busy)
        }
    }

    private func search() {
        guard let query else { return }
        busy = true
        error = nil
        Task {
            do {
                if let data = try await model.artworkResolver.online.cover(for: query) {
                    save(data)
                } else {
                    error = String(localized: "Não encontrei esta capa. Confirma os nomes ou escolhe uma imagem.")
                }
            } catch {
                self.error = String(localized: "Sem ligação ao MusicBrainz. Tenta mais tarde.")
            }
            busy = false
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Escolher a imagem da capa")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = ArtworkStore.jpeg(from: url) else {
            error = String(localized: "Não consegui abrir esta imagem.")
            return
        }
        save(data)
    }

    /// `nil`: this folder has no artwork.
    private func save(_ data: Data?) {
        model.artworkResolver.cache.saveUser(data, folder: ArtworkResolver.folderKey(entry))
        model.artwork.invalidate(entry)
        dismiss()
    }
}
