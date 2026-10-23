import SwiftUI

private struct BottomEdge: Equatable {
    let distance: CGFloat
    let height: CGFloat
}

struct TranscriptScroll<Content: View>: View {
    @Binding var position: ScrollPosition
    @ViewBuilder let content: Content

    @State private var isAtBottom = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView { content }
            .defaultScrollAnchor(.bottom)
            .scrollPosition($position)
            .onScrollGeometryChange(for: BottomEdge.self) { BottomEdge(distance: $0.contentSize.height - $0.visibleRect.maxY + $0.contentInsets.bottom, height: $0.containerSize.height) } action: { old, new in
                isAtBottom = new.distance < 40
                if new.height < old.height, old.distance < 40 { position.scrollTo(edge: .bottom) }
            }
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
