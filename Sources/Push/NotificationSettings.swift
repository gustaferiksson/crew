import SwiftUI

struct NotificationSettings: View {
    @Environment(Connection.self) private var connection
    @Environment(PushCenter.self) private var push
    @Environment(\.dismiss) private var dismiss
    @State private var testResult: String?
    @State private var isSending = false

    var body: some View {
        @Bindable var push = push
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Status") {
                        Text("\(Image(systemName: push.isPushing ? "checkmark.circle.fill" : "exclamationmark.circle.fill")) \(statusTitle)")
                            .foregroundStyle(push.isPushing ? .green : .orange)
                    }
                    if [.notDetermined, .provisional].contains(push.authorization) {
                        Button("Allow Banners and Sounds") {
                            Task {
                                await push.authorize()
                                await push.register(on: connection)
                            }
                        }
                    }
                    Button("Send Test Notification") {
                        Task {
                            isSending = true
                            do {
                                try await push.sendTest(on: connection)
                                testResult = String(localized: "Sent. It should arrive in a few seconds.")
                            } catch {
                                testResult = error.localizedDescription
                            }
                            isSending = false
                        }
                    }
                    .disabled(!push.isPushing || isSending || connection.state != .connected)
                } footer: {
                    Text(testResult ?? statusDetail)
                }
                Section {
                    Toggle("Replies", isOn: $push.prefs.replies)
                    Toggle("Approvals", isOn: $push.prefs.approvals)
                    Toggle("Questions", isOn: $push.prefs.questions)
                    Toggle("Routines", isOn: $push.prefs.routines)
                    Toggle("Show Previews", isOn: $push.prefs.previews)
                } header: {
                    Text("Notify Me About")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Notifications")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
            .task {
                guard Snapshot.requested == nil else { return }
                await push.register(on: connection)
                await push.refreshPlugin(on: connection)
            }
            .onChange(of: push.prefs) {
                Task { await push.register(on: connection) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 480)
        #endif
    }

    private var statusTitle: String {
        if push.status == .notAuthorized { return String(localized: "Not allowed") }
        if push.status == .notInstalled { return String(localized: "Not set up on server") }
        if case .registered(let configured) = push.status { return configured ? String(localized: "Registered") : String(localized: "APNs key missing") }
        if case .unavailable = push.status { return String(localized: "Unavailable") }
        return String(localized: "Checking…")
    }

    private var statusDetail: String {
        let fallback = String(localized: "Until then, Crew notifies you while it's running.")
        if push.status == .notAuthorized { return String(localized: "Notifications are turned off for Crew in System Settings.") }
        if push.status == .notInstalled { return String(localized: "Install the crew-push plugin on \(connection.session?.server.host() ?? "the server") to get notifications when Crew is closed. \(fallback)") }
        if case .registered(false) = push.status { return String(localized: "The server has the plugin but no APNs key yet. \(fallback)") }
        if case .unavailable(let reason) = push.status { return "\(reason) \(fallback)" }
        guard push.isPushing, let plugin = push.plugin else { return "" }
        return String(localized: "crew-push \(plugin.pluginVersion) on \(connection.session?.server.host() ?? "the server"), \(plugin.devices) devices.")
    }
}
