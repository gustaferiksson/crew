import SwiftUI

struct ChatActions {
    var send: (String, [Attachment], SendMode) -> Void = { _, _, _ in }
    var stop: () -> Void = {}
    var transcribe: (Data) async throws -> String = { _ in "" }
    var openPersona: () -> Void = {}
    var changeModel: (ModelChoice) -> Void = { _ in }
    var respond: (ApprovalRequest.ID, ApprovalChoice) -> Void = { _, _ in }
    var answer: (QuestionRequest.ID, [String: String]) -> Void = { _, _ in }
}

struct ChatPresentation {
    var revealsTimestamps = false
    var expandedTurns: Set<Turn.ID> = []
    var expandedWork: Set<WorkItem.ID> = []
    var scrollTarget: Turn.ID?
    var attachments: [Attachment] = []
    var dictation: Dictation?
}

private let separatorGap: TimeInterval = 60 * 60

private let bottomID = "bottom"

private let separatorFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    return formatter
}()

struct ChatView: View {
    let botName: String
    let avatar: BotAvatar
    let transcript: Transcript
    var request: PendingRequest?
    var offlineReason: String?
    var activity: String?
    var models: ModelSwitcher?
    var actions = ChatActions()

    @State private var draft = ""
    @State private var tray: AttachmentTray
    @State private var position = ScrollPosition(idType: Turn.ID.self)
    @State private var isAtBottom = true
    @State private var expandedTurns: Set<Turn.ID>
    @State private var expandedWork: Set<WorkItem.ID>
    @State private var expandedRuns: Set<String> = []
    @GestureState private var dragTravel: CGFloat = 0
    @State private var trackpadTravel: CGFloat = 0
    @State private var timestampWidth: CGFloat = 40
    private let presentation: ChatPresentation

    init(botName: String, avatar: BotAvatar, transcript: Transcript, request: PendingRequest? = nil, offlineReason: String? = nil, activity: String? = nil, models: ModelSwitcher? = nil, presentation: ChatPresentation = ChatPresentation(), actions: ChatActions = ChatActions()) {
        self.botName = botName
        self.avatar = avatar
        self.transcript = transcript
        self.request = request
        self.offlineReason = offlineReason
        self.activity = activity
        self.models = models
        self.actions = actions
        self.presentation = presentation
        _expandedTurns = State(initialValue: presentation.expandedTurns)
        _expandedWork = State(initialValue: presentation.expandedWork)
        _tray = State(initialValue: AttachmentTray(items: presentation.attachments))
    }

    private var reveal: CGFloat {
        if presentation.revealsTimestamps { return -timestampWidth }
        return -min(max(0, -(dragTravel + trackpadTravel)) / 3, timestampWidth)
    }

    private var composerPhase: Composer.Phase {
        if let offlineReason { return .offline(reason: offlineReason) }
        return transcript.turns.last?.status == .streaming ? .running : .idle
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(Array(transcript.turns.enumerated()), id: \.element.id) { index, turn in
                            VStack(alignment: .leading, spacing: 12) {
                                let previousEnd = index > 0 ? transcript.turns[index - 1].finishedAt ?? transcript.turns[index - 1].startedAt : nil
                                let start = turn.prompt?.sentAt ?? turn.startedAt
                                if previousEnd.map({ start.timeIntervalSince($0) > separatorGap || !Calendar.current.isDate($0, inSameDayAs: start) }) ?? true {
                                    Text(separatorFormatter.string(from: start))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                }
                                TurnView(
                                    turn: turn,
                                    activity: index == transcript.turns.count - 1 ? activity : nil,
                                    reveal: reveal,
                                    timestampWidth: timestampWidth,
                                    expandedTurns: $expandedTurns,
                                    expandedWork: $expandedWork,
                                    expandedRuns: $expandedRuns
                                )
                            }
                            .id(turn.id)
                        }
                    }
                    .scrollTargetLayout()
                    .animation(.interactiveSpring, value: reveal)
                    .padding(16)
                    Color.clear
                        .frame(height: 0)
                        .id(bottomID)
                }
            }
            .defaultScrollAnchor(.bottom)
            .scrollPosition($position)
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY + geometry.contentInsets.bottom
            } action: { _, distance in
                isAtBottom = distance < 40
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 16, inputKinds: [.directTouch, .indirectTouch])
                    .updating($dragTravel) { value, state, _ in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        state = min(0, value.translation.width)
                    }
            )
            .background {
                Text(Calendar.current.date(bySettingHour: 22, minute: 58, second: 0, of: .now) ?? .now, format: .dateTime.hour().minute())
                    .font(.caption)
                    .monospacedDigit()
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { timestampWidth = $0 }
            }
            #if os(macOS)
            .background {
                TrackpadSwipe { trackpadTravel = $0 }
            }
            #endif
            .onChange(of: transcript) {
                if isAtBottom { position.scrollTo(edge: .bottom) }
            }
            .dropDestination(for: URL.self) { urls, _ in
                tray.add(urls)
                return true
            }
            .safeAreaBar(edge: .bottom) {
                VStack(spacing: 8) {
                    if case .approval(let approval) = request {
                        ApprovalCard(request: approval, botName: botName) { actions.respond(approval.id, $0) }
                            .frame(maxWidth: 560)
                            .padding(.horizontal, 16)
                    }
                    if case .question(let question) = request {
                        QuestionCard(request: question, botName: botName) { actions.answer(question.id, $0) }
                            .frame(maxWidth: 560)
                            .padding(.horizontal, 16)
                    }
                    Composer(botName: botName, phase: composerPhase, draft: $draft, tray: tray, dictation: presentation.dictation, transcribe: actions.transcribe) { mode in
                        actions.send(draft, tray.take(), mode)
                        draft = ""
                    } stop: {
                        actions.stop()
                    }
                }
                .overlay(alignment: .top) {
                    if !isAtBottom {
                        Button("Jump to Latest", systemImage: "arrow.down") {
                            withAnimation(.smooth) { proxy.scrollTo(bottomID, anchor: .bottom) }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        #if os(macOS)
                        .controlSize(.large)
                        #endif
                        .transition(.scale.combined(with: .opacity))
                        .padding(.bottom, 12)
                        .frame(height: 0, alignment: .bottom)
                    }
                }
                .animation(.smooth, value: isAtBottom)
                #if os(iOS)
                .ignoresSafeArea(.container, edges: .bottom)
                #endif
                #if os(macOS)
                .padding(.trailing, NSScroller.preferredScrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0)
                #endif
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectHidden(true, for: .bottom)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PersonaPill(botName: botName, avatar: avatar, action: actions.openPersona)
                        .contextMenu {
                            if let models, !models.providers.isEmpty {
                                ModelPicker(
                                    providers: models.providers,
                                    selection: Binding(get: { models.current }, set: { if let choice = $0 { actions.changeModel(choice) } })
                                )
                                .pickerStyle(.menu)
                            }
                        }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .navigationTitle(botName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #else
            .toolbar(removing: .title)
            #endif
            .task {
                guard let target = presentation.scrollTarget else { return }
                position.scrollTo(id: target, anchor: .top)
            }
        }
    }
}

private struct TurnView: View {
    let turn: Turn
    let activity: String?
    let reveal: CGFloat
    let timestampWidth: CGFloat
    @Binding var expandedTurns: Set<Turn.ID>
    @Binding var expandedWork: Set<WorkItem.ID>
    @Binding var expandedRuns: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let notice = turn.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            if let prompt = turn.prompt {
                if !prompt.attachments.isEmpty {
                    PromptAttachments(attachments: prompt.attachments)
                        .offset(x: reveal)
                }
                if !prompt.text.isEmpty {
                    UserBubble(text: prompt.text)
                        .offset(x: reveal)
                        .modifier(Timestamp(date: prompt.sentAt, reveal: reveal, width: timestampWidth))
                }
            }
            if !turn.work.isEmpty || turn.status == .streaming {
                WorkLog(turn: turn, activity: activity, expandedTurns: $expandedTurns, expandedWork: $expandedWork, expandedRuns: $expandedRuns)
                    .modifier(Timestamp(date: turn.startedAt, reveal: reveal, width: timestampWidth))
            }
            if !turn.reply.isEmpty {
                MarkdownText(source: turn.reply)
                    #if os(macOS)
                    .textSelection(.enabled)
                    #endif
                    .padding(12)
                    .modifier(MessageMenu(text: turn.reply, shape: .rect(cornerRadius: 18)))
                    .padding(-12)
                    .modifier(Timestamp(date: turn.finishedAt ?? turn.startedAt, reveal: reveal, width: timestampWidth))
            }
            if turn.status == .error {
                Label(turn.failure ?? "Something went wrong.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if turn.status == .interrupted {
                Label("Stopped", systemImage: "stop.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct Timestamp: ViewModifier {
    let date: Date
    let reveal: CGFloat
    let width: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                Text(date, format: .dateTime.hour().minute())
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .padding(.vertical, 4)
                    .padding(.leading, 8)
                    .background {
                        Rectangle()
                            .fill(.background)
                            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2)], startPoint: .leading, endPoint: .trailing))
                    }
                    .offset(x: width + 8 + reveal)
                    .opacity(-reveal / width)
                    .padding(.top, 4)
            }
            .help(Text(date, format: .dateTime.weekday().day().month().hour().minute()))
    }
}

private struct PersonaPill: View {
    let botName: String
    let avatar: BotAvatar
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                avatar
                Text(botName)
                    .font(.headline)
                    .lineLimit(1)
            }
            .padding(.trailing, 20)
            #if os(macOS)
            .padding(.leading, 4)
            .padding(.vertical, 4)
            #else
            .padding(.leading, 8)
            .padding(.vertical, 8)
            #endif
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}
