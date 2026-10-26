import SwiftUI

#if os(macOS)
let rowAvatarSize: CGFloat = 40
let rowPadding: CGFloat = 14
let dotGutter: CGFloat = 10
private let badgeSize: CGFloat = 13
#else
let rowAvatarSize: CGFloat = 52
let rowPadding: CGFloat = 8
let dotGutter: CGFloat = 12
private let badgeSize: CGFloat = 14
#endif
nonisolated let stripWidth: CGFloat = 98
nonisolated let stripThreshold: CGFloat = 240
nonisolated let stripTileSize = CGSize(width: 78, height: 86)

struct BotRow: View {
    let bot: Bot
    let photo: Image?
    let isOpen: Bool
    @Environment(\.displayScale) private var displayScale
    @Environment(BotStore.self) private var store
    @Environment(ChatSessions.self) private var chats
    @Environment(ChatDrafts.self) private var drafts

    var body: some View {
        let summary = chats.summary(of: bot, in: store)
        let status = summary.status
        HStack(spacing: 0) {
            Circle()
                .fill(.tint)
                .frame(width: 8, height: 8)
                .opacity(status == .unread ? 1 : 0)
                .frame(width: dotGutter)
                .accessibilityLabel("Unread")
                .accessibilityHidden(status != .unread)
            BotAvatar(bot: bot, status: status, photo: photo, size: rowAvatarSize)
                .padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 0) {
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

    @ViewBuilder
    private func trailingLabel(_ summary: BotSummary) -> some View {
        if case .waiting(let kind) = summary.status {
            Text(verbatim: BotStatus.waiting(kind).label ?? "")
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

extension BotStatus {
    var label: String? {
        if case .waiting(let kind) = self {
            return kind == .payment ? String(localized: "Wants to pay") : kind == .approval ? String(localized: "Needs approval") : String(localized: "Waiting for you")
        }
        if self == .working { return String(localized: "Working") }
        if self == .failed { return String(localized: "Failed") }
        if self == .unread { return String(localized: "Unread") }
        return nil
    }
}

struct StripTile<Avatar: View>: View {
    let name: String
    @ViewBuilder let avatar: Avatar

    var body: some View {
        VStack(spacing: 6) {
            avatar
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.top, 15)
        .padding(.horizontal, 4)
        .frame(width: stripTileSize.width, height: stripTileSize.height, alignment: .top)
        .frame(minWidth: 0, maxWidth: .infinity)
    }
}

struct BotStripTile: View {
    let bot: Bot
    let photo: Image?
    let isOpen: Bool
    @Environment(BotStore.self) private var store
    @Environment(ChatSessions.self) private var chats
    @Environment(ChatDrafts.self) private var drafts

    var body: some View {
        let status = chats.status(of: bot.id, in: store)
        let badge: (symbol: String, color: Color)? = if case .waiting = status {
            ("exclamationmark", .orange)
        } else if status == .working {
            ("ellipsis", .green)
        } else if status == .failed {
            ("xmark", .red)
        } else {
            nil
        }
        StripTile(name: bot.title) {
            BotAvatar(bot: bot, status: status, photo: photo, size: rowAvatarSize)
                .mask {
                    ZStack(alignment: .bottomTrailing) {
                        Rectangle()
                            .padding(-rowAvatarSize / 4)
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
                            .font(.system(size: badgeSize * 0.6, weight: .heavy))
                            .symbolEffect(.variableColor.iterative, isActive: status == .working)
                            .foregroundStyle(.white)
                            .frame(width: badgeSize, height: badgeSize)
                            .background(badge.color, in: .circle)
                    }
                }
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(.tint)
                        .frame(width: 8, height: 8)
                        .opacity(status == .unread ? 1 : 0)
                        .offset(x: -dotGutter / 2 - 4)
                }
        }
        .help([bot.title, bot.role].compactMap { $0 }.joined(separator: " · "))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [bot.title, bot.role].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityValue(Text(verbatim: [status.label, isOpen ? nil : drafts.preview(for: bot.id).map { _ in String(localized: "Draft") }].compactMap { $0 }.joined(separator: ", ")))
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
