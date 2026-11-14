import SwiftUI

struct PortraitSection: View {
    let draft: ProfileDraft
    @Bindable var portrait: PortraitGenerator

    @Environment(Connection.self) private var connection

    var body: some View {
        Section {
            TextField("Description", text: $portrait.description, prompt: Text("Describe the portrait"), axis: .vertical)
                .lineLimit(1...3)
                .labelsHidden()
                .disabled(portrait.isGenerating)
            if portrait.isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating…")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", action: portrait.cancel)
                        .buttonStyle(.borderless)
                }
            } else {
                Button("Generate Portrait", systemImage: "sparkles") {
                    guard let gateway = connection.gateway else { return }
                    portrait.generate(for: draft, via: gateway)
                }
                .disabled(connection.state != .connected)
            }
        } header: {
            Text("Portrait")
        } footer: {
            if let failure = portrait.failure {
                Text(failure)
                    .foregroundStyle(.red)
            } else {
                Text("Leave blank to use the bot's name and description.")
            }
        }
    }
}
