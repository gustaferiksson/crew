#if os(macOS)
import SwiftUI

struct SettingsView: View {
    enum Pane: String {
        case account, notifications
    }

    @AppStorage("settingsPane") private var pane = Pane.account
    @Environment(PushCenter.self) private var push

    var body: some View {
        let selection = Snapshot.requested == nil || Snapshot.isInteractive ? $pane : .constant([.settingsNotifications, .settingsNotificationsAsk].contains(Snapshot.requested) ? .notifications : .account)
        TabView(selection: selection) {
            Tab("Account", systemImage: "person.crop.circle", value: .account) {
                AccountSettings()
                    .frame(width: 480)
                    .scrollDisabled(true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Tab("Notifications", systemImage: "bell.badge", value: .notifications) {
                NotificationSettings()
                    .environment([.settingsNotifications, .settingsNotificationsAsk].contains(Snapshot.requested) ? Snapshot.fixturePush : push)
                    .frame(width: 480)
                    .scrollDisabled(true)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AccountSettings: View {
    @Environment(Connection.self) private var connection
    @Environment(PushCenter.self) private var push
    @Environment(ChatDrafts.self) private var drafts
    @Environment(\.openWindow) private var openWindow
    @AppStorage("username") private var username = ""
    @State private var confirmsSignOut = false
    @State private var isSigningOut = false

    var body: some View {
        if let host = connection.session?.server.host(), connection.state != .signedOut {
            Form {
                Section {
                    LabeledContent("Server") {
                        Text(host).truncationMode(.middle)
                    }
                    LabeledContent("User") {
                        Text(username).truncationMode(.middle)
                    }
                    LabeledContent("Status") {
                        HStack(spacing: 8) {
                            status
                            if connection.state == .unreachable {
                                Button("Retry", action: connection.retry)
                            }
                        }
                    }
                }
                Section {
                    HStack(spacing: 8) {
                        Spacer()
                        if isSigningOut {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Sign Out…") { confirmsSignOut = true }
                            .disabled(isSigningOut)
                    }
                }
            }
            .formStyle(.grouped)
            .lineLimit(1)
            .confirmationDialog("Sign out of \(host)?", isPresented: $confirmsSignOut) {
                Button("Sign Out", role: .destructive) {
                    isSigningOut = true
                    Task {
                        await push.unregister(on: connection)
                        await connection.signOut()
                        drafts.reset()
                        isSigningOut = false
                        openWindow(id: "main")
                    }
                }
            } message: {
                Text("Crew forgets this session and the unsent drafts on this Mac, and closes its chat windows.")
            }
        } else {
            ContentUnavailableView {
                Label("Not Signed In", systemImage: "person.crop.circle.badge.xmark")
            } description: {
                Text("Sign in from the Crew window.")
            } actions: {
                Button("Show Crew Window") { openWindow(id: "main") }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if connection.state == .connected {
            Text("\(Image(systemName: "checkmark.circle.fill")) Connected").foregroundStyle(.green)
        } else if connection.state == .connecting {
            Text("Connecting…").foregroundStyle(.secondary)
        } else {
            Text("\(Image(systemName: "wifi.exclamationmark")) Can't reach server").foregroundStyle(.orange)
        }
    }
}
#endif
