import Foundation
import Observation

@Observable
final class UpdateCheck {
    nonisolated static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private static let foregroundGap: TimeInterval = 5 * 60
    // `-updateManifest <url>` points the check at a local manifest and enables it in Debug builds.
    private static let manifestOverride = UserDefaults.standard.string(forKey: "updateManifest").flatMap(URL.init(string:))
    private static let manifestURL = manifestOverride ?? URL(string: "https://gustaferiksson.github.io/crew/manifest.plist")!

    private(set) var available: String?
    private(set) var isChecking = false
    var note: String?
    @ObservationIgnored private var lastCheck: Date?

    var installURL: URL? {
        var components = URLComponents(string: "itms-services://")
        components?.queryItems = [URLQueryItem(name: "action", value: "download-manifest"), URLQueryItem(name: "url", value: Self.manifestURL.absoluteString)]
        return components?.url
    }

    private static var isEnabled: Bool {
        guard manifestOverride == nil else { return true }
        #if DEBUG
        return false
        #else
        return !currentVersion.hasSuffix("-local")
        #endif
    }

    func checkOnForeground() async {
        guard Self.isEnabled, available == nil, !isChecking else { return }
        if let lastCheck, Date.now.timeIntervalSince(lastCheck) < Self.foregroundGap { return }
        await refresh()
    }

    func checkNow() async {
        guard Self.isEnabled else {
            note = String(localized: "This build doesn’t update itself.")
            return
        }
        guard !isChecking else { return }
        guard await refresh() else {
            note = String(localized: "Couldn’t reach the update server.")
            return
        }
        if available == nil { note = String(localized: "Crew \(Self.currentVersion) is up to date.") }
    }

    @discardableResult
    private func refresh() async -> Bool {
        isChecking = true
        lastCheck = .now
        defer { isChecking = false }
        guard let latest = await Self.latestVersion(from: Self.manifestURL) else { return false }
        available = isNewerVersion(latest, than: Self.currentVersion) ? latest : nil
        return true
    }

    nonisolated static func latestVersion(from manifest: URL) async -> String? {
        let request = URLRequest(url: manifest, cachePolicy: .reloadIgnoringLocalCacheData)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode ?? 200 == 200,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let items = plist["items"] as? [[String: Any]],
              let metadata = items.first?["metadata"] as? [String: Any]
        else { return nil }
        return metadata["bundle-version"] as? String
    }
}
