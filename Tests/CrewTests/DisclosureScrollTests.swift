import AppKit
import SwiftUI
import Testing

private let scout = Bot(name: "scout", displayName: "Scout", description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())
private let botThreadFile = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/bot-thread/default.history.json")

@MainActor @Observable private final class DisclosureModel {
    var turns: [Turn] = []
    var expanded: Set<Turn.ID> = []
    var position = ScrollPosition(idType: Turn.ID.self)
    @ObservationIgnored var distances: [CGFloat] = []
}

private struct DisclosureColumn: View {
    @Bindable var model: DisclosureModel
    @State private var surfaces = SurfaceStore()

    var body: some View {
        TranscriptScroll(position: $model.position, revision: model.turns.count, barHeight: 60) {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(model.turns) { turn in
                    TurnView(turn: turn, surfaces: surfaces, speaker: nil, speakerPhoto: nil, failureTarget: nil, activity: nil, reveal: 0, timestampWidth: 40, mentionable: [], speakerName: "crew-test", isExpanded: model.expanded.contains(turn.id), expandedWork: [], expandedRuns: [], canStop: false)
                        .id(turn.id)
                }
            }
            .scrollTargetLayout()
            .padding(16)
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height - $0.visibleRect.maxY + $0.contentInsets.bottom } action: { model.distances.append($1) }
        .safeAreaBar(edge: .bottom) {
            Color.gray.frame(height: 60)
        }
    }
}

private func botThread(endingWith last: String) throws -> [Turn] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let thread = Transcript(history: try decoder.decode([HistoryRow].self, from: Data(contentsOf: botThreadFile))).visible.turns
    let end = try #require(thread.lastIndex { last == "to" ? $0.outgoingMessage != nil : $0.agentMessage != nil })
    let start = try #require(thread.first?.startedAt).addingTimeInterval(-200 * 60)
    let earlier = (0..<200).map { index in
        Turn(id: "u\(index)", prompt: Prompt(text: "Question \(index) about the trip?", sentAt: start.addingTimeInterval(Double(index) * 60)), reply: String(repeating: "A reply that wraps across the column a few times. ", count: 1 + (index * 7) % 40), status: .complete, startedAt: start.addingTimeInterval(Double(index) * 60), finishedAt: start.addingTimeInterval(Double(index) * 60 + 5))
    }
    return earlier + thread[...end]
}

@MainActor struct DisclosureScrollTests {
    @Test(.serialized, arguments: ["from", "to"])
    func theLastBotMessageRowOpensAndClosesWithTheEndHeld(last: String) throws {
        let model = DisclosureModel()
        model.turns = try botThread(endingWith: last)
        let row = try #require(model.turns.last?.id)
        let window = OffscreenWindow(size: NSSize(width: 600, height: 500), styleMask: [.titled, .resizable])
        window.isRestorable = false
        window.contentViewController = NSHostingController(rootView: DisclosureColumn(model: model).environment(BotStore(fixture: [scout], statuses: [:])))
        window.setContentSize(NSSize(width: 600, height: 500))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle(1)

        let scroll = try #require(window.contentView.flatMap(scrollView(in:)))
        let height = { scroll.documentView?.frame.height ?? 0 }
        for step in ["open", "close", "open", "close"] {
            let before = height()
            model.distances = []
            withTransaction(.disclosure(.snappy)) { model.expanded.formSymmetricDifference([row]) }
            settle(1)
            let worst = model.distances.max() ?? 0
            print("Disclosure \(last): \(step) height \(before) -> \(height()), \(model.distances.count) geometry changes, farthest from the end \(worst)")
            #expect(abs(height() - before) > 20, "\(step) did not change the row: height \(before) -> \(height())")
            #expect(worst < 1, "\(step) left the end by \(worst) pt during the animation")
            #expect(model.distances.count < 10, "\(step) changed the scroll geometry \(model.distances.count) times")
        }
    }
}
