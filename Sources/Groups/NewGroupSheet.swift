import SwiftUI

struct NewGroupSheet: View {
    let onCreated: (Room) -> Void

    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var store
    @Environment(GroupStore.self) private var groups
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var picked: [Bot.ID] = []
    @State private var isCreating = false
    @State private var failure: String?

    private var members: [Bot] {
        picked.compactMap { id in store.bots.first { $0.id == id } }
    }

    private var resolvedName: String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((typed.isEmpty ? members.map(\.title).formatted(.list(type: .and)) : typed).prefix(200))
    }

    private var canCreate: Bool {
        (2...6).contains(members.count) && !isCreating && connection.state == .connected
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        GroupAvatar(members: members, size: 96)
                        Text(resolvedName.isEmpty ? String(localized: "New Group") : resolvedName)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                if let failure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                    }
                }
                Section("Name") {
                    TextField("Name", text: $name, prompt: Text(resolvedName.isEmpty ? String(localized: "Group Name") : resolvedName))
                }
                Section {
                    ForEach(store.bots.filter { $0.meta.hidden != true }) { bot in
                        let isPicked = picked.contains(bot.id)
                        Button {
                            if isPicked { picked.removeAll { $0 == bot.id } } else { picked.append(bot.id) }
                        } label: {
                            HStack(spacing: 12) {
                                BotAvatar(bot: bot, status: .idle, photo: store.photos[bot.id], size: 28)
                                Text(bot.title)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isPicked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                    .font(.title3)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isPicked && (picked.count >= 6 || bot.name.contains("_")))
                    }
                } header: {
                    Text("Members")
                } footer: {
                    Text("Pick 2 to 6 bots. Members can't change after the group is created.")
                }
            }
            .formStyle(.grouped)
            .disabled(isCreating)
            .navigationTitle("New Group")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Create", role: .confirm) { Task { await create() } }
                            .disabled(!canCreate)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isCreating)
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 600)
        #endif
    }

    private func create() async {
        guard let gateway = connection.gateway, canCreate else { return }
        isCreating = true
        defer { isCreating = false }
        failure = nil
        do {
            onCreated(try await groups.create(named: resolvedName, with: members, via: gateway))
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
