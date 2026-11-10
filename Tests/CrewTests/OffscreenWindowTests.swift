import AppKit
import SwiftUI
import Testing

@MainActor struct OffscreenWindowTests {
    private func onScreen(_ window: NSWindow) -> [CGRect] {
        NSScreen.screens.map(\.frame).filter { $0.intersects(window.frame) }
    }

    @Test(arguments: [[.borderless], [.titled, .resizable], [.titled, .resizable, .closable, .miniaturizable, .fullSizeContentView]] as [NSWindow.StyleMask])
    func aHostedTestWindowNeverTouchesAScreen(styleMask: NSWindow.StyleMask) {
        let window = OffscreenWindow(size: NSSize(width: 600, height: 700), styleMask: styleMask)
        window.isRestorable = false
        window.alphaValue = 0
        #expect(onScreen(window).isEmpty, "created at \(window.frame)")

        window.contentViewController = NSHostingController(rootView: Color.clear.frame(minWidth: 100, minHeight: 100))
        window.setContentSize(NSSize(width: 600, height: 700))
        #expect(onScreen(window).isEmpty, "hosted at \(window.frame)")

        window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle()
        #expect(onScreen(window).isEmpty, "ordered in at \(window.frame)")

        window.setContentSize(NSSize(width: 500, height: 600))
        settle()
        #expect(onScreen(window).isEmpty, "resized to \(window.frame)")
    }

    @Test func aWindowLargerThanTheScreenKeepsItsSize() throws {
        let screen = try #require(NSScreen.main?.frame.size)
        let size = NSSize(width: screen.width + 500, height: screen.height + 500)
        let window = OffscreenWindow(size: size, styleMask: [.titled, .resizable])
        window.isRestorable = false
        window.alphaValue = 0
        window.contentViewController = NSHostingController(rootView: Color.clear.frame(minWidth: 100, minHeight: 100))
        window.setContentSize(size)
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        settle()

        #expect(window.contentRect(forFrameRect: window.frame).size == size)
        #expect(onScreen(window).isEmpty, "ordered in at \(window.frame)")
    }
}
