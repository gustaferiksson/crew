import SwiftUI

struct TaskList: View {
    let bot: Bot
    let todos: [TodoItem]

    var body: some View {
        if todos.isEmpty {
            ContentUnavailableView("No Tasks", systemImage: "checklist", description: Text("When \(bot.title) plans a run, its steps show up here."))
        } else {
            let done = todos.filter { $0.status == .completed }.count
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(todos.contains { $0.status == .inProgress || $0.status == .pending } ? "Current Run" : "Last Run")
                        .font(.headline)
                    Spacer()
                    Text("\(done) of \(todos.count) done")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    ForEach(todos) { todo in
                        TaskRow(todo: todo)
                        if todo.id != todos.last?.id {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
                .background(.fill.quaternary, in: .rect(cornerRadius: 16))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
