import SwiftUI

let transcriptEnd = "transcript-end"

private struct BottomEdge: Equatable {
    let distance: CGFloat
    let height: CGFloat
    // The bar's inset can change without the distance changing, and the action must still run.
    let inset: CGFloat
}

struct TranscriptScroll<Revision: Equatable, Content: View>: View {
    @Binding var position: ScrollPosition
    let revision: Revision
    let barHeight: CGFloat
    @ViewBuilder let content: Content

    @State private var isAtBottom = true
    @State private var phase = ScrollPhase.idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var followsEnd: Bool {
        position.isPositionedByUser || position.viewID.map { AnyHashable($0) == AnyHashable(transcriptEnd) } ?? true
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                content
                Color.clear
                    .frame(height: 0)
                    .id(transcriptEnd)
            }
        }
        #if os(iOS)
        // iOS 27 applies the size-change anchor to LazyVStack height estimates and parks the viewport past the drawn rows (#153).
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        #else
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .defaultScrollAnchor(followsEnd ? .bottom : nil, for: .sizeChanges)
        #endif
        .scrollPosition($position)
        .onScrollGeometryChange(for: BottomEdge.self) { BottomEdge(distance: $0.contentSize.height - $0.visibleRect.maxY + $0.contentInsets.bottom, height: $0.containerSize.height, inset: $0.contentInsets.bottom) } action: { old, new in
            isAtBottom = new.distance < 40
            if position.edge == .bottom, new.distance < 1 { position.scrollTo(id: transcriptEnd, anchor: .bottom) }
            if followsEnd, old.height == 0, new.height > 0 { position.scrollTo(id: transcriptEnd, anchor: .bottom) }
            if followsEnd, old.distance < 40, new.distance >= 1, phase == .idle, new.height <= old.height { position.scrollTo(id: transcriptEnd, anchor: .bottom) }
        }
        .onScrollPhaseChange { old, new in
            phase = new
            if old.isScrolling, old != .animating, new == .idle, isAtBottom { position.scrollTo(id: transcriptEnd, anchor: .bottom) }
        }
        .onChange(of: revision) {
            if followsEnd, isAtBottom, phase == .idle { position.scrollTo(id: transcriptEnd, anchor: .bottom) }
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
                }
            }
            .animation(.smooth, value: isAtBottom)
            .padding(.bottom, barHeight + 12)
            .ignoresSafeArea(.container, edges: .bottom)
            #if os(macOS)
            .padding(.trailing, NSScroller.preferredScrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0)
            #endif
        }
    }
}
