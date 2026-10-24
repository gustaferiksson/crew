import SwiftUI

struct ConnectionPill: View {
    @Environment(Connection.self) private var connection

    var body: some View {
        let title = connection.state == .connecting ? String(localized: "Connecting…") : String(localized: "Can't reach server")
        let host = connection.session?.server.host() ?? ""
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: title)
                        .font(.callout.weight(.semibold))
                    Text(verbatim: host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
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
            Button(action: connection.retry) {
                icon
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
        }
        #if os(iOS)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        #else
        .padding(12)
        #endif
    }

    @ViewBuilder
    private var icon: some View {
        if connection.state == .connecting {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
        }
    }
}
