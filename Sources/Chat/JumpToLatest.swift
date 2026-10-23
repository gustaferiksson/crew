import SwiftUI

struct JumpToLatest: ViewModifier {
    let isAtBottom: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                ZStack {
                    if !isAtBottom {
                        Button("Jump to Latest", systemImage: "arrow.down", action: action)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            #if os(macOS)
                            .controlSize(.large)
                            #endif
                            .transition(.scale.combined(with: .opacity))
                            .padding(.bottom, 12)
                            .frame(height: 0, alignment: .bottom)
                    }
                }
                .animation(.smooth, value: isAtBottom)
            }
    }
}
