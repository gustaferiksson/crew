import SwiftUI

struct LoginView: View {
    @Environment(Connection.self) private var connection
    @AppStorage("server") private var server = ""
    @AppStorage("username") private var username = ""
    @State private var password = ""
    @State private var isSigningIn = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Server") {
                    TextField("Server", text: $server, prompt: Text("hermes.example.com"))
                        .textContentType(.URL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .labelsHidden()
                }
                LabeledContent("Username") {
                    TextField("Username", text: $username, prompt: Text("Required"))
                        .textContentType(.username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .labelsHidden()
                }
                LabeledContent("Password") {
                    SecureField("Password", text: $password, prompt: Text("Required"))
                        .textContentType(.password)
                        .labelsHidden()
                }
            } header: {
                VStack(spacing: 8) {
                    AvatarView(shape: .blob, color: "#ec4899", expression: .attentive, seed: "crew", size: 64)
                    Text("Crew")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.primary)
                    Text("Sign in to your Hermes server.")
                        .font(.body)
                        .foregroundStyle(Color.secondary)
                }
                .textCase(nil)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            } footer: {
                VStack(alignment: .leading, spacing: 16) {
                    if case .unreachable = connection.signInError, let error = connection.signInError {
                        Label(error.localizedDescription, systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.orange)
                    } else if let error = connection.signInError {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    Button {
                        Task { await signIn() }
                    } label: {
                        Text(isSigningIn ? "Signing In…" : "Sign In")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(isSigningIn || server.isEmpty || username.isEmpty || password.isEmpty)
                }
                .padding(.top, 8)
            }
        }
        .formStyle(.grouped)
        .defaultScrollAnchor(.center)
        .scrollEdgeEffectHidden(true, for: .top)
        #if os(macOS)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
        .onSubmit { Task { await signIn() } }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func signIn() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        await connection.signIn(server: server, username: username, password: password)
        isSigningIn = false
        if connection.state != .signedOut { password = "" }
    }
}
