import SwiftUI

struct TranscriptScroll<Content: View>: View {
    @Binding var position: ScrollPosition
    @ViewBuilder let content: Content

    @State private var isAtBottom = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView { content }
            .defaultScrollAnchor(.bottom)
            .scrollPosition($position)
            .onScrollGeometryChange(for: Bool.self) { $0.contentSize.height - $0.visibleRect.maxY + $0.contentInsets.bottom < 40 } action: { isAtBottom = $1 }
            .overlay(alignment: .bottom) {
                ZStack {
                    if !isAtBottom {
                        Button("Jump to Latest", systemImage: "arrow.down") {
                            withAnimation(reduceMotion ? nil : .smooth) { position.scrollTo(edge: .bottom) }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        #if os(macOS)
                        .controlSize(.large)
                        #endif
                        .transition(.scale.combined(with: .opacity))
                        .padding(.bottom, 12)
                    }
                }
                .animation(.smooth, value: isAtBottom)
                #if os(macOS)
                .padding(.trailing, NSScroller.preferredScrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0)
                #endif
            }
    }
}
