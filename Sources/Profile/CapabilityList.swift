import SwiftUI

enum CapabilityKind: String, CaseIterable, Identifiable {
    case skills, toolsets, mcpServers

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .skills: "Skills"
        case .toolsets: "Toolsets"
        case .mcpServers: "MCP Servers"
        }
    }

    var systemImage: String {
        switch self {
        case .skills: "sparkles"
        case .toolsets: "wrench.and.screwdriver"
        case .mcpServers: "server.rack"
        }
    }

    var items: WritableKeyPath<ProfileDraft.Fields, [ProfileCapability]> {
        switch self {
        case .skills: \.skills
        case .toolsets: \.toolsets
        case .mcpServers: \.mcpServers
        }
    }
}

struct CapabilityList: View {
    let kind: CapabilityKind
    @Binding var items: [ProfileCapability]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List($items) { $item in
                let detail = [item.description, item.transport].compactMap { $0 }.first { !$0.isEmpty }
                Toggle(isOn: $item.enabled) {
                    Text(item.label ?? item.name)
                    if let detail {
                        Text(detail)
                    }
                }
                .toggleStyle(.switch)
                .disabled(kind == .toolsets && item.enabled && items.filter(\.enabled).count == 1)
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text(kind.title)
                        } icon: {
                            Image(systemName: kind.systemImage)
                        }
                    } description: {
                        Text("This profile has none configured.")
                    }
                }
            }
            .navigationTitle(kind.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 480)
        #endif
    }
}
