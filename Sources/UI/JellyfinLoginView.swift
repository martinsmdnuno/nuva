import SwiftUI

/// Folha para juntar um servidor Jellyfin: endereço, utilizador e palavra-passe.
struct JellyfinLoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Adicionar Jellyfin")
                .font(.dsTitle)
                .foregroundStyle(Color.ink)
            field("Endereço") {
                TextField("https://jellyfin.exemplo.pt", text: $address)
                    .textContentType(.URL)
            }
            field("Utilizador") {
                TextField("", text: $username)
                    .textContentType(.username)
            }
            field("Palavra-passe") {
                SecureField("", text: $password)
                    .textContentType(.password)
            }
            if let error {
                Text(error)
                    .font(.dsCaption)
                    .foregroundStyle(Color.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.s2) {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .buttonStyle(.keyText)
                    .keyboardShortcut(.cancelAction)
                Button(busy ? "A entrar…" : "Entrar") { submit() }
                    .buttonStyle(.keyText)
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || serverURL == nil || username.isEmpty)
            }
            .padding(.top, Space.s2)
        }
        .padding(Space.s4)
        .frame(width: 320)
        .background(Color.surface1)
    }

    private func field(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
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

    /// Aceita "jellyfin.exemplo.pt" sem esquema (assume https) e tira a barra final.
    private var serverURL: URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.host() != nil else { return nil }
        return url
    }

    private func submit() {
        guard let server = serverURL else { return }
        busy = true
        error = nil
        Task {
            do {
                let source = try await model.sources.addJellyfin(
                    server: server, username: username.trimmingCharacters(in: .whitespaces), password: password)
                model.browser.open(BrowserLocation(sourceID: source.id, path: ""))
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
