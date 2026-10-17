import SwiftUI
#if os(iOS)
import SafariServices
#endif

nonisolated enum LinkDestination {
    case inApp
    case system

    init(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host()?.lowercased(), !host.isEmpty else {
            self = .system
            return
        }
        // Crew's OTA install page links to itms-services, which SFSafariViewController can't run.
        let isInstallPage = host == "gustaferiksson.github.io" && ["/crew", "/crew/", "/crew/index.html"].contains(url.path(percentEncoded: false).lowercased())
        self = isInstallPage ? .system : .inApp
    }
}

#if os(iOS)
extension OpenURLAction {
    static let inAppBrowser = OpenURLAction { url in
        guard LinkDestination(url) == .inApp else { return .systemAction }
        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { openedInApp in
            guard !openedInApp else { return }
            presentSafari(with: url)
        }
        return .handled
    }

    private static func presentSafari(with url: URL) {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first { $0.isKeyWindow }?
            .rootViewController
        guard let root else { return UIApplication.shared.open(url) }
        guard let top = Array(sequence(first: root, next: \.presentedViewController)).last, !(top is SFSafariViewController) else { return }
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let safari = SFSafariViewController(url: url, configuration: configuration)
        safari.modalPresentationStyle = .pageSheet
        top.present(safari, animated: true)
    }
}
#endif
