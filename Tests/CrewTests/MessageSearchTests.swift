import Foundation
import SwiftUI
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

private let botChat = StoredSessionID(rawValue: "20261013_144627_bb3f2e")

private let crewTest = Bot(
    name: "crew-test", displayName: nil, description: nil, model: nil, isDefault: false, hasAvatar: false,
    canonicalSession: CanonicalSession(id: botChat, resolvedID: botChat, preview: nil, lastActive: nil, messageCount: 373),
    meta: BotMeta(), metaRevision: 1
)

private func decoded<Value: Decodable>(_ name: String, as type: Value.Type) throws -> Value {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(type, from: Data(contentsOf: fixtures.appending(path: name)))
}

private func hits(_ name: String) throws -> [MessageHit] {
    try decoded(name, as: SessionMatchPage.self).results.compactMap { MessageHit(bot: crewTest, match: $0) }
}

private func match(_ snippet: String, role: String?, session: String = "other", title: String? = "Other") -> SessionMatch {
    SessionMatch(sessionId: StoredSessionID(rawValue: session), lineageRoot: nil, title: title, snippet: snippet, role: role, lastActive: 100, sessionStarted: nil, startedAt: nil)
}

private func emphasised(_ text: AttributedString) -> [String] {
    text.runs.filter { $0.font != nil }.map { String(text[$0.range].characters) }
}

nonisolated private final class WeatherSearchFixture: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil),
              let data = try? Data(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/sessions.search.weather.v0.22.2.json"))
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private nonisolated struct HistoryPage: Decodable {
    let messages: [HistoryRow]
}

@Suite struct MessageSearchTests {
    @Test func recordedReplySplitsBotChatFromOtherConversations() throws {
        let found = try hits("sessions.search.weather.v0.22.2.json")
        #expect(found.count == 4)
        #expect(found[0].isInBotChat)
        #expect(found[0].speaker == "You")
        #expect(String(found[0].highlighted("weather").characters) == "You: Compare the last 7 days of weather in Stockholm as a chart")
        #expect(found.dropFirst().allSatisfy { !$0.isInBotChat && $0.speaker == nil && $0.title?.contains("hike") == true })
        #expect(found[0].conversationDate == Date(timeIntervalSince1970: 1792183058.1799))
    }

    @Test func snippetsFlattenMarkdownAndFences() throws {
        let found = try hits("sessions.search.weather.v0.22.2.json")
        let fenced = flattenedSnippet(found[1].snippet)
        #expect(!fenced.contains("```"))
        #expect(!fenced.contains("\n"))
        #expect(fenced.hasSuffix("before leaving. …"))
        let checklist = flattenedSnippet(found[2].snippet)
        #expect(checklist.hasPrefix("…Menstrual supplies, if needed · Insect repellent"))
        #expect(checklist.contains("Before Leaving · Check >>>weather<<<, trail conditions"))
        #expect(!checklist.contains("[ ]"))
        #expect(!checklist.contains("###"))
        #expect(emphasised(found[2].highlighted("weather")) == ["weather"])
        let shown = String(found[2].highlighted("weather").characters)
        #expect(shown.hasPrefix("…"))
        #expect(shown.prefix(32).contains("Check weather"))
        #expect(String(found[3].highlighted("weather").characters).hasPrefix("Assuming a mild-weather weekend"))
    }

    @Test func toolRowsAreNotMessageHits() throws {
        #expect(try decoded("sessions.search.colour.v0.22.2.json", as: SessionMatchPage.self).results.count == 1)
        #expect(try hits("sessions.search.colour.v0.22.2.json").isEmpty)
    }

    @Test func titleNoticeDeliveryAndWidgetRowsAreDropped() {
        #expect(MessageHit(bot: crewTest, match: match("Use your terminal tool to run ls", role: nil, title: "Bot Chat")) == nil)
        #expect(MessageHit(bot: crewTest, match: match("[IMPORTANT: Background process proc_1 finished >>>boat<<<", role: "user")) == nil)
        #expect(MessageHit(bot: crewTest, match: match("[System: The active model is >>>boat<<<", role: "user")) == nil)
        #expect(MessageHit(bot: crewTest, match: match("<a2ui-action>{\"name\": \">>>boat<<<\"}</a2ui-action>", role: "user")) == nil)
        #expect(MessageHit(bot: crewTest, match: match("{\"ok\": true, \">>>boat<<<\": 1}", role: "tool")) == nil)
        #expect(MessageHit(bot: crewTest, match: match("...No session found matching 'Bot >>>Chat<<<' and a new titled session could not be created.\n]", role: "user", title: "Bot Chat")) == nil)
        #expect(MessageHit(bot: crewTest, match: match("...[System: The active model is >>>boat<<<", role: "user")) == nil)
    }

    @Test func agentMessagesNameTheirSender() throws {
        let hit = try #require(MessageHit(bot: crewTest, match: match("Message from 🤖 Scout (@scout): The >>>boat<<< leaves at 10:15.", role: "user")))
        #expect(hit.speaker == "Scout")
        #expect(String(hit.highlighted("boat").characters) == "Scout: The boat leaves at 10:15.")
    }

    @Test func lineageRootAlsoMeansBotChat() throws {
        let tip = SessionMatch(sessionId: StoredSessionID(rawValue: "newer-tip"), lineageRoot: botChat, title: "Compressed", snippet: ">>>boat<<<", role: "assistant", lastActive: 1, sessionStarted: nil, startedAt: nil)
        #expect(try #require(MessageHit(bot: crewTest, match: tip)).isInBotChat)
        #expect(try #require(MessageHit(bot: crewTest, match: match(">>>boat<<<", role: "assistant"))).isInBotChat == false)
    }

    @Test func markerlessSnippetsHighlightTheQueryWords() throws {
        let hit = try #require(MessageHit(bot: crewTest, match: match("Book the Boat early; tours thin out", role: "assistant")))
        #expect(emphasised(hit.highlighted("boat tours")) == ["Boat", "tours"])
        #expect(emphasised(hit.highlighted("b bo")) == ["B", "B"])
        #expect(String(hit.highlighted("(boat").characters).hasSuffix("tours thin out"))
        #expect(flattenedSnippet("call __init__ on **it**") == "call __init__ on it")
    }

    @Test func recordedToolSnippetFindsTheTurnWhoseAnswerItQuotes() throws {
        let transcript = Transcript(history: try decoded("chat.history.v0.21.7.json", as: HistoryPage.self).messages)
        let colour = try decoded("sessions.search.colour.v0.22.2.json", as: SessionMatchPage.self).results[0].snippet
        let holding = transcript.turns.filter { turn in turn.prompt?.text.contains("which colour I prefer") == true }
        #expect(holding.count == 2)
        #expect(transcript.turn(matching: colour)?.id == holding.first?.id)
        #expect(transcript.turn(matching: colour.replacing("red", with: "blue"))?.id == holding.last?.id)
    }

    @Test func cutSnippetsMatchOnTheLongestPieceThenOnTerms() {
        let start = Date(timeIntervalSince1970: 0)
        let packing = Turn(id: "packing", prompt: Prompt(text: "What should I pack?", sentAt: start), reply: "### Gear\n- Trail shoes with grip\n- Dry bag for the boat trip\n\n> Book the boat early.", status: .complete, startedAt: start)
        let later = Turn(id: "later", prompt: Prompt(text: "Thanks", sentAt: start), reply: "Have a good trip.", status: .complete, startedAt: start)
        let transcript = Transcript(turns: [packing, later])
        #expect(transcript.turn(matching: "...Trail shoes with grip\n- Dry bag for the >>>boat<<< trip\n\n> Book...")?.id == "packing")
        #expect(transcript.turn(matching: "...the >>>boat<<< left from >>>book<<< harbour...")?.id == "packing")
        #expect(transcript.turn(matching: "...nothing like this anywhere...") == nil)
    }

    @Test func searchNeedsTwoCharactersAndAConnection() async {
        #expect(!MessageSearch.isSearchable(" b "))
        #expect(MessageSearch.isSearchable("bo"))
        let search = MessageSearch()
        await search.run("boat", in: [crewTest], on: nil, with: .shared)
        #expect(search.phase == .offline)
        #expect(search.hits.isEmpty)
        await search.run("b", in: [crewTest], on: nil, with: .shared)
        #expect(search.phase == .idle)
    }

    @Test func fixtureSearchFiltersByQuery() async throws {
        let boat = try #require(MessageHit(bot: crewTest, match: match("The >>>boat<<< leaves", role: "assistant")))
        let search = MessageSearch(fixture: [boat])
        await search.run("boat", in: [], on: nil, with: .shared)
        #expect(search.hits == [boat])
        await search.run("train", in: [], on: nil, with: .shared)
        #expect(search.hits.isEmpty)
        #expect(search.phase == .done)
    }

    @Test func hiddenBotsAreStillSearched() async throws {
        var hidden = crewTest
        hidden.meta.hidden = true
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WeatherSearchFixture.self]
        let search = MessageSearch()
        await search.run("weather", in: [hidden], on: URL(string: "https://hermes.invalid"), with: URLSession(configuration: configuration))
        #expect(search.searched == 1)
        #expect(search.hits.count == 4)
        #expect(search.hits.allSatisfy { $0.bot == hidden.id })
    }
}
