import A2UICore
import SwiftUI

let crewTones: [String: Color] = ["info": .blue, "success": .green, "warning": .orange, "critical": .red, "accent": .accentColor]

struct CrewHeader: View {
    let node: Node

    @Environment(\.hiddenHeader) private var hiddenHeader

    var body: some View {
        if hiddenHeader != node.id { header }
    }

    @ViewBuilder private var header: some View {
        let subtitle = node.string(for: "subtitle")
        let tint = crewTones[node.string(for: "tone") ?? ""] ?? .accentColor
        VStack(alignment: .leading, spacing: 16) {
            if let url = node.string(for: "image").flatMap(URL.init(string:)), url.scheme == "https" {
                CachedImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(.fill.tertiary)
                    }
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityHidden(true)
            }
            HStack(spacing: 12) {
                if let symbol = systemSymbol(node.string(for: "symbol")) {
                    Image(systemName: symbol)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(tint.gradient, in: .rect(cornerRadius: 12))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.string(for: "title") ?? "")
                        .font(.title3.weight(.semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct CrewImage: View {
    let node: Node

    var body: some View {
        Group {
            if let url = node.string(for: "url").flatMap(URL.init(string:)), url.scheme == "https" {
                CardImage(url: url, variant: node.string(for: "variant") ?? "mediumFeature", fit: node.string(for: "fit") ?? "fill")
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40, minHeight: 40)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(node.string(for: "description") ?? "Image")
        .accessibilityAddTraits(.isImage)
    }
}

struct CrewSteps: View {
    let node: Node

    @Environment(\.cardModel) private var model

    var body: some View {
        let items = node.array(for: "items") ?? []
        VStack(alignment: .leading, spacing: 16) {
            ForEach(items.indices, id: \.self) { index in
                let timed = items[index] as? ResolvedDictionary
                let text = timed?.string(for: "text") ?? items[index] as? String ?? ""
                let seconds = timed?.double(for: "seconds") ?? 0
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(index + 1, format: .number)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(.tint, in: .circle)
                        Text(cardMarkdown(text))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                    if let model, seconds > 0 {
                        CardTimerRow(model: model, id: "\(node.id)-\(index + 1)", title: nil, name: String(localized: "Step \(index + 1)"), alert: text, seconds: seconds)
                            .padding(.leading, 36)
                    }
                }
            }
        }
    }
}

struct CrewBadge: View {
    let node: Node

    var body: some View {
        let tint = crewTones[node.string(for: "tone") ?? ""] ?? .secondary
        HStack(spacing: 4) {
            if let symbol = systemSymbol(node.string(for: "symbol")) {
                Image(systemName: symbol)
            }
            Text(node.string(for: "text") ?? "")
                .contentTransition(.numericText())
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.16), in: .capsule)
        .fixedSize()
    }
}

struct CrewTable: View {
    let node: Node

    @State private var width: CGFloat = 0
    @State private var natural: CGFloat = 0

    var body: some View {
        let columns = (node.array(for: "columns") ?? []).map { $0 as? String ?? "" }
        let rows = (node.array(for: "rows") ?? []).map { (($0 as? ResolvedArray)?.elements ?? []).map { $0 as? String ?? "" } }
        let numeric = columns.indices.map { column in
            rows.allSatisfy { row in column >= row.count || row[column].first.map { $0.isNumber || "-+−$€£¥".contains($0) } ?? true }
        }
        let grid = Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 12) {
            GridRow {
                ForEach(columns.indices, id: \.self) { index in
                    if index > 0 {
                        Color.clear.frame(minWidth: 12, maxWidth: .infinity, maxHeight: 0)
                    }
                    Text(columns[index])
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .gridColumnAlignment(numeric[index] ? .trailing : .leading)
                }
            }
            ForEach(rows.indices, id: \.self) { row in
                Divider()
                GridRow {
                    ForEach(rows[row].indices, id: \.self) { column in
                        if column > 0 {
                            Color.clear.frame(minWidth: 12, maxWidth: .infinity, maxHeight: 0)
                        }
                        Text(rows[row][column])
                            .font(.subheadline)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .fontWeight(column == 0 ? .medium : .regular)
                            .fixedSize()
                    }
                }
            }
        }
        ScrollView(.horizontal) {
            grid
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { natural = $0 }
                .frame(minWidth: width, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .preference(key: TableWidth.self, value: natural)
    }
}

struct CrewKeyValue: View {
    let node: Node

    var body: some View {
        let items = (node.array(for: "items") ?? []).compactMap { $0 as? ResolvedDictionary }
        let isStacked = items.contains { ($0.string(for: "key") ?? "").count + ($0.string(for: "value") ?? "").count > 40 }
        VStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                if index > 0 {
                    Divider()
                }
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    if let symbol = systemSymbol(items[index].string(for: "symbol")) {
                        Image(systemName: symbol)
                            .foregroundStyle(.tint)
                            .frame(width: 24)
                    }
                    let key = items[index].string(for: "key") ?? ""
                    let value = items[index].string(for: "value") ?? ""
                    if isStacked {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key)
                            Text(value)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(key)
                        Spacer(minLength: 16)
                        Text(value)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .multilineTextAlignment(.trailing)
                    }
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
