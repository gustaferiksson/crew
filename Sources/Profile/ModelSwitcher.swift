import Observation
import SwiftUI

@Observable
final class ModelSwitcher {
    struct Confirmation {
        let choice: ModelChoice
        let message: String
    }

    private(set) var options: [ModelProvider]
    private(set) var current: ModelChoice?
    private(set) var changing: ModelChoice?
    var confirmation: Confirmation?
    var failure: String?

    init(providers: [ModelProvider] = [], current: ModelChoice? = nil) {
        options = providers
        self.current = current
    }

    var providers: [ModelProvider] {
        guard let current, !options.contains(where: { $0.slug == current.provider && $0.models.contains(current.model) }) else { return options }
        return options + [ModelProvider(slug: current.provider, name: current.provider, models: [current.model])]
    }

    func load(profile: String, via gateway: Gateway) async {
        guard let reply = try? await gateway.call("model.options", ["profile": profile], as: ModelOptions.self) else { return }
        options = reply.providers
        current = reply.current
    }

    func change(to choice: ModelChoice, confirmation: ModelConfirmation = .ask, profile: String, via gateway: Gateway) async {
        guard changing == nil, choice != current else { return }
        changing = choice
        defer { changing = nil }
        do {
            let outcome = try await changeModel(of: profile, to: choice, confirmation: confirmation, via: gateway)
            if case .needsConfirmation(let message) = outcome {
                self.confirmation = Confirmation(choice: choice, message: message)
                return
            }
            current = choice
        } catch {
            failure = if case GatewayError.rpc(_, let message) = error { message } else { error.localizedDescription }
        }
    }
}

struct ModelPicker: View {
    let providers: [ModelProvider]
    @Binding var selection: ModelChoice?

    var body: some View {
        Picker(selection: $selection) {
            ForEach(providers) { provider in
                Section(provider.name) {
                    ForEach(provider.models, id: \.self) { model in
                        Text(model).tag(Optional(ModelChoice(provider: provider.slug, model: model)))
                    }
                }
            }
        } label: {
            Label("Model", systemImage: "cpu")
        }
    }
}
