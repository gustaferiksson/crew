import SwiftUI

nonisolated struct SlashCommand: Hashable, Sendable {
    let name: String
    let summary: String
    var isSkill = false
}

nonisolated struct SlashReply: Decodable, Sendable {
    let output: String?
    let warning: String?
    let type: String?
    let target: String?
    let message: String?
    let notice: String?
    let display: String?
}

nonisolated func slashInvocation(_ text: String, in commands: [SlashCommand]) -> (command: SlashCommand, arg: String)? {
    let name = text.prefix { !$0.isWhitespace }
    guard let command = commands.first(where: { $0.name == name }) else { return nil }
    return (command, text.dropFirst(name.count).trimmingCharacters(in: .whitespacesAndNewlines))
}

nonisolated struct SlashCatalog: Decodable, Sendable {
    private struct BuiltIn: Decodable {
        let desktop: String?
    }

    private enum CodingKeys: String, CodingKey {
        case pairs, commands, skills
    }

    let commands: [SlashCommand]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let builtIns = try container.decode([String: BuiltIn].self, forKey: .commands)
        let skills = try container.decode([String: JSONValue].self, forKey: .skills)
        commands = try container.decode([[String]].self, forKey: .pairs).compactMap { pair in
            guard pair.count == 2, !["/branch", "/resume"].contains(pair[0]) else { return nil }
            if skills[pair[0]] != nil { return SlashCommand(name: pair[0], summary: pair[1], isSkill: true) }
            guard builtIns[pair[0]].map({ $0.desktop == nil }) == true else { return nil }
            return SlashCommand(name: pair[0], summary: pair[1])
        }
    }
}

struct SlashPicker: View {
    let query: String
    let commands: [SlashCommand]
    let pick: (String) -> Void

    var matches: [SlashCommand] {
        let query = query.lowercased()
        return commands.filter { $0.name.dropFirst().lowercased().hasPrefix(query) }
    }

    var body: some View {
        if !matches.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(matches, id: \.name) { command in
                        Button {
                            pick(command.name)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(command.name)
                                    .font(.body.monospaced())
                                    .foregroundStyle(.tint)
                                    .lineLimit(1)
                                Text(command.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 240)
            .fixedSize(horizontal: false, vertical: true)
            .glassEffect(in: .rect(cornerRadius: 20))
            .transition(.opacity)
        }
    }
}
