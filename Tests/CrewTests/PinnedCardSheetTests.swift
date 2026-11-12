import AppKit
import SwiftUI
import Testing

@MainActor @Observable private final class MenuModel {
    var canShow = false
    var shows = 0
}

private struct ShowPinnedCard: View {
    let model: MenuModel
    @FocusedBinding(\.showsPinnedCard) private var isPresented

    var body: some View {
        Color.clear
            .frame(height: 0)
            .onChange(of: isPresented == nil, initial: true) { model.canShow = isPresented != nil }
            .onChange(of: model.shows) { isPresented = true }
    }
}

private struct PinnedChat: View {
    let transcript: Transcript
    let presentation: ChatPresentation
    let model: MenuModel
    @State private var draft = Draft()
    @State private var tray = AttachmentTray()

    var body: some View {
        VStack(spacing: 0) {
            ChatView(botName: "crew-test", avatar: EmptyView(), transcript: transcript, emptyState: EmptyView(), mentionable: [], draft: draft, tray: tray, pinKey: "crew-test", presentation: presentation)
            ShowPinnedCard(model: model)
        }
    }
}

private final class KeyWindow: OffscreenWindow {
    override var isKeyWindow: Bool { true }
}

@MainActor private func scrollViews(in view: NSView) -> [NSScrollView] {
    [view as? NSScrollView].compactMap(\.self) + view.subviews.flatMap(scrollViews(in:))
}

private let partyList = """
    [
      {"version": "v0.9", "createSurface": {"surfaceId": "party-list", "catalogId": "https://crew.gustaf.dev/catalogs/crew/v1.json"}},
      {"version": "v0.9", "updateComponents": {"surfaceId": "party-list", "components": [
        {"id": "root", "component": "Card", "child": "body"},
        {"id": "body", "component": "Column", "children": ["header", "table"]},
        {"id": "header", "component": "Header", "title": "Inköpslista till festen", "symbol": "cart", "tone": "success"},
        {"id": "table", "component": "Table", "columns": ["Köp", "Dryck", "Sektion", "Hylla"],
          "rows": [["3 st", "Alkoholfritt mousserande vin, torrt, 75 cl", "Mejeri och juice", "Gång 8, översta hyllan"], ["4 påsar", "Isbitar 2 kg", "Frys", "Frysdisken vid ingången, bredvid blommorna"]]}
      ]}}
    ]
    """

@MainActor @Suite(.serialized) struct PinnedCardSheetTests {
    private let transcript = Transcript(turns: [
        Turn(id: "list", prompt: Prompt(text: "Make a shopping list for the party drinks", sentAt: .now), reply: "Here's the list.\n\n```a2ui\n\(partyList)\n```", status: .complete, startedAt: .now, finishedAt: .now)
    ])

    private func host(width: CGFloat, presentation: ChatPresentation = ChatPresentation(), model: MenuModel = MenuModel()) -> KeyWindow {
        let pins = ChatPins(fileURL: nil)
        pins.pin("party-list", in: "crew-test")
        let window = KeyWindow(size: NSSize(width: width, height: 900), styleMask: [.titled, .resizable])
        window.isRestorable = false
        window.contentViewController = NSHostingController(rootView: PinnedChat(transcript: transcript, presentation: presentation, model: model).environment(BotStore(fixture: [], statuses: [:])).environment(pins))
        window.setContentSize(NSSize(width: width, height: 900))
        window.orderBack(nil)
        return window
    }

    @Test func showPinnedCardOpensASheetThatFitsTheTableAndEscapeClosesIt() throws {
        let model = MenuModel()
        let window = host(width: 700, model: model)
        defer { window.orderOut(nil) }
        settle(1.5)
        #expect(window.attachedSheet == nil, "the chat opened with a sheet")

        #expect(model.canShow, "View > Show Pinned Card is disabled")
        model.shows += 1
        settle(1.5)
        let sheet = try #require(window.attachedSheet, "Show Pinned Card opened no sheet")
        let tables = scrollViews(in: try #require(sheet.contentView)).filter { $0.hasHorizontalScroller || ($0.documentView?.frame.width ?? 0) > $0.frame.width.rounded() + 1 }
        #expect(sheet.frame.width.rounded() > 560, "the sheet is \(sheet.frame.width.rounded()) pt, narrower than the table")
        #expect(tables.isEmpty, "the table scrolls inside the sheet")

        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: sheet.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        sheet.sendEvent(escape)
        settle(1)
        #expect(window.attachedSheet == nil, "Escape left the sheet open")
    }

    @Test(arguments: [(1000, false), (520, true)])
    func anExpandedTableCardGrowsUntilTheColumnIsFull(width: CGFloat, scrolls: Bool) throws {
        let window = host(width: width, presentation: ChatPresentation(expandedCards: ["party-list"]))
        defer { window.orderOut(nil) }
        settle(1.5)
        let content = try #require(window.contentView)
        let transcriptHeight = scrollViews(in: content).map { $0.frame.height }.max() ?? 0
        let tables = scrollViews(in: content).filter { $0.frame.height < transcriptHeight }
        #expect(tables.isEmpty == !scrolls, "\(tables.count) horizontal table scroll views at a \(width) pt window")
    }
}
