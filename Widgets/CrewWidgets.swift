import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct CrewWidgets: WidgetBundle {
    var body: some Widget {
        TalkControl()
        VoiceActivity()
    }
}

struct TalkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "dev.gustaf.crew.talk", intent: TalkControlConfiguration.self) { configuration in
            ControlWidgetButton(action: TalkToBotIntent(bot: configuration.bot)) {
                Label(configuration.bot?.title ?? String(localized: "Talk to Bot"), systemImage: "waveform")
            }
        }
        .displayName("Talk to Bot")
        .description("Record a voice message and send it to a bot.")
    }
}

struct VoiceActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceAttributes.self) { context in
            VoiceActivityView(attributes: context.attributes, state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VoiceAvatar(bot: context.attributes.bot, size: 44)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.bot.title)
                            .font(.headline)
                        VoiceStatus(attributes: context.attributes, state: context.state)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VoiceControls(phase: context.state.phase)
                }
            } compactLeading: {
                VoiceAvatar(bot: context.attributes.bot, size: 24)
            } compactTrailing: {
                VoicePhaseSymbol(phase: context.state.phase)
            } minimal: {
                VoiceAvatar(bot: context.attributes.bot, size: 24)
            }
        }
    }
}
