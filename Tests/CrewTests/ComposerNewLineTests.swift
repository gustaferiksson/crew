import SwiftUI
import Testing

@MainActor struct ComposerNewLineTests {
    private func caret(of selection: TextSelection, in text: String) -> Int? {
        guard case .selection(let range) = selection.indices, range.isEmpty else { return nil }
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }

    @Test func insertsAtTheCaretMidText() {
        var text = "Line one"
        let selection = text.insertNewLine(at: TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: 4)))
        #expect(text == "Line\n one")
        #expect(caret(of: selection, in: text) == 5)
    }

    @Test func insertsAtTheEnd() {
        var text = "Line one"
        let selection = text.insertNewLine(at: TextSelection(insertionPoint: text.endIndex))
        #expect(text == "Line one\n")
        #expect(caret(of: selection, in: text) == 9)
    }

    @Test func replacesTheSelectedRange() {
        var text = "Line one"
        let selection = text.insertNewLine(at: TextSelection(range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex))
        #expect(text == "Line\n")
        #expect(caret(of: selection, in: text) == 5)
    }

    @Test func appendsWhenTheSelectionIsFromALongerDraft() {
        let sent = "A long draft that was sent"
        var text = "Hi"
        let selection = text.insertNewLine(at: TextSelection(insertionPoint: sent.endIndex))
        #expect(text == "Hi\n")
        #expect(caret(of: selection, in: text) == 3)
    }

    @Test func appendsWithoutASelection() {
        var text = "Hej då 👋"
        let selection = text.insertNewLine(at: nil)
        #expect(text == "Hej då 👋\n")
        #expect(caret(of: selection, in: text) == 9)
    }
}
