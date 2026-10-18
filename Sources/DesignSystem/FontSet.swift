/// The families behind the design system's text styles. Sizes, weights and line
/// heights are the same in every set; only the family changes.
enum FontSet: String, CaseIterable, Sendable {
    /// Inter and IBM Plex Mono, embedded (OFL). The 1.0 look.
    case inter
    /// SF Pro and SF Mono, from the system.
    case system

    var name: String {
        switch self {
        case .inter: "Inter + IBM Plex Mono"
        case .system: "SF Pro + SF Mono"
        }
    }
}
