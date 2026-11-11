import Observation

@Observable
final class Draft {
    var text: String {
        didSet {
            guard text != oldValue else { return }
            save()
        }
    }

    var reply: ReplyTarget?

    @ObservationIgnored private let save: () -> Void

    init(_ text: String = "", save: @escaping () -> Void = {}) {
        self.text = text
        self.save = save
    }
}
