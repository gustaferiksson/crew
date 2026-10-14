import SwiftUI

struct AvatarGallery: View {
    private let colors = ["#ffffff", "#ef4444", "#14b8a6", "#8b5cf6"]

    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        shapes
                        sizes
                    }
                    expressions
                }
                .frame(minWidth: 880)
                VStack(spacing: 16) {
                    shapes
                    expressions
                    sizes
                }
            }
            .padding(16)
        }
    }

    private var shapes: some View {
        GroupBox("Shapes") {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(colors, id: \.self) { color in
                    GridRow {
                        ForEach(AvatarShape.allCases) { shape in
                            AvatarView(shape: shape, color: color, seed: shape.rawValue + color, size: 36)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var expressions: some View {
        GroupBox("Expressions") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], spacing: 8) {
                ForEach(AvatarExpression.allCases) { expression in
                    VStack(spacing: 4) {
                        AvatarView(shape: .squircle, color: "#38bdf8", expression: expression, seed: expression.rawValue, size: 36)
                        Text(expression.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var sizes: some View {
        GroupBox("Sizes and Moods") {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach([24, 32, 48, 80, 120], id: \.self) { size in
                    AvatarView(shape: .blob, color: "#f59e0b", seed: "size\(size)", size: CGFloat(size))
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 16) {
                ForEach(AvatarMood.allCases) { mood in
                    VStack(spacing: 4) {
                        AvatarView(shape: .circle, color: "#22c55e", mood: mood, seed: mood.rawValue, size: 40)
                        Text(mood.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 4) {
                    AvatarView(shape: .circle, color: "#22c55e", photo: Snapshot.samplePhoto, size: 40)
                    Text("Photo")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }
}

struct AvatarPickerFixture: View {
    @State private var shape = AvatarShape.blob
    @State private var color = "#8b5cf6"
    @State private var expression = AvatarExpression.happy

    var body: some View {
        Form {
            AvatarPicker(shape: $shape, color: $color, expression: $expression) {
                shape = .circle
                color = AvatarColor.adaptiveHex
                expression = .neutral
            }
        }
        .formStyle(.grouped)
    }
}
