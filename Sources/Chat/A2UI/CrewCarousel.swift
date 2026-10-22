import A2UICore
import SwiftUI

extension EnvironmentValues {
    @Entry var carouselBleed: CGFloat = 20
}

private let tileSpacing: CGFloat = 12

private struct CarouselItem {
    let title: String
    let subtitle: String?
    let price: String?
    let badge: String?
    let tone: String?
    let image: URL?
    let url: URL?
    let text: AttributedString?

    init(_ item: ResolvedDictionary) {
        let https = { (key: String) in item.string(for: key).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil } }
        title = item.string(for: "title") ?? ""
        subtitle = item.string(for: "subtitle")
        price = item.string(for: "price")
        badge = item.string(for: "badge")
        tone = item.string(for: "tone")
        image = https("image")
        url = https("url")
        text = item.string(for: "text").map { source in
            var text = cardMarkdown(source)
            text.link = nil
            return text
        }
    }
}

struct CrewCarousel: View {
    let node: Node

    @Environment(\.carouselBleed) private var bleed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0
    @State private var current = 0
    @State private var position = ScrollPosition(idType: Int.self)
    @State private var isHovering = false

    var body: some View {
        let items = (node.array(for: "items") ?? []).compactMap { $0 as? ResolvedDictionary }.map(CarouselItem.init)
        let showsImage = items.contains { $0.image != nil }
        let tileWidth = items.count < 2 ? width : width - (bleed > 0 ? 16 : 36)
        VStack(spacing: 4) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: tileSpacing) {
                    ForEach(items.indices, id: \.self) { index in
                        CarouselTile(item: items[index], position: index + 1, count: items.count, showsImage: showsImage)
                            .frame(width: max(tileWidth, 0))
                            .frame(maxHeight: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, bleed, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollPosition($position)
            .onScrollGeometryChange(for: Int.self) { geometry in
                let maxOffset = geometry.contentSize.width + geometry.contentInsets.trailing - geometry.containerSize.width
                guard geometry.contentOffset.x < maxOffset - 1 else { return items.count - 1 }
                let page = ((geometry.contentOffset.x + geometry.contentInsets.leading) / (tileWidth + tileSpacing)).rounded()
                return min(max(Int(page), 0), items.count - 1)
            } action: { _, page in
                current = page
            }
            .padding(.horizontal, -bleed)
            #if os(macOS)
            .overlay(alignment: .top) {
                if isHovering, items.count > 1 {
                    HStack {
                        arrow("chevron.left", label: "Previous", to: current - 1, count: items.count)
                        Spacer()
                        arrow("chevron.right", label: "Next", to: current + 1, count: items.count)
                    }
                    .padding(.horizontal, 8)
                    .frame(maxHeight: showsImage ? 184 : .infinity)
                    .transition(.opacity)
                }
            }
            #endif
            if (2...10).contains(items.count) {
                dots(count: items.count)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { isHovering = hovering }
        }
    }

    private func scroll(to page: Int, count: Int) {
        guard (0..<count).contains(page) else { return }
        withAnimation(reduceMotion ? nil : .smooth) { position.scrollTo(id: page, anchor: .leading) }
    }

    private func dots(count: Int) -> some View {
        HStack(spacing: 9) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(width: 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .contentShape(.rect)
        .onTapGesture { location in
            let currentDot = width / 2 + (CGFloat(current) - CGFloat(count - 1) / 2) * 16
            scroll(to: current + (location.x < currentDot ? -1 : 1), count: count)
        }
        .accessibilityHidden(true)
    }

    #if os(macOS)
    @ViewBuilder
    private func arrow(_ symbol: String, label: LocalizedStringKey, to page: Int, count: Int) -> some View {
        if (0..<count).contains(page) {
            Button(label, systemImage: symbol) { scroll(to: page, count: count) }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        } else {
            Color.clear.frame(width: 32, height: 32)
        }
    }
    #endif
}

private struct CarouselTile: View {
    let item: CarouselItem
    let position: Int
    let count: Int
    let showsImage: Bool

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let label = ([item.badge, item.title, item.subtitle, item.price, item.text.map { String($0.characters) }].compactMap(\.self) + [String(localized: "\(position) of \(count)")]).joined(separator: ", ")
        if let url = item.url {
            Button { openURL(url) } label: { content(opens: true) }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Open", systemImage: "arrow.up.right") { openURL(url) }
                    Button("Copy Link", systemImage: "doc.on.doc") {
                        #if os(iOS)
                        UIPasteboard.general.url = url
                        #else
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        #endif
                    }
                    ShareLink(item: url)
                }
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isLink)
        } else {
            content(opens: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        }
    }

    private func content(opens: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsImage {
                AsyncImage(url: item.image) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else if item.image != nil, phase.error == nil {
                        ProgressView()
                    } else {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .background(.fill.tertiary)
                .clipShape(.rect(cornerRadius: 12))
            }
            if let badge = item.badge {
                CrewBadge(node: Node(id: "badge", type: "Badge", catalogID: crewCatalogID, properties: ["text": badge, "tone": item.tone ?? ""]))
            }
            Text(item.title)
                .font(.headline)
                .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    item.subtitle.map { Text($0).font(.footnote).foregroundStyle(.secondary) }
                    item.price.map { Text($0).font(.subheadline.weight(.semibold)) }
                }
            } else if item.subtitle != nil || item.price != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    item.subtitle.map { Text($0).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer(minLength: 0)
                    item.price.map { Text($0).font(.subheadline.weight(.semibold)).monospacedDigit().fixedSize() }
                }
            }
            if let text = item.text {
                Text(text)
                    .font(.subheadline)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            if opens {
                HStack(spacing: 4) {
                    Text("Open")
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
        .contentShape(.rect(cornerRadius: 16))
    }
}
