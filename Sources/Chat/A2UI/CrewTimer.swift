import A2UICore
import SwiftUI

struct CrewTimer: View {
    let node: Node

    @Environment(\.cardModel) private var model

    var body: some View {
        let seconds = node.double(for: "seconds") ?? 0
        let label = node.string(for: "label") ?? String(localized: "Timer")
        if let model, seconds > 0 {
            CardTimerRow(model: model, id: node.id, title: label, name: label, alert: label, seconds: seconds)
        }
    }
}
