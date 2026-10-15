import CoreGraphics

func pinPoint(_ projected: CGPoint, in size: CGSize) -> CGPoint {
    #if os(macOS)
    // AppKit snapshots project with a bottom-left origin.
    CGPoint(x: projected.x, y: size.height - projected.y)
    #else
    projected
    #endif
}
