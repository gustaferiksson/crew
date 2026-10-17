import Foundation
import Observation
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

nonisolated struct PushPrefs: Codable, Equatable, Sendable {
    var replies = true
    var approvals = true
    var questions = true
    var routines = false
    var previews = true
}

enum PushStatus: Equatable {
    case unknown
    case notAuthorized
    case notInstalled
    case unavailable(String)
    case registered(apnsConfigured: Bool)
}

nonisolated private struct DeviceRegistration: Encodable, Sendable {
    let token: String
    let platform: String
    let environment: String
    let name: String
    let prefs: PushPrefs
}

nonisolated private struct ReadAnnouncement: Encodable, Sendable {
    let token: String
    let profile: String
    let sessionID: String
    let readAt: Double

    private enum CodingKeys: String, CodingKey {
        case token, profile
        case sessionID = "session_id"
        case readAt = "read_at"
    }
}

nonisolated private struct RegistrationReply: Decodable, Sendable {
    let installId: String
    let apnsConfigured: Bool
}

nonisolated private let denyPaymentAction = "DENY_PAYMENT"

@Observable
final class PushCenter: NSObject {
    private(set) var status: PushStatus
    private(set) var plugin: PluginStatus?
    private(set) var authorization = UNAuthorizationStatus.notDetermined
    private(set) var deviceToken: String?
    var pendingRoute: PushRoute?
    var prefs: PushPrefs {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(prefs), forKey: "pushPrefs") }
    }

    private var tokenError: String?
    private var visibleBot: Bot.ID?
    private let launchedAt = Date.now

    override init() {
        status = .unknown
        prefs = UserDefaults.standard.data(forKey: "pushPrefs").flatMap { try? JSONDecoder().decode(PushPrefs.self, from: $0) } ?? PushPrefs()
        super.init()
    }

    init(fixture status: PushStatus, plugin: PluginStatus? = nil) {
        self.status = status
        self.plugin = plugin
        self.authorization = .authorized
        self.prefs = PushPrefs()
    }

    var isPushing: Bool {
        status == .registered(apnsConfigured: true)
    }

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let deny = UNNotificationAction(identifier: denyPaymentAction, title: String(localized: "Deny"), options: .destructive, icon: UNNotificationActionIcon(systemImageName: "xmark"))
        let payment = UNNotificationCategory(
            identifier: "CREW_PAYMENT", actions: [deny], intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: String(localized: "Payment request"), options: .hiddenPreviewsShowTitle
        )
        center.setNotificationCategories(Set(["CREW_REPLY", "CREW_APPROVAL", "CREW_QUESTION", "CREW_ROUTINE"].map {
            UNNotificationCategory(identifier: $0, actions: [], intentIdentifiers: [], options: .hiddenPreviewsShowTitle)
        } + [payment]))
        Task { await refreshAuthorization() }
    }

    var readiness: String {
        "\(authorization.rawValue) \(deviceToken ?? tokenError ?? "")"
    }

    func authorize() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
    }

    private func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard isAuthorized else { return }
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #else
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    func received(token: Data) {
        deviceToken = token.map { String(format: "%02x", $0) }.joined()
        tokenError = nil
    }

    func failedToRegister(_ error: any Error) {
        tokenError = error.localizedDescription
    }

    func register(on connection: Connection) async {
        guard connection.state == .connected, let server = connection.session?.server else { return }
        guard isAuthorized else {
            status = authorization == .notDetermined ? .unknown : .notAuthorized
            return
        }
        guard let deviceToken else {
            await refreshPlugin(on: connection)
            if plugin != nil { status = .unavailable(tokenError ?? String(localized: "Waiting for Apple to issue a device token.")) }
            return
        }
        #if os(iOS)
        let registration = DeviceRegistration(token: deviceToken, platform: "ios", environment: environment, name: String(UIDevice.current.name.prefix(80)), prefs: prefs)
        #else
        let registration = DeviceRegistration(token: deviceToken, platform: "macos", environment: environment, name: String((Host.current().localizedName ?? "Mac").prefix(80)), prefs: prefs)
        #endif
        var request = hermesRequest("api/plugins/crew-push/devices", on: server)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(registration)
        do {
            let reply = try await fetch(request, with: connection.urlSession, as: RegistrationReply.self)
            status = .registered(apnsConfigured: reply.apnsConfigured)
            UserDefaults.standard.set(reply.installId, forKey: "pushInstallID")
        } catch HermesError.server(404, _) {
            status = .notInstalled
            return
        } catch {
            status = .unavailable(error.localizedDescription)
            return
        }
        let previous = UserDefaults.standard.string(forKey: "pushRegisteredToken")
        UserDefaults.standard.set(deviceToken, forKey: "pushRegisteredToken")
        guard let previous, previous != deviceToken else { return }
        await removeDevice(previous, on: connection)
    }

    func unregister(on connection: Connection) async {
        if let deviceToken, case .registered = status { await removeDevice(deviceToken, on: connection) }
        UserDefaults.standard.removeObject(forKey: "pushRegisteredToken")
        UserDefaults.standard.removeObject(forKey: "pushInstallID")
        status = .unknown
        plugin = nil
    }

    func refreshPlugin(on connection: Connection) async {
        guard let server = connection.session?.server else { return }
        do {
            plugin = try await fetch(hermesRequest("api/plugins/crew-push/status", on: server), with: connection.urlSession, as: PluginStatus.self)
        } catch HermesError.server(404, _) {
            plugin = nil
            status = .notInstalled
        } catch {
            plugin = nil
        }
    }

    func sendTest(on connection: Connection) async throws {
        guard let server = connection.session?.server, let deviceToken else { return }
        var request = hermesRequest("api/plugins/crew-push/test", on: server)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["token": deviceToken])
        _ = try await fetch(request, with: connection.urlSession, as: Empty.self)
    }

    func announceRead(of bot: Bot, on connection: Connection) async {
        guard isPushing, let deviceToken, let server = connection.session?.server else { return }
        let announcement = ReadAnnouncement(token: deviceToken, profile: bot.id, sessionID: bot.canonicalSession?.resolvedID.rawValue ?? "", readAt: Date.now.timeIntervalSince1970)
        var request = hermesRequest("api/plugins/crew-push/read", on: server)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(announcement)
        _ = try? await fetch(request, with: connection.urlSession, as: Empty.self)
    }

    func hide(_ bot: Bot.ID) {
        if visibleBot == bot { visibleBot = nil }
    }

    func show(_ bot: Bot.ID?) {
        visibleBot = bot
        guard let bot else { return }
        Task { await removeDelivered(of: bot) }
    }

    func readElsewhere(_ route: PushRoute) async {
        guard route.installID == nil || route.installID == UserDefaults.standard.string(forKey: "pushInstallID") else { return }
        if route.kind == "read" { return await removeDelivered(of: route.profile) }
        guard route.kind == "payment_resolved", let requestID = route.requestID else { return }
        await removeDeliveredPayments { $0.requestID == requestID }
    }

    func removeStalePayments() async {
        let now = Date.now
        await removeDeliveredPayments { $0.isStalePayment(at: now) }
    }

    private func removeDeliveredPayments(where matches: (PushRoute) -> Bool) async {
        let center = UNUserNotificationCenter.current()
        let ended = await center.deliveredNotifications().filter { notification in
            PushRoute(userInfo: notification.request.content.userInfo).map { $0.kind == "payment" && matches($0) } ?? false
        }
        center.removeDeliveredNotifications(withIdentifiers: ended.map(\.request.identifier))
    }

    private func removeDelivered(of bot: Bot.ID) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let read = delivered.filter { $0.request.content.threadIdentifier == "profile.\(bot)" }
        center.removeDeliveredNotifications(withIdentifiers: read.map(\.request.identifier))
        guard read.count == delivered.count else { return }
        try? await center.setBadgeCount(0)
    }

    func notifyLocally(from old: [Bot.ID: BotStatus], to new: [Bot.ID: BotStatus], bots: [Bot]) {
        guard !isPushing, isAuthorized else { return }
        for bot in bots where new[bot.id] != old[bot.id] && bot.meta.hidden != true {
            let content = UNMutableNotificationContent()
            content.title = bot.title
            content.threadIdentifier = "profile.\(bot.id)"
            content.sound = .default
            content.userInfo = ["crew": ["profile": bot.id, "session_id": ""]]
            if new[bot.id] == .waiting(.payment), prefs.approvals {
                content.body = String(localized: "Wants to pay")
                content.categoryIdentifier = "CREW_APPROVAL"
                content.interruptionLevel = .timeSensitive
            } else if new[bot.id] == .waiting(.approval), prefs.approvals {
                content.body = String(localized: "Needs approval")
                content.categoryIdentifier = "CREW_APPROVAL"
                content.interruptionLevel = .timeSensitive
            } else if case .waiting(let kind) = new[bot.id], kind != .approval, kind != .payment, prefs.questions {
                content.body = String(localized: "Has a question")
                content.categoryIdentifier = "CREW_QUESTION"
                content.interruptionLevel = .timeSensitive
            } else if new[bot.id] == .unread, prefs.replies, bot.canonicalSession?.lastActive ?? .distantPast > launchedAt {
                content.body = prefs.previews ? bot.canonicalSession?.preview ?? String(localized: "Replied") : String(localized: "Replied")
                content.categoryIdentifier = "CREW_REPLY"
            } else {
                continue
            }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "local.\(bot.id)", content: content, trigger: nil))
        }
    }

    private var isAuthorized: Bool {
        ![.notDetermined, .denied].contains(authorization)
    }

    private var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private func removeDevice(_ token: String, on connection: Connection) async {
        guard let server = connection.session?.server else { return }
        var request = hermesRequest("api/plugins/crew-push/devices/\(token)", on: server)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 5
        _ = try? await fetch(request, with: connection.urlSession, as: Empty.self)
    }

    private func presentation(for route: PushRoute?) -> UNNotificationPresentationOptions {
        #if os(iOS)
        let isActive = UIApplication.shared.applicationState == .active
        #else
        let isActive = NSApplication.shared.isActive
        #endif
        guard let route, isActive, route.profile == visibleBot else { return [.banner, .list, .sound] }
        return []
    }

    private func open(_ route: PushRoute?) {
        guard let route else { return }
        let expected = UserDefaults.standard.string(forKey: "pushInstallID")
        if let installID = route.installID, let expected, installID != expected { return }
        pendingRoute = route
    }
}

extension PushCenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let route = PushRoute(userInfo: notification.request.content.userInfo)
        completionHandler(MainActor.assumeIsolated { presentation(for: route) })
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let route = PushRoute(userInfo: response.notification.request.content.userInfo)
        guard response.actionIdentifier == denyPaymentAction else { return await MainActor.run { open(route) } }
        guard let route, route.kind == "payment", let requestID = route.requestID else { return }
        guard await !denyPayment(in: route.sessionID, requestID: requestID) else { return }
        let content = UNMutableNotificationContent()
        content.title = route.profile
        content.body = String(localized: "Couldn't reach Hermes. Open Crew to answer.")
        content.threadIdentifier = "profile.\(route.profile)"
        content.userInfo = ["crew": ["profile": route.profile, "session_id": route.sessionID]]
        try? await center.add(UNNotificationRequest(identifier: "deny-failed.\(requestID)", content: content, trigger: nil))
    }
}
