import SwiftUI

/// NuVa ▸ Terms and Privacy: TERMS.md from the bundle, in the interface language.
struct TermsView: View {
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        Group {
            // ImageRenderer doesn't draw ScrollView contents.
            if isSnapshot {
                content.frame(maxHeight: .infinity, alignment: .top).clipped()
            } else {
                ScrollView { content }
            }
        }
        .frame(minWidth: 420, idealWidth: 520, minHeight: 360, idealHeight: 620)
        .background(Color.surface0)
        .id(SkinStore.shared.renderID)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(Array(Self.blocks().enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    enum Block {
        case title(String), heading(String), paragraph(String), bullet(String)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .title(let text):
            Text(text).font(Typography.sans(20, .semibold)).foregroundStyle(Color.ink)
        case .heading(let text):
            Text(text).font(.dsTitle).foregroundStyle(Color.ink).padding(.top, Space.s3)
        case .paragraph(let text):
            Text(Self.inline(text)).font(.dsBody).foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("·").font(.dsBody).foregroundStyle(Color.inkMuted)
                Text(Self.inline(text)).font(.dsBody).foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    /// The English half of TERMS.md, or the Portuguese one when the interface is in Portuguese.
    static func blocks(language: String? = Bundle.main.preferredLocalizations.first) -> [Block] {
        guard let url = Bundle.main.url(forResource: "TERMS", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let halves = text.components(separatedBy: "\n---\n")
        let half = (language?.hasPrefix("pt") == true ? halves.last : halves.first) ?? text
        return parse(half)
    }

    static func parse(_ markdown: String) -> [Block] {
        markdown.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            let s = String(line)
            if s.hasPrefix("# ") { return .title(String(s.dropFirst(2))) }
            if s.hasPrefix("## ") { return .heading(String(s.dropFirst(3))) }
            if s.hasPrefix("- ") { return .bullet(String(s.dropFirst(2))) }
            return .paragraph(s)
        }
    }
}
