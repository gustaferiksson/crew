import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")
private let session = RuntimeSessionID(rawValue: "rt-1")
private let streaming: @Sendable () async throws -> SubmitStatus = { SubmitStatus(status: "streaming") }

private func recorded(_ name: String, finished: Bool = true, dropping type: String? = nil) throws -> AsyncStream<GatewayEvent> {
    let lines = try String(contentsOf: fixtures.appending(path: name), encoding: .utf8).split(separator: "\n")
    let (stream, continuation) = AsyncStream.makeStream(of: GatewayEvent.self)
    for line in lines {
        let event = try JSONDecoder().decode(GatewayEvent.self, from: Data(line.utf8))
        if event.type != type { continuation.yield(event) }
    }
    if finished { continuation.finish() }
    return stream
}

@Test func aRecordedTurnAnswersWithItsCompletedReply() async throws {
    let answer = try await BotAnswer.wait(in: session, for: try recorded("chat.first-turn.v0.22.4.jsonl"), after: streaming, until: .now + .seconds(5))
    #expect(answer == .reply("hi"))
}

@Test func eventsOfAnotherSessionAreIgnored() async throws {
    let answer = try await BotAnswer.wait(in: RuntimeSessionID(rawValue: "rt-other"), for: try recorded("chat.first-turn.v0.22.4.jsonl"), after: streaming, until: .now + .seconds(5))
    #expect(answer == .pending)
}

@Test func noCompletionBeforeTheDeadlineLeavesTheAnswerPending() async throws {
    let events = try recorded("chat.first-turn.v0.22.4.jsonl", finished: false, dropping: "message.complete")
    let started = ContinuousClock.now
    let answer = try await BotAnswer.wait(in: session, for: events, after: streaming, until: .now + .milliseconds(200))
    #expect(answer == .pending)
    #expect(ContinuousClock.now - started < .seconds(2))
}

@Test func aSubmitThatHangsPastTheDeadlineLeavesTheAnswerPending() async throws {
    let hanging: @Sendable () async throws -> SubmitStatus = {
        try await Task.sleep(for: .seconds(30))
        return SubmitStatus(status: "streaming")
    }
    let answer = try await BotAnswer.wait(in: session, for: try recorded("chat.first-turn.v0.22.4.jsonl", finished: false), after: hanging, until: .now + .milliseconds(200))
    #expect(answer == .pending)
}

@Test func aTurnThatEndsWithoutCompletingFails() async throws {
    await #expect(throws: BotTurnFailure.self) {
        try await BotAnswer.wait(in: session, for: try recorded("chat.interrupt-turn.v0.21.7.jsonl"), after: streaming, until: .now + .seconds(5))
    }
}

@Test func aQueuedMessageDoesNotWaitForTheRunningTurnsReply() async throws {
    let answer = try await BotAnswer.wait(in: session, for: try recorded("chat.first-turn.v0.22.4.jsonl"), after: { SubmitStatus(status: "queued") }, until: .now + .seconds(5))
    #expect(answer == .pending)
}

@Test func aFailedSubmitThrowsItsOwnError() async throws {
    await #expect(throws: GatewayError.self) {
        try await BotAnswer.wait(in: session, for: try recorded("chat.first-turn.v0.22.4.jsonl"), after: { throw GatewayError.disconnected }, until: .now + .seconds(5))
    }
}

@Test func speechDropsMarkdownCardsAndCode() {
    let reply = """
    ## Today

    You have **two** meetings and a [doc](https://example.com) to read:

    - Standup at 9
    - Review at 14

    <a2ui-json>
    ```json
    [{"beginRendering": {"surfaceId": "s"}}]
    ```
    </a2ui-json>

    ```a2ui
    [{"beginRendering": {"surfaceId": "t"}}]
    ```

    ```swift
    print("hi")
    ```
    """
    #expect(BotAnswer.speech(from: reply) == "Today.\nYou have two meetings and a doc to read:\nStandup at 9.\nReview at 14.")
}

@Test func aCardOnlyReplyHasNothingToSay() {
    #expect(BotAnswer.speech(from: "<a2ui-json>[{\"beginRendering\": {}}]</a2ui-json>") == "")
}
