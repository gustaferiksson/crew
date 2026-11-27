import SwiftUI

struct BotExchangeGroup<Row: View>: View {
    let id: String
    let turns: [Turn]
    let reveal: CGFloat
    let timestampWidth: CGFloat
    @ViewBuilder let row: (Turn) -> Row

    @Environment(BotStore.self) private var bots
    @Environment(\.transcriptExpansion) private var expansion

    private var isExpanded: Bool { expansion?.turns.contains(id) == true }

    private var participants: [(handle: String, name: String, bot: Bot?)] {
        let messages = turns.compactMap(\.agentMessage)
        return messages.reduce(into: [(handle: String, name: String, bot: Bot?)]()) { found, message in
            guard !found.contains(where: { $0.handle == message.handle }) else { return }
            let bot = bots.bots.first { $0.name == message.handle }
            found.append((message.handle, bot?.title ?? message.sender, bot))
        }
    }

    var body: some View {
        let participants = participants
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withTransaction(.disclosure(.snappy)) { expansion?.turns.formSymmetricDifference([id]) }
            } label: {
                HStack(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(participants, id: \.handle) { participant in
                            if let bot = participant.bot {
                                BotAvatar(bot: bot, status: nil, photo: bots.photos[bot.id], size: 16)
                            }
                        }
                    }
                    .padding(.trailing, 4)
                    Text("^[\(turns.count) message](inflect: true) with \(participants.map(\.name).formatted(.list(type: .and)))")
                        .phaseAnimator(turns.contains { $0.status == .streaming } ? [1, 0.6] : [1]) { content, opacity in
                            content.opacity(opacity)
                        } animation: { _ in
                            .easeInOut(duration: 1)
                        }
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
            .modifier(Timestamp(date: turns[0].startedAt, reveal: reveal, width: timestampWidth))
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(turns) { row($0) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }
}
