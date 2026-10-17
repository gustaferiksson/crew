import AppKit
import CoreText
import Foundation
import SwiftUI
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

private struct SearchPage: Decodable {
    struct Result: Decodable {
        let snippet: String
    }

    let results: [Result]
}

private func steerAnswerReply() throws -> String {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let rows = try decoder.decode([HistoryRow].self, from: Data(contentsOf: fixtures.appending(path: "chat.steer-answer.history.json")))
    return try #require(rows.last?.content)
}

private func checklistReply() throws -> String {
    let page = try JSONDecoder().decode(SearchPage.self, from: Data(contentsOf: fixtures.appending(path: "sessions.search.weather.v0.22.2.json")))
    return try #require(page.results.map(\.snippet).first { $0.contains("### Before Leaving") })
}

private func onlyText(_ source: String) throws -> NSAttributedString {
    let segments = replySegments(from: source)
    try #require(segments.count == 1)
    guard case .text(let text) = segments[0] else { throw CocoaError(.coderInvalidValue) }
    return text
}

private func textView(_ source: String) throws -> ReplyTextView {
    let view = ReplyTextView.make()
    view.frame = NSRect(x: 0, y: 0, width: 420, height: 800)
    view.show(try onlyText(source))
    view.source = source
    return view
}

private func copied(from view: ReplyTextView) throws -> (plain: String, rich: NSAttributedString) {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("crew-tests-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    #expect(view.writeSelection(to: pasteboard, types: [.rtf, .string]))
    let plain = try #require(pasteboard.string(forType: .string))
    let rtf = try #require(pasteboard.data(forType: .rtf))
    return (plain, try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil))
}

@MainActor
struct ReplySelectionTests {
    @Test func codeFenceIsOneBoxWithItsCaptionOutsideTheText() throws {
        let text = try onlyText(try steerAnswerReply())
        #expect(text.string == "step-one\nstep-two")
        let style = try #require(text.attribute(.paragraphStyle, at: text.length - 1, effectiveRange: nil) as? NSParagraphStyle)
        let box = try #require(style.textBlocks.first as? ReplyCodeBlock)
        #expect(box.language == "text")
        let firstLine = try #require(text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(firstLine.textBlocks.first === box)
    }

    @Test func cardSplitsTheReplyIntoTextAndCard() throws {
        let source = a2uiFenced(try String(contentsOf: fixtures.appending(path: "chat.a2ui-recipe.v0.21.7.md"), encoding: .utf8))
        let segments = replySegments(from: source)
        guard case .text(let intro) = segments.first, case .card(let card) = segments.dropFirst().first else {
            Issue.record("expected text then card, got \(segments)")
            return
        }
        #expect(intro.string.hasPrefix("Pancakes: Whisk flour"))
        #expect(card.hasPrefix("[") && card.contains("pancakes-checklist"))
    }

    @Test func dragAcrossHeadingListAndParagraphsCopiesAllOfIt() throws {
        let view = try textView(try checklistReply())
        view.selectAll(nil)
        let plain = try copied(from: view).plain
        let lines = plain.split(separator: "\n").map(String.init)
        #expect(!plain.contains("\t"))
        #expect(lines.contains("• [ ] Insect repellent and tick remover"))
        #expect(lines.contains("Before Leaving"))
        let heading = try #require(lines.firstIndex(of: "Before Leaving"))
        #expect(lines[heading + 1].hasPrefix("• "))
        #expect(lines[heading - 1].hasPrefix("• "))
    }

    @Test func partialSelectionFromAParagraphIntoACodeBlock() throws {
        let view = try textView("See [the docs](https://example.com/docs) first.\n\n1. Build it\n2. Run it\n\n```yaml\nruns-on: macos-26\n```\n\nDone.")
        let string = view.string as NSString
        let start = string.range(of: "the docs").location
        let end = NSMaxRange(string.range(of: "runs-on"))
        view.setSelectedRange(NSRange(location: start, length: end - start))
        #expect(try copied(from: view).plain == "the docs first.\n1. Build it\n2. Run it\nruns-on")
        #expect(!view.string.contains("yaml"))
        let link = view.textStorage?.attribute(.link, at: start, effectiveRange: nil) as? URL
        #expect(link == URL(string: "https://example.com/docs"))
    }

    @Test func longNumberedListKeepsAGapAfterEachNumber() throws {
        let view = try textView((1...11).map { "\($0). Step" }.joined(separator: "\n"))
        let string = view.string as NSString
        let layout = try #require(view.layoutManager)
        let container = try #require(view.textContainer)
        container.size = NSSize(width: 420, height: 10_000)
        layout.ensureLayout(for: container)
        for number in [9, 10, 11] {
            let marker = string.range(of: "\(number).")
            let step = NSRange(location: NSMaxRange(marker) + 1, length: 4)
            let markerEnd = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: marker, actualCharacterRange: nil), in: container).maxX
            let stepStart = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: step, actualCharacterRange: nil), in: container).minX
            #expect(stepStart - markerEnd >= 7.5, "\(number). ends at \(markerEnd), text starts at \(stepStart)")
        }
    }

    @Test func codeKeepsAsciiHyphensOnScreenAndWhenCopied() throws {
        let view = try textView("Still on `macos-15`:\n\n```sh\nxcodebuild -scheme Crew --flag value -- -x\n```")
        view.selectAll(nil)
        let plain = try copied(from: view).plain
        #expect(Array(plain.utf8) == Array("Still on macos-15:\nxcodebuild -scheme Crew --flag value -- -x".utf8))
        let storage = try #require(view.textStorage)
        let layout = try #require(view.layoutManager)
        for needle in ["macos-15", "--flag", "-- -x"] {
            let range = (storage.string as NSString).range(of: needle)
            let font = try #require(storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let names = (glyphs.location..<NSMaxRange(glyphs)).compactMap { CTFontCopyNameForGlyph(font, layout.cgGlyph(at: $0)) as String? }
            #expect(names.filter { $0.contains("dash") }.isEmpty, "\(needle): \(names)")
            #expect(names.filter { $0 == "hyphen" }.count == needle.filter { $0 == "-" }.count, "\(needle): \(names)")
        }
    }

    @Test func copiedRichTextCarriesNoLabelColourInDarkMode() throws {
        let view = try textView(try checklistReply())
        view.appearance = NSAppearance(named: .darkAqua)
        view.selectAll(nil)
        let rich = try copied(from: view).rich
        #expect(rich.length > 0)
        var colours = 0
        rich.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: rich.length)) { value, _, _ in
            if value != nil { colours += 1 }
        }
        #expect(colours == 0)
    }

    @Test func streamingUpdateKeepsTheSelection() throws {
        let partial = "First paragraph.\n\nSecond"
        let view = try textView(partial)
        view.setSelectedRange(NSRange(location: 0, length: 16))
        view.show(try onlyText(partial + " paragraph grows.\n\n- and a list"))
        #expect(view.selectedRange() == NSRange(location: 0, length: 16))
        view.show(try onlyText("First"))
        #expect(view.selectedRange() == NSRange(location: 0, length: 5))
    }

    @Test func rightClickOffersMessageActionsAndTheTextMenu() throws {
        let view = try textView("Hello **there**.")
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let titles = try #require(view.menu(for: event)).items.map { $0.isSeparatorItem ? "-" : $0.title }
        #expect(Array(titles.prefix(3)) == ["Copy Message", "Share Message", "-"])
        #expect(titles.contains("Copy"))
        #expect(titles.filter { ["Cut", "Paste", "Paste and Match Style", "Font", "Spelling and Grammar", "Substitutions"].contains($0) }.isEmpty)
        #expect(!zip(titles, titles.dropFirst()).contains { $0 == "-" && $1 == "-" } && titles.last != "-")
    }

    @Test func heightFollowsTheColumnWidth() throws {
        let text = try onlyText(try checklistReply())
        func height(at width: CGFloat) -> CGFloat {
            NSHostingView(rootView: ReplySegmentText(text: text, source: "", offset: 0).frame(width: width)).fittingSize.height
        }
        #expect(height(at: 640) > 100)
        #expect(height(at: 320) > height(at: 640))
    }

    @Test func repliesTakeNoDropsTabStopsOrFindBar() throws {
        let view = try textView("Hello.")
        #expect(view.registeredDraggedTypes.isEmpty)
        #expect(!view.canBecomeKeyView)
        #expect(!view.usesFindBar && !view.usesFindPanel)
        view.setSelectedRange(NSRange(location: 0, length: 3))
        #expect(view.resignFirstResponder())
        #expect(view.selectedRange().length == 0)
    }
}
