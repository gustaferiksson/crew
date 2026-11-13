import A2UICore
import SwiftUI

extension EnvironmentValues {
    @Entry var cardModel: SurfaceViewModel?
}

struct CardTimerRow: View {
    let model: SurfaceViewModel
    let id: String
    let title: String?
    let name: String
    let alert: String
    let seconds: TimeInterval

    @Environment(\.surfaces) private var surfaces
    @Environment(CardTimers.self) private var timers: CardTimers?
    @Environment(PushCenter.self) private var push: PushCenter?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(model: SurfaceViewModel, id: String, title: String?, name: String, alert: String, seconds: TimeInterval) {
        self.model = model
        self.id = id
        self.title = title
        self.name = name
        self.alert = alert
        self.seconds = seconds
    }

    var body: some View {
        let timer = self.timer
        let ends: [Date] = if case .running(let end) = timer { [end] } else { [] }
        TimelineView(.explicit(ends)) { _ in
            let now = Date.now
            let isDone = timer.isDone(at: now)
            let remaining = Duration.seconds(Int(timer.remaining(of: seconds, at: now).rounded(.up)))
            let shown = remaining.formatted(.time(pattern: remaining >= .seconds(3600) ? .hourMinuteSecond : .minuteSecond))
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                HStack(spacing: 8) {
                    if let title {
                        Text(title)
                    }
                    if isDone {
                        Label("Done", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if case .running(let end) = timer {
                        Text(timerInterval: now...end, countsDown: true)
                            .foregroundStyle(.tint)
                    } else {
                        Text(shown)
                            .foregroundStyle(timer == .idle ? .primary : .secondary)
                    }
                }
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(name) timer"))
                .accessibilityValue(isDone ? Text("Done") : timer == .idle ? Text(shown) : ends.isEmpty ? Text("Paused, \(shown)") : Text(timerInterval: now...ends[0], countsDown: true))
                .accessibilityActions {
                    if isDone {
                        Button("Reset", action: reset)
                    } else if case .running = timer {
                        Button("Pause", action: pause)
                    } else {
                        Button(timer == .idle ? "Start" : "Resume", action: start)
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    if isDone {
                        EmptyView()
                    } else if case .running = timer {
                        Button("Pause", systemImage: "pause.fill", action: pause)
                    } else {
                        Button(timer == .idle ? "Start" : "Resume", systemImage: "play.fill", action: start)
                    }
                    if timer != .idle {
                        Button("Reset", systemImage: "arrow.counterclockwise", action: reset)
                            .labelStyle(.iconOnly)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .environment(\.isEnabled, true)
            }
            #if os(iOS)
            .frame(minHeight: 44)
            #endif
        }
    }

    private var key: String {
        CardTimers.key(chat: surfaces?.saved?.chat, surface: model.surfaceID, timer: id)
    }

    private var timer: CardTimer {
        timers?.timer(key) ?? .idle
    }

    private func start() {
        let next = timer.started(for: seconds, at: .now)
        timers?.set(next, for: key)
        guard case .running(let end) = next else { return }

        let request = CardTimer.alert(id: key, card: CardSummary(model.rootNode).title, what: alert, chat: surfaces?.saved?.chat, after: end.timeIntervalSinceNow)
        Task { await push?.scheduleTimer(request) }
    }

    private func pause() {
        timers?.set(timer.paused(at: .now), for: key)
        push?.cancelTimer(key)
    }

    private func reset() {
        timers?.set(.idle, for: key)
        push?.cancelTimer(key)
    }
}
