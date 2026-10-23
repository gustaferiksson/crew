import AppKit
import SwiftUI
import Testing

private func productPhoto(width: Int, height: Int) throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

@Test @MainActor func aCardImageLaidOutAgainAfterScrollingAwayKeepsItsLoadedHeight() throws {
    let url = try #require(URL(string: "https://images.example.com/slippers-\(UUID().uuidString).jpg"))
    let card = CardImage(url: url, variant: "mediumFeature", fit: "fill")
    #expect(NSHostingController(rootView: card.fixedSize(horizontal: false, vertical: true)).sizeThatFits(in: CGSize(width: 330, height: CGFloat.infinity)).height == 200)

    cachedImages.setObject(try productPhoto(width: 1600, height: 2000), forKey: url as NSURL)
    let recycled = CardImage(url: url, variant: "mediumFeature", fit: "fill")
    let recycledHeight = NSHostingController(rootView: recycled.fixedSize(horizontal: false, vertical: true)).sizeThatFits(in: CGSize(width: 330, height: CGFloat.infinity)).height
    #expect(abs(recycledHeight - 412.5) < 1, "\(recycledHeight)")
}

@Test @MainActor func manyShopPhotosDecodingAtOnceAllFinish() throws {
    let photo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "fixtures/images/haika-slipper.avif")
    let count = ProcessInfo.processInfo.activeProcessorCount * 4
    let finished = DispatchSemaphore(value: 0)
    Task.detached {
        let decoded = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<count { group.addTask { (try? await downloadDownsampledImage(photo)) != nil } }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        if decoded == count { finished.signal() }
    }
    #expect(finished.wait(timeout: .now() + 60) == .success, "\(count) AVIF decodes did not all succeed within 60 s")
}
