import SwiftUI

struct AddToBotsPage: View {
    let bot: Bot
    let server: MCPServer

    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var store
    @State private var picked: Set<Bot.ID>
    @State private var outcomes: [Bot.ID: ConnectionAddOutcome]
    @State private var writing: Bot.ID?
    @State private var isAdding = false

    init(bot: Bot, server: MCPServer, picked: Set<Bot.ID> = [], outcomes: [Bot.ID: ConnectionAddOutcome] = [:]) {
        self.bot = bot
        self.server = server
        _picked = State(initialValue: picked)
        _outcomes = State(initialValue: outcomes)
    }

    private var isOnline: Bool {
        connection.state == .connected
    }

    private var isFinished: Bool {
        !isAdding && !outcomes.isEmpty
    }

    var body: some View {
        Form {
            Section {
                ForEach(store.bots.filter { $0.id != bot.id && $0.meta.hidden != true }) { target in
                    row(target)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(server.name) is added with its settings.")
                    if server.auth == "header" {
                        Text("A bot without its own \(server.name) API key is skipped.")
                    }
                    if server.auth == "oauth" {
                        Text("Each bot signs in separately.")
                    }
                    if !isOnline {
                        Text("Crew is offline.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Add to Other Bots")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationBarBackButtonHidden(isAdding)
        .interactiveDismissDisabled(isAdding)
        .toolbar {
            if !isFinished {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add() } }
                        .disabled(picked.isEmpty || !isOnline || isAdding)
                }
            }
        }
    }

    private func row(_ target: Bot) -> some View {
        let isPicked = picked.contains(target.id)
        return Button {
            guard !isAdding, !isFinished else { return }
            if isPicked { picked.remove(target.id) } else { picked.insert(target.id) }
        } label: {
            HStack(spacing: 12) {
                BotAvatar(bot: target, status: nil, photo: store.photos[target.id], size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let outcome = outcomes[target.id] {
                        outcomeText(outcome)
                            .font(.subheadline)
                    } else if isAdding, isPicked, writing != target.id {
                        Text("Waiting")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if writing == target.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isPicked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .font(.title3)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private func outcomeText(_ outcome: ConnectionAddOutcome) -> some View {
        let name = server.name
        if case .failed(let message) = outcome {
            return Text(message).foregroundStyle(.red)
        }
        if outcome == .needsSignIn {
            return Text("Added. Needs Sign-In.").foregroundStyle(.orange)
        }
        let lines: [ConnectionAddOutcome: LocalizedStringResource] = [
            .added: "Added",
            .addedOff: "Added, turned off",
            .alreadyAdded: "Already has \(name)",
            .differentConnection: "Skipped: a different \(name) is already on this bot.",
            .missingKey: "Skipped: no \(name) API key on this bot.",
            .writtenKey: "Skipped: \(name)'s key is written in its config.",
            .removed: "\(name) was removed on the server.",
        ]
        let line = lines[outcome] ?? "Added"
        return Text(line).foregroundStyle(.secondary)
    }

    private func add() async {
        guard let url = connection.session?.server else { return }
        let urlSession = connection.urlSession
        let targets = store.bots.filter { picked.contains($0.id) }
        isAdding = true
        defer {
            writing = nil
            isAdding = false
        }

        let entry: Substring?
        do {
            entry = try rawServerEntry(server.name, in: try await rawConfigText(of: bot.name, on: url, with: urlSession))
        } catch {
            for target in targets { outcomes[target.id] = .failed(error.localizedDescription) }
            return
        }
        guard let entry else {
            for target in targets { outcomes[target.id] = .removed }
            return
        }

        for target in targets {
            writing = target.id
            outcomes[target.id] = await addConnection(server.name, entry: entry, to: target.name, on: url, with: urlSession)
        }
    }
}
