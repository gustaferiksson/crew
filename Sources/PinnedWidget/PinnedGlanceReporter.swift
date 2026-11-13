#if os(iOS)
import A2UICore
import SwiftUI

struct PinnedGlanceReporter: View {
    @ObservedObject var model: SurfaceViewModel
    let chat: String

    @Environment(ChatPins.self) private var pins

    var body: some View {
        let summary = CardSummary(model.rootNode)
        let glance = model.rootNode.map { _ in
            PinnedGlance(surface: model.surfaceID, title: summary.title, subtitle: summary.subtitle, symbol: summary.symbol, tone: summary.tone, progress: summary.checklist.map { PinnedGlance.Progress(done: $0.done, total: $0.total) })
        }
        Color.clear
            .onChange(of: glance, initial: true) { _, glance in
                guard let glance else { return }
                pins.show(glance, in: chat)
            }
    }
}
#endif
