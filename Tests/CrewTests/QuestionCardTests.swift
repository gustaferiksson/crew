import Foundation
import Testing

private let fixtures = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures")

private func threeQuestions() throws -> QuestionRequest {
    let request = try JSONDecoder().decode(ServerRequest.self, from: Data(contentsOf: fixtures.appending(path: "clarify.three-questions.json")))
    guard case .question(let question) = PendingRequest(request) else { throw CocoaError(.coderReadCorrupt) }
    return question
}

@Test func theThreeQuestionPayloadDecodesKindsAndTheRecommendedChoice() throws {
    let request = try threeQuestions()
    #expect(request.id == "srq-5d4c3b2a1f0e")
    #expect(request.questions.map(\.id) == ["q0", "q1", "q2"])
    #expect(request.questions.map(\.isMultiSelect) == [false, true, false])
    #expect(request.questions[0].choices == ["By the lake", "In a bookshop", "On a long bike ride", "At home with a film"])
    #expect(request.questions[1].choices.first == "Cinnamon buns")
    #expect(request.questions.map(\.recommended) == [0, 0, nil])
    #expect(request.questions[2].choices.isEmpty)
}

@Test func theRecommendedLabelIsStrippedCaseInsensitively() {
    let question = QuestionRequest.Question(id: "q0", text: "Colour?", choices: [" red (recommended) ", "blue"])
    #expect(question.choices == ["red", "blue"])
    #expect(question.recommended == 0)
}

@Test func onlyTheRecommendedChoiceLosesItsLabel() {
    let question = QuestionRequest.Question(id: "q0", text: "Plan?", choices: ["Ship (Recommended)", "Wait (recommended)"])
    #expect(question.choices == ["Ship", "Wait (recommended)"])
    #expect(question.recommended == 0)
}

@Test func aFreeTextQuestionWithoutChoicesIsNeverMultiSelect() {
    #expect(!QuestionRequest.Question(id: "q0", text: "Name?", choices: [], isMultiSelect: true).isMultiSelect)
}

@Test func allAnswersAreSentTogetherInChoiceOrder() throws {
    let request = try threeQuestions()
    let progress = QuestionProgress(step: 2, picks: ["q0": [0], "q1": [2, 0]], texts: ["q2": "  Sprout \n"])
    #expect(request.answers(progress) == ["q0": "By the lake", "q1": #"["Cinnamon buns","Fresh fruit"]"#, "q2": "Sprout"])
}

@Test func aMultiSelectWithNothingPickedIsSentEmptyLikeHermesTUI() throws {
    let request = try threeQuestions()
    let progress = QuestionProgress(picks: ["q0": [1]], texts: ["q2": "Bolt"])
    #expect(request.answers(progress) == ["q0": "In a bookshop", "q1": "", "q2": "Bolt"])
}

@Test func anUnansweredChoiceOrBlankTextBlocksSending() throws {
    let request = try threeQuestions()
    #expect(request.questions[0].answer(in: QuestionProgress()) == nil)
    #expect(request.questions[2].answer(in: QuestionProgress(texts: ["q2": "   "])) == nil)
    #expect(request.answers(QuestionProgress(picks: ["q0": [1]], texts: ["q2": " "])) == nil)
}
