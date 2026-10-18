import SwiftUI
import UniformTypeIdentifiers

/// A fila. Duplo clique ou Enter toca; Delete remove; arrastar reordena.
struct QueueList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var selection: QueueItem.ID?
    @FocusState private var focused: Bool

    var body: some View {
        let player = model.player
        list(player)
    }

    private func list(_ player: PlayerController) -> some View {
        Group {
            if player.queue.isEmpty {
                emptyState
            } else if isSnapshot {
                Color.clear.overlay(alignment: .top) { rows(player) }.clipped()
            } else {
                ScrollViewReader { proxy in
                    ScrollView { rows(player) }
                        .onReceive(NotificationCenter.default.publisher(for: .revealCurrentTrack)) { _ in
                            guard let id = player.currentID else { return }
                            selection = id
                            withAnimation(nil) { proxy.scrollTo(id, anchor: .center) }
                        }
                        .onChange(of: selection) { _, id in
                            if let id { proxy.scrollTo(id) }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.return) {
            if let selection { player.play(selection) }
            return .handled
        }
        .onKeyPress(.delete) { removeSelection(); return .handled }
        .onKeyPress(.deleteForward) { removeSelection(); return .handled }
    }

    private func rows(_ player: PlayerController) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, item in
                ListRow(
                    leading: .track,
                    name: item.entry.listName,
                    trailing: model.durations.values[item.entry.id].map(TimeFormat.short) ?? "",
                    isSelected: selection == item.id,
                    isPlaying: player.currentID == item.id,
                    help: item.entry.name
                )
                .id(item.id)
                .task(id: item.entry.id) { await model.durations.load(item.entry) }
                .onTapGesture(count: 2) { player.play(item.id) }
                .simultaneousGesture(TapGesture().onEnded {
                    selection = item.id
                    focused = true
                })
                .contextMenu {
                    Button("Tocar") { player.play(item.id) }
                    Button("Remover da fila") { remove(item.id) }
                }
                .modifier(Reorderable(item: item, index: index, player: player, enabled: !isSnapshot))
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.sources.sources.isEmpty {
            firstRun
        } else {
            VStack(alignment: .leading, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Fila vazia").font(.dsBody).foregroundStyle(Color.ink)
                    Text("Abrir as pastas e tocar uma.").font(.dsCaption).foregroundStyle(Color.inkMuted)
                }
                Button("Mostrar pastas") { model.windowMode = .browser }
                    .buttonStyle(.keyText)
                    .keyFocus()
                    .help("⌘B")
            }
            .padding(.horizontal, Space.s2)
            .padding(.top, Space.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Primeiro arranque: as duas formas de trazer música, cada uma com o que é e o atalho.
    private var firstRun: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("começar").legend()
            source("Adicionar pasta", detail: "Música no Mac ou num disco de rede", shortcut: "⌘O") {
                model.addFolder()
            }
            source("Adicionar Jellyfin", detail: "Servidor Jellyfin, com o teu utilizador", shortcut: "⇧⌘O") {
                model.addJellyfin()
            }
        }
        .padding(.horizontal, Space.s2)
        .padding(.top, Space.s1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func source(
        _ title: LocalizedStringKey, detail: LocalizedStringKey, shortcut: String, action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Button(action: action) { Text(title).frame(width: 116) }
                .buttonStyle(.keyText)
                .keyFocus()
            VStack(alignment: .leading, spacing: 2) {
                Text(detail)
                    .font(.dsCaption)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(shortcut).font(Typography.mono(10, .regular)).foregroundStyle(Color.inkMuted)
            }
            .layoutPriority(1)
        }
    }

    private func moveSelection(_ delta: Int) {
        let queue = model.player.queue
        guard !queue.isEmpty else { return }
        let current = queue.firstIndex { $0.id == (selection ?? model.player.currentID) } ?? (delta > 0 ? -1 : queue.count)
        let next = min(max(current + delta, 0), queue.count - 1)
        selection = queue[next].id
    }

    private func removeSelection() {
        guard let selection else { return }
        let queue = model.player.queue
        if let i = queue.firstIndex(where: { $0.id == selection }) {
            self.selection = queue.indices.contains(i + 1) ? queue[i + 1].id : (i > 0 ? queue[i - 1].id : nil)
        }
        remove(selection)
    }

    private func remove(_ id: QueueItem.ID) {
        guard let i = model.player.queue.firstIndex(where: { $0.id == id }) else { return }
        model.player.remove(atOffsets: [i])
    }
}

/// Cabeçalho da fila, como impresso no chassis: à esquerda a pista "pastas" (do lado
/// de onde a gaveta abre), à direita a pista "fila" com o total. Fica no compacto,
/// para quem não conhece a app ver por onde se volta.
struct QueueHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let player = model.player
        let isOpen = model.windowMode == .browser
        HStack(alignment: .bottom, spacing: Space.s2) {
            // A mesma tecla que fecha a gaveta no cabeçalho do navegador; o LED diz se está aberta.
            HStack(alignment: .bottom, spacing: Space.s2) {
                Button { model.toggleBrowser() } label: { Image(systemName: "sidebar.left") }
                    .buttonStyle(.key(.mode))
                    .keyFocus()
                    .help(isOpen ? String(localized: "Esconder pastas ⌘B") : String(localized: "Mostrar pastas ⌘B"))
                    .keyLED(isOpen)
                // Ao meio da face da tecla.
                Text("pastas").legend()
                    .padding(.bottom, Space.s3)
            }
            Spacer()
            LegendToggle(
                isOn: model.windowMode != .compact, label: "fila",
                detail: player.queue.isEmpty ? nil : summary(player),
                help: model.windowMode == .compact
                    ? String(localized: "Mostrar fila ⌘1") : String(localized: "Esconder fila ⌘3")
            ) { model.toggleQueue() }
            .padding(.bottom, Space.s3)
        }
        .padding(.trailing, Space.s2)
    }

    /// "11 faixas · 39:18"; sem o total enquanto faltarem durações.
    private func summary(_ player: PlayerController) -> String {
        let count = player.queue.count
        let label = String(localized: "\(count) faixas")
        let known = player.queue.compactMap { model.durations.values[$0.entry.id] }
        guard known.count == count else { return label }
        return "\(label) · \(TimeFormat.short(known.reduce(0, +)))"
    }
}

/// Legenda clicável com LED, como os presets do equalizador. `ink-muted` em repouso,
/// `ink` no hover e quando ligada; o LED acende quando ligada.
private struct LegendToggle: View {
    let isOn: Bool
    var symbol: String?
    let label: LocalizedStringKey
    var detail: String?
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s1 + 2) {
                // Na coluna dos LEDs das faixas, para alinhar.
                LED(isOn: isOn).frame(width: symbol == nil ? nil : 12)
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10))
                }
                Text(label).font(.dsLegend)
                if let detail {
                    Text(detail).font(Typography.mono(10, .regular))
                }
            }
            .foregroundStyle(hovering || isOn ? Color.ink : Color.inkMuted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Arrastar uma linha para outra posição da fila.
private struct Reorderable: ViewModifier {
    let item: QueueItem
    let index: Int
    let player: PlayerController
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .draggable(item.id.uuidString)
                .dropDestination(for: String.self) { ids, _ in
                    guard let raw = ids.first,
                          let from = player.queue.firstIndex(where: { $0.id.uuidString == raw }) else { return false }
                    player.move(fromOffsets: [from], toOffset: index > from ? index + 1 : index)
                    return true
                }
        } else {
            content
        }
    }
}

extension Notification.Name {
    /// ⌘L: mostrar e selecionar a faixa atual na fila.
    static let revealCurrentTrack = Notification.Name("revealCurrentTrack")
}

extension EnvironmentValues {
    /// Em captura (ImageRenderer) não há ScrollView.
    @Entry var isSnapshot = false
}
