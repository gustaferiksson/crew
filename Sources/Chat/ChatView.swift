import SwiftUI

struct ChatActions {
    var send: (String, [Attachment], [Bot], SendMode) -> Void = { _, _, _, _ in }
    var sendHidden: (String) -> Void = { _ in }
    var completePath: (String) async -> [PathCompletion] = { _ in [] }
    var stop: () -> Void = {}
    var transcribe: (Data) async throws -> String = { _ in "" }
    var openPersona: () -> Void = {}
    var changeModel: (ModelChoice) -> Void = { _ in }
    var respond: (ApprovalRequest.ID, ApprovalChoice) -> Void = { _, _ in }
    var retry: (String) -> Void = { _ in }
    var unqueue: (Turn.ID) -> Void = { _ in }
    var answer: (QuestionRequest.ID, [String: String]) -> Void = { _, _ in }
    var retryPayment: (ApprovalRequest.ID) -> Void = { _ in }
    var expirePayment: (ApprovalRequest.ID) -> Void = { _ in }
    var dismissPaymentNotice: () -> Void = {}
    var addShop: (String) -> Void = { _ in }
    var dismissShopOffer: () -> Void = {}
}

struct ChatPresentation {
    var revealsTimestamps = false
    var expandedTurns: Set<Turn.ID> = []
    var expandedWork: Set<WorkItem.ID> = []
    var scrollTarget: Turn.ID?
    var attachments: [Attachment] = []
    var draft = ""
    var dictation: Dictation?
    var holdProgress = 0.0
    var questionProgress = QuestionProgress()
}

private let separatorGap: TimeInterval = 60 * 60

private let separatorFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    return formatter
}()

struct ChatView<Avatar: View, EmptyState: View>: View {
    let botName: String
    var title: String?
    let avatar: Avatar
    let transcript: Transcript
    let emptyState: EmptyState
    let mentionable: [Bot]
    let slashCommands: [SlashCommand]
    var features: ComposerFeatures
    var request: PendingRequest?
    var payment: PaymentCardState?
    var paymentNotice: String?
    var shopOffer: String?
    var offlineReason: String?
    var activity: String?
    var models: ModelSwitcher?
    var focus: SearchFocus?
    var actions = ChatActions()

    @Binding var draft: String
    let tray: AttachmentTray
    @State private var position = ScrollPosition(idType: Turn.ID.self)
    @State private var barRoom = CGFloat.infinity
    @State private var barHeight: CGFloat = 0
    @State private var expandedTurns: Set<Turn.ID>
    @State private var expandedWork: Set<WorkItem.ID>
    @State private var expandedRuns: Set<String> = []
    @GestureState private var dragTravel: CGFloat = 0
    @State private var trackpadTravel: CGFloat = 0
    @State private var timestampWidth: CGFloat = 40
    @State private var surfaces = SurfaceStore()
    @State private var highlighted: Turn.ID?
    @State private var handledFocus: UUID?
    @State private var responses: [SensoryFeedback] = []
    @FocusState private var isComposerFocused: Bool
    private let presentation: ChatPresentation

    init(botName: String, title: String? = nil, avatar: Avatar, transcript: Transcript, emptyState: EmptyState, mentionable: [Bot], slashCommands: [SlashCommand] = [], draft: Binding<String>, tray: AttachmentTray, features: ComposerFeatures = .all, request: PendingRequest? = nil, payment: PaymentCardState? = nil, paymentNotice: String? = nil, shopOffer: String? = nil, offlineReason: String? = nil, activity: String? = nil, models: ModelSwitcher? = nil, focus: SearchFocus? = nil, presentation: ChatPresentation = ChatPresentation(), actions: ChatActions = ChatActions()) {
        self.botName = botName
        self.title = title
        self.avatar = avatar
        self.transcript = transcript
        self.emptyState = emptyState
        self.mentionable = mentionable
        self.slashCommands = slashCommands
        self.features = features
        self.request = request
        self.payment = payment
        self.paymentNotice = paymentNotice
        self.shopOffer = shopOffer
        self.offlineReason = offlineReason
        self.activity = activity
        self.models = models
        self.focus = focus
        self.actions = actions
        self.presentation = presentation
        _expandedTurns = State(initialValue: presentation.expandedTurns)
        _expandedWork = State(initialValue: presentation.expandedWork)
        _draft = draft
        self.tray = tray
    }

    private var reveal: CGFloat {
        if presentation.revealsTimestamps { return -timestampWidth }
        return -min(max(0, -(dragTravel + trackpadTravel)) / 3, timestampWidth)
    }

    private var composerPhase: Composer.Phase {
        if let offlineReason { return .offline(reason: offlineReason) }
        return transcript.turns.last { $0.pending == nil }?.status == .streaming ? .running : .idle
    }

    var body: some View {
        TranscriptScroll(position: $position, revision: transcript, barHeight: barHeight) {
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
                            surfaces: surfaces,
                            activity: turn.status == .streaming ? activity : nil,
                            reveal: reveal,
                            timestampWidth: timestampWidth,
                            mentionable: mentionable,
                            expandedTurns: $expandedTurns,
                            expandedWork: $expandedWork,
                            expandedRuns: $expandedRuns,
                            stop: offlineReason == nil ? actions.stop : nil,
                            retry: actions.retry,
                            unqueue: { actions.unqueue(turn.id) }
                        )
                        .background {
                            if highlighted == turn.id {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.tint.opacity(0.12))
                                    .padding(-8)
                            }
                        }
                    }
                    .id(turn.id)
                }
            }
            .scrollTargetLayout()
            .animation(.interactiveSpring, value: reveal)
            .padding(16)
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.bottom } action: { barRoom = $0 }
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
        .onChange(of: transcript, initial: true) {
            surfaces.send = actions.sendHidden
            surfaces.sync(transcript)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard features.contains(.attachments) else { return false }
            tray.add(urls)
            return true
        }
        .overlay {
            if transcript.turns.isEmpty { emptyState }
        }
        .safeAreaBar(edge: .bottom) {
            HeightCap(cap: barRoom) {
                VStack(spacing: 8) {
                    if let paymentNotice {
                        PaymentNoticeCard(text: paymentNotice, dismiss: actions.dismissPaymentNotice)
                            .frame(maxWidth: 560)
                            .padding(.horizontal, 16)
                    } else if case .approval(let approval) = request, approval.isPayment {
                        PaymentCard(
                            request: approval,
                            state: payment ?? PaymentCardState(lookup: .unverified(featureMissing: false)),
                            botName: botName,
                            avatar: avatar.scaleEffect(20 / 28).frame(width: 20, height: 20),
                            holdProgress: presentation.holdProgress,
                            respond: { actions.respond(approval.id, $0) },
                            retry: { actions.retryPayment(approval.id) },
                            expire: { actions.expirePayment(approval.id) }
                        )
                        .disabled(offlineReason != nil)
                        .id(approval.id)
                        .frame(maxWidth: 560)
                        .padding(.horizontal, 16)
                        .transition(.blurReplace)
                        #if os(iOS)
                        .onAppear { isComposerFocused = false }
                        .simultaneousGesture(TapGesture().onEnded { isComposerFocused = false })
                        .simultaneousGesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.height > 0 { isComposerFocused = false } })
                        #endif
                    } else if case .approval(let approval) = request {
                        ApprovalCard(request: approval, botName: botName) { choice in
                            responses.append(choice == .deny ? .impact(flexibility: .rigid) : .success)
                            actions.respond(approval.id, choice)
                        }
                            .frame(maxWidth: 560)
                            .padding(.horizontal, 16)
                    } else if request == nil, let shopOffer {
                        ShopOfferCard(botName: botName, host: shopOffer, notNow: actions.dismissShopOffer) { actions.addShop(shopOffer) }
                            .frame(maxWidth: 560)
                            .padding(.horizontal, 16)
                    }
                    if case .question(let question) = request {
                        QuestionCard(request: question, botName: botName, progress: presentation.questionProgress) { answers in
                            responses.append(.success)
                            actions.answer(question.id, answers)
                        }
                            .id(question.id)
                            .frame(maxWidth: 560)
                            .padding(.horizontal, 16)
                    }
                    Composer(botName: botName, phase: composerPhase, draft: $draft, isFocused: $isComposerFocused, tray: tray, mentionable: mentionable, slashCommands: slashCommands, features: features, completePath: actions.completePath, dictation: presentation.dictation, transcribe: actions.transcribe) { mode in
                        position.scrollTo(id: transcriptEnd)
                        actions.send(draft, tray.take(), mentionedBots(in: draft, among: mentionable), mode)
                        draft = ""
                    } stop: {
                        actions.stop()
                    }
                }
            }
            .animation(.smooth, value: request?.id)
            .sensoryFeedback(.warning, trigger: request?.id) { _, id in id != nil }
            .sensoryFeedback(.selection, trigger: models?.current) { previous, _ in previous != nil }
            .sensoryFeedback(trigger: responses) { _, responses in responses.last }
            .sensoryFeedback(trigger: transcript.turns.last { $0.pending == nil && $0.prompt != nil }?.status) { old, new in
                guard old == .streaming else { return nil }
                return new == .error ? .error : nil
            }
            #if os(iOS)
            .ignoresSafeArea(.container, edges: .bottom)
            #endif
            #if os(macOS)
            .padding(.trailing, NSScroller.preferredScrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0)
            #endif
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { barHeight = $0 }
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let title {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    PersonaPill(botName: botName, avatar: avatar) {
                        #if os(iOS)
                        isComposerFocused = false
                        #endif
                        actions.openPersona()
                    }
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
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .navigationTitle(title ?? botName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .toolbar(removing: .title)
        #endif
        .onChange(of: [focus?.id.uuidString, "\(transcript.turns.count)"], initial: true) {
            guard let focus, focus.id != handledFocus, let target = transcript.turn(matching: focus.snippet) else { return }
            position.scrollTo(id: target.id, anchor: .center)
            handledFocus = focus.id
            highlighted = target.id
        }
        .task(id: highlighted) {
            guard highlighted != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.6)) { highlighted = nil }
        }
        .task(id: surfaces.blocks.count) {
            guard let target = presentation.scrollTarget else { return }
            position.scrollTo(id: target, anchor: .top)
        }
    }
}

struct TurnView: View {
    let turn: Turn
    let surfaces: SurfaceStore
    let activity: String?
    let reveal: CGFloat
    let timestampWidth: CGFloat
    let mentionable: [Bot]
    @Binding var expandedTurns: Set<Turn.ID>
    @Binding var expandedWork: Set<WorkItem.ID>
    @Binding var expandedRuns: Set<String>
    var stop: (() -> Void)?
    var retry: (String) -> Void = { _ in }
    var unqueue: () -> Void = {}

    @Environment(BotStore.self) private var bots

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let speaker = turn.speaker {
                let bot = bots.bots.first { $0.name == speaker }
                HStack(spacing: 8) {
                    if let bot {
                        BotAvatar(bot: bot, status: .idle, photo: bots.photos[bot.id], size: 24)
                    }
                    Text(bot?.title ?? speaker)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                if let notice = turn.notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                if let output = turn.output {
                    ReplyText(source: "```\n\(output)\n```")
                        .modifier(MessageMenu(text: output, shape: .rect(cornerRadius: 12)))
                }
                if turn.isCommand, turn.finishedAt == nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                }
                if let prompt = turn.prompt {
                    if !prompt.attachments.isEmpty {
                        PromptAttachments(attachments: prompt.attachments)
                            .offset(x: reveal)
                    }
                    if !prompt.text.isEmpty {
                        UserBubble(text: prompt.text, mentionable: mentionable, turnID: turn.id, pending: turn.pending, unqueue: unqueue)
                            .offset(x: reveal)
                            .modifier(Timestamp(date: prompt.sentAt, reveal: reveal, width: timestampWidth))
                    }
                    if let pending = turn.pending {
                        Text(pending == .queued ? "Queued" : "Waiting")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .offset(x: reveal)
                            .padding(.top, -12)
                    }
                }
                if let answer = turn.answer {
                    ReplyText(source: a2uiFenced(answer))
                        .environment(\.surfaces, surfaces)
                        .padding(12)
                        .modifier(MessageMenu(text: answer, shape: .rect(cornerRadius: 18)))
                        .padding(-12)
                        .modifier(Timestamp(date: turn.startedAt, reveal: reveal, width: timestampWidth))
                }
                if !turn.work.isEmpty || turn.status == .streaming {
                    WorkLog(turn: turn, activity: activity, expandedTurns: $expandedTurns, expandedWork: $expandedWork, expandedRuns: $expandedRuns, stop: turn.status == .streaming && turn.agentMessage == nil ? stop : nil)
                        .modifier(Timestamp(date: turn.startedAt, reveal: reveal, width: timestampWidth))
                }
                ForEach(Array(turn.paymentReceipts.enumerated()), id: \.offset) { _, receipt in
                    PaymentReceiptRow(receipt: receipt)
                }
                if !turn.reply.isEmpty {
                    ReplyText(source: a2uiFenced(turn.reply))
                        .environment(\.surfaces, surfaces)
                        .padding(12)
                        .modifier(MessageMenu(text: turn.reply, shape: .rect(cornerRadius: 18)))
                        .padding(-12)
                        .modifier(Timestamp(date: turn.finishedAt ?? turn.startedAt, reveal: reveal, width: timestampWidth))
                }
                if turn.status == .error {
                    HStack(spacing: 8) {
                        Label(turn.failure ?? "Something went wrong.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        if let retryID = turn.retryID {
                            Button("Retry") { retry(retryID) }
                                .buttonStyle(.borderless)
                        }
                    }
                    .font(.footnote)
                }
                if let failure = turn.deliveryFailure {
                    let bot = bots.bots.first { $0.name == failure.target }?.title ?? failure.target ?? String(localized: "the bot")
                    let tint = failure.isUnconfirmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red)
                    Label {
                        Text("\(Text(failure.headline(for: bot)).foregroundStyle(tint))\(failure.explanation(for: bot).map { " " + $0 } ?? "")")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(tint)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                if turn.status == .interrupted {
                    Label("Stopped", systemImage: "stop.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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

private struct PersonaPill<Avatar: View>: View {
    let botName: String
    let avatar: Avatar
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

private struct HeightCap: Layout {
    let cap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: proposal.height.map { min($0, cap) })) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.minX, y: bounds.maxY), anchor: .bottomLeading, proposal: ProposedViewSize(bounds.size))
    }
}
