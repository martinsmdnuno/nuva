import SwiftUI

/// One line that scrolls when it doesn't fit, like the name on an amplifier's display: it rests at
/// the start, slides until the end shows, rests and slides back. Still when it fits; with Reduce
/// Motion and in snapshots it truncates at the end instead. The full text is the tooltip, unless one is given.
struct ScrollingText: View {
    let text: String
    var tooltip: String?
    /// Points per second.
    var speed: CGFloat = 30
    /// The rest at each end.
    var pause: Duration = .seconds(2)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var boxWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: CGFloat { max(0, textWidth - boxWidth) }
    private var scrolls: Bool { overflow > 0 && !reduceMotion && !isSnapshot }

    var body: some View {
        // The truncated line sets the size; the full line slides inside it.
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(scrolls ? 0 : 1)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { boxWidth = $0 }
            .overlay(alignment: .leading) {
                Text(text)
                    .lineLimit(1)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { textWidth = $0 }
                    .offset(x: offset)
                    .opacity(scrolls ? 1 : 0)
            }
            .clipped()
            .help(tooltip ?? text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .task(id: scrolls ? overflow : 0) { await scroll() }
    }

    private func scroll() async {
        offset = 0
        guard scrolls else { return }
        let distance = overflow
        let duration = Double(distance / speed)
        while !Task.isCancelled {
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: duration)) { offset = -distance }
            try? await Task.sleep(for: .seconds(duration) + pause)
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: duration)) { offset = 0 }
            try? await Task.sleep(for: .seconds(duration))
        }
    }
}
