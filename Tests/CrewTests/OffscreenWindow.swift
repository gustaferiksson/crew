import AppKit

class OffscreenWindow: NSWindow {
    convenience init(size: NSSize, styleMask: NSWindow.StyleMask) {
        // A titled window's init moves an offscreen contentRect onto a screen, and ordering it in runs constrainFrameRect.
        self.init(contentRect: NSRect(origin: .zero, size: size), styleMask: styleMask, backing: .buffered, defer: false)
        setFrameOrigin(NSPoint(x: -20000, y: -20000))
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
