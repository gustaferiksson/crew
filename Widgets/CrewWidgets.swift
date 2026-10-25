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
                Label(configuration.bot?.title ?? String(localized: "Talk to Bot"), systemImage: "phone.fill")
            }
        }
        .displayName("Talk to Bot")
        .description("Start a voice call with a bot. Press again to end it.")
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
                    VoiceCallSummary(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VoiceEndButton()
                }
            } compactLeading: {
                VoiceAvatar(bot: context.attributes.bot, size: 24)
            } compactTrailing: {
                VoiceCompactTrailing(attributes: context.attributes, state: context.state)
            } minimal: {
                VoiceAvatar(bot: context.attributes.bot, size: 24)
            }
        }
    }
}
