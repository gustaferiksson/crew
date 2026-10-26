#if os(iOS)
import SwiftUI

struct VoiceActivityFixture: View {
    private let attributes = VoiceAttributes(
        bot: VoiceBot(name: "vera", title: "Vera", session: nil, lastActive: nil, shape: "blob", color: "#8b5cf6", expression: "happy", hidden: false),
        startedAt: .now.addingTimeInterval(-14)
    )
    private let states: [VoiceAttributes.ContentState] = [
        .init(phase: .recording),
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
                ForEach([states[0], states[3]], id: \.self) { state in
                    VStack(spacing: 8) {
                        HStack(alignment: .top) {
                            VoiceAvatar(bot: attributes.bot, size: 44)
                            Spacer()
                            Capsule()
                                .fill(.gray.opacity(0.3))
                                .frame(width: 126, height: 37)
                            Spacer()
                            VoiceExpandedTrailing(attributes: attributes, state: state)
                        }
                        VoiceExpandedBottom(attributes: attributes, state: state)
                    }
                    .padding(16)
                    .frame(width: 371)
                    .background(.black, in: .rect(cornerRadius: 44))
                    .environment(\.colorScheme, .dark)
                }
                ForEach(states, id: \.self) { state in
                    HStack(spacing: 8) {
                        HStack {
                            VoiceAvatar(bot: attributes.bot, size: 24)
                            Spacer()
                            VoiceCompactTrailing(attributes: attributes, state: state)
                        }
                        .padding(.horizontal, 12)
                        .frame(width: 230, height: 37)
                        .background(.black, in: .capsule)
                        VoiceMinimal(attributes: attributes, state: state)
                            .frame(width: 37, height: 37)
                            .background(.black, in: .circle)
                    }
                    .environment(\.colorScheme, .dark)
                }
            }
            .padding()
        }
    }
}
#endif
