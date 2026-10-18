import AppKit
import Foundation

/// Asks GitHub for the latest release and tells the user when there's a newer one.
/// Never downloads anything: "Download" opens the release page in the browser.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let releasesAPI = URL(string: "https://api.github.com/repos/martinsmdnuno/nuva/releases/latest")!

    struct Release: Decodable, Sendable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }

        /// "v1.1" → "1.1".
        var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
    }

    private let defaults: UserDefaults
    private let session: URLSession

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
    }

    static var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// "1.10" > "1.9"; missing parts count as 0 ("1.1" == "1.1.0").
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = installed.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// At launch: at most once a day, quietly. Shows an alert only for a newer version the user hasn't skipped.
    func checkAtLaunch() {
        // Not while tests run inside the app.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let last = defaults.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 3600 else { return }
        Task {
            guard let release = try? await latest() else { return }
            defaults.set(Date(), forKey: "lastUpdateCheck")
            guard Self.isNewer(release.version, than: Self.installedVersion),
                  defaults.string(forKey: "skippedVersion") != release.version else { return }
            showUpdate(release, allowSkip: true)
        }
    }

    /// NuVa ▸ Check for Updates…: always answers, also when up to date or offline.
    func checkNow() {
        Task {
            do {
                let release = try await latest()
                defaults.set(Date(), forKey: "lastUpdateCheck")
                if Self.isNewer(release.version, than: Self.installedVersion) {
                    showUpdate(release, allowSkip: false)
                } else {
                    alert(String(localized: "A NuVa está atualizada"),
                          String(localized: "Tens a versão mais recente (\(Self.installedVersion))."))
                }
            } catch {
                alert(String(localized: "Não foi possível procurar atualizações"),
                      String(localized: "Sem ligação ao GitHub. Tenta mais tarde."))
            }
        }
    }

    func latest() async throws -> Release {
        var request = URLRequest(url: Self.releasesAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NuVa/\(Self.installedVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private func showUpdate(_ release: Release, allowSkip: Bool) {
        let alert = NSAlert()
        alert.messageText = String(localized: "NuVa \(release.version) disponível")
        alert.informativeText = String(localized: "Tens a \(Self.installedVersion). A nova versão está no GitHub; a NuVa não descarrega nada sozinha.")
        alert.addButton(withTitle: String(localized: "Descarregar"))
        alert.addButton(withTitle: String(localized: "Mais tarde"))
        if allowSkip { alert.addButton(withTitle: String(localized: "Ignorar esta versão")) }
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(release.htmlURL)
        case .alertThirdButtonReturn: defaults.set(release.version, forKey: "skippedVersion")
        default: break
        }
    }

    private func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }
}
