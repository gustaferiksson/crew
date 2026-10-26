#if os(iOS)
import SwiftUI

struct VoiceIndicator: View {
    let voice: VoiceMessage

    var body: some View {
        if let attributes = voice.attributes {
            HStack(spacing: 12) {
                Link(destination: attributes.bot.chatURL) {
                    HStack(spacing: 12) {
                        VoiceAvatar(bot: attributes.bot, size: 36)
                        VoiceSummary(attributes: attributes, state: voice.state)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the chat.")
                VoiceButtons(phase: voice.state.phase)
            }
            .padding(8)
            .padding(.leading, 4)
            .glassEffect(.regular, in: .capsule)
            .frame(maxWidth: 560)
            .padding(.horizontal, 16)
            .animation(.smooth, value: voice.state)
        }
    }
}
#endif
