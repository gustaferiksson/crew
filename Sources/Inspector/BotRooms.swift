import SwiftUI

struct BotRooms: View {
    let bot: Bot
    @Binding var isPresented: Bool
    let select: ((String) -> Void)?

    @Environment(BotStore.self) private var bots
    @Environment(GroupStore.self) private var groups

    var body: some View {
        let rooms = groups.rooms(with: bot)
        if !rooms.isEmpty {
            Section("Rooms") {
                ForEach(rooms) { room in
                    if let select {
                        Button {
                            isPresented = false
                            select(room.selectionID)
                        } label: {
                            row(room)
                        }
                        #if os(macOS)
                        .buttonStyle(.plain)
                        #else
                        .tint(.primary)
                        #endif
                    } else {
                        row(room)
                    }
                }
            }
        }
    }

    private func row(_ room: Room) -> some View {
        let others = room.members.filter { $0.isPeer || $0.profile != bot.name }
            .map { member in bots.bots.first { $0.name == member.profile }?.title ?? member.displayName ?? member.memberID }
            .formatted(.list(type: .and))
        return HStack(spacing: 12) {
            GroupAvatar(members: room.members.compactMap { member in bots.bots.first { $0.name == member.profile } }, size: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(room.name)
                    .lineLimit(1)
                Text("with \(others)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(macOS)
            if select != nil {
                Image(systemName: "chevron.forward")
                    .foregroundStyle(.tertiary)
            }
            #endif
        }
        .contentShape(.rect)
        .accessibilityElement()
        .accessibilityLabel(room.name)
        .accessibilityValue(Text("with \(others)"))
    }
}
