import Foundation

nonisolated struct LimitFailure: Codable, Sendable, Equatable {
    struct Suggestion: Codable, Sendable, Equatable {
        let model: String
        let label: String?
        let provider: String?

        var choice: ModelChoice { ModelChoice(provider: provider ?? "nous", model: model) }
    }

    struct Surface: Decodable, Sendable {
        struct UsageLimit: Decodable, Sendable {
            let limitName: String?
            let resetsAtMs: Double?
            let suggestions: [Suggestion]?
        }

        let code: String?
        let providerLabel: String?
        let resetsAt: Double?
        let usageLimit: UsageLimit?
    }

    var provider: String?
    var limitName: String?
    var isRateLimit: Bool
    var resetsAt: Date?
    var suggestions: [Suggestion] = []

    init?(_ surface: Surface?) {
        guard let surface, let code = surface.code, ["usage_window", "rate_limit", "upstream_rate_limit"].contains(code) else { return nil }
        provider = surface.providerLabel.flatMap { $0.isEmpty ? nil : $0 }
        limitName = surface.usageLimit?.limitName.flatMap { $0.isEmpty ? nil : $0 }
        isRateLimit = code != "usage_window"
        let seconds = surface.usageLimit?.resetsAtMs.map { $0 / 1000 } ?? surface.resetsAt
        resetsAt = seconds.map(Date.init(timeIntervalSince1970:))
        suggestions = surface.usageLimit?.suggestions ?? []
    }

    func sentence(at now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let name = limitName ?? (isRateLimit ? String(localized: "rate", locale: locale) : String(localized: "usage", locale: locale))
        guard let resetsAt, resetsAt > now else {
            return provider.map { String(localized: "Your \($0) \(name) limit was reached.", locale: locale) } ?? String(localized: "Your \(name) limit was reached.", locale: locale)
        }

        let headline = provider.map { String(localized: "Your \($0) \(name) limit is reached.", locale: locale) } ?? String(localized: "Your \(name) limit is reached.", locale: locale)
        let time = resetsAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        let remaining = resetsAt.timeIntervalSince(now)
        if remaining < 3600 {
            let minutes = Duration.seconds(60 * max(1, (remaining / 60).rounded(.up))).formatted(.units(allowed: [.minutes], width: .wide).locale(locale))
            return headline + " " + String(localized: "It resets in \(minutes).", locale: locale)
        }
        if calendar.isDate(resetsAt, inSameDayAs: now) {
            return headline + " " + String(localized: "It resets at \(time).", locale: locale)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(resetsAt, inSameDayAs: tomorrow) {
            return headline + " " + String(localized: "It resets tomorrow at \(time).", locale: locale)
        }
        let day = resetsAt.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide).month(.abbreviated).day())
        return headline + " " + String(localized: "It resets \(day) at \(time).", locale: locale)
    }

    func switchable(among providers: [ModelProvider], current: ModelChoice?) -> Suggestion? {
        suggestions.first { suggestion in
            suggestion.choice != current && providers.contains { $0.slug == suggestion.choice.provider && $0.models.contains(suggestion.model) }
        }
    }
}
