import SwiftUI

let transcriptEnd = "transcript-end"

private struct BottomEdge: Equatable {
    let distance: CGFloat
    let height: CGFloat
}

struct TranscriptScroll<Revision: Equatable, Content: View>: View {
    @Binding var position: ScrollPosition
    let revision: Revision
    @ViewBuilder let content: Content

    @State private var isAtBottom = true
    @State private var phase = ScrollPhase.idle

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
        .defaultScrollAnchor(.bottom)
        .scrollPosition($position)
        .onScrollGeometryChange(for: BottomEdge.self) { BottomEdge(distance: $0.contentSize.height - $0.visibleRect.maxY + $0.contentInsets.bottom, height: $0.containerSize.height) } action: { old, new in
            isAtBottom = new.distance < 40
            if old.height == 0, new.height > 0 { position.scrollTo(id: transcriptEnd) }
            if followsEnd, old.distance < 40, new.distance >= 1, phase == .idle, new.height <= old.height { position.scrollTo(id: transcriptEnd) }
        }
        .onScrollPhaseChange { old, new in
            phase = new
            if old.isScrolling, old != .animating, new == .idle, isAtBottom { position.scrollTo(id: transcriptEnd) }
        }
        .onChange(of: revision) {
            if isAtBottom { position.scrollTo(id: transcriptEnd) }
        }
        .overlay(alignment: .bottom) {
            ZStack {
                if !isAtBottom {
                    Button("Jump to Latest", systemImage: "arrow.down") {
                        position.scrollTo(id: transcriptEnd)
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
