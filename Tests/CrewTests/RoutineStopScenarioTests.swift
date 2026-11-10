import Foundation
import Synchronization
import Testing

nonisolated private let scenario = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/scenarios/routine-stop")

nonisolated private func recordedJSON(_ name: String) -> [String: Any] {
    let data = (try? Data(contentsOf: scenario.appending(path: "\(name).json"))) ?? Data()
    return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
}

nonisolated private func listing(_ job: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: [job])) ?? Data()
}

private func job(_ object: [String: Any]) throws -> RoutineJob {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode([RoutineJob].self, from: listing(object))[0]
}

private func missed(finishedAt: String) -> [String: Any] {
    var object = recordedJSON("jobs.stopped")
    object["latest_execution"] = [
        "id": "m1", "status": "missed", "error": "missed ×3 (skipped, catch-up off; next run 2026-11-11T19:58:24+00:00)",
        "claimed_at": finishedAt, "finished_at": finishedAt, "scheduled_instant": "2026-11-10T17:00:00+00:00",
    ]
    return object
}

@Test func recordedRowsShowRunningAndStopped() throws {
    let idle = try job(recordedJSON("jobs.idle"))
    #expect(idle.tracksRuns)
    #expect(idle.liveRunID == nil)
    #expect(idle.lastRun == nil)
    #expect(idle.schedule == "every 1440m")
    #expect(idle.title == "Long check")

    let running = try job(recordedJSON("jobs.running"))
    #expect(running.liveRunID == "4ea12cffbe6d4962a7d57412fb1d22a4")

    let stopped = try job(recordedJSON("jobs.stopped"))
    #expect(stopped.liveRunID == nil)
    #expect(stopped.lastStatus == "cancelled")
    #expect(stopped.lastRun != nil)
    #expect(stopped.issue == nil)
    #expect(stopped.result.text == "Stopped")
    #expect(stopped.result.symbol == "stop.circle")

    let scheduled = try job(recordedJSON("jobs.scheduled"))
    #expect(scheduled.liveRunID != nil)
    #expect(scheduled.latestRun?.scheduledInstant != nil)

    let pausedWhileRunning = try job(recordedJSON("jobs.paused-running"))
    #expect(pausedWhileRunning.isPaused)
    #expect(pausedWhileRunning.liveRunID != nil)
}

@Test func aMissNewerThanTheLastRunIsTheResult() throws {
    let routine = try job(missed(finishedAt: "2026-11-10T20:30:00+00:00"))
    #expect(routine.lastStatus == "missed")
    #expect(routine.missedRuns == 3)
    #expect(routine.lastRun == (try Date("2026-11-10T17:00:00+00:00", strategy: .iso8601)))
    #expect(routine.result.text == "Missed 3 runs")
    #expect(routine.result.symbol == "calendar.badge.exclamationmark")
}

@Test func aMissBookedDuringTheLastRunDoesNotHideItsResult() throws {
    let routine = try job(missed(finishedAt: "2026-11-10T19:58:50+00:00"))
    #expect(routine.lastStatus == "cancelled")
    #expect(routine.missedRuns == nil)
}

@Test func aServerWithoutTheLedgerNeverShowsRunning() throws {
    var object = recordedJSON("jobs.idle")
    object["live_execution"] = nil
    object["latest_execution"] = nil
    #expect(try job(object).tracksRuns == false)
}

@Test func theRestFireErrorObjectIsTheIssue() throws {
    var object = recordedJSON("jobs.idle")
    object["last_fire_error"] = ["at": "2026-11-10T19:00:00+00:00", "detail": "scheduled fire could not be forwarded"]
    #expect(try job(object).issue == "scheduled fire could not be forwarded")
}

nonisolated private struct CronStub: Sendable {
    var list = listing(recordedJSON("jobs.idle"))
    var afterCancel = listing(recordedJSON("jobs.stopped"))
    var cancelReply = Data(#"{"cancelled": true, "execution_id": "4ea12cffbe6d4962a7d57412fb1d22a4", "success": true}"#.utf8)
    var triggerFails = false
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
        let (body, fails): (Data, Bool) = CronServer.state.withLock { stub in
            if path.hasSuffix("/cancel") {
                if String(decoding: stub.cancelReply, as: UTF8.self).contains(#""cancelled": true"#) { stub.list = stub.afterCancel }
                return (stub.cancelReply, false)
            }
            if path.hasSuffix("/trigger") { return (Data("{}".utf8), stub.triggerFails) }
            return (stub.list, false)
        }
        let delay = path.hasSuffix("/trigger") ? 0.5 : 0
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
    private func connectedStore(_ stub: CronStub) async throws -> RoutineStore {
        CronServer.state.withLock { $0 = stub }
        let server = try #require(URL(string: "https://hermes.example.com"))
        let gateway = Gateway(server: server, urlSession: CronServer.session) { "" }
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
        CronServer.state.withLock { $0.list = listing(recordedJSON("jobs.running")) }
        await trigger.value

        #expect(store.alert == nil)
        #expect(store.isRunning(store.jobs[0]))
    }

    @Test func aRunNowThatFailsWithNothingRunningShowsTheFailure() async throws {
        let store = try await connectedStore(CronStub(triggerFails: true))
        await store.trigger(store.jobs[0])
        #expect(store.alert?.title == "Couldn't Update Routine")
        #expect(!store.isRunning(store.jobs[0]))
    }

    @Test func stopSettlesOnTheStoppedRunThenSaysNothingWasRunning() async throws {
        let store = try await connectedStore(CronStub(list: listing(recordedJSON("jobs.running"))))
        #expect(store.isRunning(store.jobs[0]))

        await store.stop(store.jobs[0])
        #expect(store.alert == nil)
        #expect(store.jobs[0].result.text == "Stopped")
        #expect(!store.isRunning(store.jobs[0]))
        #expect(store.stopping.isEmpty && store.inFlight.isEmpty)

        CronServer.state.withLock { $0.cancelReply = (try? Data(contentsOf: scenario.appending(path: "cancel.idle.json"))) ?? Data() }
        await store.stop(store.jobs[0])
        #expect(store.alert?.title == "Nothing Was Running")
    }

    @Test func stopDoesNotWaitForARunThatStartsRightAfter() async throws {
        var next = recordedJSON("jobs.running")
        next["live_execution"] = ["id": "next-run", "status": "running", "claimed_at": "2026-11-10T19:59:01+00:00"]
        let store = try await connectedStore(CronStub(list: listing(recordedJSON("jobs.running")), afterCancel: listing(next)))
        let started = Date.now
        await store.stop(store.jobs[0])
        #expect(Date.now.timeIntervalSince(started) < 5)
        #expect(store.isRunning(store.jobs[0]))
        #expect(store.alert == nil)
    }
}
