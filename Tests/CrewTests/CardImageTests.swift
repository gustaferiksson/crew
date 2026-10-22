import AppKit
import SwiftUI
import Testing

@MainActor private func height(_ view: some View, width: CGFloat) -> CGFloat {
    NSHostingController(rootView: view.fixedSize(horizontal: false, vertical: true)).sizeThatFits(in: CGSize(width: width, height: .infinity)).height
}

private func productPhoto(width: Int, height: Int) throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

@Test @MainActor func aCardImageLaidOutAgainAfterScrollingAwayKeepsItsLoadedHeight() throws {
    let url = try #require(URL(string: "https://images.example.com/slippers-\(UUID().uuidString).jpg"))
    let card = CardImage(url: url, variant: "mediumFeature", fit: "fill")
    #expect(height(card, width: 330) == 200)

    cachedImages.setObject(try productPhoto(width: 1600, height: 2000), forKey: url as NSURL)
    let recycled = CardImage(url: url, variant: "mediumFeature", fit: "fill")
    let recycledHeight = height(recycled, width: 330)
    #expect(abs(recycledHeight - 412.5) < 1, "\(recycledHeight)")
}
