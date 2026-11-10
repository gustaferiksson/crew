import SwiftUI

struct EarlierHistoryRow: View {
    let state: EarlierHistory
    let retry: () -> Void

    var body: some View {
        Group {
            if state == .failed {
                VStack(spacing: 4) {
                    Text("Couldn't load earlier messages")
                        .foregroundStyle(.secondary)
                    #if os(iOS)
                    Button(action: retry) {
                        Text("Try Again")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .padding(.top, -4)
                    #else
                    Button("Try Again", action: retry)
                    #endif
                }
                .font(.footnote)
            } else {
                ProgressView()
                    .accessibilityLabel("Loading earlier messages")
            }
        }
        .frame(maxWidth: .infinity)
    }
}
