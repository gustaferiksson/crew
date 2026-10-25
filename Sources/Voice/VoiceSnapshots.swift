#if os(iOS)
import SwiftUI

struct VoiceActivityFixture: View {
    private let attributes = VoiceAttributes(
        bot: VoiceBot(name: "vera", title: "Vera", session: nil, lastActive: nil, shape: "blob", color: "#8b5cf6", expression: "happy", hidden: false),
        startedAt: .now.addingTimeInterval(-14)
    )
    private let states: [VoiceAttributes.ContentState] = [
        .init(phase: .listening),
        .init(phase: .sending),
        .init(phase: .sent),
        .init(phase: .failed, failure: String(localized: "Couldn't send. It's saved as a draft.")),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(states, id: \.self) { state in
                    VoiceActivityView(attributes: attributes, state: state)
                        .background(.regularMaterial, in: .rect(cornerRadius: 24))
                }
                ForEach(states, id: \.self) { state in
                    HStack {
                        VoiceAvatar(bot: attributes.bot, size: 24)
                        Spacer()
                        VoicePhaseSymbol(phase: state.phase)
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 250, height: 37)
                    .background(.black, in: .capsule)
                    .environment(\.colorScheme, .dark)
                }
            }
            .padding()
        }
    }
}
#endif
