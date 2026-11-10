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
                    Button("Try Again", action: retry)
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
