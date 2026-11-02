import SwiftUI
#if os(macOS)
import AppKit

private typealias PlatformFont = NSFont
nonisolated private let primaryText = NSColor.labelColor
nonisolated private let secondaryText = NSColor.secondaryLabelColor
#else
import UIKit

private typealias PlatformFont = UIFont
nonisolated private let primaryText = UIColor.label
nonisolated private let secondaryText = UIColor.secondaryLabel
#endif

nonisolated enum ReplySegment {
    case text(NSAttributedString)
    case card(String)
}

extension NSAttributedString.Key {
    nonisolated static let replyPlainText = NSAttributedString.Key("crew.replyPlainText")
}

nonisolated private let builtSegments = ParseCache<[ReplySegment]>(costLimit: 4 * 1024 * 1024)

nonisolated func replySegments(from source: String) -> [ReplySegment] {
    builtSegments.value(for: source, parse: buildReplySegments)
}

nonisolated func buildReplySegments(from source: String) -> [ReplySegment] {
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
    let body = PlatformFont.preferredFont(forTextStyle: .body)
    let style = NSMutableParagraphStyle()
    style.paragraphSpacingBefore = spacing
    switch block.kind {
    case .paragraph:
        return replyInline(block.content, font: body, color: primaryText, style: style)
    case .heading(let level):
        let font = PlatformFont.preferredFont(forTextStyle: level == 1 ? .title2 : level == 2 ? .title3 : .headline)
        return replyInline(block.content, font: replyFont(font, bold: true, italic: false), color: primaryText, style: style)
    case .listItem(let marker, let depth):
        let markerFont = PlatformFont.monospacedDigitSystemFont(ofSize: body.pointSize, weight: .regular)
        let column = CGFloat(depth - 1) * 20 + max(12, ceil((marker as NSString).size(withAttributes: [.font: markerFont]).width))
        style.tabStops = [NSTextTab(textAlignment: .right, location: column), NSTextTab(textAlignment: .left, location: column + 8)]
        style.headIndent = column + 8
        let item = NSMutableAttributedString(string: "\t\(marker)\t", attributes: [
            .font: markerFont,
            .foregroundColor: secondaryText,
            .paragraphStyle: style,
            .replyPlainText: "\(marker) ",
        ])
        item.append(replyInline(block.content, font: body, color: primaryText, style: style))
        return item
    case .code(let language):
        let callout = PlatformFont.preferredFont(forTextStyle: .callout)
        let caption = language.flatMap { $0.isEmpty ? nil : $0 }
        #if os(macOS)
        let box = ReplyCodeBlock(language: caption)
        box.setWidth(spacing, type: .absoluteValueType, for: .margin, rectEdge: .minYEdge)
        style.paragraphSpacingBefore = 0
        style.textBlocks = [box]
        #else
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        style.tailIndent = -12
        #endif
        let code = NSMutableAttributedString(string: String(block.content.characters).trimmingCharacters(in: .newlines), attributes: [
            .font: PlatformFont.monospacedSystemFont(ofSize: callout.pointSize, weight: .regular),
            .foregroundColor: primaryText,
            .paragraphStyle: style,
        ])
        #if os(iOS)
        let top = caption.map { _ in 12 + ceil(ReplyDecoration.caption.lineHeight) + 4 } ?? 12
        replyFrame(code, in: ReplyDecoration(kind: .code(caption), gap: spacing), top: spacing + top, bottom: 12)
        #endif
        return code
    case .quote:
        #if os(macOS)
        let bar = ReplyQuoteBlock()
        bar.setWidth(spacing, type: .absoluteValueType, for: .margin, rectEdge: .minYEdge)
        style.paragraphSpacingBefore = 0
        style.textBlocks = [bar]
        return replyInline(block.content, font: body, color: secondaryText, style: style)
        #else
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        let quote = NSMutableAttributedString(attributedString: replyInline(block.content, font: body, color: secondaryText, style: style))
        replyFrame(quote, in: ReplyDecoration(kind: .quote, gap: spacing), top: spacing, bottom: 0)
        return quote
        #endif
    case .rule:
        #if os(macOS)
        let rule = ReplyRuleBlock()
        rule.setWidth(spacing, type: .absoluteValueType, for: .margin, rectEdge: .minYEdge)
        style.paragraphSpacingBefore = 0
        style.textBlocks = [rule]
        #endif
        let line = NSMutableAttributedString(string: " ", attributes: [.font: PlatformFont.systemFont(ofSize: 1), .paragraphStyle: style, .replyPlainText: "---"])
        #if os(iOS)
        replyFrame(line, in: ReplyDecoration(kind: .rule, gap: spacing), top: spacing + 4, bottom: 4)
        #endif
        return line
    }
}

nonisolated private func replyFont(_ font: PlatformFont, bold: Bool, italic: Bool) -> PlatformFont {
    var traits = font.fontDescriptor.symbolicTraits
    #if os(macOS)
    if bold { traits.insert(.bold) }
    if italic { traits.insert(.italic) }
    return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
    #else
    if bold { traits.insert(.traitBold) }
    if italic { traits.insert(.traitItalic) }
    return font.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font
    #endif
}

nonisolated private func replyInline(_ content: AttributedString, font: PlatformFont, color: Any, style: NSParagraphStyle) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for run in content.runs {
        let intent = run.inlinePresentationIntent ?? []
        let base = intent.contains(.code) ? PlatformFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular) : font
        var attributes: [NSAttributedString.Key: Any] = [
            .font: replyFont(base, bold: intent.contains(.stronglyEmphasized), italic: intent.contains(.emphasized)),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link = run.link { attributes[.link] = link }
        result.append(NSAttributedString(string: String(content[run.range].characters), attributes: attributes))
    }
    return result
}

#if os(macOS)
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

#if os(iOS)
extension NSAttributedString.Key {
    nonisolated static let replyDecoration = NSAttributedString.Key("crew.replyDecoration")
}

nonisolated final class ReplyDecoration: NSObject {
    enum Kind {
        case code(String?)
        case quote
        case rule
    }

    let kind: Kind
    let gap: CGFloat

    init(kind: Kind, gap: CGFloat) {
        self.kind = kind
        self.gap = gap
    }

    static var caption: UIFont {
        UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .medium)
    }
}

nonisolated private func replyFrame(_ text: NSMutableAttributedString, in decoration: ReplyDecoration, top: CGFloat, bottom: CGFloat) {
    text.addAttribute(.replyDecoration, value: decoration, range: NSRange(location: 0, length: text.length))
    let string = text.string as NSString
    var location = 0
    while location < text.length {
        let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
        text.enumerateAttribute(.paragraphStyle, in: paragraph) { value, range, _ in
            guard let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else { return }
            style.paragraphSpacingBefore = paragraph.location == 0 ? top : 0
            style.paragraphSpacing = NSMaxRange(paragraph) == text.length ? bottom : 0
            text.addAttribute(.paragraphStyle, value: style, range: range)
        }
        location = NSMaxRange(paragraph)
    }
}

nonisolated final class ReplyLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let whole = NSRange(location: 0, length: storage.length)
        let shown = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        var location = shown.location
        while location < NSMaxRange(shown) {
            var range = NSRange()
            let decoration = storage.attribute(.replyDecoration, at: location, longestEffectiveRange: &range, in: whole) as? ReplyDecoration
            location = NSMaxRange(range)
            guard let decoration else { continue }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let first = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let last = lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
            let box = CGRect(x: origin.x, y: origin.y + first.minY + decoration.gap, width: container.size.width, height: last.maxY - first.minY - decoration.gap)
            draw(decoration.kind, in: box)
        }
    }

    private func draw(_ kind: ReplyDecoration.Kind, in box: CGRect) {
        switch kind {
        case .code(let language):
            UIColor.quaternarySystemFill.setFill()
            UIBezierPath(roundedRect: box, cornerRadius: 12).fill()
            (language as NSString?)?.draw(at: CGPoint(x: box.minX + 12, y: box.minY + 12), withAttributes: [.font: ReplyDecoration.caption, .foregroundColor: UIColor.secondaryLabel])
        case .quote:
            UIColor.tertiaryLabel.setFill()
            UIBezierPath(roundedRect: CGRect(x: box.minX, y: box.minY, width: 4, height: box.height), cornerRadius: 2).fill()
        case .rule:
            UIColor.separator.setFill()
            let scale = UITraitCollection.current.displayScale
            UIRectFill(CGRect(x: box.minX, y: (box.midY * scale).rounded() / scale, width: box.width, height: 1 / scale))
        }
    }
}

final class SelectableTextView: UITextView, UIEditMenuInteractionDelegate {
    var startsSelected = true
    var didResign: () -> Void = {}
    private var hasStarted = false
    private var showsMenu = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, startsSelected, !hasStarted else { return }
        hasStarted = true
        guard becomeFirstResponder() else { return didResign() }
        selectAll(nil)
        UIAccessibility.post(notification: .layoutChanged, argument: self)
        showsMenu = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard showsMenu, bounds.height > 0, let range = selectedTextRange else { return }
        showsMenu = false
        let menu = UIEditMenuInteraction(delegate: self)
        addInteraction(menu)
        let selection = selectionRects(for: range).reduce(CGRect.null) { $0.union($1.rect) }
        let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: selection.midX, y: selection.minY))
        configuration.preferredArrowDirection = .down
        menu.presentEditMenu(with: configuration)
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
        guard let range = selectedTextRange else { return .null }
        return selectionRects(for: range).reduce(CGRect.null) { $0.union($1.rect) }
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        didResign()
        return true
    }

    override func copy(_ sender: Any?) {
        guard selectedRange.length > 0 else { return }
        let selection = textStorage.attributedSubstring(from: selectedRange)
        let plain = NSMutableString(string: selection.string)
        selection.enumerateAttribute(.replyPlainText, in: NSRange(location: 0, length: selection.length), options: .reverse) { value, range, _ in
            guard let value = value as? String else { return }
            plain.replaceCharacters(in: range, with: value)
        }
        UIPasteboard.general.string = plain as String
    }
}

struct SelectableText: UIViewRepresentable {
    let text: NSAttributedString
    var tint: UIColor?
    var startsSelected = true
    @Binding var isSelecting: Bool

    @Environment(\.openURL) private var openURL

    final class Coordinator: NSObject, UITextViewDelegate {
        var isSelecting: Binding<Bool>
        var openURL: OpenURLAction
        var text: NSAttributedString?
        var hasSelection = false
        var isReplacingText = false
        var measured: (width: CGFloat?, size: CGSize)?

        init(isSelecting: Binding<Bool>, openURL: OpenURLAction) {
            self.isSelecting = isSelecting
            self.openURL = openURL
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView.selectedRange.length > 0 {
                hasSelection = true
            } else if hasSelection, !isReplacingText {
                isSelecting.wrappedValue = false
            }
        }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .link(let url) = textItem.content else { return defaultAction }
            return UIAction { [isSelecting, openURL] _ in
                isSelecting.wrappedValue = false
                openURL(url)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isSelecting: $isSelecting, openURL: openURL)
    }

    func makeUIView(context: Context) -> SelectableTextView {
        let storage = NSTextStorage()
        let layout = ReplyLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: .zero)
        container.lineFragmentPadding = 0
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let view = SelectableTextView(frame: .zero, textContainer: container)
        view.isEditable = false
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.backgroundColor = .clear
        view.dataDetectorTypes = []
        view.startsSelected = startsSelected
        view.delegate = context.coordinator
        view.didResign = { context.coordinator.isSelecting.wrappedValue = false }
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: SelectableTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isSelecting = $isSelecting
        coordinator.openURL = openURL
        view.tintColor = tint
        guard coordinator.text?.isEqual(to: text) != true else { return }
        let selection = view.selectedRange
        coordinator.isReplacingText = true
        view.textStorage.setAttributedString(text)
        let location = min(selection.location, text.length)
        view.selectedRange = NSRange(location: location, length: min(selection.length, text.length - location))
        coordinator.isReplacingText = false
        coordinator.text = text
        coordinator.measured = nil
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: SelectableTextView, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        if let measured = context.coordinator.measured, measured.width == width { return measured.size }
        let container = view.textContainer
        container.size = CGSize(width: width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.layoutManager.ensureLayout(for: container)
        let used = view.layoutManager.usedRect(for: container)
        let size = CGSize(width: width ?? ceil(used.width), height: ceil(used.height))
        context.coordinator.measured = (width, size)
        return size
    }
}
#endif
