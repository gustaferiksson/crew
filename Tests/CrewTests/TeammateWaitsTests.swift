import Foundation
import Testing

private let folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/teammate-waits")

private struct Answer: Decodable {
    let deliveries: [TeammateDelivery]
}

private func recorded(_ name: String, state: String? = nil) throws -> [TeammateDelivery] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    var text = try String(contentsOf: folder.appending(path: "deliveries.\(name).json"), encoding: .utf8)
    if let state { text = text.replacingOccurrences(of: #""state" : "\#(name)""#, with: #""state" : "\#(state)""#) }
    return try decoder.decode(Answer.self, from: Data(text.utf8)).deliveries
}

private func bot(_ name: String, title: String) -> Bot {
    Bot(name: name, displayName: title, description: nil, model: nil, isDefault: false, hasAvatar: false, canonicalSession: nil, meta: BotMeta(), metaRevision: nil)
}

private func store() -> DismissedDeliveries {
    DismissedDeliveries(fileURL: FileManager.default.temporaryDirectory.appending(path: "dismissed-\(UUID().uuidString).json"))
}

@Test func recordedWorkingDeliveryReadsAsWorkingOnIt() throws {
    let row = try #require(try recorded("working").first)
    #expect(row.target == "crew-test-peer")
    #expect(row.state == .working)
    #expect(row.status(for: "Crew Peer") == "Working on it")
    #expect(row.age(at: row.since.addingTimeInterval(5 * 60 + 20)) == "5m")
    #expect(row.age(at: row.since.addingTimeInterval(-30)) == "now")
}

@Test func recordedUnknownOutcomeSaysItMayHaveActed() throws {
    let row = try #require(try recorded("failed").first)
    #expect(row.isUnknownOutcome)
    #expect(row.status(for: "Crew Peer") == "Outcome unknown. It may have acted, so check its chat before asking again.")
}

@Test func waitingOnYouDerivedFromARecordedRowNamesWhatTheUserOwes() throws {
    let waiting = try #require(try recorded("working", state: "waiting_on_you").first)
    #expect(waiting.state == .waitingOnYou)
    #expect(waiting.status(for: "Crew Peer") == "Needs your answer")
    let approval = TeammateDelivery(id: "d", target: "peer", state: .waitingOnYou, since: .now, waitingOn: "approval")
    #expect(approval.status(for: "Peer") == "Needs your approval")
}

@Test func typedFailureReasonsReadAsSentences() {
    let offline = TeammateDelivery(id: "d", target: "peer", state: .failed, since: .now, reason: "runtime_offline")
    #expect(offline.status(for: "Peer") == "Peer is offline. Ask again when it's back.")
    let new = TeammateDelivery(id: "d", target: "peer", state: .failed, since: .now, reason: "something_new", error: "Disk full")
    #expect(new.status(for: "Peer") == "Disk full")
}

@Test func openTargetsTheTeammateAndNeverTheSender() throws {
    let row = try #require(try recorded("working").first)
    let peer = bot("crew-test-peer", title: "Crew Peer")
    let sender = bot("crew-test", title: "Crew Test")
    #expect(row.teammate(in: [sender, peer], sender: "crew-test")?.id == "crew-test-peer")
    #expect(row.teammate(in: [sender], sender: "crew-test") == nil)
    #expect(row.teammate(in: [peer], sender: "crew-test-peer") == nil)
}

private struct Offline: Error {}

@Test func waitingRowsComeFirstAndDismissedFailuresDrop() async {
    let now = Date.now
    let dismissed = store()
    let waits = TeammateWaits()
    await waits.refresh(dismissed: dismissed) { [
        TeammateDelivery(id: "f1", target: "a", state: .failed, since: now, reason: "cancelled"),
        TeammateDelivery(id: "w1", target: "b", state: .working, since: now),
        TeammateDelivery(id: "f2", target: "c", state: .failed, since: now, reason: "cancelled"),
        TeammateDelivery(id: "y1", target: "d", state: .waitingOnYou, since: now, waitingOn: "clarify"),
    ] }
    #expect(waits.visible(excluding: dismissed).map(\.id) == ["y1", "w1", "f1", "f2"])
    dismissed.dismiss("f1")
    dismissed.dismiss("w1")
    #expect(waits.visible(excluding: dismissed).map(\.id) == ["y1", "w1", "f2"])
}

@Test func failedPollKeepsTheLastRowsMarkedStaleUntilAnAnswerComes() async {
    let dismissed = store()
    let waits = TeammateWaits()
    let row = TeammateDelivery(id: "w1", target: "b", state: .working, since: .now)
    await waits.refresh(dismissed: dismissed) { [row] }
    await waits.refresh(dismissed: dismissed) { throw Offline() }
    #expect(waits.visible(excluding: dismissed) == [row])
    #expect(waits.isStale && waits.isSupported)
    await waits.refresh(dismissed: dismissed) { [] }
    #expect(waits.visible(excluding: dismissed).isEmpty && !waits.isStale)
}

@Test func serverWithoutTheMethodHidesTheStripAndStopsPolling() async {
    let dismissed = store()
    let waits = TeammateWaits()
    await waits.refresh(dismissed: dismissed) { [TeammateDelivery(id: "w1", target: "b", state: .working, since: .now)] }
    await waits.refresh(dismissed: dismissed) { throw GatewayError.rpc(code: -32601, message: "unknown method: bot_delivery.list") }
    #expect(waits.visible(excluding: dismissed).isEmpty && !waits.isSupported && !waits.isStale)
    let other = TeammateWaits()
    await other.refresh(dismissed: dismissed) { throw GatewayError.rpc(code: -32000, message: "Method not found") }
    #expect(!other.isSupported)
}

@Test func dismissalsSurviveARestartAndAgeOut() {
    let url = FileManager.default.temporaryDirectory.appending(path: "dismissed-\(UUID().uuidString).json")
    let first = DismissedDeliveries(fileURL: url)
    let now = Date.now
    first.dismiss("old", at: now.addingTimeInterval(-25 * 3600))
    first.dismiss("fresh", at: now)
    first.dismiss("gone", at: now)
    let second = DismissedDeliveries(fileURL: url)
    #expect(second.contains("fresh") && second.contains("old") && second.contains("gone"))
    second.keep(listed: ["old", "fresh"], at: now)
    #expect(!second.contains("old") && !second.contains("gone") && second.contains("fresh"))
    #expect(DismissedDeliveries(fileURL: url).contains("fresh"))
    second.reset()
    #expect(!DismissedDeliveries(fileURL: url).contains("fresh"))
}
