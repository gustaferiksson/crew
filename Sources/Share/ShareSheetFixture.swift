#if os(iOS)
import SwiftUI

struct ShareSheetFixture: View {
    let tooLarge: Bool

    private static let bots = [
        VoiceBot(name: "chef", title: "Chef", session: nil, lastActive: .now, shape: "blob", color: "#f97316", expression: "happy", hidden: false),
        VoiceBot(name: "default", title: "Hermes", session: nil, lastActive: .now.addingTimeInterval(-3600), shape: "blob", color: "#8b5cf6", expression: "happy", hidden: false),
    ]

    private var items: [SharedItem] {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120)).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
        }
        return [
            .link(URL(string: "https://www.example.com/recipes/weeknight-risotto")!, title: "Weeknight Risotto"),
            .file(Attachment(kind: .image, name: "IMG_0412.png", data: photo)),
            .file(Attachment(kind: .file, name: "Quarterly Shopping Budget.pdf", data: Data(count: tooLarge ? 16_000_000 : 182_000))),
        ]
    }

    var body: some View {
        ShareSheet(bots: Self.bots, isSignedIn: true, load: { items }, send: { _, _, _ in }, cancel: {})
    }
}
#endif
