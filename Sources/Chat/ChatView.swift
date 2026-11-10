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
    var continueDiscussion: (String) -> Void = { _ in }
    var unqueue: (Turn.ID) -> Void = { _ in }
    var answer: (QuestionRequest.ID, [String: String]) -> Void = { _, _ in }
    var retryPayment: (ApprovalRequest.ID) -> Void = { _ in }
    var expirePayment: (ApprovalRequest.ID) -> Void = { _ in }
    var dismissPaymentNotice: () -> Void = {}
    var addShop: (String) -> Void = { _ in }
    var dismissShopOffer: () -> Void = {}
    var loadEarlier: () -> Void = {}
}

struct ChatPresentation {
    var revealsTimestamps = false
    var expandedTurns: Set<Turn.ID> = []
    var expandedWork: Set<WorkItem.ID> = []
    var expandedCards: Set<String> = []
    var scrollTarget: Turn.ID?
    var attachments: [Attachment] = []
    var draft = ""
    var dictation: Dictation?
    var holdProgress = 0.0
    var questionProgress = QuestionProgress()
}

@Observable
final class TranscriptExpansion {
    var turns: Set<Turn.ID>
    var work: Set<WorkItem.ID>
    var runs: Set<String> = []

    init(turns: Set<Turn.ID> = [], work: Set<WorkItem.ID> = []) {
        self.turns = turns
        self.work = work
    }
}

final class LatestChatActions {
    var actions = ChatActions()
}

extension EnvironmentValues {
    @Entry var chatActions: LatestChatActions?
    @Entry var transcriptExpansion: TranscriptExpansion?
}

private struct TranscriptRevision: Equatable {
    let count: Int
    let last: Turn?
}

private let separatorGap: TimeInterval = 60 * 60
private let earlierLead = 5
private let focusPageLimit = 4

private let separatorFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.doesRelativeDateFormatting = true
    return formatter
}()

struct ChatView<Avatar: View, EmptyState: View>: View {
    let botName: String
    var profile: String?
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
    var earlier = EarlierHistory.complete
    var pinKey: String?
    var actions = ChatActions()

    @Binding var draft: String
    let tray: AttachmentTray
    @State private var position = ScrollPosition(idType: Turn.ID.self)
    #if os(iOS)
    @State private var barRoom = CGFloat.infinity
    #else
    private let barRoom = CGFloat.infinity
    #endif
    @State private var barHeight: CGFloat = 0
    @State private var expansion: TranscriptExpansion
    @State private var latestActions = LatestChatActions()
    @GestureState private var dragTravel: CGFloat = 0
    @State private var trackpadTravel: CGFloat = 0
    @State private var timestampWidth: CGFloat = 40
    @State private var surfaces = SurfaceStore()
    @State private var highlighted: Turn.ID?
    @State private var handledFocus: UUID?
    @State private var focusPages: (focus: UUID, count: Int)?
    @State private var responses: [SensoryFeedback] = []
    @State private var openedCard: OpenedCard?
    @State private var expandedCards: Set<String>
    @State private var chipFrame = CGRect.zero
    @State private var unpins = 0
    @State private var isOnScreen = false
    @State private var liveTurn: Turn.ID?
    @State private var transcriptTaps = 0
    @Environment(ChatPins.self) private var pins
    @Environment(BotStore.self) private var bots
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @Environment(\.appearsActive) private var appearsActive
    #else
    private let appearsActive = true
    #endif
    @FocusState private var isComposerFocused: Bool
    private let presentation: ChatPresentation

    init(botName: String, profile: String? = nil, title: String? = nil, avatar: Avatar, transcript: Transcript, emptyState: EmptyState, mentionable: [Bot], slashCommands: [SlashCommand] = [], draft: Binding<String>, tray: AttachmentTray, features: ComposerFeatures = .all, request: PendingRequest? = nil, payment: PaymentCardState? = nil, paymentNotice: String? = nil, shopOffer: String? = nil, offlineReason: String? = nil, activity: String? = nil, models: ModelSwitcher? = nil, focus: SearchFocus? = nil, earlier: EarlierHistory = .complete, pinKey: String? = nil, presentation: ChatPresentation = ChatPresentation(), actions: ChatActions = ChatActions()) {
        self.botName = botName
        self.profile = profile
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
        self.earlier = earlier
        self.pinKey = pinKey
        self.actions = actions
        self.presentation = presentation
        _expansion = State(initialValue: TranscriptExpansion(turns: presentation.expandedTurns, work: presentation.expandedWork))
        _expandedCards = State(initialValue: presentation.expandedCards)
        _draft = draft
        self.tray = tray
    }

    private var composer: some View {
        Composer(botName: botName, phase: composerPhase, draft: $draft, isFocused: $isComposerFocused, tray: tray, mentionable: mentionable, slashCommands: slashCommands, features: features, completePath: actions.completePath, dictation: presentation.dictation, transcribe: actions.transcribe) { mode in
            position.scrollTo(id: transcriptEnd, anchor: .bottom)
            Speaker.shared.stop()
            actions.send(draft, tray.take(), mentionedBots(in: draft, among: mentionable), mode)
            draft = ""
        } stop: {
            actions.stop()
        }
    }

    private var lastTurnState: [String]? {
        transcript.turns.last { $0.pending == nil && $0.outgoingMessage == nil }.map { [$0.id, $0.status.rawValue] }
    }

    private func readFinishedReply() {
        guard isOnScreen, scenePhase == .active, appearsActive else {
            liveTurn = nil
            return
        }
        if let live = liveTurn, let done = transcript.turns.first(where: { $0.id == live }), done.status != .streaming {
            liveTurn = nil
            if let profile { Speaker.shared.readAloud(done, profile: profile, from: botName) }
        }
        if let turn = transcript.turns.last(where: { $0.pending == nil && $0.outgoingMessage == nil }), turn.status == .streaming { liveTurn = turn.id }
    }

    private var reveal: CGFloat {
        if presentation.revealsTimestamps { return -timestampWidth }
        return -min(max(0, -(dragTravel + trackpadTravel)) / 3, timestampWidth)
    }

    private var pinnedCard: String? {
        guard let pinKey, request == nil, paymentNotice == nil, shopOffer == nil, let id = pins.pinned(in: pinKey), surfaces.present.contains(id) else { return nil }
        return id
    }

    private var showsPinnedCard: Binding<Bool> {
        Binding(get: { openedCard != nil && openedCard?.id == pinnedCard }, set: { openedCard = $0 ? pinnedCard.map { OpenedCard(id: $0, anchor: openedCard?.anchor) } : nil })
    }

    @ViewBuilder private var cardSheet: some View {
        if let id = openedCard?.id {
            PinnedCardContent(surfaces: surfaces, id: id, fallbackTitle: cardFallbackTitle, isPinned: pinKey.map { pins.pinned(in: $0) == id }) {
                guard let pinKey else { return }
                unpins += 1
                pins.pin(pins.pinned(in: pinKey) == id ? nil : id, in: pinKey)
            }
        }
    }

    private var cardFallbackTitle: String {
        profile == nil ? String(localized: "Card") : String(localized: "Card from \(botName)")
    }

    private var composerPhase: Composer.Phase {
        if let offlineReason { return .offline(reason: offlineReason) }
        return transcript.turns.last { $0.pending == nil && $0.outgoingMessage == nil }?.status == .streaming ? .running : .idle
    }

    var body: some View {
        chat
        .onChange(of: surfaces.present) {
            if let openedCard, !surfaces.present.contains(openedCard.id) { self.openedCard = nil }
        }
        .onChange(of: openedCard) {
            if openedCard != nil { isComposerFocused = false }
        }
        .onChange(of: request?.id) {
            if request != nil { openedCard = nil }
        }
        .popover(isPresented: Binding(get: { openedCard != nil }, set: { if !$0 { openedCard = nil } }), attachmentAnchor: .rect(.rect(openedCard?.anchor ?? chipFrame))) {
            cardSheet
        }
        .coordinateSpace(.named(chatSpace))
        #if os(macOS)
        .focusedSceneValue(\.pinnedCard, pinnedCard == nil ? nil : showsPinnedCard)
        #endif
    }

    private var chat: some View {
        latestActions.actions = actions
        return TranscriptScroll(position: $position, revision: TranscriptRevision(count: transcript.turns.count, last: transcript.turns.last), barHeight: barHeight) {
            if earlier != .complete {
                EarlierHistoryRow(state: earlier, retry: actions.loadEarlier)
                    .padding([.horizontal, .top], 16)
            }
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
                        let speaker = turn.speaker.flatMap { name in bots.bots.first { $0.name == name } }
                        TurnView(
                            turn: turn,
                            surfaces: surfaces,
                            speaker: speaker,
                            speakerPhoto: speaker.flatMap { bots.photos[$0.id] },
                            failureTarget: turn.deliveryFailure.flatMap { failure in bots.bots.first { $0.name == failure.target }?.title },
                            activity: turn.status == .streaming ? activity : nil,
                            reveal: reveal,
                            timestampWidth: timestampWidth,
                            mentionable: mentionable,
                            profile: profile,
                            speakerName: speaker?.title ?? turn.speaker ?? botName,
                            isExpanded: expansion.turns.contains(turn.id),
                            expandedWork: expansion.work.filter { id in turn.work.contains { $0.id == id } },
                            expandedRuns: expansion.runs.filter { id in turn.work.contains { $0.id == id } },
                            canStop: offlineReason == nil
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
            .environment(\.pinKey, pinKey)
            .environment(\.openedCard, $openedCard)
            .environment(\.chatActions, latestActions)
            .environment(\.transcriptExpansion, expansion)
            .environment(\.expandedCards, $expandedCards)
            .environment(\.transcriptTaps, transcriptTaps)
            .animation(.interactiveSpring, value: reveal)
            .padding(16)
        }
        .onScrollTargetVisibilityChange(idType: Turn.ID.self, threshold: 0.01) { ids in
            guard earlier == .more, transcript.turns.prefix(earlierLead).contains(where: { ids.contains($0.id) }) else { return }
            actions.loadEarlier()
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(TapGesture().onEnded { transcriptTaps += 1 })
        .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.bottom } action: { barRoom = $0 }
        #endif
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
        .onChange(of: transcript.turns.map(\.status), initial: true) {
            surfaces.send = actions.sendHidden
            surfaces.sync(transcript)
        }
        .onChange(of: surfaces.newest, initial: true) {
            guard let pinKey, let newest = surfaces.newest else { return }
            pins.arrived(newest, in: pinKey)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard features.contains(.attachments) else { return false }
            tray.add(urls)
            return true
        }
        .overlay {
            if transcript.turns.isEmpty { emptyState }
        }
        #if os(macOS)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        #else
        .safeAreaBar(edge: .bottom) { bottomBar }
        #endif
        .scrollEdgeEffectStyle(.soft, for: .top)
        #if os(iOS)
        .scrollEdgeEffectHidden(true, for: .bottom)
        #endif
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
        .onAppear { isOnScreen = true }
        .onChange(of: lastTurnState, readFinishedReply)
        .onDisappear {
            isOnScreen = false
            liveTurn = nil
            guard let speaking = Speaker.shared.speakingID, transcript.turns.contains(where: { speaking.hasPrefix("\($0.id)-") }) else { return }
            Speaker.shared.stop()
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .toolbar(removing: title == nil ? .title : nil)
        #endif
        .onChange(of: [focus?.id.uuidString, "\(transcript.turns.count)", "\(earlier)"], initial: true) {
            guard let focus, focus.id != handledFocus else { return }
            guard let target = transcript.turn(matching: focus.snippet) else {
                let pages = focusPages?.focus == focus.id ? focusPages?.count ?? 0 : 0
                guard earlier == .more, pages < focusPageLimit else { return }
                focusPages = (focus.id, pages + 1)
                return actions.loadEarlier()
            }
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

    private var bottomBar: some View {
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
                if let pinKey, let pinnedCard, let model = surfaces.processor.surfaceGroupModel[pinnedCard] {
                    PinnedCardChip(model: model, fallbackTitle: cardFallbackTitle) {
                        showsPinnedCard.wrappedValue = true
                    } unpin: {
                        unpins += 1
                        pins.pin(nil, in: pinKey)
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(chatSpace)) } action: { chipFrame = $0 }
                    .transition(.scale(0.5, anchor: .leading).combined(with: .opacity))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    #if os(iOS)
                    .padding(.horizontal, isComposerFocused ? 16 : 28)
                    #else
                    .padding(.horizontal, 16)
                    #endif
                }
                #if os(iOS)
                if let voice = VoiceMessage.shared.attributes, voice.bot.name == profile {
                    VoiceComposer(voice: .shared)
                } else {
                    if VoiceMessage.shared.attributes != nil {
                        VoiceIndicator(voice: .shared)
                    }
                    composer
                }
                #else
                composer
                #endif
            }
        }
        .animation(.smooth, value: request?.id)
        .animation(.smooth, value: pinnedCard)
        .sensoryFeedback(.impact(weight: .light), trigger: unpins)
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
}

struct TurnView: View {
    let turn: Turn
    let surfaces: SurfaceStore
    let speaker: Bot?
    let speakerPhoto: Image?
    let failureTarget: String?
    let activity: String?
    let reveal: CGFloat
    let timestampWidth: CGFloat
    let mentionable: [Bot]
    var profile: String?
    let speakerName: String
    let isExpanded: Bool
    let expandedWork: Set<WorkItem.ID>
    let expandedRuns: Set<String>
    let canStop: Bool

    @Environment(\.chatActions) private var latest

    #if DEBUG
    static var bodies = 0
    #endif

    var body: some View {
        #if DEBUG
        let _ = Self.bodies += 1
        #endif
        VStack(alignment: .leading, spacing: 8) {
            if let name = turn.speaker {
                HStack(spacing: 8) {
                    if let speaker {
                        BotAvatar(bot: speaker, status: nil, photo: speakerPhoto, size: 24)
                    }
                    Text(speaker?.title ?? name)
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
                if let discussion = turn.continueID {
                    Button("Continue") { latest?.actions.continueDiscussion(discussion) }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tint)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                        .accessibilityLabel("Continue Discussion")
                        .accessibilityInputLabels(["Continue", "Continue Discussion"])
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, -12)
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
                        UserBubble(text: prompt.text, mentionable: mentionable, turnID: turn.id, pending: turn.pending, unqueue: { latest?.actions.unqueue(turn.id) })
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
                        .modifier(MessageMenu(text: answer, shape: .rect(cornerRadius: 18), speech: turn.status == .streaming ? nil : ("\(turn.id)-answer", turn.speaker ?? profile, speakerName)))
                        .padding(-12)
                        .modifier(Timestamp(date: turn.startedAt, reveal: reveal, width: timestampWidth))
                }
                if !turn.work.isEmpty || turn.status == .streaming {
                    WorkLog(turn: turn, activity: activity, isExpanded: isExpanded, expandedWork: expandedWork, expandedRuns: expandedRuns, stop: canStop && turn.status == .streaming && turn.agentMessage == nil ? { latest?.actions.stop() } : nil)
                        .modifier(Timestamp(date: turn.startedAt, reveal: reveal, width: timestampWidth))
                }
                ForEach(Array(turn.paymentReceipts.enumerated()), id: \.offset) { _, receipt in
                    PaymentReceiptRow(receipt: receipt)
                }
                ForEach(turn.warnings, id: \.self) { warning in
                    Label {
                        Text(warning)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Warning")
                    }
                    .font(.footnote)
                }
                if !turn.reply.isEmpty {
                    ReplyText(source: a2uiFenced(turn.reply))
                        .environment(\.surfaces, surfaces)
                        .padding(12)
                        .modifier(MessageMenu(text: turn.reply, shape: .rect(cornerRadius: 18), speech: turn.status == .streaming ? nil : ("\(turn.id)-reply", turn.speaker ?? profile, speakerName)))
                        .padding(-12)
                        .modifier(Timestamp(date: turn.finishedAt ?? turn.startedAt, reveal: reveal, width: timestampWidth))
                }
                if turn.status == .error {
                    HStack(spacing: 8) {
                        Label(turn.failure ?? "Something went wrong.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        if let retryID = turn.retryID {
                            Button("Retry") { latest?.actions.retry(retryID) }
                                .buttonStyle(.borderless)
                        }
                    }
                    .font(.footnote)
                }
                if let failure = turn.deliveryFailure {
                    let bot = failureTarget ?? failure.target ?? String(localized: "the bot")
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
