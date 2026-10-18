#if os(iOS)
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    let push = PushCenter()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if Snapshot.requested == nil || Snapshot.postsNotification { push.start() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        push.received(token: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        push.failedToRegister(error)
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let route = PushRoute(userInfo: userInfo) else { return completionHandler(.noData) }
        Task {
            await push.readElsewhere(route)
            completionHandler(.noData)
        }
    }
}
#else
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let push = PushCenter()
    let updater = AppUpdater()

    func applicationWillFinishLaunching(_ notification: Notification) {
        if Snapshot.requested == nil { push.start() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.requested == nil { updater.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        updater.installOnQuit()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        push.received(token: deviceToken)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        push.failedToRegister(error)
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        guard let route = PushRoute(userInfo: userInfo) else { return }
        Task { await push.readElsewhere(route) }
    }
}
#endif
