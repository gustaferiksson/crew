import A2UICore
import A2UISwiftUI
import BasicCatalogSwiftUI
import SwiftUI

struct CrewText: View {
    let node: Node

    var body: some View {
        let source = node.string(for: "text") ?? ""
        let variant = node.string(for: "variant") ?? "body"
        let text = Text(cardMarkdown(source))
        if variant == "caption" {
            text.font(.footnote).foregroundStyle(.secondary)
        } else if variant == "h5" {
            text.font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        } else if let font = ["h1": Font.title.bold(), "h2": .title2.bold(), "h3": .title3.weight(.semibold), "h4": .headline][variant] {
            text.font(font).padding(.top, variant == "h4" ? 4 : 0)
        } else {
            text
        }
    }
}

struct CrewColumn: View {
    let node: Node

    var body: some View {
        let align = node.string(for: "align") ?? "stretch"
        let alignment = ["center": HorizontalAlignment.center, "end": .trailing][align] ?? .leading
        VStack(alignment: alignment, spacing: 12) {
            ForEach(node.children(for: "children")) { child in
                ComponentNodeView(node: child)
                    .frame(maxWidth: align == "stretch" ? .infinity : nil, alignment: Alignment(horizontal: alignment, vertical: .center))
            }
        }
        .frame(maxWidth: align == "stretch" ? .infinity : nil, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}

struct CrewCard: View {
    let node: Node

    var body: some View {
        if let child = node.child(for: "child") {
            if node.id == "root" {
                ComponentNodeView(node: child)
            } else {
                ComponentNodeView(node: child)
                    .environment(\.carouselBleed, 0)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.fill.quaternary, in: .rect(cornerRadius: 16))
            }
        }
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
            .padding(.horizontal, 4)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(!node.isValid)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        if variant == "primary" {
            button.buttonStyle(.borderedProminent)
        } else if variant == "borderless" {
            button.buttonStyle(.borderless)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

struct CrewCheckBox: View {
    let node: Node

    var body: some View {
        let isOn = node.binding(for: "value", default: false)
        let error = node.validationErrors.first
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.snappy) { isOn.wrappedValue.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isOn.wrappedValue ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                    Text(node.string(for: "label") ?? "")
                        .strikethrough(isOn.wrappedValue)
                        .foregroundStyle(isOn.wrappedValue ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

struct CrewChoicePicker: View {
    let node: Node

    var body: some View {
        let label = node.string(for: "label") ?? ""
        let isExclusive = node.string(for: "variant") != "multipleSelection"
        let selection = node.binding(for: "value", default: [String]())
        let options = (node.array(for: "options") ?? []).compactMap { $0 as? ResolvedDictionary }.map { option in
            (label: option.string(for: "label") ?? "", value: option.string(for: "value") ?? "")
        }
        let toggle = { (value: String) in
            withAnimation(.snappy) {
                let current = selection.wrappedValue
                selection.wrappedValue = isExclusive ? [value] : current.contains(value) ? current.filter { $0 != value } : current + [value]
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            if !label.isEmpty {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if node.string(for: "displayStyle") == "chips" {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(options, id: \.value) { option in
                            let isSelected = selection.wrappedValue.contains(option.value)
                            let chip = Button(option.label) { toggle(option.value) }
                                .buttonBorderShape(.capsule)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            if isSelected {
                                chip.buttonStyle(.borderedProminent)
                            } else {
                                chip.buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.hidden)
                .padding(-4)
            } else {
                ForEach(options, id: \.value) { option in
                    let isSelected = selection.wrappedValue.contains(option.value)
                    Button { toggle(option.value) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                                .contentTransition(.symbolEffect(.replace))
                            Text(option.label)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
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

struct CrewDateTimeInput: View {
    let node: Node

    var body: some View {
        HStack {
            Text(node.string(for: "label") ?? "")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            A2UIDateTimeInput(node: Node(id: node.id, type: node.type, catalogID: node.catalogID, properties: node.properties.filter { $0.key != "label" }))
                .fixedSize()
        }
    }
}
