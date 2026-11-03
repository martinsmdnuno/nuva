import SwiftUI

/// The families behind the design system's text styles. Sizes, weights and line
/// heights are the same in every set; only the family changes.
enum FontSet: String, CaseIterable, Sendable {
    /// Inter and IBM Plex Mono, embedded (OFL). The 1.0 look.
    case inter
    /// SF Pro and SF Mono, from the system.
    case system
    /// IBM Plex Sans and Plex Mono, embedded (OFL): one engineered family, for Rams.
    case plex
    /// DM Sans and DM Mono, embedded (OFL): geometric and crisp, for Graphite Orange.
    case dm
    /// Share Tech and Share Tech Mono, embedded (OFL): a digital readout, for Phosphor. One weight.
    case shareTech

    var name: String {
        switch self {
        case .inter: "Inter + IBM Plex Mono"
        case .system: "SF Pro + SF Mono"
        case .plex: "IBM Plex Sans + Plex Mono"
        case .dm: "DM Sans + DM Mono"
        case .shareTech: "Share Tech + Share Tech Mono"
        }
    }

    /// The sans family, or nil for the system's.
    var sans: String? {
        switch self {
        case .inter: "Inter"
        case .system: nil
        case .plex: "IBM Plex Sans"
        case .dm: "DM Sans"
        case .shareTech: "Share Tech"
        }
    }

    /// The mono face for a weight (light, regular or medium), or nil for the system's.
    func mono(_ weight: Font.Weight) -> String? {
        switch self {
        case .inter, .plex: weight == .light ? "IBMPlexMono-Light" : weight == .medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular"
        case .dm: weight == .light ? "DMMono-Light" : weight == .medium ? "DMMono-Medium" : "DMMono-Regular"
        case .shareTech: "ShareTechMono-Regular"
        case .system: nil
        }
    }
}
