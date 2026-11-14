import Foundation
import Synchronization
import Testing

nonisolated private let scenario = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios")

nonisolated private func recorded(_ name: String) -> Data {
    let data = (try? Data(contentsOf: scenario.appending(path: "\(name).json"))) ?? Data()
    return Data("[".utf8) + data + Data("]".utf8)
}

private func job(_ name: String) throws -> RoutineJob {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode([RoutineJob].self, from: recorded(name))[0]
}

struct RoutineDestinationTests {
    @Test func recordedRowsReadBackTheirDestination() throws {
        #expect(try job("routine-room/jobs.room").destination == .room("room-crew-probe"))
        #expect(try job("routine-room/jobs.local").destination == .history)
        #expect(try job("routine-stop/jobs.idle").destination == .history)

        let disbanded = try job("routine-room/jobs.room.disbanded")
        #expect(disbanded.destination == .room("room-crew-probe"))
        #expect(disbanded.result.text == "Delivery failed")
        #expect(disbanded.issue == "room:room-crew-probe@default: no live Group Chat with that id on this machine")
    }

    @Test func deliverTargetsParseLikeHermes() {
        #expect(RoutineDestination(deliver: "room:ops.daily:eu@default") == .room("ops.daily:eu"))
        #expect(RoutineDestination(deliver: "room:ops") == .room("ops"))
        #expect(RoutineDestination(deliver: "bot-chat") == .other("bot-chat"))
        #expect(RoutineDestination(deliver: "room:ops@default,telegram") == .other("room:ops@default,telegram"))
        #expect(RoutineDestination(deliver: "local") == .history)
        #expect(RoutineDestination(deliver: nil) == .history)
        #expect(RoutineDestination.room("ops").deliver == "room:ops@default")
        #expect(RoutineDestination.history.deliver == "local")
    }
}

nonisolated private final class EditServer: URLProtocol {
    static let state = Mutex((list: Data(), updates: [[String: String]]()))
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EditServer.self]
        return URLSession(configuration: configuration)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let body = request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable, case let read = stream.read(&buffer, maxLength: buffer.count), read > 0 { data.append(buffer, count: read) }
            return data
        } ?? request.httpBody
        let isUpdate = request.httpMethod == "PUT"
        let list = EditServer.state.withLock { state in
            if isUpdate, let body, let sent = try? JSONDecoder().decode([String: [String: String]].self, from: body) { state.updates.append(sent["updates"] ?? [:]) }
            return state.list
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: isUpdate ? Data("{}".utf8) : list)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized) struct RoutineEditTests {
    private let gateway = Gateway(server: URL(string: "https://hermes.example.com")!, urlSession: EditServer.session) { "" }

    private func connectedStore() async throws -> RoutineStore {
        EditServer.state.withLock { $0 = (recorded("routine-room/jobs.room"), []) }
        let store = RoutineStore()
        Task { await store.run(profile: "crew-test-peer", gateway: gateway, urlSession: EditServer.session) }
        for _ in 0..<100 where !store.isLoaded { try await Task.sleep(for: .milliseconds(20)) }
        try #require(store.jobs.count == 1)
        return store
    }

    @Test func anEditSendsOnlyTheChangedDestination() async throws {
        let store = try await connectedStore()
        let routine = store.jobs[0]
        try await store.update(routine, title: routine.title, prompt: routine.prompt, schedule: routine.schedule, destination: .history)
        #expect(EditServer.state.withLock { $0.updates } == [["deliver": "local"]])
    }

    @Test func aRenameKeepsTheBotPrefixAndAnUntouchedEditSendsNothing() async throws {
        let store = try await connectedStore()
        let routine = store.jobs[0]
        try await store.update(routine, title: routine.title, prompt: routine.prompt, schedule: routine.schedule, destination: routine.destination)
        try await store.update(routine, title: "Evening post", prompt: routine.prompt, schedule: routine.schedule, destination: routine.destination)
        #expect(EditServer.state.withLock { $0.updates } == [["name": "[bot:crew-test-peer] Evening post"]])
    }

    @Test func aForeignTargetIsLeftAlone() async throws {
        let store = try await connectedStore()
        let routine = store.jobs[0]
        var foreign = routine
        foreign.destination = .other("bot-chat")
        try await store.update(foreign, title: routine.title, prompt: "New prompt", schedule: routine.schedule, destination: foreign.destination)
        #expect(EditServer.state.withLock { $0.updates } == [["prompt": "New prompt"]])
    }
}
