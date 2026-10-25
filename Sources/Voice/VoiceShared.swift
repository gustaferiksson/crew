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
            case listening, sending, sent, failed
        }

        let phase: Phase
        var failure: String?
    }

    let bot: VoiceBot
    let startedAt: Date
}

struct TalkToBotIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Talk to Bot"
    static let description = IntentDescription("Records a voice message and sends it to a bot's Bot Chat.")
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
        switch await VoiceMessage.shared.start(bot?.id) {
        case .started:
            break
        case .needsPermission:
            try await continueInForeground("Crew needs the microphone to record.")
            _ = await VoiceMessage.shared.start(bot?.id)
        case .needsCrew(let reason):
            throw needsToContinueInForegroundError(IntentDialog(stringLiteral: reason))
        case .failed(let reason):
            throw VoiceFailure(errorDescription: reason)
        }
        #endif
        return .result()
    }
}

nonisolated struct VoiceFailure: LocalizedError {
    let errorDescription: String?
}

nonisolated struct SendVoiceMessageIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Send Voice Message"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await VoiceMessage.shared.send()
        #endif
        return .result()
    }
}

nonisolated struct CancelVoiceMessageIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Cancel Voice Message"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await VoiceMessage.shared.cancel()
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

struct VoiceStatus: View {
    let attributes: VoiceAttributes
    let state: VoiceAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .listening:
            Text(timerInterval: attributes.startedAt...Date.distantFuture, countsDown: false)
                .monospacedDigit()
        case .sending:
            Text("Sending…")
        case .sent:
            Text("Sent to \(attributes.bot.title)")
        case .failed:
            Text(state.failure ?? String(localized: "Couldn't send"))
        }
    }
}

struct VoiceControls: View {
    let phase: VoiceAttributes.ContentState.Phase

    var body: some View {
        if phase == .listening {
            HStack {
                Button(intent: CancelVoiceMessageIntent()) {
                    Label("Cancel", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(intent: SendVoiceMessageIntent()) {
                    Label("Send", systemImage: "arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .buttonBorderShape(.capsule)
            .labelStyle(.titleAndIcon)
        }
    }
}

struct VoiceActivityView: View {
    let attributes: VoiceAttributes
    let state: VoiceAttributes.ContentState

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VoiceAvatar(bot: attributes.bot, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attributes.bot.title)
                        .font(.headline)
                    VoiceStatus(attributes: attributes, state: state)
                        .font(.subheadline)
                        .foregroundStyle(state.phase == .failed ? .red : .secondary)
                }
                Spacer(minLength: 0)
                VoicePhaseSymbol(phase: state.phase)
                    .font(.title2)
            }
            VoiceControls(phase: state.phase)
        }
        .padding()
    }
}

struct VoicePhaseSymbol: View {
    let phase: VoiceAttributes.ContentState.Phase

    var body: some View {
        switch phase {
        case .listening:
            Image(systemName: "waveform")
                .foregroundStyle(.red)
                .symbolEffect(.variableColor.iterative)
        case .sending:
            Image(systemName: "arrow.up.circle")
                .foregroundStyle(.secondary)
        case .sent:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
#endif
