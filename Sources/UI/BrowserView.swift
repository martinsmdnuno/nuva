import SwiftUI

/// Navegador de pastas (janela 720 × 480, à esquerda).
/// Enter ou duplo clique: entra na pasta ou toca a partir da faixa.
/// ⌘Enter junta à fila. ← ou Delete sobe um nível.
struct BrowserView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var selection: String?
    @FocusState private var focused: Bool

    var body: some View {
        let browser = model.browser
        VStack(spacing: 0) {
            header(browser)
                .padding(Space.s3)
            Rectangle().fill(Color.line).frame(height: 1)
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
        .background(Color.surface1, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
        .onChange(of: browser.location) { selection = nil }
    }

    // MARK: Linhas

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
        let rows = currentRows(browser)
        var trackNumber = 0
        let numbers: [String: Int] = rows.reduce(into: [:]) { acc, row in
            if case .entry(let e) = row, e.kind == .track {
                trackNumber += 1
                acc[e.id] = trackNumber
            }
        }
        return LazyVStack(spacing: 0) {
            ForEach(rows) { row in
                rowView(row, number: numbers[row.id] ?? 0)
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
                .padding(Space.s3)
            }
        }
        .padding(.horizontal, Space.s1)
    }

    @ViewBuilder
    private func rowView(_ row: Row, number: Int) -> some View {
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
                leading: .number(number), name: e.name,
                trailing: model.durations.values[e.id].map(TimeFormat.short) ?? "",
                isSelected: selection == row.id,
                isPlaying: model.player.current?.entry == e
            )
            .task(id: e.id) { await model.durations.load(e) }
        }
    }

    @ViewBuilder
    private func menu(_ row: Row) -> some View {
        switch row {
        case .source(let id, _, _, _):
            Button("Remover fonte") { model.sources.remove(id) }
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

    // MARK: Cabeçalho e estados

    private func header(_ browser: Browser) -> some View {
        HStack(spacing: Space.s2) {
            if browser.location != nil {
                Button(action: goUp) { Image(systemName: "chevron.left") }
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
            Spacer(minLength: Space.s2)
            if let location = browser.location {
                Button("Tocar pasta") { Task { await model.playFolder(location) } }
                    .buttonStyle(.keyText)
                    .keyFocus()
            }
        }
        .frame(height: Size.key)
    }

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

    // MARK: Ações

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

    private func goUp() {
        let from = model.browser.location
        model.browser.up()
        // Ao subir, a pasta de onde se veio fica selecionada.
        if let from, !from.path.isEmpty {
            selection = "\(from.sourceID.uuidString)/\(from.path)"
        } else if let from {
            selection = "source/\(from.sourceID.uuidString)"
        }
    }

    private func moveSelection(_ delta: Int) {
        let rows = currentRows(model.browser)
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : rows.count)
        selection = rows[min(max(current + delta, 0), rows.count - 1)].id
    }
}
