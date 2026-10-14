import Foundation
import Observation

@Observable
final class UpdateCheck {
    nonisolated static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private static let interval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "updateLastCheck"
    // `-updateManifest <url>` points the check at a local manifest and enables it in Debug builds.
    private static let manifestOverride = UserDefaults.standard.string(forKey: "updateManifest").flatMap(URL.init(string:))
    private static let manifestURL = manifestOverride ?? URL(string: "https://gustaferiksson.github.io/crew/manifest.plist")!

    private(set) var available: String?

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

    func checkIfDue() async {
        let defaults = UserDefaults.standard
        guard Self.isEnabled, available == nil else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date, Self.manifestOverride == nil, Date.now.timeIntervalSince(last) < Self.interval { return }
        guard let latest = await Self.latestVersion(from: Self.manifestURL) else { return }
        guard isNewerVersion(latest, than: Self.currentVersion) else {
            defaults.set(Date.now, forKey: Self.lastCheckKey)
            return
        }
        available = latest
    }

    nonisolated static func latestVersion(from manifest: URL) async -> String? {
        guard let (data, response) = try? await URLSession.shared.data(from: manifest),
              (response as? HTTPURLResponse)?.statusCode ?? 200 == 200,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let items = plist["items"] as? [[String: Any]],
              let metadata = items.first?["metadata"] as? [String: Any]
        else { return nil }
        return metadata["bundle-version"] as? String
    }
}
