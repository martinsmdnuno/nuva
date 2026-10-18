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
        VStack(spacing: Space.s1 + 2) {
            if !player.queue.isEmpty { header(player) }
            list(player)
        }
    }

    /// Legenda "fila" e o total, como impresso no chassis.
    private func header(_ player: PlayerController) -> some View {
        HStack {
            Text("fila").legend()
            Spacer()
            Text(summary(player))
                .font(Typography.mono(10, .regular))
                .foregroundStyle(Color.inkMuted)
        }
        .padding(.horizontal, Space.s2)
    }

    /// "11 faixas · 39:18"; sem o total enquanto faltarem durações.
    private func summary(_ player: PlayerController) -> String {
        let count = player.queue.count
        let label = count == 1 ? "1 faixa" : "\(count) faixas"
        let known = player.queue.compactMap { model.durations.values[$0.entry.id] }
        guard known.count == count else { return label }
        return "\(label) · \(TimeFormat.short(known.reduce(0, +)))"
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

    private var emptyState: some View {
        VStack(spacing: Space.s3) {
            Text("Fila vazia")
                .font(.dsCaption)
                .foregroundStyle(Color.inkMuted)
            if model.sources.sources.isEmpty {
                HStack(spacing: Space.s2) {
                    Button("Adicionar pasta") { model.addFolder() }
                        .buttonStyle(.keyText)
                        .keyFocus()
                    Button("Adicionar Jellyfin") { model.addJellyfin() }
                        .buttonStyle(.keyText)
                        .keyFocus()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
