import A2UICore
import A2UISwiftUI
import SwiftUI

struct CrewText: View {
    let node: Node

    var body: some View {
        let source = node.string(for: "text") ?? ""
        let variant = node.string(for: "variant") ?? "body"
        let text = Text((try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source))
        if variant == "caption" {
            text.font(.footnote).foregroundStyle(.secondary)
        } else if variant == "body" {
            text
        } else {
            text.font(["h1": .title2.bold(), "h2": .title3.bold(), "h3": .headline, "h4": .headline][variant] ?? .subheadline.weight(.semibold))
        }
    }
}

struct CrewCard: View {
    let node: Node

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let child = node.child(for: "child") {
                ComponentNodeView(node: child)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 20))
    }
}

struct CrewButton: View {
    let node: Node

    @Environment(\.surfaceChoice) private var choice

    var body: some View {
        let isChosen = choice == node.id
        let variant = isChosen ? "primary" : node.string(for: "variant") ?? "default"
        let button = Button {
            node.action(for: "action")?()
        } label: {
            HStack(spacing: 4) {
                if isChosen {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                }
                if let child = node.child(for: "child") {
                    ComponentNodeView(node: child)
                }
            }
        }
        .buttonBorderShape(.capsule)
        .disabled(!node.isValid)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        if variant == "primary" {
            button.buttonStyle(.glassProminent)
        } else if variant == "borderless" {
            button.buttonStyle(.borderless)
        } else {
            button.buttonStyle(.glass)
        }
    }
}

struct CrewTable: View {
    let node: Node

    var body: some View {
        let columns = (node.array(for: "columns") ?? []).map { $0 as? String ?? "" }
        let rows = (node.array(for: "rows") ?? []).map { (($0 as? ResolvedArray)?.elements ?? []).map { $0 as? String ?? "" } }
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    ForEach(columns.indices, id: \.self) { index in
                        Text(columns[index])
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(rows.indices, id: \.self) { row in
                    Divider()
                    GridRow {
                        ForEach(rows[row].indices, id: \.self) { column in
                            Text(rows[row][column])
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

struct CrewKeyValue: View {
    let node: Node

    var body: some View {
        let items = (node.array(for: "items") ?? []).compactMap { $0 as? ResolvedDictionary }
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                if index > 0 {
                    Divider()
                }
                GridRow {
                    Text(items[index]["key"].map { $0 as? String ?? "" } ?? "")
                        .foregroundStyle(.secondary)
                    Text(items[index]["value"].map { $0 as? String ?? "" } ?? "")
                }
            }
        }
    }
}

struct CrewTextField: View {
    let node: Node

    var body: some View {
        let label = node.string(for: "label") ?? ""
        let variant = node.string(for: "variant") ?? "shortText"
        let text = node.binding(for: "value", default: "")
        let error = node.validationErrors.first
        VStack(alignment: .leading, spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(error == nil ? .secondary : Color.red)
            }
            Group {
                if variant == "obscured" {
                    SecureField(label, text: text, prompt: Text(""))
                } else if variant == "longText" {
                    TextField(label, text: text, prompt: Text(""), axis: .vertical)
                        .lineLimit(3...8)
                } else {
                    TextField(label, text: text, prompt: Text(""))
                        #if os(iOS)
                        .keyboardType(variant == "number" ? .decimalPad : .default)
                        #endif
                }
            }
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.fill.tertiary, in: .rect(cornerRadius: 12))
            .overlay {
                if error != nil {
                    RoundedRectangle(cornerRadius: 12).stroke(.red)
                }
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
