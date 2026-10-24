import SwiftUI

struct AvatarPicker: View {
    @Binding var shape: AvatarShape
    @Binding var color: String
    @Binding var expression: AvatarExpression
    let reset: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            AvatarView(shape: shape, color: color, expression: expression, size: 120)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
        }
        Section("Shape") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(AvatarShape.allCases) { option in
                    Button {
                        shape = option
                    } label: {
                        AvatarView(shape: option, color: color, expression: expression, size: 44)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .contentShape(.rect(cornerRadius: 16))
                            .overlay {
                                if option == shape {
                                    RoundedRectangle(cornerRadius: 16).strokeBorder(.tint, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.rawValue.capitalized)
                    .accessibilityAddTraits(option == shape ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
        Section("Color") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 48), spacing: 8)], spacing: 8) {
                ForEach(AvatarColor.palette) { swatch in
                    Button {
                        color = swatch.hex
                    } label: {
                        Circle()
                            .fill(AvatarColor.body(swatch.hex, in: colorScheme))
                            .overlay { Circle().strokeBorder(.separator, lineWidth: 1) }
                            .padding(4)
                            .overlay {
                                if swatch.hex == color.lowercased() {
                                    Circle().strokeBorder(.primary, lineWidth: 2)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(swatch.name)
                    .accessibilityAddTraits(swatch.hex == color.lowercased() ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
        Section("Expression") {
            ForEach(AvatarExpression.allCases) { option in
                Button {
                    expression = option
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(shape: shape, color: color, expression: option, size: 32)
                        Text(option.rawValue.capitalized)
                            .foregroundStyle(.primary)
                        Spacer()
                        if option == expression {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == expression ? .isSelected : [])
            }
        }
        Section {
            Button("Reset to Default", systemImage: "arrow.counterclockwise", action: reset)
        }
    }
}
