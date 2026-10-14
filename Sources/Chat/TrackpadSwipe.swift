#if os(macOS)
import AppKit
import SwiftUI

struct TrackpadSwipe: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> TrackpadSwipeView {
        TrackpadSwipeView(onChange: onChange)
    }

    func updateNSView(_ view: TrackpadSwipeView, context: Context) {
        view.onChange = onChange
    }

    static func dismantleNSView(_ view: TrackpadSwipeView, coordinator: ()) {
        view.stopMonitoring()
    }
}

final class TrackpadSwipeView: NSView {
    private enum Tracking {
        case pending(CGSize, nested: [NSScrollView])
        case horizontal(CGFloat)
        case vertical
        case coasting
    }

    var onChange: (CGFloat) -> Void
    private var monitor: Any?
    private var tracking: Tracking?

    init(onChange: @escaping (CGFloat) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        tracking = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return onChange(0) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.phase.contains(.began) {
            let isInside = event.window === window && bounds.contains(convert(event.locationInWindow, from: nil))
            let hit = window?.contentView.flatMap { $0.hitTest($0.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow) }
            let nested = sequence(first: hit, next: { $0?.superview }).compactMap { $0 as? NSScrollView }
            tracking = isInside ? .pending(.zero, nested: nested) : nil
            return event
        }
        if !event.momentumPhase.isEmpty {
            guard case .coasting = tracking else { return event }
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) { tracking = nil }
            return nil
        }
        guard let current = tracking else { return event }
        if case .coasting = current {
            tracking = nil
            return event
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            guard case .horizontal = current else {
                tracking = nil
                return event
            }
            tracking = .coasting
            onChange(0)
            return nil
        }
        let finger = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        if case .horizontal(let offset) = current {
            let next = min(0, offset + finger)
            tracking = .horizontal(next)
            onChange(next)
            return nil
        }
        guard case .pending(let travel, let nested) = current else { return event }
        let moved = CGSize(width: travel.width + finger, height: travel.height + event.scrollingDeltaY)
        if max(abs(moved.width), abs(moved.height)) < 8 {
            tracking = .pending(moved, nested: nested)
            return event
        }
        if abs(moved.width) <= abs(moved.height) || moved.width > 0 || nested.contains(where: { canScrollHorizontally($0, finger: moved.width) }) {
            tracking = .vertical
            return event
        }
        let next = min(0, moved.width)
        tracking = .horizontal(next)
        onChange(next)
        return nil
    }
}

func canScrollHorizontally(_ scrollView: NSScrollView, finger: CGFloat) -> Bool {
    guard let document = scrollView.documentView else { return false }
    let visible = scrollView.contentView.bounds
    if finger < 0 { return visible.maxX < document.frame.maxX - 1 }
    return visible.minX > document.frame.minX + 1
}
#endif
