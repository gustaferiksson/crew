import Foundation
import Observation

@Observable
final class DismissedDeliveries {
    static let shared = DismissedDeliveries()
    static let window: TimeInterval = 24 * 3600

    private(set) var dismissed: [String: Date]
    private let fileURL: URL?

    init(fileURL: URL? = URL.applicationSupportDirectory.appending(path: "dismissed-deliveries.json")) {
        self.fileURL = fileURL
        dismissed = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
    }

    func contains(_ id: String) -> Bool {
        dismissed[id] != nil
    }

    func dismiss(_ id: String, at date: Date = .now) {
        dismissed[id] = date
        save()
    }

    func keep(listed ids: Set<String>, at date: Date = .now) {
        let kept = dismissed.filter { ids.contains($0.key) && date.timeIntervalSince($0.value) < Self.window }
        guard kept.count != dismissed.count else { return }
        dismissed = kept
        save()
    }

    func reset() {
        guard !dismissed.isEmpty else { return }
        dismissed = [:]
        save()
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(dismissed) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
