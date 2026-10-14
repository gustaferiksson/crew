import SwiftUI

struct BotDeletion: ViewModifier {
    @Binding var bot: Bot?
    var onDeleted: (Bot.ID) -> Void = { _ in }

    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var store
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Delete \(bot?.title ?? "")?",
                isPresented: Binding(get: { bot != nil }, set: { if !$0 { bot = nil } }),
                titleVisibility: .visible,
                presenting: bot
            ) { target in
                Button("Delete \(target.title)", role: .destructive) {
                    Task { await delete(target) }
                }
            } message: { target in
                Text("This permanently deletes the \(target.name) profile on the server, including its chats, memory and skills.")
            }
            .alert("Couldn't Delete Bot", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
    }

    private func delete(_ target: Bot) async {
        guard let gateway = connection.gateway else { return }
        do {
            try await store.delete(target, via: gateway, urlSession: connection.urlSession)
            onDeleted(target.id)
        } catch {
            failure = if case GatewayError.rpc(_, let message) = error { message } else { error.localizedDescription }
        }
    }
}
