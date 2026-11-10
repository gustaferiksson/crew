import Foundation
import Synchronization
import Testing

nonisolated private let scenario = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/routine-stop")

nonisolated private func listing(_ name: String, _ edit: (inout [String: Any]) -> Void = { _ in }) -> Data {
    let data = (try? Data(contentsOf: scenario.appending(path: "\(name).json"))) ?? Data()
    var object = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    edit(&object)
    return (try? JSONSerialization.data(withJSONObject: [object])) ?? Data()
}

nonisolated private let recordedLiveRunID = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: scenario.appending(path: "jobs.running.json")))) as? [String: Any])
    .flatMap { ($0["live_execution"] as? [String: Any])?["id"] as? String } ?? ""

private func job(_ listed: Data) throws -> RoutineJob {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode([RoutineJob].self, from: listed)[0]
}

private func missed(secondsAfterTheLastRun offset: TimeInterval) throws -> Data {
    let finishedAt = try #require(try job(listing("jobs.stopped")).lastRun).addingTimeInterval(offset).ISO8601Format()
    return listing("jobs.stopped") {
        $0["latest_execution"] = [
            "id": "m1", "status": "missed", "error": "missed ×3 (skipped, catch-up off; next run 2026-11-11T19:58:24+00:00)",
            "claimed_at": finishedAt, "finished_at": finishedAt, "scheduled_instant": "2026-11-10T17:00:00+00:00",
        ]
    }
}

@Test func recordedRowsShowRunningAndStopped() throws {
    let idle = try job(listing("jobs.idle"))
    #expect(idle.tracksRuns)
    #expect(idle.liveRunID == nil)
    #expect(idle.lastRun == nil)
    #expect(idle.schedule == "every 1440m")
    #expect(idle.title == "Long check")

    let running = try job(listing("jobs.running"))
    #expect(running.liveRunID == recordedLiveRunID && !recordedLiveRunID.isEmpty)

    let stopped = try job(listing("jobs.stopped"))
    #expect(stopped.liveRunID == nil)
    #expect(stopped.lastStatus == "cancelled")
    #expect(stopped.lastRun != nil)
    #expect(stopped.issue == nil)
    #expect(stopped.result.text == "Stopped")
    #expect(stopped.result.symbol == "stop.circle")

    let scheduled = try job(listing("jobs.scheduled"))
    #expect(scheduled.liveRunID != nil)
    #expect(scheduled.latestRun?.scheduledInstant != nil)

    let pausedWhileRunning = try job(listing("jobs.paused-running"))
    #expect(pausedWhileRunning.isPaused)
    #expect(pausedWhileRunning.liveRunID != nil)
}

@Test func aMissNewerThanTheLastRunIsTheResult() throws {
    let routine = try job(missed(secondsAfterTheLastRun: 3600))
    #expect(routine.lastStatus == "missed")
    #expect(routine.missedRuns == 3)
    #expect(routine.lastRun == (try Date("2026-11-10T17:00:00+00:00", strategy: .iso8601)))
    #expect(routine.result.text == "Missed 3 runs")
    #expect(routine.result.symbol == "calendar.badge.exclamationmark")
}

@Test func aMissBookedDuringTheLastRunDoesNotHideItsResult() throws {
    let routine = try job(missed(secondsAfterTheLastRun: -10))
    #expect(routine.lastStatus == "cancelled")
    #expect(routine.missedRuns == nil)
}

@Test func aServerWithoutTheLedgerHasNoStop() throws {
    let routine = try job(listing("jobs.idle") {
        $0["live_execution"] = nil
        $0["latest_execution"] = nil
    })
    #expect(routine.tracksRuns == false)
}

@Test func theRestFireErrorObjectIsTheIssue() throws {
    let routine = try job(listing("jobs.idle") { $0["last_fire_error"] = ["at": "2026-11-10T19:00:00+00:00", "detail": "scheduled fire could not be forwarded"] })
    #expect(routine.issue == "scheduled fire could not be forwarded")
}

nonisolated private struct CronStub: Sendable {
    var list = listing("jobs.idle")
    var afterCancel = listing("jobs.stopped")
    var cancels = true
    var triggerFails = false
    var triggerDelay = 1.0
}

nonisolated private final class CronServer: URLProtocol {
    static let state = Mutex(CronStub())
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CronServer.self]
        return URLSession(configuration: configuration)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let path = url.path()
        let (body, fails, delay): (Data, Bool, Double) = CronServer.state.withLock { stub in
            if path.hasSuffix("/cancel") {
                if stub.cancels { stub.list = stub.afterCancel }
                return (Data(#"{"cancelled": \#(stub.cancels), "execution_id": "\#(recordedLiveRunID)", "success": true}"#.utf8), false, 0)
            }
            if path.hasSuffix("/trigger") { return (Data("{}".utf8), stub.triggerFails, stub.triggerDelay) }
            return (stub.list, false, 0)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            if fails {
                client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
                return
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

@Suite(.serialized) struct RoutineStopStoreTests {
    private let gateway = Gateway(server: URL(string: "https://hermes.example.com")!, urlSession: CronServer.session) { "" }

    private func connectedStore(_ stub: CronStub) async throws -> RoutineStore {
        CronServer.state.withLock { $0 = stub }
        let store = RoutineStore()
        Task { await store.run(profile: "crew-test", gateway: gateway, urlSession: CronServer.session) }
        for _ in 0..<100 where !store.isLoaded { try await Task.sleep(for: .milliseconds(20)) }
        try #require(store.jobs.count == 1)
        return store
    }

    @Test func runNowShowsRunningAndATimeoutWhileLiveIsNoFailure() async throws {
        let store = try await connectedStore(CronStub(triggerFails: true))
        let idle = store.jobs[0]
        #expect(!store.isRunning(idle))

        let trigger = Task { await store.trigger(idle) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.isRunning(idle))
        #expect(!store.inFlight.contains(idle.id))
        CronServer.state.withLock { $0.list = listing("jobs.running") }
        await trigger.value

        #expect(store.alert == nil)
        #expect(store.isRunning(store.jobs[0]))
    }

    @Test func stopReachesARunWhileRunNowIsStillOpen() async throws {
        let store = try await connectedStore(CronStub(triggerDelay: 3))
        let trigger = Task { await store.trigger(store.jobs[0]) }
        try await Task.sleep(for: .milliseconds(100))
        CronServer.state.withLock { $0.list = listing("jobs.running") }

        await store.stop(store.jobs[0])
        #expect(store.alert == nil)
        #expect(store.jobs[0].result.text == "Stopped")
        await trigger.value
        #expect(!store.isRunning(store.jobs[0]))
    }

    @Test func aRunNowThatFailsWithNothingRunningShowsTheFailure() async throws {
        let store = try await connectedStore(CronStub(triggerFails: true))
        await store.trigger(store.jobs[0])
        #expect(store.alert?.title == "Couldn't Update Routine")
        #expect(!store.isRunning(store.jobs[0]))
    }

    @Test func aRunNowLeftBehindByABotSwitchStaysSilent() async throws {
        let store = try await connectedStore(CronStub(triggerFails: true))
        let trigger = Task { await store.trigger(store.jobs[0]) }
        try await Task.sleep(for: .milliseconds(100))
        Task { await store.run(profile: "crew-test-other", gateway: gateway, urlSession: CronServer.session) }
        await trigger.value
        #expect(store.alert == nil)
    }

    @Test func runNowOnAServerWithoutTheLedgerStillShowsRunning() async throws {
        let store = try await connectedStore(CronStub(list: listing("jobs.idle") {
            $0["live_execution"] = nil
            $0["latest_execution"] = nil
        }))
        let trigger = Task { await store.trigger(store.jobs[0]) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.isRunning(store.jobs[0]))
        await trigger.value
        #expect(!store.isRunning(store.jobs[0]))
    }

    @Test func stopSettlesOnTheStoppedRunThenSaysNothingWasRunning() async throws {
        let store = try await connectedStore(CronStub(list: listing("jobs.running")))
        #expect(store.isRunning(store.jobs[0]))

        await store.stop(store.jobs[0])
        #expect(store.alert == nil)
        #expect(store.jobs[0].result.text == "Stopped")
        #expect(!store.isRunning(store.jobs[0]))
        #expect(store.stopping.isEmpty && store.inFlight.isEmpty)

        CronServer.state.withLock { $0.cancels = false }
        await store.stop(store.jobs[0])
        #expect(store.alert?.title == "Nothing Was Running")
    }

    @Test func stopDoesNotWaitForARunThatStartsRightAfter() async throws {
        let next = listing("jobs.running") { $0["live_execution"] = ["id": "next-run", "status": "running", "claimed_at": "2026-11-10T19:59:01+00:00"] }
        let store = try await connectedStore(CronStub(list: listing("jobs.running"), afterCancel: next))
        let started = Date.now
        await store.stop(store.jobs[0])
        #expect(Date.now.timeIntervalSince(started) < 5)
        #expect(store.isRunning(store.jobs[0]))
        #expect(store.alert == nil)
    }
}
