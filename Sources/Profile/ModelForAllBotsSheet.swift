import SwiftUI

struct ModelForAllBotsSheet: View {
    @State private var run: ModelForAllBots
    @State private var models: ModelSwitcher
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var store

    init(run: ModelForAllBots = ModelForAllBots(), models: ModelSwitcher = ModelSwitcher()) {
        _run = State(initialValue: run)
        _models = State(initialValue: models)
    }

    private var isOnline: Bool { connection.state == .connected }

    private var targets: [Bot] { ModelForAllBots.targets(in: store.bots, for: run.choice) }

    var body: some View {
        NavigationStack {
            Form {
                switch run.phase {
                case .choosing, .confirming:
                    choosing
                case .running:
                    running
                case .finished:
                    finished
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Set Model for All Bots")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(run.phase == .finished ? "Done" : "Cancel") { dismiss() }
                        .disabled(run.phase == .running)
                }
            }
            .interactiveDismissDisabled(run.phase == .running)
            .alert(
                "Use \(run.choice?.model ?? "this model")?",
                isPresented: Binding(get: { run.phase == .confirming }, set: { if !$0, run.phase == .confirming { run.cancelConfirmation() } }),
                presenting: run.confirmationMessage
            ) { _ in
                Button("Use Anyway") { start { await run.confirm(apply: apply, roster: { store.bots }) } }
                Button("Cancel", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
        #if os(macOS)
        .frame(width: 420, height: 380)
        #endif
        .task(id: connection.state == .connected) {
            guard let gateway = connection.gateway, let host = store.bots.first(where: \.isDefault) ?? store.bots.first else { return }
            await models.load(profile: host.name, via: gateway)
        }
        .onChange(of: scenePhase) { if scenePhase != .active { run.stop() } }
        .onChange(of: isOnline) { if !isOnline { run.stop() } }
        .onChange(of: run.phase) {
            guard run.phase == .finished else { return }
            AccessibilityNotification.Announcement(String(localized: "Changed \(run.changed) of \(run.total). \(run.failures.count) failed.")).post()
        }
    }

    @ViewBuilder
    private var choosing: some View {
        Section {
            if models.providers.isEmpty {
                LabeledContent("Model", value: String(localized: "No models available"))
            } else {
                ModelPicker(providers: models.providers, selection: $run.choice)
            }
        } footer: {
            footer
        }
        Section {
            Button("Set Model for ^[\(targets.count) Bot](inflect: true)") {
                start { await run.start(on: store.bots, apply: apply, roster: { store.bots }) }
            }
            .frame(maxWidth: .infinity)
            .disabled(run.choice == nil || targets.isEmpty || !isOnline)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let choice = run.choice, targets.isEmpty {
                Text("All bots already use \(choice.model).")
            } else {
                Text("Changes the model on ^[\(targets.count) bot](inflect: true). Each can be changed again. Bots in the middle of a turn change too, from their next turn.")
            }
            let hidden = store.bots.count { !$0.isDefault && $0.meta.hidden == true }
            if hidden > 0 {
                Text("Not changed: ^[\(hidden) hidden bot](inflect: true).")
            }
        }
    }

    private var running: some View {
        Section {
            ProgressView(value: Double(run.attempted), total: Double(max(run.total, 1))) {
                Text("Changing \(min(run.attempted + 1, run.total)) of \(run.total)…")
            } currentValueLabel: {
                Text(verbatim: run.current)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button(run.isStopping ? "Stopping…" : "Stop", role: .destructive) { run.stop() }
                .frame(maxWidth: .infinity)
                .disabled(run.isStopping)
        }
    }

    @ViewBuilder
    private var finished: some View {
        Section {
            if run.wasStopped {
                Text("Stopped")
                    .font(.headline)
            }
            Text("Changed \(run.changed) of ^[\(run.total) bot](inflect: true).")
                .font(run.wasStopped ? .body : .headline)
            ForEach(run.failures.prefix(3)) { failure in
                Label {
                    Text("Couldn't change \(failure.bot): \(failure.message)")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                }
            }
            if run.failures.count > 3 {
                Text("and \(run.failures.count - 3) more")
                    .foregroundStyle(.secondary)
            }
            if run.added > 0 {
                Text("^[\(run.added) bot](inflect: true) added during the run, not changed.")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        if !run.remaining.isEmpty {
            Section {
                Button(run.failures.isEmpty ? "Continue" : "Try Again") {
                    start { await run.run(apply: apply, roster: { store.bots }) }
                }
                .frame(maxWidth: .infinity)
                .disabled(!isOnline)
            }
        }
    }

    private var apply: ModelForAllBots.Apply {
        { [connection] bot, choice, confirmation in
            guard let gateway = connection.gateway else { throw GatewayError.notConnected }
            return try await changeModel(of: bot, to: choice, confirmation: confirmation, via: gateway)
        }
    }

    private func start(_ work: @escaping () async -> Void) {
        Task {
            await work()
            guard let gateway = connection.gateway else { return }
            await store.reload(gateway)
        }
    }
}
