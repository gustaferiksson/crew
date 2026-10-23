import Foundation
import Testing

private func isBold(_ text: AttributedString, _ substring: String) -> Bool {
    guard let range = text.range(of: substring) else { return false }
    return text[range].runs.allSatisfy { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
}

struct CardMarkdownTests {
    @Test func headingFromVerasCardDropsTheHashesAndKeepsTheLink() {
        let text = cardMarkdown("### 1. [Evi Beige, Jakobs Handmade](https://jakobshandmade.se/evi-beige) · 235 kr\n**36 och 37 finns tillgängliga.** Trots färgnamnet Beige är mockan varmt ljusbrun.")
        #expect(String(text.characters) == "1. Evi Beige, Jakobs Handmade · 235 kr\n36 och 37 finns tillgängliga. Trots färgnamnet Beige är mockan varmt ljusbrun.")
        #expect(isBold(text, "1. Evi Beige, Jakobs Handmade · 235 kr"))
        #expect(!isBold(text, "Trots färgnamnet"))
        let link = text.range(of: "Evi Beige, Jakobs Handmade").map { text[$0].runs.first?.link }
        #expect(link == URL(string: "https://jakobshandmade.se/evi-beige"))
    }

    @Test func headingWithBoldInsideStaysBoldThroughout() {
        let text = cardMarkdown("## Pick **this** one")
        #expect(String(text.characters) == "Pick this one")
        #expect(isBold(text, "Pick this one"))
    }

    @Test func hashesThatAreNotHeadingsStay() {
        #expect(String(cardMarkdown("#hashtag stays").characters) == "#hashtag stays")
        #expect(String(cardMarkdown("Gate # 2 is open").characters) == "Gate # 2 is open")
        #expect(String(cardMarkdown("1. Mix the flour.\n2. Whisk.").characters) == "1. Mix the flour.\n2. Whisk.")
    }

    @Test func lineBreaksSurviveAroundAHeading() {
        let text = cardMarkdown("Intro line\n#### Title\nLine two\nLine three")
        #expect(String(text.characters) == "Intro line\nTitle\nLine two\nLine three")
        #expect(isBold(text, "Title"))
        #expect(!isBold(text, "Line two"))
        #expect(!isBold(text, "Intro line"))
    }
}
