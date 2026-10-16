import SwiftUI
import UniformTypeIdentifiers

enum ChatFixture {
    case conversation, history, timestamps, workLog, question, offline, attachments, dictation, mentions, agentMessage, a2ui, a2uiCards, a2uiForm, a2uiTable, a2uiChart, a2uiMap

    var presentation: ChatPresentation {
        if self == .history { return ChatPresentation(scrollTarget: "t1") }
        if self == .a2ui { return ChatPresentation(scrollTarget: "a1") }
        if self == .a2uiCards { return ChatPresentation(scrollTarget: "a2") }
        if self == .a2uiForm { return ChatPresentation(scrollTarget: "a6") }
        if self == .a2uiTable { return ChatPresentation(scrollTarget: "a5") }
        if self == .a2uiChart { return ChatPresentation(scrollTarget: "a4") }
        if self == .a2uiMap { return ChatPresentation(scrollTarget: "a7") }
        if self == .timestamps { return ChatPresentation(revealsTimestamps: true, scrollTarget: "t2") }
        if self == .workLog { return ChatPresentation(expandedTurns: ["t4"], expandedWork: ["t4-w0", "t4-w2"], scrollTarget: "t4") }
        if self == .attachments {
            return ChatPresentation(attachments: [
                Attachment(kind: .image, name: "Trailhead.png", data: Self.samplePhoto),
                Attachment(kind: .file, name: "Lofoten itinerary.pdf"),
            ])
        }
        if self == .mentions { return ChatPresentation(draft: "Loop in @ada and @sc") }
        if self == .agentMessage { return ChatPresentation(expandedTurns: ["m2"]) }
        if self == .dictation {
            let levels = (0..<Dictation.levelCount).map { 0.25 + 0.6 * abs(sin(Double($0) * 0.7)) * Double($0 % 5 + 1) / 5 }
            return ChatPresentation(dictation: Dictation(fixture: levels, startedAt: .now.addingTimeInterval(-7)))
        }
        return ChatPresentation()
    }

    var request: PendingRequest? {
        if self == .conversation {
            return .approval(ApprovalRequest(
                id: "srq-1a2b3c4d5e6f",
                command: "kubectl --context staging apply -f deploy/staging/crew-api.yaml",
                description: "Applies the new API deployment to the staging cluster.",
                toolName: "terminal",
                choices: [.once, .session, .always, .deny]
            ))
        }
        if self == .question {
            return .question(QuestionRequest(id: "srq-9f8e7d6c5b4a", questions: [
                .init(id: "env", text: "Which environment should I deploy to?", choices: ["Staging", "Production", "Both, staging first"]),
            ]))
        }
        return nil
    }

    var transcript: Transcript {
        let now = Date.now
        let turns = [greeting(now.addingTimeInterval(-26 * 3600)), packing(now.addingTimeInterval(-3 * 3600)), notes(now.addingTimeInterval(-2.8 * 3600)), ciFix(now.addingTimeInterval(-25 * 60))]
        if [.offline, .history, .dictation].contains(self) { return Transcript(turns: turns) }
        if [.a2ui, .a2uiCards, .a2uiForm, .a2uiTable, .a2uiChart, .a2uiMap].contains(self) { return Transcript(turns: Self.a2uiTurns(now)) }
        if self == .attachments { return Transcript(turns: [greeting(now.addingTimeInterval(-26 * 3600)), receipt(now.addingTimeInterval(-6 * 60))]) }
        if self == .mentions {
            let reply = Turn(id: "t8", agentMessage: AgentMessage("Message from 🤖 Scout (@scout): Found three options under 2 000 kr: SAS on Friday at 07:10, Norwegian on Saturday at 09:45, and Widerøe via Bodø."), status: .complete, startedAt: now.addingTimeInterval(-4 * 60))
            return Transcript(turns: [greeting(now.addingTimeInterval(-26 * 3600)), handoff(now.addingTimeInterval(-6 * 60)), reply])
        }
        if self == .agentMessage { return Transcript(turns: [greeting(now.addingTimeInterval(-26 * 3600)), message("m1", "Flights for Saturday are booked.", reply: "Thanks, Scout!", at: now.addingTimeInterval(-40 * 60)), message("m2", "Can you add the Lofoten ferry to the trip notes?", reply: "Added the 08:15 ferry to the trip notes.", at: now.addingTimeInterval(-5 * 60))]).visible }
        return Transcript(turns: turns + [deploy(now.addingTimeInterval(-48))])
    }

    private func greeting(_ start: Date) -> Turn {
        Turn(
            id: "t1",
            prompt: Prompt(text: "Hey, are you up?", sentAt: start),
            work: [WorkItem(id: "t1-w0", kind: .thinking("Casual greeting late in the evening. Keep it short and friendly."), startedAt: start.addingTimeInterval(1), duration: 2)],
            reply: "Always. What are we working on tonight?",
            status: .complete,
            startedAt: start,
            finishedAt: start.addingTimeInterval(4)
        )
    }

    private func message(_ id: String, _ text: String, reply: String, at start: Date) -> Turn {
        Turn(
            id: id,
            agentMessage: AgentMessage("Message from 🤖 Scout (@scout): \(text)"),
            work: [WorkItem(id: "\(id)-w0", kind: .tool(ToolCall(name: "message_agent", subject: "scout", arguments: #"{"target": "scout"}"#, status: .success)), startedAt: start.addingTimeInterval(2), duration: 1)],
            reply: reply,
            status: .complete,
            startedAt: start,
            finishedAt: start.addingTimeInterval(4)
        )
    }

    private func packing(_ start: Date) -> Turn {
        Turn(
            id: "t2",
            prompt: Prompt(text: "What should I pack for Lofoten next week? Mostly hiking, maybe one boat trip.", sentAt: start),
            work: [
                WorkItem(id: "t2-w0", kind: .thinking("**Checking the forecast first.** Late October in Lofoten is wet and windy, so layering matters more than warmth alone."), startedAt: start.addingTimeInterval(1), duration: 3),
                WorkItem(id: "t2-w1", kind: .tool(ToolCall(name: "web_search", subject: "Lofoten weather late October", arguments: #"{"query": "Lofoten weather late October"}"#, result: #"{"success": true, "results": 5}"#, outcome: "Found 5 results in 1.4s", status: .success)), startedAt: start.addingTimeInterval(4), duration: 1.4),
            ],
            reply: """
            Expect **4 to 9 °C**, rain most days and strong wind on the ridges. Pack in layers:

            ### Clothing
            1. Base layers
               - Merino top and leggings
               - Two pairs of wool socks
            2. Mid layer: a light fleece or synthetic puffy
            3. Shell: waterproof jacket *and* trousers

            ### Gear
            - Trail shoes with grip; the rock is slick when wet
            - Headlamp, daylight is only about **8 hours**
            - Dry bag for the boat trip

            > Book the boat early; tours thin out after the season ends.
            """,
            status: .complete,
            startedAt: start,
            finishedAt: start.addingTimeInterval(14)
        )
    }

    private func notes(_ start: Date) -> Turn {
        Turn(
            id: "t3",
            prompt: Prompt(text: """
            Here are my raw notes from the planning call, can you turn them into a checklist?
            - flights: OSL to BOO on Thursday, 07:40, then the Widerøe hop to Leknes
            - car: pick up at Leknes airport, ask about winter tyres
            - Friday: Reinebringen if the weather holds, otherwise Kvalvika beach
            - Saturday: boat to Trollfjord, 11:00 from Svolvær, bring the dry bag
            - Sunday: rest day, Henningsvær, maybe the climbing café
            - book the rorbu in Hamnøy for three nights, check if they take card
            - buy groceries in Leknes before driving out, shops close early on Saturday
            - return flight Monday 13:15, leave Hamnøy by 10
            - remember the power bank and the camera charger
            """, sentAt: start),
            work: [WorkItem(id: "t3-w0", kind: .thinking("Group by day, keep the bookings at the top since they are time sensitive."), startedAt: start.addingTimeInterval(1), duration: 2)],
            reply: """
            **Book now**
            - Rorbu in Hamnøy, 3 nights (ask about card payment)
            - Trollfjord boat, Saturday 11:00 from Svolvær

            **Before you go**
            - Power bank, camera charger, dry bag

            Want me to add these to your reminders?
            """,
            status: .complete,
            startedAt: start,
            finishedAt: start.addingTimeInterval(9)
        )
    }

    private func ciFix(_ start: Date) -> Turn {
        let steps: [(WorkItem.Kind, TimeInterval)] = [
            (.thinking("The CI failure is probably in the snapshot or the build step. Start with the latest run log before touching code."), 4),
            (.tool(ToolCall(name: "terminal", subject: "gh run list --limit 3", arguments: #"{"command": "gh run list --limit 3"}"#, result: "X  Build  main  push  3m12s\n✓  Build  main  push  3m40s", status: .success)), 2),
            (.tool(ToolCall(name: "terminal", subject: "gh run view 9921 --log-failed", arguments: #"{"command": "gh run view 9921 --log-failed"}"#, result: "error: 'safeAreaBar(edge:content:)' is only available in iOS 26.0 or newer", status: .success)), 3),
            (.thinking("The runner image still uses the iOS 18 SDK. The fix is to pin the Xcode version in the workflow, not to add availability checks."), 5),
            (.tool(ToolCall(name: "read_file", subject: ".github/workflows/build.yml", arguments: #"{"path": ".github/workflows/build.yml"}"#, result: "runs-on: macos-15\nsteps:\n  - uses: actions/checkout@v4", status: .success)), 1),
            (.tool(ToolCall(name: "search_files", subject: "xcode-version", arguments: #"{"pattern": "xcode-version", "path": "."}"#, result: #"{"matches": []}"#, status: .success)), 1),
            (.tool(ToolCall(name: "web_search", subject: "GitHub Actions macos-26 runner Xcode 27", arguments: #"{"query": "GitHub Actions macos-26 runner Xcode 27"}"#, result: #"{"success": true, "results": 4}"#, outcome: "Found 4 results in 2.1s", status: .success)), 2),
            (.tool(ToolCall(name: "patch", subject: ".github/workflows/build.yml", arguments: #"{"path": ".github/workflows/build.yml", "old": "macos-15", "new": "macos-26"}"#, result: #"{"success": true}"#, status: .success)), 1),
            (.tool(ToolCall(name: "terminal", subject: "./build.sh", arguments: #"{"command": "./build.sh"}"#, result: #"{"exit_code": 1, "error": "xcodegen: command not found"}"#, outcome: "Exited with code 1", status: .error)), 6),
            (.note("XcodeGen isn't installed in this container, installing it before retrying."), 0),
            (.tool(ToolCall(name: "terminal", subject: "brew install xcodegen", arguments: #"{"command": "brew install xcodegen"}"#, result: "==> Pouring xcodegen--2.46.0.arm64_tahoe.bottle.tar.gz", status: .success)), 38),
            (.tool(ToolCall(name: "terminal", subject: "./build.sh", arguments: #"{"command": "./build.sh"}"#, result: "✅ Built .build/Build/Products/Debug/Crew.app", status: .success)), 61),
            (.tool(ToolCall(name: "terminal", subject: "git checkout -b fix/ci-runner", arguments: #"{"command": "git checkout -b fix/ci-runner"}"#, result: "Switched to a new branch 'fix/ci-runner'", status: .success)), 1),
            (.tool(ToolCall(name: "terminal", subject: "git commit -am \"Pin CI to macos-26\"", arguments: #"{"command": "git commit -am \"Pin CI to macos-26\""}"#, result: "[fix/ci-runner 4f2a9c1] Pin CI to macos-26", status: .success)), 1),
            (.tool(ToolCall(name: "terminal", subject: "gh pr create --fill", arguments: #"{"command": "gh pr create --fill"}"#, result: "https://github.com/gustaferiksson/crew/pull/42", status: .success)), 3),
            (.thinking("PR is open. Summarise the cause, the fix and the follow-up about XcodeGen in the image."), 2),
            (.tool(ToolCall(name: "memory", subject: "CI runner needs macos-26 for the 27 SDK", arguments: #"{"action": "add", "content": "CI runner needs macos-26 for the 27 SDK"}"#, result: #"{"success": true}"#, status: .success)), 1),
        ]
        var work: [WorkItem] = []
        for (offset, (kind, duration)) in steps.enumerated() {
            let startedAt = work.last.map { $0.startedAt.addingTimeInterval(($0.duration ?? 0) + 1) } ?? start.addingTimeInterval(2)
            work.append(WorkItem(id: "t4-w\(offset)", kind: kind, startedAt: startedAt, duration: duration))
        }
        return Turn(
            id: "t4",
            prompt: Prompt(text: "CI is red on crew again. Can you fix it and open a PR?", sentAt: start),
            work: work,
            reply: """
            Fixed and opened [PR #42](https://github.com/gustaferiksson/crew/pull/42).

            The runner was still on `macos-15`, which ships the iOS 18 SDK, so every Liquid Glass API failed to resolve. I pinned the workflow to `macos-26`:

            ```yaml
            runs-on: macos-26
            ```

            The local build passes. One follow-up: the image has no XcodeGen, so I added it to the setup step.
            """,
            status: .complete,
            startedAt: start,
            finishedAt: start.addingTimeInterval(160)
        )
    }

    private func receipt(_ start: Date) -> Turn {
        Turn(
            id: "t6",
            prompt: Prompt(text: "Does this receipt match the booking?", sentAt: start, attachments: [
                Attachment(kind: .image, name: "Receipt.png", data: Self.samplePhoto),
                Attachment(kind: .file, name: "Booking confirmation.pdf"),
            ]),
            work: [WorkItem(id: "t6-w0", kind: .tool(ToolCall(name: "vision_analyze", subject: "Receipt.png", arguments: "{}", status: .success)), startedAt: start.addingTimeInterval(2), duration: 3)],
            reply: "Yes. Both show **2 480 kr** for two nights at Reine Rorbuer, 24 to 26 October.",
            status: .complete,
            startedAt: start,
            finishedAt: start.addingTimeInterval(9)
        )
    }

    private func handoff(_ start: Date) -> Turn {
        Turn(
            id: "t7",
            prompt: Prompt(text: "Can you ask @scout to find flights for the Lofoten trip in March? Two adults, flexible dates, and @ada, please add the booking to my calendar.", sentAt: start),
            work: [WorkItem(id: "t7-w0", kind: .tool(ToolCall(name: "message_agent", subject: "scout", arguments: #"{"target": "scout", "message": "Please find flights to Lofoten in March for two adults, flexible dates."}"#, result: #"{"status": "queued", "process_id": "proc_7f3a"}"#, status: .success)), startedAt: start.addingTimeInterval(2), duration: 1)],
            reply: "Asked Scout to look for flights to Lofoten. The results will show up in Scout's chat.",
            status: .complete,
            startedAt: start,
            finishedAt: start.addingTimeInterval(5)
        )
    }

    static var samplePhoto: Data {
        let renderer = ImageRenderer(content:
            LinearGradient(colors: [.teal, .blue, .indigo], startPoint: .top, endPoint: .bottom)
                .overlay { Image(systemName: "mountain.2.fill").font(.system(size: 72)).foregroundStyle(.white) }
                .frame(width: 320, height: 240)
        )
        renderer.scale = 2
        let output = NSMutableData()
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    private func deploy(_ start: Date) -> Turn {
        Turn(
            id: "t5",
            prompt: Prompt(text: "Nice. Deploy it to staging.", sentAt: start),
            work: [
                WorkItem(id: "t5-w0", kind: .thinking("Need the staging context and the manifest path before applying anything."), startedAt: start.addingTimeInterval(1), duration: 3),
                WorkItem(id: "t5-w1", kind: .tool(ToolCall(name: "read_file", subject: "deploy/staging/crew-api.yaml", arguments: #"{"path": "deploy/staging/crew-api.yaml"}"#, result: "apiVersion: apps/v1\nkind: Deployment", status: .success)), startedAt: start.addingTimeInterval(5), duration: 1),
                WorkItem(id: "t5-w2", kind: .tool(ToolCall(name: "terminal", subject: "kubectl --context staging apply -f deploy/staging/crew-api.yaml", arguments: #"{"command": "kubectl --context staging apply -f deploy/staging/crew-api.yaml"}"#, status: .running)), startedAt: start.addingTimeInterval(8)),
            ],
            status: .streaming,
            startedAt: start
        )
    }
}

struct ChatFixtureScreen: View {
    let fixture: ChatFixture

    @Environment(BotStore.self) private var bots
    @State private var session: ChatSession?

    private static let hermes = Bot(
        name: "default", displayName: "Hermes", description: nil, model: nil, isDefault: true, hasAvatar: false, canonicalSession: nil,
        meta: BotMeta(shape: "blob", color: "#8b5cf6", expression: "happy"), metaRevision: nil
    )

    init(fixture: ChatFixture) {
        self.fixture = fixture
        _session = State(initialValue: fixture == .mentions ? ChatSession(fixture: Self.hermes, transcript: fixture.transcript, todos: []) : nil)
    }

    var body: some View {
        #if os(iOS)
        NavigationStack(path: .constant([0])) {
            Text("Crew")
                .navigationTitle("Crew")
                .navigationDestination(for: Int.self) { _ in chat }
        }
        #else
        NavigationStack { chat }
        #endif
    }

    private var chat: some View {
        ChatView(
            botName: "Hermes",
            avatar: BotAvatar(
                bot: Self.hermes,
                status: fixture == .conversation ? .waiting(.approval) : .idle,
                photo: nil,
                size: 28
            ),
            transcript: fixture == .mentions ? fixture.transcript.visible : fixture.transcript,
            emptyState: EmptyView(),
            mentionable: bots.bots.filter { $0.id != "default" },
            request: fixture.request,
            offlineReason: fixture == .offline ? "Can't reach hermes.example.com" : nil,
            activity: fixture == .conversation ? "Preparing terminal" : nil,
            presentation: fixture.presentation
        )
        .environment(\.chatSession, session)
    }
}
