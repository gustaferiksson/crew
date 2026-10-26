#if os(iOS)
import ActivityKit
import AppIntents
import AVFoundation
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
            case recording, sending, sent, failed
        }

        let phase: Phase
        var failure: String?
    }

    let bot: VoiceBot
    let startedAt: Date
}

struct TalkToBotIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Talk to Bot"
    static let description = IntentDescription("Records a voice message for a bot, or sends the one being recorded.")
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
        voiceLog.notice("TalkToBotIntent perform, mode: \(systemContext.currentMode.debugDescription, privacy: .public)")
        switch await VoiceMessage.shared.toggle(bot?.id) {
        case .started:
            break
        case .needsPermission:
            try await openCrew(String(localized: "Crew needs the microphone to record."))
            voiceLog.notice("in foreground, asking for the microphone")
            _ = await AVAudioApplication.requestRecordPermission()
            if case .failed(let reason) = await VoiceMessage.shared.toggle(bot?.id) {
                throw VoiceFailure(errorDescription: reason)
            }
        case .needsCrew(let reason):
            try await openCrew(reason)
        case .failed(let reason):
            throw VoiceFailure(errorDescription: reason)
        }
        #endif
        return .result()
    }

    #if !WIDGET_EXTENSION
    @MainActor
    private func openCrew(_ reason: String) async throws {
        do {
            try await continueInForeground(IntentDialog(stringLiteral: reason), alwaysConfirm: false)
        } catch {
            voiceLog.error("continue in foreground failed: \(error, privacy: .public)")
            VoiceMessage.shared.showFailure(reason, for: bot?.id)
            throw error
        }
    }
    #endif
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

struct VoiceTimer: View {
    let attributes: VoiceAttributes

    var body: some View {
        Text(timerInterval: attributes.startedAt...Date.distantFuture, countsDown: false)
            .monospacedDigit()
    }
}

struct VoiceStatus: View {
    let attributes: VoiceAttributes
    let state: VoiceAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .recording:
            HStack(spacing: 6) {
                VoiceWaveform()
                VoiceTimer(attributes: attributes)
            }
            .foregroundStyle(.red)
        case .sending:
            Text("Sending…")
        case .sent:
            Label("Sent", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Text(state.failure ?? String(localized: "Couldn't send."))
                .foregroundStyle(.red)
        }
    }
}

struct VoiceWaveform: View {
    var body: some View {
        Image(systemName: "waveform")
            .foregroundStyle(.red)
            .symbolEffect(.variableColor.iterative)
            .accessibilityLabel("Recording")
    }
}

struct VoiceButtons: View {
    let phase: VoiceAttributes.ContentState.Phase

    var body: some View {
        HStack(spacing: 12) {
            if phase == .recording || phase == .failed {
                Button(intent: CancelVoiceMessageIntent()) {
                    Label("Cancel", systemImage: "xmark")
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .background(.fill.secondary, in: .circle)
            }
            if phase == .recording {
                Button(intent: SendVoiceMessageIntent()) {
                    Label("Send", systemImage: "arrow.up")
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(.tint, in: .circle)
            }
        }
        .labelStyle(.iconOnly)
        .font(.title3.weight(.semibold))
    }
}

struct VoiceSummary: View {
    let attributes: VoiceAttributes
    let state: VoiceAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(attributes.bot.title)
                .font(.headline)
                .lineLimit(1)
            VoiceStatus(attributes: attributes, state: state)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
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
            VoiceSummary(attributes: attributes, state: state)
            VoiceButtons(phase: state.phase)
        }
        .padding(14)
    }
}

struct VoiceExpandedTrailing: View {
    let attributes: VoiceAttributes
    let state: VoiceAttributes.ContentState

    var body: some View {
        Group {
            if state.phase == .recording {
                VoiceStatus(attributes: attributes, state: state)
                    .foregroundStyle(.red)
                    .frame(width: 84, alignment: .trailing)
            } else {
                VoiceCompactTrailing(attributes: attributes, state: state)
            }
        }
        .font(.title3.weight(.semibold))
        .frame(height: 44)
    }
}

struct VoiceExpandedBottom: View {
    let attributes: VoiceAttributes
    let state: VoiceAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.bot.title)
                    .font(.headline)
                    .lineLimit(1)
                if state.phase != .recording {
                    VoiceStatus(attributes: attributes, state: state)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VoiceButtons(phase: state.phase)
        }
        .frame(minHeight: 44)
    }
}

struct VoiceCompactTrailing: View {
    let attributes: VoiceAttributes
    let state: VoiceAttributes.ContentState

    var body: some View {
        switch state.phase {
        case .recording:
            VoiceTimer(attributes: attributes)
                .frame(width: 40)
                .foregroundStyle(.red)
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

struct VoiceMinimal: View {
    let attributes: VoiceAttributes
    let state: VoiceAttributes.ContentState

    var body: some View {
        if state.phase == .recording {
            VoiceWaveform()
        } else {
            VoiceCompactTrailing(attributes: attributes, state: state)
        }
    }
}
#endif
