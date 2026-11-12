import AppKit
import SwiftUI
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
private let crewTest = Bot(name: "crew-test", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta())

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

@MainActor @Observable private final class JumpModel {
    var turns: [Turn] = []
    var position = ScrollPosition(idType: Turn.ID.self)
    @ObservationIgnored var frames: [Turn.ID: CGRect] = [:]
}

private struct JumpColumn: View {
    let model: JumpModel
    @State private var surfaces = SurfaceStore()

    var body: some View {
        TranscriptScroll(position: Bindable(model).position, revision: model.turns.count, barHeight: 60) {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(model.turns) { turn in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(turn.startedAt, format: .dateTime)
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        TurnView(turn: turn, surfaces: surfaces, speaker: nil, speakerPhoto: nil, failureTarget: nil, activity: nil, reveal: 0, timestampWidth: 40, mentionable: [], speakerName: "crew-test", isExpanded: false, expandedWork: [], expandedRuns: [], canStop: false)
                    }
                    .id(turn.id)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { model.frames[turn.id] = $0 }
                    .onDisappear { model.frames[turn.id] = nil }
                }
            }
            .scrollTargetLayout()
            .padding(16)
        }
        .safeAreaBar(edge: .bottom) {
            Color.gray.frame(height: 60)
        }
    }
}

private func longChat(repeats: Int) throws -> [Turn] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let turns = Transcript(history: try decoder.decode(HistoryFile.self, from: Data(contentsOf: fixtures.appending(path: "chat.long-replies.history.json"))).messages).visible.turns
    return (0..<repeats).flatMap { round in
        turns.map { turn in
            var copy = turn
            copy.id = "\(round)-\(turn.id)"
            return copy
        }
    }
}

@MainActor struct TranscriptJumpTests {
    @Test func scrollingUpALongChatMovesTheTopRowByTheScrollOnly() throws {
        let model = JumpModel()
        model.turns = try longChat(repeats: 20)
        let window = OffscreenWindow(size: NSSize(width: 700, height: 900), styleMask: [.titled, .resizable])
        window.isRestorable = false
        window.contentViewController = NSHostingController(rootView: JumpColumn(model: model).environment(BotStore(fixture: [crewTest], statuses: [:])).environment(ChatPins(fileURL: nil)))
        window.setContentSize(NSSize(width: 700, height: 900))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle(1)

        let scroll = try #require(window.contentView.flatMap(scrollView(in:)))
        let step: CGFloat = 400
        let contentHeight = { scroll.documentView?.frame.height ?? 0 }
        var heightChanges: [CGFloat] = []
        for _ in 0..<10 {
            let anchor = try #require(model.frames.filter { $0.value.maxY > 0 }.min { $0.value.minY < $1.value.minY }, "no row on screen")
            let height = contentHeight()
            userScroll(scroll, by: step)
            heightChanges.append(contentHeight() - height)
            let landed = try #require(model.frames[anchor.key], "row \(anchor.key) left the realised rows after one \(step) pt scroll")
            #expect(abs(landed.minY - anchor.value.minY - step) < 1, "row \(anchor.key) moved \(landed.minY - anchor.value.minY - step) pt more than the scroll")
        }
        print("TranscriptJump: content height changes \(heightChanges.map(Int.init))")
        withKnownIssue("the LazyVStack swaps its height estimate for measured rows mid-scroll, so the scroller thumb jumps while the rows stay put (#12)") {
            #expect(heightChanges.allSatisfy { abs($0) < 1 }, "content height changed by \(heightChanges.map(Int.init)) pt while scrolling")
        }
    }
}
