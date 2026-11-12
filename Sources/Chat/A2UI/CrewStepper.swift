import A2UICore
import A2UISwiftUI
import SwiftUI

struct CrewStepper: View {
    let node: Node

    var body: some View {
        let lower = node.double(for: "min") ?? 1
        let upper = max(lower, node.double(for: "max") ?? 99)
        let value = node.binding(for: "value", default: lower)
        let label = node.string(for: "label") ?? ""
        HStack {
            Group {
                Text(label)
                Spacer(minLength: 12)
                Text(value.wrappedValue, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Stepper(label, value: value, in: lower...upper)
                .labelsHidden()
                .accessibilityValue(Text(value.wrappedValue, format: .number))
        }
    }
}
