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
    @State private var histories: [String: RoomHistory?] = [:]
    @State private var historiesLoaded = false
    @State private var isWorking = false
    @State private var compressing: String?
    @State private var confirmingCompress: RoomMember?
    @State private var compressResult: (title: String, message: String)?
    @FocusState private var isEditingName: Bool

    init(room: Room, isPresented: Binding<Bool>, histories: [String: RoomHistory?]? = nil, select: @escaping (Bot.ID) -> Void) {
        self.room = room
        _isPresented = isPresented
        self.select = select
        _name = State(initialValue: room.name)
        _histories = State(initialValue: histories ?? [:])
        _historiesLoaded = State(initialValue: histories != nil)
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
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .frame(minWidth: 0, maxWidth: .infinity)
        .contentMargins(.bottom, 24, for: .scrollIndicators)
        .toolbar {
            if isPresented {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { isPresented = false }
                }
            }
        }
        #endif
        .task(id: connection.state == .connected) { await loadHistories() }
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
        .confirmationDialog(
            "Compress \(confirmingCompress.map(memberName) ?? "")'s Room History?",
            isPresented: Binding(get: { confirmingCompress != nil }, set: { if !$0 { confirmingCompress = nil } }),
            titleVisibility: .visible,
            presenting: confirmingCompress
        ) { member in
            Button("Compress") { Task { await compress(member) } }
        } message: { member in
            Text("\(memberName(member)) replaces older room messages in its context with a summary. The room's transcript stays.")
        }
        .alert(compressResult?.title ?? "", isPresented: Binding(get: { compressResult != nil }, set: { if !$0 { compressResult = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(compressResult?.message ?? "")
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
                    if let role = bot?.role {
                        Text(role)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if compressing == member.profile {
                    ProgressView()
                        .controlSize(.small)
                } else if historiesLoaded, let label = roomHistoryLabel(bot == nil ? nil : histories[member.profile], isPeer: member.isPeer, isOnline: connection.state == .connected) {
                    Text(label)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                #if os(macOS)
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.tertiary)
                    .opacity(bot == nil ? 0 : 1)
                #endif
            }
            .contentShape(.rect)
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #else
        .tint(.primary)
        #endif
        .disabled(bot == nil)
        .swipeActions(edge: .trailing) {
            if canCompress(member) {
                Button("Compress") { confirmingCompress = member }
            }
        }
        .contextMenu {
            if canCompress(member) {
                Button("Compress Room History…", systemImage: "arrow.down.right.and.arrow.up.left") { confirmingCompress = member }
            }
        }
    }

    private func memberName(_ member: RoomMember) -> String {
        bots.bots.first { $0.name == member.profile }?.title ?? member.displayName ?? member.memberID
    }

    private func canCompress(_ member: RoomMember) -> Bool {
        let history = histories[member.profile] ?? nil
        return history != nil && !member.isPeer && !isWorking && compressing == nil && connection.state == .connected
    }

    private func loadHistories() async {
        guard let gateway = connection.gateway, connection.state == .connected else { return }
        isWorking = (try? await gateway.call("groups.state", ["room_id": room.id], as: RoomState.self))?.driverStatus?.working ?? false
        var loaded: [String: RoomHistory?] = [:]
        for member in room.members where !member.isPeer && bots.bots.contains(where: { $0.name == member.profile }) {
            do {
                loaded[member.profile] = .some(try await roomHistory(of: member.profile, in: room.id, via: gateway))
            } catch {
                continue
            }
        }
        histories = loaded
        historiesLoaded = true
    }

    private func compress(_ member: RoomMember) async {
        guard let gateway = connection.gateway, let history = histories[member.profile] ?? nil else { return }
        compressing = member.profile
        defer { compressing = nil }
        let name = memberName(member)
        let failed = String(localized: "Couldn't Compress Room History")
        do {
            let outcome = try await compressRoomHistory(history, of: member.profile, via: gateway)
            compressResult = switch outcome {
            case .compressed(let headline): (String(localized: "Room History Compressed"), headline)
            case .pending: (String(localized: "Still Compressing"), String(localized: "Hermes is finishing in the background. Check again in a minute."))
            case .busy: (failed, String(localized: "\(name) is busy right now. Try again when the room is quiet."))
            case .aborted(let note): (failed, note)
            }
        } catch {
            let message = if case GatewayError.rpc(_, let message) = error { message } else { error.localizedDescription }
            compressResult = (failed, message)
        }
        await loadHistories()
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
