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
                    .buttonStyle(.bordered)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background { Color.clear.glassEffect(in: .capsule) }
        #if os(iOS)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        #else
        .padding(12)
        #endif
    }
}

struct ConnectionBadge: View {
    @Environment(Connection.self) private var connection

    var body: some View {
        let title = connection.state == .connecting ? String(localized: "Connecting…") : String(localized: "Can't reach server")
        let host = connection.session?.server.host() ?? ""
        Button(action: connection.retry) {
            Group {
                if connection.state == .connecting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 36, height: 36)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(connection.state != .unreachable)
        .glassEffect(in: .circle)
        .help(Text(verbatim: "\(title), \(host)"))
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: host))
        .accessibilityHint(connection.state == .unreachable ? Text("Retry") : Text(verbatim: ""))
        .padding(12)
    }
}
