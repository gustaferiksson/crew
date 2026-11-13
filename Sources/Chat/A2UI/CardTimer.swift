import Foundation
import UserNotifications

nonisolated enum CardTimer: Equatable {
    case idle
    case running(until: Date)
    case paused(remaining: TimeInterval)

    init(_ saved: String?) {
        let parts = saved?.split(separator: " ") ?? []
        guard parts.count == 2, let number = Double(parts[1]) else {
            self = .idle
            return
        }
        if parts[0] == "running" {
            self = .running(until: Date(timeIntervalSince1970: number))
        } else if parts[0] == "paused" {
            self = .paused(remaining: number)
        } else {
            self = .idle
        }
    }

    var saved: String? {
        if case .running(let end) = self { return "running \(end.timeIntervalSince1970)" }
        if case .paused(let remaining) = self { return "paused \(remaining)" }
        return nil
    }

    func remaining(of duration: TimeInterval, at now: Date) -> TimeInterval {
        if case .running(let end) = self { return max(0, end.timeIntervalSince(now)) }
        if case .paused(let remaining) = self { return remaining }
        return duration
    }

    func isDone(at now: Date) -> Bool {
        guard case .running(let end) = self else { return false }
        return end <= now
    }

    func started(for duration: TimeInterval, at now: Date) -> CardTimer {
        if case .running = self { return self }
        return .running(until: now.addingTimeInterval(remaining(of: duration, at: now)))
    }

    func paused(at now: Date) -> CardTimer {
        guard case .running = self, !isDone(at: now) else { return self }
        return .paused(remaining: remaining(of: 0, at: now))
    }

    static func alert(id: String, card: String?, what: String, chat: String?, after interval: TimeInterval) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = card ?? String(localized: "Timer")
        content.body = String(localized: "Time's up: \(what)")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "timer.\(chat ?? "")"
        content.userInfo = ["crew": ["profile": chat ?? "", "kind": "timer"]]
        return UNNotificationRequest(identifier: id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false))
    }
}
