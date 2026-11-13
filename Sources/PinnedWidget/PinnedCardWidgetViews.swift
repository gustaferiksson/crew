#if os(iOS)
import SwiftUI
import WidgetKit

struct PinnedCardSmall: View {
    let content: PinnedWidgetContent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Image(systemName: content.symbol)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                    .widgetAccentable()
                    .frame(width: 44, height: 44)
                    .background((content.glance.map { crewTones[$0.tone ?? ""] ?? .accentColor } ?? .gray).gradient, in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if case .bot(let bot, _) = content {
                    VoiceAvatar(bot: bot, size: 24)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 8)
            Text(content.title)
                .font(.headline)
                .lineLimit(3)
                .privacySensitive(content.glance != nil)
            if let progress = content.glance?.progress {
                Text("\(progress.done) of \(progress.total)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .privacySensitive()
            }
            if let detail = content.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct PinnedCardRectangular: View {
    let content: PinnedWidgetContent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: content.symbol)
                    .widgetAccentable()
                    .accessibilityHidden(true)
                Text(content.title)
                    .privacySensitive(content.glance != nil)
            }
            .font(.headline)
            .lineLimit(1)
            if let progress = content.glance?.progress {
                Text("\(progress.done) of \(progress.total)")
                    .monospacedDigit()
                    .privacySensitive()
            } else if let subtitle = content.glance?.subtitle {
                Text(subtitle)
                    .lineLimit(1)
                    .privacySensitive()
            }
            if let detail = content.detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PinnedCardCircular: View {
    let content: PinnedWidgetContent

    var body: some View {
        if let progress = content.glance?.progress {
            Gauge(value: Double(progress.done), in: 0...Double(max(progress.total, 1))) {
                Text(content.title)
            } currentValueLabel: {
                VStack(spacing: 0) {
                    Image(systemName: content.symbol)
                        .font(.caption)
                        .widgetAccentable()
                    Text(progress.done, format: .number)
                        .monospacedDigit()
                        .privacySensitive()
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityValue(Text("\(progress.done) of \(progress.total) done"))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: content.symbol)
                    .font(.title2)
                    .widgetAccentable()
            }
            .accessibilityElement()
            .accessibilityLabel(content.title)
        }
    }
}

struct PinnedCardInline: View {
    let content: PinnedWidgetContent

    var body: some View {
        if let progress = content.glance?.progress {
            Label("\(content.title) \(progress.done) of \(progress.total)", systemImage: content.symbol)
                .privacySensitive()
        } else {
            Label(content.title, systemImage: content.symbol)
                .privacySensitive(content.glance != nil)
        }
    }
}
#endif
