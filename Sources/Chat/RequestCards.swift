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
}

nonisolated struct QuestionRequest: Identifiable, Sendable, Equatable {
    struct Question: Identifiable, Sendable, Equatable {
        let id: String
        let text: String
        let choices: [String]
    }

    let id: String
    let questions: [Question]
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
}

struct ApprovalCard: View {
    let request: ApprovalRequest
    let botName: String
    let respond: (ApprovalChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(botName) wants to run a command", systemImage: "exclamationmark.shield.fill")
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
                    Button("Deny", role: .destructive) { respond(.deny) }
                    Button("Allow Once") { respond(.once) }
                        .buttonStyle(.glassProminent)
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .buttonSizing(.flexible)
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 28))
    }
}

struct QuestionCard: View {
    let request: QuestionRequest
    let botName: String
    let answer: ([String: String]) -> Void

    @State private var answers: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(botName) has a question", systemImage: "questionmark.bubble.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
            ForEach(request.questions) { question in
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.text)
                    if question.choices.isEmpty {
                        TextField("Your answer", text: Binding { answers[question.id] ?? "" } set: { answers[question.id] = $0 }, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...4)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                    } else {
                        ForEach(question.choices, id: \.self) { choice in
                            Button {
                                answers[question.id] = choice
                            } label: {
                                Label(choice, systemImage: answers[question.id] == choice ? "checkmark.circle.fill" : "circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.roundedRectangle(radius: 12))
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Button("Skip") { answer([:]) }
                    .buttonStyle(.glass)
                Button("Send") { answer(answers) }
                    .buttonStyle(.glassProminent)
                    .disabled(request.questions.contains { (answers[$0.id] ?? "").isEmpty })
            }
            .buttonBorderShape(.capsule)
            .buttonSizing(.flexible)
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 28))
    }
}
