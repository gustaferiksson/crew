import SwiftUI

nonisolated enum ApprovalChoice: String, Codable, Sendable, CaseIterable {
    case once, session, always, deny
}

nonisolated struct ApprovalRequest: Identifiable, Sendable, Equatable {
    let id: String
    let command: String
    let description: String
    let toolName: String?
    let choices: [ApprovalChoice]
    var requester: String?
    var requestID: String?

    var isPayment: Bool {
        command.hasPrefix(paymentCommandPrefix)
    }
}

nonisolated private let recommendedSuffix = "(recommended)"

nonisolated struct QuestionRequest: Identifiable, Sendable, Equatable {
    struct Question: Identifiable, Sendable, Equatable {
        let id: String
        let text: String
        let choices: [String]
        let recommended: Int?
        let isMultiSelect: Bool

        init(id: String, text: String, choices: [String], isMultiSelect: Bool = false) {
            var trimmed = choices.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let recommended = trimmed.firstIndex { $0.lowercased().hasSuffix(recommendedSuffix) }
            if let recommended {
                trimmed[recommended] = String(trimmed[recommended].dropLast(recommendedSuffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            self.id = id
            self.text = text
            self.choices = trimmed
            self.recommended = recommended
            self.isMultiSelect = isMultiSelect && !choices.isEmpty
        }

        func answer(in progress: QuestionProgress) -> String? {
            if choices.isEmpty {
                let text = (progress.texts[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
            let picked = (progress.picks[id] ?? []).sorted().map { choices[$0] }
            guard isMultiSelect else { return picked.first }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            return picked.isEmpty ? "" : (try? encoder.encode(picked)).map { String(decoding: $0, as: UTF8.self) }
        }
    }

    let id: String
    let questions: [Question]

    func answers(_ progress: QuestionProgress) -> [String: String]? {
        var answers: [String: String] = [:]
        for question in questions {
            guard let answer = question.answer(in: progress) else { return nil }
            answers[question.id] = answer
        }
        return answers
    }
}

nonisolated struct QuestionProgress: Equatable, Sendable {
    var step = 0
    var picks: [String: Set<Int>] = [:]
    var texts: [String: String] = [:]
}

nonisolated enum PendingRequest: Identifiable, Sendable, Equatable {
    case approval(ApprovalRequest)
    case question(QuestionRequest)

    var id: String {
        switch self {
        case .approval(let request): request.id
        case .question(let request): request.id
        }
    }

    var isPayment: Bool {
        guard case .approval(let request) = self else { return false }
        return request.isPayment
    }
}

struct ApprovalCard: View {
    let request: ApprovalRequest
    let botName: String
    let respond: (ApprovalChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(request.requester ?? botName) wants to run a command", systemImage: "exclamationmark.shield.fill")
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.multicolor)
            Text(request.command)
                .font(.footnote.monospaced())
                .lineLimit(4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.tertiary, in: .rect(cornerRadius: 12))
            if !request.description.isEmpty {
                Text(request.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    if request.choices.contains(.session) {
                        Button("Allow for Session") { respond(.session) }
                    }
                    if request.choices.contains(.always) {
                        Button("Always Allow") { respond(.always) }
                    }
                }
                GridRow {
                    Button(role: .destructive) {
                        respond(.deny)
                    } label: {
                        Text("Deny")
                            .foregroundStyle(.red)
                    }
                    Button("Allow Once") { respond(.once) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .buttonSizing(.flexible)
        }
        .padding(16)
        .background { Color.clear.glassEffect(in: .rect(cornerRadius: 28)) }
    }
}

struct QuestionCard: View {
    let request: QuestionRequest
    let botName: String
    let answer: ([String: String]) -> Void

    @State private var progress: QuestionProgress
    @State private var isForward = true
    @State private var autoAdvance: Task<Void, Never>?
    @AccessibilityFocusState private var isQuestionFocused: Bool
    @FocusState private var isFieldFocused: Bool
    @FocusState private var isCardFocused: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverOn
    @Environment(\.accessibilitySwitchControlEnabled) private var isSwitchControlOn
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    init(request: QuestionRequest, botName: String, progress: QuestionProgress = QuestionProgress(), answer: @escaping ([String: String]) -> Void) {
        self.request = request
        self.botName = botName
        self.answer = answer
        _progress = State(initialValue: progress)
    }

    private var question: QuestionRequest.Question? {
        request.questions.indices.contains(progress.step) ? request.questions[progress.step] : nil
    }

    private var isLastStep: Bool {
        progress.step >= request.questions.count - 1
    }

    private var canAdvance: Bool {
        isLastStep ? request.answers(progress) != nil : question?.answer(in: progress) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("\(botName) has a question", systemImage: "questionmark.bubble.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
                if request.questions.count > 1 {
                    Text("\(progress.step + 1) of \(request.questions.count)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(countsDown: !isForward))
                        .accessibilityLabel("Question \(progress.step + 1) of \(request.questions.count)")
                }
            }
            if let question {
                ZStack(alignment: .topLeading) {
                    page(question)
                        .id(question.id)
                        .transition(reducesMotion ? .opacity : .push(from: isForward ? .trailing : .leading))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .mask { Rectangle().padding(.vertical, -16) }
            }
            HStack(spacing: 8) {
                Button("Skip") { answer([:]) }
                    .buttonStyle(.bordered)
                if progress.step > 0 {
                    Button("Back") { move(by: -1) }
                        .buttonStyle(.bordered)
                }
                Button(isLastStep ? "Send" : "Next", action: advance)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
            }
            .buttonBorderShape(.capsule)
            .buttonSizing(.flexible)
        }
        .padding(16)
        .background { Color.clear.glassEffect(in: .rect(cornerRadius: 28)) }
        .animation(.smooth, value: progress.step)
        #if os(macOS)
        .focusable()
        .focusEffectDisabled()
        .focused($isCardFocused)
        .onKeyPress(.return, phases: .down, action: advance(on:))
        #endif
        .onChange(of: progress.step) {
            focusStep()
            isQuestionFocused = true
        }
    }

    private func page(_ question: QuestionRequest.Question) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.text)
                .accessibilityLabel(request.questions.count > 1 ? "Question \(progress.step + 1) of \(request.questions.count). \(question.text)" : question.text)
                .accessibilityFocused($isQuestionFocused)
            if question.choices.isEmpty {
                TextField("Your answer", text: Binding { progress.texts[question.id] ?? "" } set: { progress.texts[question.id] = $0 }, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isFieldFocused)
                    .onKeyPress(.return, phases: .down, action: advance(on:))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 12))
            } else {
                ForEach(question.choices.indices, id: \.self) { index in
                    choice(index, of: question)
                }
            }
        }
    }

    private func choice(_ index: Int, of question: QuestionRequest.Question) -> some View {
        let isPicked = progress.picks[question.id, default: []].contains(index)
        let indicator = question.isMultiSelect ? "square" : "circle"
        return Button {
            pick(index, of: question)
        } label: {
            HStack(spacing: 8) {
                Label(question.choices[index], systemImage: isPicked ? "checkmark.\(indicator).fill" : indicator)
                    .foregroundStyle(isPicked ? Color.accentColor : Color.primary)
                Spacer(minLength: 0)
                if question.recommended == index {
                    Text("Recommended")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.fill.tertiary, in: .capsule)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(isPicked ? .accentColor : .secondary)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private func pick(_ index: Int, of question: QuestionRequest.Question) {
        isCardFocused = true
        if question.isMultiSelect {
            progress.picks[question.id, default: []].formSymmetricDifference([index])
            return
        }
        progress.picks[question.id] = [index]
        guard !isLastStep, !isVoiceOverOn, !isSwitchControlOn else { return }
        autoAdvance?.cancel()
        autoAdvance = Task {
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            move(by: 1)
        }
    }

    private func advance() {
        guard canAdvance else { return }
        guard isLastStep else { return move(by: 1) }
        if let answers = request.answers(progress) { answer(answers) }
    }

    private func advance(on press: KeyPress) -> KeyPress.Result {
        guard !press.modifiers.contains(.shift), canAdvance else { return .ignored }
        advance()
        return .handled
    }

    private func move(by offset: Int) {
        autoAdvance?.cancel()
        isForward = offset > 0
        progress.step += offset
    }

    private func focusStep() {
        let isText = question?.choices.isEmpty == true
        isFieldFocused = isText
        #if os(macOS)
        isCardFocused = !isText
        #endif
    }
}
