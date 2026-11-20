import AppKit
import Foundation
import Testing
@testable import NuVa

@MainActor
struct DockMenuTests {
    @Test func namesTheTrackAndOffersTheKeys() throws {
        let suite = "dock-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        let before = AppDelegate.model
        AppDelegate.model = model
        defer { AppDelegate.model = before }
        let delegate = AppDelegate()

        // Nothing to play: the Dock shows its own menu only.
        #expect(delegate.applicationDockMenu(NSApp) == nil)

        let source = UUID()
        model.player.debugSet(
            queue: [Entry(sourceID: source, path: "Fleetwood Mac/Tusk/01 - Over & Over.flac", name: "01 - Over & Over.flac", kind: .track)],
            current: 0, time: 0, duration: 200, format: "FLAC")
        let menu = try #require(delegate.applicationDockMenu(NSApp))
        let titles = menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
        #expect(titles.prefix(3) == ["Over & Over", "Fleetwood Mac · Tusk", "-"])
        #expect(menu.items.suffix(3).allSatisfy { $0.action != nil && $0.target === delegate })
        #expect(menu.items.prefix(2).allSatisfy { $0.action == nil })
    }
}
