import CoreGraphics
import Testing

@Test func coordinateAboveCentreGetsSmallerYOnMac() {
    let size = CGSize(width: 100, height: 400)
    let aboveCentreInAppKit = CGPoint(x: 10, y: 300)
    #expect(pinPoint(aboveCentreInAppKit, in: size) == CGPoint(x: 10, y: 100))
}
