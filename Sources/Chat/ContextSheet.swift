import SwiftUI

struct ContextSheet: View {
    let usage: ContextUsage
    let loadBreakdown: () async throws -> [ContextCategory]
    let compact: (() -> Void)?
    @State private var categories: [ContextCategory] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(usage.summary)
                            .font(.headline)
                        ProgressView(value: usage.fraction)
                            .accessibilityHidden(true)
                        Text(usage.percentUsed)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                if !categories.isEmpty {
                    Section {
                        ForEach(categories) { category in
                            LabeledContent(category.label, value: "~\(category.tokens.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))))")
                        }
                        LabeledContent("Free Space", value: max(0, usage.window - usage.used).formatted(.number.notation(.compactName).precision(.fractionLength(0...1))))
                    } header: {
                        Text("Estimated Breakdown")
                    }
                }

                if let compact, usage.isHigh {
                    Section {
                        Button("Compact Chat…", systemImage: "arrow.down.right.and.arrow.up.left", action: compact)
                    } footer: {
                        Text("Replaces older messages in the bot's context with a summary, so the chat has room to continue.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Context")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
            .task(id: usage) {
                categories = (try? await loadBreakdown()) ?? categories
            }
        }
        .frame(idealWidth: 420, idealHeight: 460)
        .presentationDetents([.medium, .large])
    }
}
