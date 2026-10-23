import SwiftUI

/// Folder browser, below the keys in place of the queue (⌘B swaps them). Its keys (up, Play Folder,
/// eject) sit in the header row above it (`BrowserControls`), so the rows get the room.
/// Enter or double-click: opens the folder or plays from the track.
/// ⌘Enter adds to the queue. ← or Delete goes up one level.
struct BrowserView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var selection: String?
    @FocusState private var focused: Bool

    var body: some View {
        let browser = model.browser
        VStack(spacing: 0) {
            Group {
                if let message = browser.errorMessage {
                    errorState(message)
                } else if isSnapshot {
                    Color.clear.overlay(alignment: .top) { rows(browser) }.clipped()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView { rows(browser) }
                            .onChange(of: selection) { _, id in if let id { proxy.scrollTo(id) } }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.leftArrow) { goUp(); return .handled }
        .onKeyPress(.delete) { goUp(); return .handled }
        .onKeyPress(.rightArrow) {
            if let row = selectedRow, case .entry(let e) = row, e.kind == .folder { activate(row) }
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            guard let row = selectedRow else { return .handled }
            if press.modifiers.contains(.command), case .entry(let e) = row {
                Task { await model.enqueue(e) }
            } else {
                activate(row)
            }
            return .handled
        }
        .onChange(of: browser.location) { old, new in selection = Self.cameFrom(old, to: new) }
        // Keyboard first: swapping to the folders puts the arrows in them.
        .onAppear { if !isSnapshot { focused = true } }
    }

    // MARK: Rows

    private enum Row: Identifiable {
        case source(id: UUID, name: String, symbol: String, error: String?)
        case entry(Entry)

        var id: String {
            switch self {
            case .source(let id, _, _, _): "source/\(id.uuidString)"
            case .entry(let e): e.id
            }
        }
    }

    private func currentRows(_ browser: Browser) -> [Row] {
        guard browser.location != nil else {
            let open = model.sources.sources.map {
                Row.source(id: $0.id, name: $0.name, symbol: $0.kind.symbol, error: nil)
            }
            let failed = model.sources.failed.sorted { $0.value < $1.value }.map {
                Row.source(id: $0.key, name: $0.value, symbol: "internaldrive", error: $0.value)
            }
            return open + failed
        }
        return browser.entries.map(Row.entry)
    }

    private func rows(_ browser: Browser) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(currentRows(browser)) { row in
                rowView(row)
                    .id(row.id)
                    .onTapGesture(count: 2) { activate(row) }
                    .simultaneousGesture(TapGesture().onEnded {
                        selection = row.id
                        focused = true
                    })
                    .contextMenu { menu(row) }
            }
            if browser.location == nil {
                HStack(spacing: Space.s2) {
                    Button("Adicionar pasta") { model.addFolder() }
                        .buttonStyle(.keyText)
                        .keyFocus()
                    Button("Adicionar Jellyfin") { model.addJellyfin() }
                        .buttonStyle(.keyText)
                        .keyFocus()
                    Spacer()
                }
                .padding(.vertical, Space.s3)
            }
        }
        // Going into a folder or back up cross-fades the rows in place.
        .motion(Motion.state, value: currentRows(browser).map(\.id))
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .source(_, let name, let symbol, let error):
            ListRow(leading: .symbol(symbol), name: name, isSelected: selection == row.id, isError: error != nil)
                .help(error ?? name)
        case .entry(let e) where e.kind == .folder:
            ListRow(
                leading: .folder, name: e.name, trailing: model.browser.summaries[e.id] ?? "",
                trailingIsDuration: false, isSelected: selection == row.id
            )
            .task(id: e.id) { await model.browser.loadSummary(e) }
        case .entry(let e):
            ListRow(
                leading: .track, name: e.listName,
                trailing: model.durations.values[e.id].map(TimeFormat.short) ?? "",
                isSelected: selection == row.id,
                isPlaying: model.player.current?.entry == e,
                help: e.name
            )
            .task(id: e.id) { await model.durations.load(e) }
        }
    }

    @ViewBuilder
    private func menu(_ row: Row) -> some View {
        switch row {
        case .source(let id, _, _, _):
            if let disc = model.sources.source(id) as? DiscSource {
                Button("Ejetar CD") { model.ejectDisc(disc) }
            } else {
                Button("Remover fonte") { model.sources.remove(id) }
            }
        case .entry(let e) where e.kind == .folder:
            Button("Tocar pasta") {
                Task { await model.playFolder(BrowserLocation(sourceID: e.sourceID, path: e.path)) }
            }
            Button("Adicionar à fila") { Task { await model.enqueue(e) } }
        case .entry(let e):
            Button("Tocar") { activate(row) }
            Button("Adicionar à fila") { Task { await model.enqueue(e) } }
        }
    }

    // MARK: States

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Space.s3) {
            Label(message, systemImage: "folder")
                .font(.dsCaption)
                .foregroundStyle(Color.danger)
            Button("Tentar de novo") { model.browser.reload() }
                .buttonStyle(.keyText)
                .keyFocus()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private var selectedRow: Row? {
        currentRows(model.browser).first { $0.id == selection }
    }

    private func activate(_ row: Row) {
        switch row {
        case .source(let id, _, _, let error):
            guard error == nil else { return }
            model.browser.open(BrowserLocation(sourceID: id, path: ""))
        case .entry(let e) where e.kind == .folder:
            model.browser.enter(e)
        case .entry(let e):
            Task {
                await model.playFolder(BrowserLocation(sourceID: e.sourceID, path: e.parentPath), startingAt: e)
            }
        }
    }

    private func goUp() { model.browser.up() }

    /// Going up (with ←, Delete or the header's key), the folder you came from stays selected.
    private static func cameFrom(_ old: BrowserLocation?, to new: BrowserLocation?) -> String? {
        guard let old else { return nil }
        guard let new else { return "source/\(old.sourceID.uuidString)" }
        let isParent = new.sourceID == old.sourceID && !old.path.isEmpty
            && (old.path as NSString).deletingLastPathComponent == new.path
        return isParent ? "\(old.sourceID.uuidString)/\(old.path)" : nil
    }

    private func moveSelection(_ delta: Int) {
        let rows = currentRows(model.browser)
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : rows.count)
        selection = rows[min(max(current + delta, 0), rows.count - 1)].id
    }
}

/// The browser's keys, in the header row above the folders: up, where you are, Play Folder and,
/// for a CD, eject. They stand in for the "pastas" and "fila" labels while the folders show.
struct BrowserControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let browser = model.browser
        HStack(spacing: Space.s2) {
            if browser.location != nil {
                Button { browser.up() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.key(.mode))
                    .keyFocus()
                    .help("Subir ←")
            }
            if let source = browser.source {
                Image(systemName: source.kind.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.inkMuted)
            }
            Text(browser.title)
                .font(.dsLabel)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(browser.location?.path ?? "")
                .contentTransition(.opacity)
                .motion(Motion.state, value: browser.title)
            Spacer(minLength: Space.s2)
            if let location = browser.location {
                Button("Tocar pasta") { Task { await model.playFolder(location) } }
                    .buttonStyle(.keyText)
                    .keyFocus()
                    // With the eject key there's less room: the title truncates, not the key.
                    .fixedSize()
            }
            if let disc = browser.source as? DiscSource {
                Button { model.ejectDisc(disc) } label: { Image(systemName: "eject") }
                    .buttonStyle(.key(.mode))
                    .keyFocus()
                    .help(String(localized: "Ejetar CD ⌘E"))
            }
        }
        .frame(height: Size.key)
    }
}
