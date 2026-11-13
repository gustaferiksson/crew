import AppIntents
import SwiftUI
import WidgetKit

struct PinnedCardConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Pinned Card"
    static let description = IntentDescription("Shows a bot's pinned card.")

    @Parameter(title: "Bot")
    var bot: BotEntity?
}

struct PinnedCardEntry: TimelineEntry {
    let date: Date
    let content: PinnedWidgetContent
}

struct PinnedCardProvider: AppIntentTimelineProvider {
    private let sample = PinnedWidgetContent.bot(
        VoiceBot(name: "chef", title: "Chef", session: nil, lastActive: nil, shape: "blob", color: "#f97316", expression: "happy", hidden: false),
        PinnedGlance(surface: "groceries", title: String(localized: "Groceries"), subtitle: nil, symbol: "cart", tone: "success", progress: .init(done: 2, total: 6))
    )

    func placeholder(in context: Context) -> PinnedCardEntry {
        PinnedCardEntry(date: .now, content: sample)
    }

    func snapshot(for configuration: PinnedCardConfiguration, in context: Context) async -> PinnedCardEntry {
        let entry = entry(for: configuration)
        guard context.isPreview else { return entry }
        return PinnedCardEntry(date: .now, content: sample)
    }

    func timeline(for configuration: PinnedCardConfiguration, in context: Context) async -> Timeline<PinnedCardEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: PinnedCardConfiguration) -> PinnedCardEntry {
        PinnedCardEntry(date: .now, content: PinnedWidgetContent(bot: configuration.bot?.id, bots: VoiceBot.cached(), glances: PinnedGlance.saved(at: PinnedGlance.fileURL)))
    }
}

struct PinnedCardWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: PinnedGlance.widgetKind, intent: PinnedCardConfiguration.self, provider: PinnedCardProvider()) { entry in
            PinnedCardWidgetView(content: entry.content)
        }
        .configurationDisplayName("Pinned Card")
        .description("A bot's pinned card, like a shopping list or a recipe.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct PinnedCardWidgetView: View {
    let content: PinnedWidgetContent

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: PinnedCardRectangular(content: content)
            case .accessoryCircular: PinnedCardCircular(content: content)
            case .accessoryInline: PinnedCardInline(content: content)
            default: PinnedCardSmall(content: content)
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(content.url)
    }
}
