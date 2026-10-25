import SwiftUI

struct TaskList: View {
    let bot: Bot
    let todos: [TodoItem]

    var body: some View {
        if todos.isEmpty {
            Section {} header: {
                ContentUnavailableView("No Tasks", systemImage: "checklist", description: Text("When \(bot.title) plans a run, its steps show up here."))
            }
        } else {
            Section {
                ForEach(todos) { TaskRow(todo: $0) }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text(todos.contains { $0.status == .inProgress || $0.status == .pending } ? "Current Run" : "Last Run")
                    Spacer()
                    Text("\(todos.filter { $0.status == .completed }.count) of \(todos.count) done")
                        .monospacedDigit()
                }
            }
        }
    }
}

private struct TaskRow: View {
    let todo: TodoItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: todo.status == .inProgress)
                .frame(width: 16)
            Text(todo.content)
                .strikethrough(todo.status == .cancelled)
                .foregroundStyle(todo.status == .completed || todo.status == .cancelled ? .secondary : .primary)
                .fontWeight(todo.status == .inProgress ? .medium : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(todo.status.rawValue)
    }

    private var symbol: String {
        if todo.status == .completed { return "checkmark.circle.fill" }
        if todo.status == .inProgress { return "circle.dotted.circle.fill" }
        if todo.status == .cancelled { return "xmark.circle" }
        return "circle"
    }

    private var tint: Color {
        if todo.status == .completed { return .green }
        if todo.status == .inProgress { return .accentColor }
        return .secondary
    }
}
