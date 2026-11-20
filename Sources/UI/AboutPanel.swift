import AppKit

/// NuVa ▸ About NuVa: the system's panel, with what NuVa is, where it lives and whose fonts it carries.
@MainActor
enum AboutPanel {
    static let site = "https://nuva.martinsnuno.com"
    static let repository = "https://github.com/martinsmdnuno/nuva"

    static func show() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    /// What the panel says under the version: one line, two links, the fonts' licence.
    static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        let plain: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ]
        let text = NSMutableAttributedString()
        func line(_ string: String, link: String? = nil) {
            var attributes = plain
            if let link, let url = URL(string: link) { attributes[.link] = url }
            text.append(NSAttributedString(string: string, attributes: attributes))
            text.append(NSAttributedString(string: "\n", attributes: plain))
        }
        line(String(localized: "Toca a música das tuas pastas, tal como estão."))
        line("nuva.martinsnuno.com", link: site)
        line(String(localized: "Código-fonte no GitHub"), link: repository)
        line(String(localized: "Tipos de letra Inter, IBM Plex, DM Sans, DM Mono e Share Tech, sob a SIL Open Font License."))
        return text
    }
}
