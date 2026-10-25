import PhotosUI
import SwiftUI

#if os(macOS)
private let fieldHeight: CGFloat = 36
private let rowSpacing: CGFloat = 8
#else
private let fieldHeight: CGFloat = 40
private let rowSpacing: CGFloat = 12
#endif
#if os(macOS)
private let sideMargin: CGFloat = 16
#else
private let sideMargin: CGFloat = 28
#endif
private let holdThreshold = Duration.milliseconds(250)

nonisolated enum SendMode: Sendable {
    case send, steer, queue
}

struct ComposerFeatures: OptionSet {
    let rawValue: Int

    static let attachments = ComposerFeatures(rawValue: 1 << 0)
    static let steering = ComposerFeatures(rawValue: 1 << 1)
    static let all: ComposerFeatures = [.attachments, .steering]
}

struct Composer: View {
    private struct Hold: Equatable {
        let began: Date
        let cancels: Bool
    }

    enum Phase: Equatable {
        case idle
        case running
        case offline(reason: String)
    }

    let botName: String
    let phase: Phase
    @Binding var draft: String
    let tray: AttachmentTray
    let mentionable: [Bot]
    let slashCommands: [SlashCommand]
    let features: ComposerFeatures
    let completePath: (String) async -> [PathCompletion]
    let transcribe: (Data) async throws -> String
    let send: (SendMode) -> Void
    let stop: () -> Void

    @Namespace private var glass
    @State private var dictation: Dictation
    @State private var isPickingPhotos = false
    @State private var isImportingFiles = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var showsHoldHint = false
    #if os(iOS)
    @State private var selection: TextSelection?
    #endif
    @GestureState private var hold: Hold?
    let isFocused: FocusState<Bool>.Binding

    init(botName: String, phase: Phase, draft: Binding<String>, isFocused: FocusState<Bool>.Binding, tray: AttachmentTray, mentionable: [Bot], slashCommands: [SlashCommand] = [], features: ComposerFeatures = .all, completePath: @escaping (String) async -> [PathCompletion], dictation: Dictation? = nil, transcribe: @escaping (Data) async throws -> String, send: @escaping (SendMode) -> Void, stop: @escaping () -> Void) {
        self.botName = botName
        self.phase = phase
        _draft = draft
        self.isFocused = isFocused
        self.tray = tray
        self.mentionable = mentionable
        self.slashCommands = slashCommands
        self.features = features
        self.completePath = completePath
        self.transcribe = transcribe
        self.send = send
        self.stop = stop
        _dictation = State(initialValue: dictation ?? Dictation())
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !tray.items.isEmpty }
    private var isOffline: Bool { if case .offline = phase { true } else { false } }
    private var mentionQuery: String? { draft.firstMatch(of: /(?:^|\s)@([^\s@]*)$/).map { String($0.1) } }
    private var slashQuery: String? { draft.wholeMatch(of: /\/(\S*)/).map { String($0.1) } }

    var body: some View {
        VStack(spacing: 8) {
            if case .offline(let reason) = phase {
                Label(reason, systemImage: "wifi.exclamationmark")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if showsHoldHint {
                Label("Hold to record", systemImage: "waveform.mid")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            if !tray.items.isEmpty {
                PendingAttachments(tray: tray)
            }
            if let mentionQuery {
                MentionPicker(query: mentionQuery, bots: mentionable, completePath: completePath) { tag in
                    draft = String(draft.dropLast(mentionQuery.count + 1)) + tag + " "
                    isFocused.wrappedValue = true
                }
            }
            if let slashQuery {
                SlashPicker(query: slashQuery, commands: slashCommands) { command in
                    draft = command + " "
                    isFocused.wrappedValue = true
                }
            }
            GlassEffectContainer(spacing: rowSpacing) {
                HStack(alignment: .bottom, spacing: rowSpacing) {
                    if features.contains(.attachments) {
                        attachMenu
                            .disabled(isOffline)
                    }
                    field
                        .frame(maxWidth: .infinity, minHeight: fieldHeight)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: fieldHeight / 2))
                        .glassEffectID("field", in: glass)
                    #if os(macOS)
                    if phase == .running {
                        Button("Stop", systemImage: "stop.fill", action: stop)
                            .composerCircle(.regular.interactive())
                            .glassEffectID("stop", in: glass)
                    }
                    if dictation.phase == .idle {
                        actionButton
                    }
                    #endif
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .menuStyle(.button)
            }
        }
        .animation(.smooth, value: canSend)
        .animation(.smooth, value: phase)
        .animation(.smooth, value: dictation.phase)
        .animation(.smooth, value: tray.items)
        .animation(.smooth, value: mentionQuery == nil)
        .animation(.smooth, value: slashQuery == nil)
        .animation(.smooth, value: showsHoldHint)
        .animation(.smooth, value: hold?.cancels)
        .sensoryFeedback(.start, trigger: dictation.phase) { _, phase in phase == .listening }
        .onChange(of: hold) { previous, current in
            guard let previous else { return beginHold(current) }
            if current == nil { endHold(previous) }
        }
        .task(id: showsHoldHint) {
            guard showsHoldHint else { return }
            try? await Task.sleep(for: .seconds(1.5))
            showsHoldHint = false
        }
        .photosPicker(isPresented: $isPickingPhotos, selection: $photos, maxSelectionCount: Attachment.maxCount, matching: .images)
        .onChange(of: photos) { _, picked in
            guard !picked.isEmpty else { return }
            photos = []
            tray.add(picked)
        }
        .fileImporter(isPresented: $isImportingFiles, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            do {
                tray.add(try result.get())
            } catch {
                tray.failure = error.localizedDescription
            }
        }
        #if os(macOS)
        .onPasteCommand(of: [.fileURL, .png, .tiff]) { _ in
            if features.contains(.attachments) { tray.paste() }
        }
        #endif
        .alert("Can't Attach", isPresented: Binding(get: { tray.failure != nil }, set: { if !$0 { tray.failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(tray.failure ?? "")
        }
        .onChange(of: dictation.text) { _, text in
            if !text.isEmpty { draft = text }
        }
        .onDisappear {
            Task { await dictation.stop() }
        }
        .alert("Dictation Unavailable", isPresented: Binding(get: { dictation.failure != nil }, set: { if !$0 { dictation.failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dictation.failure ?? "")
        }
        .padding(.horizontal, sideMargin)
        #if os(macOS)
        .padding(.bottom, 8)
        #else
        .padding(.bottom, isFocused.wrappedValue ? 8 : 28)
        #endif
    }

    private var textField: TextField<Text> {
        #if os(macOS)
        // On macOS a `selection:` binding follows every NSTextView's selection change, so a reply arriving moved the caret (#106).
        TextField("Message \(botName)", text: $draft, axis: .vertical)
        #else
        TextField("Message \(botName)", text: $draft, selection: $selection, axis: .vertical)
        #endif
    }

    private var attachMenu: some View {
        Menu {
            Button("Photos", systemImage: "photo.on.rectangle") { isPickingPhotos = true }
            Button("Files", systemImage: "folder") { isImportingFiles = true }
            #if os(macOS)
            Button("Paste", systemImage: "doc.on.clipboard") { tray.paste() }
            #endif
        } label: {
            Label("Attach", systemImage: "plus")
        }
        .menuIndicator(.hidden)
        .composerCircle(.regular.interactive())
        .glassEffectID("attach", in: glass)
    }

    private var field: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if dictation.phase == .listening {
                HStack(spacing: 12) {
                    HStack(spacing: 2) {
                        ForEach(Array(dictation.levels.enumerated()), id: \.offset) { _, level in
                            Capsule()
                                .frame(width: 3, height: max(3, level * (fieldHeight - 16)))
                        }
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .clipped()
                    .animation(.smooth(duration: 0.1), value: dictation.levels)
                    if hold?.cancels == true {
                        Text("Release to Cancel")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if let startedAt = dictation.startedAt {
                        Text(startedAt, style: .timer)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: fieldHeight)
            } else if dictation.phase != .idle {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(dictation.phase == .transcribing ? "Transcribing…" : "Starting…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: fieldHeight, alignment: .leading)
            } else {
                textField
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: fieldHeight, alignment: .leading)
                    .focused(isFocused)
                    .onKeyPress(.return, phases: [.down, .repeat]) { press in
                        if press.modifiers.contains(.shift) {
                            #if os(macOS)
                            NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
                            #else
                            selection = draft.insertNewLine(at: selection)
                            #endif
                            return .handled
                        }
                        #if os(macOS)
                        let isComposing = NSApp.windows.contains { ($0.firstResponder as? NSTextView)?.hasMarkedText() == true }
                        if isComposing { return .ignored }
                        let nothingToSend = KeyPress.Result.handled
                        #else
                        let nothingToSend = KeyPress.Result.ignored
                        #endif
                        guard press.phase == .down, canSend, !isOffline else { return nothingToSend }
                        send(phase == .running && features.contains(.steering) ? .steer : .send)
                        return .handled
                    }
            }
            if !canSend || dictation.phase != .idle {
                Image(systemName: hold?.cancels == true ? "xmark.circle.fill" : "waveform.mid")
                    .font(.title3)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(dictation.phase == .listening ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                    .frame(width: 24, height: fieldHeight, alignment: .trailing)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($hold) { value, state, _ in
                                state = Hold(began: state?.began ?? value.time, cancels: hypot(value.translation.width, value.translation.height) > 60)
                            }
                    )
                    .accessibilityElement()
                    .accessibilityLabel("Dictate")
                    .accessibilityHint("Hold to record, release to insert the transcript.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        Task {
                            if dictation.phase == .listening { return await dictation.stop() }
                            await dictation.start(fallback: transcribe)
                        }
                    }
            }
            #if os(iOS)
            if dictation.phase == .idle {
                if canSend {
                    actionButton
                        .opacity(isOffline ? 0.4 : 1)
                } else if phase == .running {
                    Button("Stop", systemImage: "stop.fill", action: stop)
                        .actionCircle(.tint)
                        .foregroundStyle(.white)
                }
            }
            #endif
        }
        .padding(.leading, 16)
        #if os(iOS)
        .padding(.trailing, dictation.phase == .idle && (canSend || phase == .running) ? 0 : 10)
        #else
        .padding(.trailing, canSend && dictation.phase == .idle ? 16 : 12)
        #endif
    }

    private func beginHold(_ pressed: Hold?) {
        Task {
            try? await Task.sleep(for: holdThreshold)
            guard let hold, hold.began == pressed?.began, !hold.cancels else { return }
            await dictation.start(fallback: transcribe)
            guard self.hold == nil else { return }
            await dictation.cancel()
            draft = ""
        }
    }

    private func endHold(_ released: Hold) {
        guard Date.now.timeIntervalSince(released.began) >= holdThreshold / .seconds(1) else {
            showsHoldHint = !released.cancels
            return
        }
        Task {
            if released.cancels {
                await dictation.cancel()
                draft = ""
                return
            }
            await dictation.stop()
        }
    }

    @ViewBuilder private var actionButton: some View {
        if canSend && phase == .running && !tray.items.isEmpty {
            Button("Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { send(.queue) }
                .actionCircle(.tint)
                .foregroundStyle(.white)
                .glassEffectID("action", in: glass)
                .disabled(isOffline)
        } else if canSend && phase == .running && features.contains(.steering) {
            Menu {
                Button("Steer", systemImage: "arrow.turn.down.right") { send(.steer) }
                Button("Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { send(.queue) }
            } label: {
                Label("Steer", systemImage: "arrow.up")
            } primaryAction: {
                send(.steer)
            }
            .menuIndicator(.hidden)
            .actionCircle(.tint)
            .foregroundStyle(.white)
            .glassEffectID("action", in: glass)
            .accessibilityAction(named: "Queue") { send(.queue) }
            .disabled(isOffline)
        } else if canSend {
            Button("Send", systemImage: "arrow.up") { send(.send) }
                .actionCircle(.tint)
                .foregroundStyle(.white)
                .glassEffectID("action", in: glass)
                .disabled(isOffline)
        }
    }
}

extension String {
    mutating func insertNewLine(at selection: TextSelection?) -> TextSelection {
        let range = if case .selection(let range)? = selection?.indices, range.upperBound <= endIndex { range } else { endIndex..<endIndex }
        let offset = utf8.distance(from: utf8.startIndex, to: range.lowerBound)
        replaceSubrange(range, with: "\n")
        return TextSelection(insertionPoint: utf8.index(utf8.startIndex, offsetBy: offset + 1))
    }
}

private extension View {
    func composerCircle(_ glass: Glass) -> some View {
        frame(width: fieldHeight, height: fieldHeight)
            .contentShape(.circle)
            .glassEffect(glass, in: .circle)
    }

    func actionCircle(_ fill: some ShapeStyle) -> some View {
        #if os(iOS)
        font(.body.weight(.semibold))
            .frame(width: 32, height: 32)
            .background(fill, in: .circle)
            .contentShape(.circle)
            .padding(4)
        #else
        composerCircle(.regular.tint(.accentColor).interactive())
        #endif
    }
}
