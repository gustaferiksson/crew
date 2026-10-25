#if os(iOS)
import ActivityKit
import AppIntents
import ImageIO
import SwiftUI

nonisolated struct BotEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bot"
    static let defaultQuery = BotEntityQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

nonisolated struct BotEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BotEntity] {
        VoiceBot.cached().filter { identifiers.contains($0.name) }.map { BotEntity(id: $0.name, title: $0.title) }
    }

    func suggestedEntities() async throws -> [BotEntity] {
        VoiceBot.cached().filter { !$0.hidden }.map { BotEntity(id: $0.name, title: $0.title) }
    }
}

nonisolated struct VoiceAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Sendable {
            case connecting, listening, thinking, speaking, failed
        }

        let phase: Phase
        var failure: String?
    }

    let bot: VoiceBot
    let startedAt: Date
}

struct TalkToBotIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Talk to Bot"
    static let description = IntentDescription("Starts a voice call with a bot, or ends the call in progress.")
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "Bot")
    var bot: BotEntity?

    init() {}

    init(bot: BotEntity?) {
        self.bot = bot
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        switch await VoiceCall.shared.toggle(bot?.id) {
        case .started:
            break
        case .needsPermission:
            try await continueInForeground("Crew needs the microphone for calls.")
            _ = await VoiceCall.shared.toggle(bot?.id)
        case .needsCrew(let reason):
            throw needsToContinueInForegroundError(IntentDialog(stringLiteral: reason))
        case .failed(let reason):
            throw VoiceFailure(errorDescription: reason)
        }
        #endif
        return .result()
    }
}

nonisolated struct EndVoiceCallIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End Voice Call"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await VoiceCall.shared.end()
        #endif
        return .result()
    }
}

struct TalkControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Talk to Bot"

    @Parameter(title: "Bot")
    var bot: BotEntity?
}

struct VoiceAvatar: View {
    let bot: VoiceBot
    let size: CGFloat

    var body: some View {
        AvatarView(shape: .resolve(bot.shape), color: bot.color, expression: .resolve(bot.expression), photo: photo, seed: bot.name, size: size)
    }

    private var photo: Image? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 120] as CFDictionary
        guard let url = VoiceBot.photoDirectory?.appending(path: bot.name),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return Image(decorative: image, scale: 1)
    }
}

struct VoiceTimer: View {
    let attributes: VoiceAttributes

    var body: some View {
        Text(timerInterval: attributes.startedAt...Date.distantFuture, countsDown: false)
            .monospacedDigit()
    }
}

struct VoiceStatus: View {
    let state: VoiceAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .connecting:
            Text("Connecting…")
        case .listening:
            Text("Listening")
        case .thinking:
            Text("Thinking…")
        case .speaking:
            Text("Speaking")
        case .failed:
            Text(state.failure ?? String(localized: "The call ended."))
                .foregroundStyle(.red)
        }
    }
}

struct VoiceEndButton: View {
    var body: some View {
        Button(intent: EndVoiceCallIntent()) {
            Label("End", systemImage: "xmark")
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(.red)
    }
}

struct VoiceCallSummary: View {
    let attributes: VoiceAttributes
    let state: VoiceAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(attributes.bot.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 4) {
                if state.phase != .failed {
                    VoiceTimer(attributes: attributes)
                    Text(verbatim: "·")
                }
                VoiceStatus(state: state)
                    .lineLimit(2)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VoiceActivityView: View {
    let attributes: VoiceAttributes
    let state: VoiceAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            VoiceAvatar(bot: attributes.bot, size: 44)
            VoiceCallSummary(attributes: attributes, state: state)
            VoiceEndButton()
        }
        .padding()
    }
}

struct VoiceCompactTrailing: View {
    let attributes: VoiceAttributes
    let state: VoiceAttributes.ContentState

    var body: some View {
        if state.phase == .failed {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        } else {
            VoiceTimer(attributes: attributes)
                .frame(width: 40)
                .foregroundStyle(.green)
        }
    }
}
#endif
