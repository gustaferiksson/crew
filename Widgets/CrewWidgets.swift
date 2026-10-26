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
        .description("Record a voice message for a bot. Press again to send it.")
    }
}

struct VoiceActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceAttributes.self) { context in
            VoiceActivityView(attributes: context.attributes, state: context.state)
                .widgetURL(context.attributes.bot.chatURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VoiceAvatar(bot: context.attributes.bot, size: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VoiceExpandedTrailing(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VoiceExpandedBottom(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                VoiceAvatar(bot: context.attributes.bot, size: 24)
            } compactTrailing: {
                VoiceCompactTrailing(attributes: context.attributes, state: context.state)
            } minimal: {
                VoiceMinimal(attributes: context.attributes, state: context.state)
            }
            .widgetURL(context.attributes.bot.chatURL)
        }
    }
}
