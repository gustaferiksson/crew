import SwiftUI

struct UserBubble: View {
    let text: String

    @State private var isUnfolded = false
    @State private var fullHeight: CGFloat = 0
    @State private var foldThreshold: CGFloat = 0

    private let shape = UnevenRoundedRectangle(
        cornerRadii: RectangleCornerRadii(topLeading: 19, bottomLeading: 19, bottomTrailing: 2, topTrailing: 19),
        style: .circular
    )

    private static let fill = LinearGradient(
        colors: [
            Color(.displayP3, red: 0x57 / 255, green: 0xA4 / 255, blue: 0xF6 / 255),
            Color(.displayP3, red: 0x52 / 255, green: 0x9F / 255, blue: 0xF5 / 255),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    private var isFoldable: Bool { fullHeight > foldThreshold + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: text)
                .lineLimit(isFoldable && !isUnfolded ? 6 : nil)
                .background {
                    Text(verbatim: text)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { fullHeight = $0 }
                }
                .background {
                    Text(verbatim: text)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { foldThreshold = $0 }
                }
            if isFoldable {
                Button(isUnfolded ? "Show less" : "Show more") {
                    withAnimation(.snappy) { isUnfolded.toggle() }
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            }
        }
        .foregroundStyle(.white)
        #if os(macOS)
        .textSelection(.enabled)
        #endif
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Self.fill, in: shape)
        .modifier(MessageMenu(text: text, shape: shape))
        .containerRelativeFrame(.horizontal, alignment: .trailing) { length, _ in min(length * 0.75, 560) }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
