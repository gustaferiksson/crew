#if os(macOS)
import AppKit
import SwiftUI

nonisolated enum ReplySegment {
    case text(NSAttributedString)
    case card(String)
}

extension NSAttributedString.Key {
    nonisolated static let replyPlainText = NSAttributedString.Key("crew.replyPlainText")
}

nonisolated func replySegments(from source: String) -> [ReplySegment] {
    var segments: [ReplySegment] = []
    let text = NSMutableAttributedString()
    var previous: MarkdownBlock.Kind?
    for block in markdownBlocks(from: source) {
        if block.kind == .code(language: "a2ui") {
            if text.length > 0 { segments.append(.text(NSAttributedString(attributedString: text))) }
            text.setAttributedString(NSAttributedString())
            previous = nil
            segments.append(.card(String(block.content.characters).trimmingCharacters(in: .newlines)))
            continue
        }
        if text.length > 0 { text.append(NSAttributedString(string: "\n")) }
        text.append(replyParagraphs(block, spacing: previous.map { replySpacing(after: $0, before: block.kind) } ?? 0))
        previous = block.kind
    }
    if text.length > 0 { segments.append(.text(text)) }
    return segments
}

nonisolated private func replySpacing(after previous: MarkdownBlock.Kind, before kind: MarkdownBlock.Kind) -> CGFloat {
    if case .listItem = previous, case .listItem = kind { return 4 }
    if case .heading = kind { return 16 }
    return 12
}

nonisolated private func replyParagraphs(_ block: MarkdownBlock, spacing: CGFloat) -> NSAttributedString {
    let body = NSFont.preferredFont(forTextStyle: .body)
    let style = NSMutableParagraphStyle()
    style.paragraphSpacingBefore = spacing
    switch block.kind {
    case .paragraph:
        return replyInline(block.content, font: body, color: .labelColor, style: style)
    case .heading(let level):
        let textStyle: NSFont.TextStyle = level == 1 ? .title2 : level == 2 ? .title3 : .headline
        let font = NSFont.preferredFont(forTextStyle: textStyle)
        let bold = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.bold), size: font.pointSize) ?? font
        return replyInline(block.content, font: bold, color: .labelColor, style: style)
    case .listItem(let marker, let depth):
        let markerFont = NSFont.monospacedDigitSystemFont(ofSize: body.pointSize, weight: .regular)
        let column = CGFloat(depth - 1) * 20 + max(12, ceil((marker as NSString).size(withAttributes: [.font: markerFont]).width))
        style.tabStops = [NSTextTab(textAlignment: .right, location: column), NSTextTab(textAlignment: .left, location: column + 8)]
        style.headIndent = column + 8
        let item = NSMutableAttributedString(string: "\t\(marker)\t", attributes: [
            .font: markerFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style,
            .replyPlainText: "\(marker) ",
        ])
        item.append(replyInline(block.content, font: body, color: .labelColor, style: style))
        return item
    case .code(let language):
        let callout = NSFont.preferredFont(forTextStyle: .callout)
        let box = ReplyCodeBlock(language: language.flatMap { $0.isEmpty ? nil : $0 })
        box.setWidth(spacing, type: .absoluteValueType, for: .margin, rectEdge: .minYEdge)
        style.paragraphSpacingBefore = 0
        style.textBlocks = [box]
        let code = String(block.content.characters).trimmingCharacters(in: .newlines)
        return NSAttributedString(string: code, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: callout.pointSize, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ])
    case .quote:
        let bar = ReplyQuoteBlock()
        bar.setWidth(spacing, type: .absoluteValueType, for: .margin, rectEdge: .minYEdge)
        style.paragraphSpacingBefore = 0
        style.textBlocks = [bar]
        return replyInline(block.content, font: body, color: .secondaryLabelColor, style: style)
    case .rule:
        let rule = ReplyRuleBlock()
        rule.setWidth(spacing, type: .absoluteValueType, for: .margin, rectEdge: .minYEdge)
        style.paragraphSpacingBefore = 0
        style.textBlocks = [rule]
        return NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 1), .paragraphStyle: style, .replyPlainText: "---"])
    }
}

nonisolated private func replyInline(_ content: AttributedString, font: NSFont, color: NSColor, style: NSParagraphStyle) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for run in content.runs {
        let intent = run.inlinePresentationIntent ?? []
        let base = intent.contains(.code) ? NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular) : font
        var traits = base.fontDescriptor.symbolicTraits
        if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
        if intent.contains(.emphasized) { traits.insert(.italic) }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: base.pointSize) ?? base,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link = run.link { attributes[.link] = link }
        result.append(NSAttributedString(string: String(content[run.range].characters), attributes: attributes))
    }
    return result
}

nonisolated final class ReplyCodeBlock: NSTextBlock {
    let language: String?

    init(language: String?) {
        self.language = language
        super.init()
        setValue(100, type: .percentageValueType, for: .width)
        let top = language.map { _ in 12 + ceil(Self.caption.ascender - Self.caption.descender) + 4 } ?? 12
        setWidth(12, type: .absoluteValueType, for: .padding)
        setWidth(top, type: .absoluteValueType, for: .padding, rectEdge: .minYEdge)
    }

    required init?(coder: NSCoder) {
        language = nil
        super.init(coder: coder)
    }

    private static var caption: NSFont {
        let font = NSFont.preferredFont(forTextStyle: .caption1)
        return NSFont.systemFont(ofSize: font.pointSize, weight: .medium)
    }

    override func drawBackground(withFrame frameRect: NSRect, in controlView: NSView?, characterRange charRange: NSRange, layoutManager: NSLayoutManager) {
        let box = frameRect.divided(atDistance: width(for: .margin, rectEdge: .minYEdge), from: .minYEdge).remainder
        NSColor.quaternarySystemFill.setFill()
        NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
        guard let language else { return }
        let origin = NSPoint(x: box.minX + 12, y: box.minY + 12)
        (language as NSString).draw(at: origin, withAttributes: [.font: Self.caption, .foregroundColor: NSColor.secondaryLabelColor])
    }
}

nonisolated final class ReplyQuoteBlock: NSTextBlock {
    override init() {
        super.init()
        setValue(100, type: .percentageValueType, for: .width)
        setWidth(12, type: .absoluteValueType, for: .padding, rectEdge: .minXEdge)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func drawBackground(withFrame frameRect: NSRect, in controlView: NSView?, characterRange charRange: NSRange, layoutManager: NSLayoutManager) {
        let box = frameRect.divided(atDistance: width(for: .margin, rectEdge: .minYEdge), from: .minYEdge).remainder
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: box.minX, y: box.minY, width: 4, height: box.height), xRadius: 2, yRadius: 2).fill()
    }
}

nonisolated final class ReplyRuleBlock: NSTextBlock {
    override init() {
        super.init()
        setValue(100, type: .percentageValueType, for: .width)
        setWidth(4, type: .absoluteValueType, for: .padding, rectEdge: .minYEdge)
        setWidth(4, type: .absoluteValueType, for: .padding, rectEdge: .maxYEdge)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func drawBackground(withFrame frameRect: NSRect, in controlView: NSView?, characterRange charRange: NSRange, layoutManager: NSLayoutManager) {
        let box = frameRect.divided(atDistance: width(for: .margin, rectEdge: .minYEdge), from: .minYEdge).remainder
        let line = NSBezierPath()
        line.move(to: NSPoint(x: box.minX, y: box.midY))
        line.line(to: NSPoint(x: box.maxX, y: box.midY))
        line.lineWidth = 0
        NSColor.separatorColor.setStroke()
        line.stroke()
    }
}

final class ReplyTextView: NSTextView {
    var source = ""

    static func make() -> ReplyTextView {
        let view = ReplyTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isRichText = true
        view.usesFindPanel = false
        view.usesFindBar = false
        view.isIncrementalSearchingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.linkTextAttributes = [.foregroundColor: NSColor.controlAccentColor, .cursor: NSCursor.pointingHand]
        return view
    }

    func show(_ text: NSAttributedString) {
        guard let storage = textStorage else { return }
        let selection = selectedRanges.map(\.rangeValue)
        storage.setAttributedString(text)
        selectedRanges = selection.map { range in
            let location = min(range.location, text.length)
            return NSValue(range: NSRange(location: location, length: min(range.length, text.length - location)))
        }
    }

    override var canBecomeKeyView: Bool { false }

    override func updateDragTypeRegistration() {
        unregisterDraggedTypes()
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        setSelectedRange(NSRange(location: 0, length: 0))
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let editing: Set<Selector> = [#selector(cut(_:)), #selector(paste(_:)), #selector(pasteAsPlainText(_:)), #selector(pasteAsRichText(_:)), #selector(NSFontManager.addFontTrait(_:)), #selector(showGuessPanel(_:)), #selector(orderFrontSubstitutionsPanel(_:))]
        let kept = menu.items.filter { item in
            item.action.map(editing.contains) != true && item.submenu?.items.contains { $0.action.map(editing.contains) == true } != true
        }
        menu.removeAllItems()
        for item in kept where !(item.isSeparatorItem && menu.items.last?.isSeparatorItem != false) {
            menu.addItem(item)
        }
        if menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.numberOfItems - 1) }
        let copy = NSMenuItem(title: "Copy Message", action: #selector(copyMessage), keyEquivalent: "")
        copy.target = self
        let share = NSSharingServicePicker(items: [source]).standardShareMenuItem
        share.title = "Share Message"
        menu.insertItem(copy, at: 0)
        menu.insertItem(share, at: 1)
        menu.insertItem(.separator(), at: 2)
        return menu
    }

    @objc private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(source, forType: .string)
    }

    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let storage = textStorage else { return false }
        let selection = NSMutableAttributedString()
        for range in selectedRanges.map(\.rangeValue) where range.length > 0 {
            if selection.length > 0 { selection.append(NSAttributedString(string: "\n")) }
            selection.append(storage.attributedSubstring(from: range))
        }
        guard selection.length > 0 else { return false }
        let whole = NSRange(location: 0, length: selection.length)
        let plain = NSMutableString(string: selection.string)
        selection.enumerateAttribute(.replyPlainText, in: whole, options: .reverse) { value, range, _ in
            guard let value = value as? String else { return }
            plain.replaceCharacters(in: range, with: value)
        }
        selection.removeAttribute(.foregroundColor, range: whole)
        selection.removeAttribute(.replyPlainText, range: whole)
        pboard.declareTypes([.rtf, .string], owner: nil)
        if let rtf = selection.rtf(from: whole) { pboard.setData(rtf, forType: .rtf) }
        return pboard.setString(plain as String, forType: .string)
    }
}

struct ReplySegmentText: NSViewRepresentable {
    let text: NSAttributedString
    let source: String
    let offset: Int

    final class Coordinator {
        var source: String?
        var offset: Int?
        var measured: (width: CGFloat?, size: CGSize)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ReplyTextView {
        ReplyTextView.make()
    }

    func updateNSView(_ view: ReplyTextView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.source != source || coordinator.offset != offset else { return }
        view.show(text)
        view.source = source
        coordinator.source = source
        coordinator.offset = offset
        coordinator.measured = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: ReplyTextView, context: Context) -> CGSize? {
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        if let measured = context.coordinator.measured, measured.width == width { return measured.size }
        container.size = NSSize(width: width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        if view.frame.width > 0 { container.size.width = view.frame.width }
        let size = CGSize(width: width ?? ceil(used.width), height: ceil(used.height))
        context.coordinator.measured = (width, size)
        return size
    }
}
#endif
