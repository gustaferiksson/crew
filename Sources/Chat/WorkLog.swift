import SwiftUI

private let toolStyles: [String: (verb: String, icon: String)] = [
    "terminal": ("Ran", "terminal"),
    "shell": ("Ran", "terminal"),
    "execute_code": ("Ran", "chevron.left.forwardslash.chevron.right"),
    "process": ("Checked", "gearshape.2"),
    "read_file": ("Read", "doc.text"),
    "write_file": ("Updated", "square.and.pencil"),
    "patch": ("Updated", "square.and.pencil"),
    "edit_file": ("Updated", "square.and.pencil"),
    "search_files": ("Searched", "magnifyingglass"),
    "web_search": ("Searched", "globe"),
    "web_extract": ("Read", "globe"),
    "browser_navigate": ("Opened", "safari"),
    "vision_analyze": ("Looked at", "eye"),
    "skill_view": ("Checked", "book.closed"),
    "skills_list": ("Checked", "book.closed"),
    "skill_manage": ("Updated", "book.closed"),
    "memory": ("Remembered", "brain.head.profile"),
    "session_search": ("Checked", "clock.arrow.trianglehead.counterclockwise.rotate.90"),
    "todo": ("Planned", "checklist"),
    "cronjob": ("Scheduled", "calendar.badge.clock"),
    "delegate_task": ("Delegated", "person.2"),
    "clarify": ("Asked", "questionmark.bubble"),
]

private let elapsedStyle = Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes, .seconds], width: .narrow)
private let collapsedRunLength = 4
private let visibleRunTail = 3

private enum LogEntry: Identifiable {
    case item(WorkItem)
    case hiddenTools(runID: String, count: Int)
    case showFewer(runID: String)

    var id: String {
        switch self {
        case .item(let item): item.id
        case .hiddenTools(let runID, _): "hidden-\(runID)"
        case .showFewer(let runID): "fewer-\(runID)"
        }
    }
}

private func logEntries(for work: [WorkItem], expandedRuns: Set<String>) -> [LogEntry] {
    let runs = work.reduce(into: [[WorkItem]]()) { runs, item in
        let isTool = if case .tool = item.kind { true } else { false }
        let lastIsTool = runs.last?.last.map { if case .tool = $0.kind { true } else { false } } ?? false
        if isTool && lastIsTool {
            runs[runs.count - 1].append(item)
        } else {
            runs.append([item])
        }
    }
    return runs.flatMap { run -> [LogEntry] in
        guard run.count > collapsedRunLength, let runID = run.first?.id else { return run.map(LogEntry.item) }
        if expandedRuns.contains(runID) { return [.showFewer(runID: runID)] + run.map(LogEntry.item) }
        return [.hiddenTools(runID: runID, count: run.count - visibleRunTail)] + run.suffix(visibleRunTail).map(LogEntry.item)
    }
}

struct WorkLog: View {
    let turn: Turn
    let activity: String?
    @Binding var expandedTurns: Set<Turn.ID>
    @Binding var expandedWork: Set<WorkItem.ID>
    @Binding var expandedRuns: Set<String>
    var stop: (() -> Void)?

    @Environment(BotStore.self) private var bots

    private var isLive: Bool { turn.status == .streaming }
    private var isExpanded: Bool { (isLive && turn.agentMessage == nil) || expandedTurns.contains(turn.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                header
                #if os(iOS)
                if let stop {
                    Spacer(minLength: 0)
                    Button("Stop", systemImage: "stop.circle.fill", action: stop)
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                        .padding(.vertical, -8)
                        .buttonStyle(.plain)
                }
                #endif
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(logEntries(for: turn.work, expandedRuns: expandedRuns)) { entry in
                        switch entry {
                        case .item(let item):
                            WorkRow(item: item, isExpanded: Binding {
                                expandedWork.contains(item.id)
                            } set: { _ in
                                withAnimation(.snappy) { expandedWork.formSymmetricDifference([item.id]) }
                            })
                        case .hiddenTools(let runID, let count):
                            runToggle("+\(count) previous tool calls", systemImage: "ellipsis", runID: runID)
                        case .showFewer(let runID):
                            runToggle("Show fewer tool calls", systemImage: "chevron.up", runID: runID)
                        }
                    }
                    if isLive {
                        TimelineView(.explicit(turn.quietSince.map { [$0.addingTimeInterval(Turn.quietGap)] } ?? [])) { context in
                            let isQuiet = turn.isQuiet(at: context.date)
                            VStack(spacing: 0) {
                                if isQuiet {
                                    WaitingDots()
                                        .transition(.asymmetric(insertion: .opacity, removal: .identity))
                                }
                            }
                            .animation(.easeOut(duration: 0.3), value: isQuiet)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }

    private var header: some View {
        Button {
            withAnimation(.snappy) { expandedTurns.formSymmetricDifference([turn.id]) }
        } label: {
            HStack(spacing: 4) {
                if let message = turn.agentMessage {
                    if let bot = bots.bots.first(where: { $0.name == message.handle }) {
                        BotAvatar(bot: bot, status: .idle, photo: bots.photos[bot.id], size: 16)
                            .padding(.trailing, 4)
                    }
                    Text("Message from \(message.sender)")
                        .phaseAnimator(isLive ? [1, 0.6] : [1]) { content, opacity in
                            content.opacity(opacity)
                        } animation: { _ in
                            .easeInOut(duration: 1)
                        }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                } else if isLive {
                    TimelineView(.periodic(from: turn.startedAt, by: 1)) { context in
                        Text("Working for \(Duration.seconds(Int(context.date.timeIntervalSince(turn.startedAt))).formatted(elapsedStyle))")
                    }
                    .phaseAnimator([1, 0.6]) { content, opacity in
                        content.opacity(opacity)
                    } animation: { _ in
                        .easeInOut(duration: 1)
                    }
                    if let activity {
                        Text(verbatim: "· \(activity)")
                            .fontWeight(.regular)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Worked for \(Duration.seconds(Int((turn.finishedAt ?? turn.startedAt).timeIntervalSince(turn.startedAt))).formatted(elapsedStyle))")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isLive && turn.agentMessage == nil)
    }

    private func runToggle(_ title: String, systemImage: String, runID: String) -> some View {
        Button {
            withAnimation(.snappy) { expandedRuns.formSymmetricDifference([runID]) }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .labelStyle(WorkLabelStyle())
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct WaitingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                dots(phase: nil)
                    .phaseAnimator([1, 0.6]) { content, opacity in
                        content.opacity(opacity)
                    } animation: { _ in
                        .easeInOut(duration: 1)
                    }
            } else {
                TimelineView(.animation) { context in
                    dots(phase: context.date.timeIntervalSinceReferenceDate / 1.2)
                }
            }
        }
        .frame(height: 20)
        .padding(.vertical, 6)
        .accessibilityElement()
        .accessibilityLabel("Thinking")
    }

    private func dots(phase: Double?) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 8, height: 8)
                    .opacity(phase.map { 0.65 + 0.35 * cos(2 * .pi * ($0 - Double(index) / 6)) } ?? 1)
            }
        }
        .foregroundStyle(.secondary)
    }
}

private struct WorkLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .frame(width: 20)
            configuration.title
        }
    }
}

private struct WorkRow: View {
    let item: WorkItem
    @Binding var isExpanded: Bool

    var body: some View {
        if case .note(let text) = item.kind {
            MarkdownText(source: text)
                .textSelection(.enabled)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 28)
                .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    isExpanded.toggle()
                } label: {
                    summary
                }
                .buttonStyle(.plain)
                if isExpanded {
                    details
                        .padding(.leading, 28)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 8) {
            Image(systemName: appearance.icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text("\(Text(appearance.verb).fontWeight(.semibold)) \(Text(subject).foregroundStyle(.secondary))")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let duration = item.duration, duration >= 1 {
                Text(Duration.seconds(Int(duration)).formatted(elapsedStyle))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            status
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .font(.subheadline)
        .padding(.vertical, 6)
        .contentShape(.rect)
    }

    @ViewBuilder private var status: some View {
        if case .tool(let call) = item.kind {
            switch call.status {
            case .running:
                ProgressView()
                    .controlSize(.mini)
            case .success:
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder private var details: some View {
        switch item.kind {
        case .thinking(let text), .note(let text):
            MarkdownText(source: text)
                .textSelection(.enabled)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .tool(let call):
            VStack(alignment: .leading, spacing: 8) {
                if let outcome = call.outcome {
                    Text(outcome)
                        .font(.footnote)
                        .foregroundStyle(call.status == .error ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
                CodeBox(title: call.name, text: call.arguments)
                if let result = call.result {
                    CodeBox(title: "Result", text: result)
                }
            }
        }
    }

    private var appearance: (verb: String, icon: String) {
        if case .thinking = item.kind { return ("Thinking", "brain") }
        guard case .tool(let call) = item.kind else { return ("", "text.bubble") }
        if call.name == "browser_vault" { return (vaultAction(call) == "fill" ? "Card" : "Checked cards", "creditcard") }
        if let style = toolStyles[call.name] { return style }
        if call.name.hasPrefix("browser_") { return ("Browsed", "safari") }
        return (call.name.replacing("_", with: " ").capitalized, "wrench.and.screwdriver")
    }

    private var subject: String {
        switch item.kind {
        case .thinking(let text), .note(let text):
            text.split(whereSeparator: \.isNewline).first.map { $0.replacing("**", with: "").replacing("#", with: "").trimmingCharacters(in: .whitespaces) } ?? ""
        case .tool(let call) where call.name == "browser_vault":
            vaultSubject(call)
        case .tool(let call):
            call.subject
        }
    }

    private func vaultAction(_ call: ToolCall) -> String? {
        ((try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) as? [String: Any])?["action"] as? String
    }

    private func vaultSubject(_ call: ToolCall) -> String {
        guard vaultAction(call) == "fill" else { return "" }
        let host = call.result.flatMap(VaultResult.init)?.origin.flatMap { URLComponents(string: $0)?.encodedHost }
        return host.map { String(localized: "at \($0)") } ?? ""
    }
}

private struct CodeBox: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) {
                Text(text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .fixedSize(horizontal: false, vertical: true)
            .scrollIndicators(.hidden)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 8))
    }
}

