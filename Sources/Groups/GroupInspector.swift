import SwiftUI

struct GroupInspector: View {
    let room: Room
    @Binding var isPresented: Bool
    let select: (Bot.ID) -> Void

    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var bots
    @Environment(GroupStore.self) private var groups
    @State private var name: String
    @State private var isRenaming = false
    @State private var renameFailure: String?
    @State private var disbanding: Room?
    @State private var disbandFailure: String?
    @FocusState private var isEditingName: Bool

    init(room: Room, isPresented: Binding<Bool>, select: @escaping (Bot.ID) -> Void) {
        self.room = room
        _isPresented = isPresented
        self.select = select
        _name = State(initialValue: room.name)
    }

    private var members: [Bot] {
        room.members.compactMap { member in bots.bots.first { $0.name == member.profile } }
    }

    var body: some View {
        Form {
            Section {
            } header: {
                header
            }
            Section("Members") {
                ForEach(room.members, id: \.memberID) { memberRow($0) }
            }
            Section {
                Button("Disband Group", role: .destructive) { disbanding = room }
                    #if os(macOS)
                    .foregroundStyle(.red)
                    #endif
                    .disabled(connection.state != .connected)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 0, maxWidth: .infinity)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .contentMargins(.bottom, 24, for: .scrollIndicators)
        .toolbar {
            if isPresented {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { isPresented = false }
                }
            }
        }
        #endif
        .onChange(of: room.name) {
            if !isEditingName { name = room.name }
        }
        .onChange(of: isEditingName) {
            if !isEditingName { rename() }
        }
        .confirmationDialog(
            "Disband \(disbanding?.name ?? "")?",
            isPresented: Binding(get: { disbanding != nil }, set: { if !$0 { disbanding = nil } }),
            titleVisibility: .visible,
            presenting: disbanding
        ) { target in
            Button("Disband \(target.name)", role: .destructive) {
                Task { await disband(target) }
            }
        } message: { _ in
            Text("This permanently ends the group and its history for every app. The bots stay.")
        }
        .alert("Couldn't Disband Group", isPresented: Binding(get: { disbandFailure != nil }, set: { if !$0 { disbandFailure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(disbandFailure ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            GroupAvatar(members: members, size: 96)
            VStack(spacing: 4) {
                TextField("Name", text: $name, prompt: Text(room.name))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .focused($isEditingName)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.fill.quaternary.opacity(isEditingName ? 1 : 0), in: .rect(cornerRadius: 8))
                    .disabled(isRenaming || connection.state != .connected)
                    .onSubmit { isEditingName = false }
                renameStatus
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .textCase(nil)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var renameStatus: some View {
        if isRenaming {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Saving…")
            }
        } else if let renameFailure {
            Label(renameFailure, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .multilineTextAlignment(.center)
        } else {
            Text("\(room.members.count) members")
        }
    }

    @ViewBuilder
    private func memberRow(_ member: RoomMember) -> some View {
        let bot = bots.bots.first { $0.name == member.profile }
        Button {
            guard let bot else { return }
            isPresented = false
            select(bot.id)
        } label: {
            HStack(spacing: 12) {
                if let bot {
                    BotAvatar(bot: bot, status: .idle, photo: bots.photos[bot.id], size: 28)
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(bot?.title ?? member.displayName ?? member.memberID)
                        .foregroundStyle(.primary)
                    if let role = bot?.role {
                        Text(role)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
            }
            .contentShape(.rect)
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
        .disabled(bot == nil)
    }

    private func rename() {
        let typed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !typed.isEmpty, typed != room.name, let gateway = connection.gateway else {
            name = room.name
            return
        }
        isRenaming = true
        renameFailure = nil
        Task {
            defer { isRenaming = false }
            do {
                try await groups.rename(room, to: typed, via: gateway)
            } catch {
                name = room.name
                renameFailure = if case GatewayError.rpc(_, let message) = error { message } else { error.localizedDescription }
            }
        }
    }

    private func disband(_ target: Room) async {
        guard let gateway = connection.gateway else { return }
        do {
            try await groups.disband(target, via: gateway)
            isPresented = false
        } catch {
            disbandFailure = if case GatewayError.rpc(_, let message) = error { message } else { error.localizedDescription }
        }
    }
}
