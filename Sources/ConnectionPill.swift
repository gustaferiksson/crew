import SwiftUI

struct ConnectionPill: View {
    @Environment(Connection.self) private var connection

    var body: some View {
        HStack(spacing: 12) {
            if connection.state == .connecting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(connection.state == .connecting ? "Connecting…" : "Can't reach server")
                    .font(.callout.weight(.semibold))
                Text(connection.session?.server.host() ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if connection.state == .unreachable {
                Button("Retry", action: connection.retry)
                    .buttonStyle(.glass)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(in: .capsule)
        #if os(iOS)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        #else
        .padding(12)
        #endif
    }
}
