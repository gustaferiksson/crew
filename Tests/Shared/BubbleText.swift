import CoreGraphics

func whiteShareInsideBubble(_ image: CGImage) -> Double {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let isFill = { (offset: Int) in pixels[offset + 2] > 200 && pixels[offset] < 140 }
    let isWhite = { (offset: Int) in pixels[offset] > 230 && pixels[offset + 1] > 230 && pixels[offset + 2] > 230 }
    let inside = (0..<height).flatMap { row -> [Int] in
        let offsets = (0..<width).map { (row * width + $0) * 4 }
        guard let first = offsets.firstIndex(where: isFill), let last = offsets.lastIndex(where: isFill) else { return [] }
        return Array(offsets[first...last])
    }
    return Double(inside.count(where: isWhite)) / Double(max(inside.count, 1))
}
