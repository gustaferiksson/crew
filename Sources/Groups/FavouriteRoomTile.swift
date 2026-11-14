import SwiftUI

struct FavouriteRoomTile: View {
    let room: Room
    let size: CGFloat
    let isSelected: Bool
    @Environment(BotStore.self) private var store
    @Environment(ChatDrafts.self) private var drafts

    private var hasDraft: Bool {
        !isSelected && drafts.preview(for: room.selectionID) != nil
    }

    var body: some View {
        VStack(spacing: 4) {
            GroupAvatar(members: room.members.compactMap { member in store.bots.first { $0.name == member.profile } }, size: size)
            Text(room.name)
                .font(.caption)
                .lineLimit(1)
            Group {
                if hasDraft {
                    Text("Draft").foregroundStyle(.red)
                } else {
                    Text("^[\(room.members.count) member](inflect: true)").fontWeight(.regular).foregroundStyle(.secondary)
                }
            }
            .font(.caption2.weight(.medium))
            .lineLimit(1)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.fill.quaternary.opacity(isSelected ? 1 : 0), in: .rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: room.name))
        .accessibilityValue(hasDraft ? Text("Draft") : Text(verbatim: ""))
    }
}
