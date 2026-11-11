import Observation

@Observable
final class Draft {
    var text: String {
        didSet {
            guard text != oldValue else { return }
            save()
        }
    }

    @ObservationIgnored private let save: () -> Void

    init(_ text: String = "", save: @escaping () -> Void = {}) {
        self.text = text
        self.save = save
    }
}
