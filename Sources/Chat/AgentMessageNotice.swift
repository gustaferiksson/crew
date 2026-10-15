import SwiftUI

struct AgentMessageNotice: View {
    let message: AgentMessage

    @Environment(BotStore.self) private var bots
    @State private var isExpanded = false

    var body: some View {
        let bot = bots.bots.first { $0.name == message.handle }
        VStack(spacing: 8) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    if let bot {
                        BotAvatar(bot: bot, status: .idle, photo: bots.photos[bot.id], size: 16)
                    }
                    Text("Message from \(bot?.title ?? message.sender)")
                    if !message.body.isEmpty {
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(message.body.isEmpty)
            if isExpanded {
                Text(message.body)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    #if os(macOS)
                    .textSelection(.enabled)
                    #endif
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 560, alignment: .leading)
                    .background(.fill.quaternary, in: .rect(cornerRadius: 12))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}
