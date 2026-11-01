import Foundation
import Testing

nonisolated private struct HistoryFile: Decodable {
    let messages: [HistoryRow]
}

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

private func replies(in name: String) throws -> [String] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let rows = try decoder.decode(HistoryFile.self, from: Data(contentsOf: fixtures.appending(path: name))).messages
    return Transcript(history: rows).turns.map(\.reply).filter { !$0.isEmpty }
}

@Test func longRepliesReadWithoutMarkdownOrCode() throws {
    let spoken = try replies(in: "chat.long-replies.history.json").map(speechText)
    #expect(spoken.count == 6)
    for text in spoken {
        #expect(!text.isEmpty)
        for markup in ["**", "```", "](", "###", "|---", "https://"] {
            #expect(!text.contains(markup), "\(markup) in \(text.prefix(80))")
        }
    }
    let code = try #require(spoken.first { $0.contains("Dictionary(grouping:)") })
    #expect(!code.contains("func groupByDay"))
    #expect(code.hasPrefix("Dictionary(grouping:) collects dates with the same key into an array."))
    let sourdough = try #require(spoken.first { $0.contains("sourdough") })
    #expect(sourdough.contains("\nFeeding.\n"))
    let recap = try #require(spoken.first { $0.contains("Test purchase") })
    #expect(recap.hasPrefix("1. Test purchase: You asked me"))
    #expect(recap.contains("\n2. Reconnecting the session: "))
    let watches = try #require(spoken.first { $0.contains("Bambino") && $0.contains("Movement") })
    #expect(watches.contains("\nMovement.\n"))
}

@Test func cardRepliesReadOnlyTheirProse() throws {
    let recipe = try String(contentsOf: fixtures.appending(path: "chat.a2ui-recipe.v0.21.7.md"), encoding: .utf8)
    #expect(speechText(from: recipe) == "Pancakes: Whisk flour, baking powder, sugar and salt with milk, an egg and melted butter, then cook small portions in a lightly buttered pan over medium heat until golden on both sides.")
    let updates = try replies(in: "chat.a2ui-update.history.json").map(speechText)
    #expect(updates.contains("Ticked off the onion and breadcrumbs."))
    #expect(updates.allSatisfy { !$0.contains("{") && !$0.contains("a2ui") })
}

@Test func codeOrCardOnlyRepliesHaveNothingToSay() {
    #expect(speechText(from: "```swift\nlet a = 1\n```") == "")
    #expect(speechText(from: "<a2ui-json>\n[{\"version\":\"v0.9\"}]\n</a2ui-json>") == "")
    #expect(speechText(from: "---") == "")
}
