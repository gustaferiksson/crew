import SwiftUI

#if os(macOS)
let rowAvatarSize: CGFloat = 40
let rowPadding: CGFloat = 14
let dotGutter: CGFloat = 10
nonisolated let compactRowWidth: CGFloat = 260
private let badgeSize: CGFloat = 12
#else
let rowAvatarSize: CGFloat = 52
let rowPadding: CGFloat = 8
let dotGutter: CGFloat = 12
nonisolated let compactRowWidth: CGFloat = 300
private let badgeSize: CGFloat = 14
#endif

struct BotRow: View {
    let bot: Bot
    let photo: Image?
    let isOpen: Bool
    let isCompact: Bool
    @Environment(\.displayScale) private var displayScale
    @Environment(BotStore.self) private var store
    @Environment(ChatSessions.self) private var chats
    @Environment(ChatDrafts.self) private var drafts

    var body: some View {
        let summary = chats.summary(of: bot, in: store)
        if isCompact {
            row(summary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: [bot.title, bot.role].compactMap { $0 }.joined(separator: ", ")))
                .accessibilityValue(Text(verbatim: [statusText(summary.status), isOpen ? nil : drafts.preview(for: bot.id).map { _ in String(localized: "Draft") }].compactMap { $0 }.joined(separator: ", ")))
        } else {
            row(summary)
        }
    }

    private func row(_ summary: BotSummary) -> some View {
        let status = summary.status
        return HStack(spacing: 0) {
            Circle()
                .fill(.tint)
                .frame(width: 8, height: 8)
                .opacity(status == .unread ? 1 : 0)
                .frame(width: dotGutter)
                .accessibilityLabel("Unread")
                .accessibilityHidden(status != .unread)
            avatar(status)
                .padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 0) {
                if isCompact {
                    Text(bot.title)
                        .font(.headline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: rowAvatarSize, alignment: .leading)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Group {
                            if let role = bot.role {
                                Text("\(bot.title)\(Text(verbatim: " · \(role)").font(.subheadline).fontWeight(.regular).foregroundStyle(.secondary))")
                                    .accessibilityLabel(Text(verbatim: "\(bot.title), \(role)"))
                            } else {
                                Text(bot.title)
                            }
                        }
                        .font(.headline)
                        .lineLimit(1)
                        Spacer(minLength: 4)
                        trailingLabel(summary)
                            .font(.subheadline)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Group {
                        if !isOpen, let draft = drafts.preview(for: bot.id) {
                            Text("\(Text("Draft:").foregroundStyle(.red)) \(draft)")
                        } else {
                            Text(summary.preview.isEmpty ? bot.description ?? "" : summary.preview)
                        }
                    }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            #if os(macOS)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.separator)
                    .frame(height: 1 / displayScale)
                    .padding(.trailing, -12)
                    .offset(y: rowPadding)
            }
            #endif
        }
    }

    private func avatar(_ status: BotStatus) -> some View {
        let badge: (symbol: String, color: Color)? = if !isCompact {
            nil
        } else if case .waiting = status {
            ("exclamationmark", .orange)
        } else if status == .working {
            ("ellipsis", .green)
        } else if status == .failed {
            ("xmark", .red)
        } else {
            nil
        }
        return BotAvatar(bot: bot, status: status, photo: photo, size: rowAvatarSize)
            .mask {
                Rectangle()
                    .overlay(alignment: .bottomTrailing) {
                        if badge != nil {
                            Circle()
                                .frame(width: badgeSize + 4, height: badgeSize + 4)
                                .offset(x: 2, y: 2)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
            }
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    Image(systemName: badge.symbol)
                        .font(.system(size: badgeSize * 0.55, weight: .heavy))
                        .symbolEffect(.variableColor.iterative, isActive: status == .working)
                        .foregroundStyle(.white)
                        .frame(width: badgeSize, height: badgeSize)
                        .background(badge.color, in: .circle)
                }
            }
    }

    private func statusText(_ status: BotStatus) -> String? {
        if case .waiting(let kind) = status {
            return kind == .payment ? String(localized: "Wants to pay") : kind == .approval ? String(localized: "Needs approval") : String(localized: "Waiting for you")
        }
        if status == .working { return String(localized: "Working") }
        if status == .failed { return String(localized: "Failed") }
        if status == .unread { return String(localized: "Unread") }
        return nil
    }

    @ViewBuilder
    private func trailingLabel(_ summary: BotSummary) -> some View {
        if case .waiting(let kind) = summary.status {
            Text(verbatim: statusText(.waiting(kind)) ?? "")
                .foregroundStyle(.orange)
        } else if summary.status == .working {
            Label("Working", systemImage: "ellipsis")
                .symbolEffect(.variableColor.iterative)
                .foregroundStyle(.green)
        } else if summary.status == .failed {
            Text("Failed")
                .foregroundStyle(.red)
        } else if let date = summary.time {
            Text(date.rowLabel)
                .foregroundStyle(.secondary)
        }
    }
}

extension Date {
    var rowLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(self) { return String(localized: "Yesterday") }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: self), to: calendar.startOfDay(for: .now)).day ?? .max
        if days < 7 { return formatted(.dateTime.weekday(.wide)) }
        if calendar.isDate(self, equalTo: .now, toGranularity: .year) { return formatted(.dateTime.day().month(.abbreviated)) }
        return formatted(.dateTime.day().month(.abbreviated).year())
    }
}
