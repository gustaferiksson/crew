import CoreGraphics
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

@Observable
final class ProfileDraft {
    enum Phase: Equatable {
        case loading, loaded, failed(String)
    }

    enum PhotoChange: Equatable {
        case unchanged, replace(Data), clear
    }

    struct Identity: Equatable {
        var title: String
        var shape: AvatarShape
        var color: String
        var expression: AvatarExpression
        var custom: Bool

        init(bot: Bot) {
            let meta = bot.meta
            let look = meta.look(name: bot.name)
            title = bot.title
            shape = look.shape
            color = look.color
            expression = AvatarExpression.resolve(meta.expression)
            custom = meta.custom ?? (meta.shape != nil || meta.color != nil)
        }
    }

    struct Fields: Equatable {
        var identity: Identity
        var description = ""
        var soul = ""
        var instructions = ""
        var skills: [ProfileCapability] = []
        var toolsets: [ProfileCapability] = []
        var mcpServers: [ProfileCapability] = []

        var richUI: Bool {
            get { skills.contains { $0.name == crewUISkillName && $0.enabled } }
            set {
                if let index = skills.firstIndex(where: { $0.name == crewUISkillName }) {
                    skills[index].enabled = newValue
                } else if newValue {
                    skills.append(ProfileCapability(name: crewUISkillName, label: nil, description: nil, transport: nil, toolCount: nil, enabled: true))
                }
            }
        }
    }

    let name: String
    let fallbackTitle: String
    var fields: Fields
    var notice: String?
    private(set) var phase = Phase.loading
    private(set) var photo: CGImage?
    private(set) var photoChange = PhotoChange.unchanged
    private(set) var isSaving = false
    private(set) var savedAt: Date?

    private var baseline: Fields
    private var meta: BotMeta
    private var revision: Int?
    private var savedPhoto: CGImage?
    private var resaveWanted = false

    init(bot: Bot) {
        name = bot.name
        fallbackTitle = bot.title
        meta = bot.meta
        revision = bot.metaRevision
        let fields = Fields(identity: Identity(bot: bot))
        self.fields = fields
        baseline = fields
    }

    convenience init(bot: Bot, details: ProfileDetails, instructions: String = "", photo: CGImage? = nil) {
        self.init(bot: bot)
        fields = Fields(
            identity: fields.identity, description: details.description, soul: details.soul, instructions: instructions,
            skills: details.skills, toolsets: details.toolsets, mcpServers: details.mcpServers
        )
        baseline = fields
        self.photo = photo
        savedPhoto = photo
        phase = .loaded
    }

    var isDirty: Bool {
        fields != baseline || photoChange != .unchanged
    }

    var title: String {
        let title = fields.identity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? fallbackTitle : title
    }

    func load(_ gateway: Gateway, urlSession: URLSession) async {
        do {
            async let details = gateway.call("profiles.describe", ["name": name], as: ProfileDetails.self)
            async let loadedInstructions = instructions(of: name, on: gateway.server, with: urlSession)
            async let roster = gateway.call("profiles.list", [String: String](), as: ProfileRoster.self)
            let (loadedDetails, loadedRoster, instructionsText) = try await (details, roster, loadedInstructions)
            guard let bot = loadedRoster.profiles.first(where: { $0.name == name }) else {
                phase = .failed(String(localized: "This bot no longer exists on the server."))
                return
            }
            let server = Fields(
                identity: Identity(bot: bot), description: loadedDetails.description, soul: loadedDetails.soul,
                instructions: instructionsText, skills: loadedDetails.skills, toolsets: loadedDetails.toolsets, mcpServers: loadedDetails.mcpServers
            )
            meta = bot.meta
            revision = bot.metaRevision
            if fields.identity == baseline.identity { fields.identity = server.identity }
            if fields.description == baseline.description { fields.description = server.description }
            if fields.soul == baseline.soul { fields.soul = server.soul }
            if fields.instructions == baseline.instructions { fields.instructions = server.instructions }
            if fields.skills == baseline.skills { fields.skills = server.skills }
            if fields.toolsets == baseline.toolsets { fields.toolsets = server.toolsets }
            if fields.mcpServers == baseline.mcpServers { fields.mcpServers = server.mcpServers }
            baseline = server
            if server.richUI { try? await installCrewUISkill(in: name, on: gateway.server, with: urlSession) }
            if photoChange == .unchanged {
                photo = bot.hasAvatar ? await fetchPhoto(gateway) : nil
                savedPhoto = photo
            }
            phase = .loaded
        } catch {
            let message = if case GatewayError.rpc(_, let message) = error { message } else { String(localized: "Crew couldn't load this bot. Check your connection and try again.") }
            phase = .failed(message)
        }
    }

    func save(_ gateway: Gateway, urlSession: URLSession) async {
        guard !isSaving else {
            resaveWanted = true
            return
        }
        guard isDirty else { return }
        isSaving = true
        notice = nil
        var sent = fields
        var failed: [String] = []
        if sent.instructions != baseline.instructions {
            do {
                try await saveInstructions(sent.instructions, of: name, on: gateway.server, with: urlSession)
                baseline.instructions = sent.instructions
            } catch {
                failed.append(String(localized: "instructions"))
            }
        }
        if sent.richUI, !baseline.richUI {
            do {
                try await installCrewUISkill(in: name, on: gateway.server, with: urlSession)
            } catch {
                sent.skills = sent.skills.compactMap { $0.name == crewUISkillName ? baseline.skills.first { $0.name == crewUISkillName } : $0 }
                failed.append(String(localized: "Rich UI"))
            }
        }
        var configured = sent
        configured.instructions = baseline.instructions
        if configured != baseline || photoChange != .unchanged {
            failed += await send(sent, gateway)
        }
        isSaving = false
        if !failed.isEmpty, notice == nil {
            notice = String(localized: "Couldn't save the \(failed.formatted(.list(type: .and))).")
        }
        if notice == nil { savedAt = .now }
        guard resaveWanted else { return }
        resaveWanted = false
        guard notice == nil else { return }
        await save(gateway, urlSession: urlSession)
    }

    func pickShape(_ shape: AvatarShape) {
        fields.identity.shape = shape
        fields.identity.custom = true
        removePhoto()
    }

    func pickColor(_ color: String) {
        fields.identity.color = color
        fields.identity.custom = true
        removePhoto()
    }

    func pickPhoto(_ data: Data) async {
        guard let jpeg = await avatarJPEG(from: data),
              let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            notice = String(localized: "Crew couldn't read that image. Try a JPEG, PNG or HEIC photo.")
            return
        }
        photo = image
        photoChange = .replace(jpeg)
        fields.identity.custom = true
    }

    func removePhoto() {
        photo = nil
        photoChange = savedPhoto == nil ? .unchanged : .clear
    }

    func resetLook() {
        let look = BotMeta().look(name: name)
        fields.identity.shape = look.shape
        fields.identity.color = look.color
        fields.identity.expression = .neutral
        fields.identity.custom = false
        removePhoto()
    }

    private func outgoingMeta(_ identity: Identity) -> BotMeta {
        var meta = meta
        if identity.title != baseline.identity.title {
            let title = identity.title.trimmingCharacters(in: .whitespacesAndNewlines)
            meta.title = title.isEmpty ? nil : title
        }
        if identity.shape != baseline.identity.shape || identity.color != baseline.identity.color || identity.custom != baseline.identity.custom {
            meta.shape = identity.custom ? identity.shape.rawValue : nil
            meta.color = identity.custom ? identity.color : nil
            meta.custom = identity.custom
        }
        if identity.expression != baseline.identity.expression {
            meta.expression = identity.expression == .neutral ? nil : identity.expression.rawValue
        }
        meta.imageKind = photo != nil ? "photo" : identity.custom ? "shape" : nil
        return meta
    }

    private func send(_ sent: Fields, _ gateway: Gateway) async -> [String] {
        let sentPhoto = photoChange
        var changes = ProfileChanges(name: name)
        if sent.identity != baseline.identity || sentPhoto != .unchanged {
            changes.uiMeta = ["hermes-bots": outgoingMeta(sent.identity)]
            changes.uiMetaExpectedRevisions = ["hermes-bots": revision ?? 0]
        }
        if sent.description != baseline.description { changes.description = sent.description.trimmingCharacters(in: .whitespacesAndNewlines) }
        if sent.soul != baseline.soul { changes.soul = sent.soul }
        if sent.skills != baseline.skills { changes.disabledSkills = sent.skills.filter { !$0.enabled }.map(\.name) }
        if sent.toolsets != baseline.toolsets { changes.enabledToolsets = sent.toolsets.filter(\.enabled).map(\.name) }
        if sent.mcpServers != baseline.mcpServers { changes.enabledMCPServers = sent.mcpServers.filter(\.enabled).map(\.name) }
        do {
            let reply = try await gateway.call("profiles.configure", changes, as: ConfigureReply.self)
            let applied = reply.applied
            let sections: [(label: String, isSent: Bool, isApplied: Bool?, commit: (inout Fields) -> Void)] = [
                (String(localized: "description"), changes.description != nil, applied.description, { $0.description = sent.description }),
                (String(localized: "soul"), changes.soul != nil, applied.soul, { $0.soul = sent.soul }),
                (String(localized: "skills"), changes.disabledSkills != nil, applied.skills, { $0.skills = sent.skills }),
                (String(localized: "toolsets"), changes.enabledToolsets != nil, applied.toolsets, { $0.toolsets = sent.toolsets }),
                (String(localized: "MCP servers"), changes.enabledMCPServers != nil, applied.mcpServers, { $0.mcpServers = sent.mcpServers }),
            ]
            var failed: [String] = []
            for section in sections where section.isSent {
                guard section.isApplied == true else {
                    failed.append(section.label)
                    continue
                }
                section.commit(&baseline)
            }
            guard let sentMeta = changes.uiMeta?["hermes-bots"] else { return failed }
            if applied.uiMeta == true {
                meta = sentMeta
                revision = applied.uiMetaRevisions?["hermes-bots"] ?? revision
                baseline.identity = sent.identity
                if !(await uploadPhoto(sentPhoto, gateway)) { failed.append(String(localized: "photo")) }
            } else if applied.uiMetaConflicts != nil {
                await reloadIdentity(gateway)
                notice = String(localized: "This bot's name or look changed on another device. Crew loaded the latest version, so make those changes again.")
            } else {
                failed.append(String(localized: "name and look"))
            }
            return failed
        } catch {
            notice = if case GatewayError.rpc(_, let message) = error { message } else { String(localized: "Couldn't save. Check your connection and try again.") }
            return []
        }
    }

    private func uploadPhoto(_ sentPhoto: PhotoChange, _ gateway: Gateway) async -> Bool {
        let change = switch sentPhoto {
        case .unchanged: nil as AssetChange?
        case .replace(let jpeg): AssetChange(name: name, data: "data:image/jpeg;base64,\(jpeg.base64EncodedString())", clear: nil)
        case .clear: AssetChange(name: name, data: nil, clear: true)
        }
        guard let change else { return true }
        guard let reply = try? await gateway.call("profiles.set_asset", change, as: AssetReply.self), reply.ok == true else { return false }
        guard photoChange == sentPhoto else { return true }
        savedPhoto = photo
        photoChange = .unchanged
        return true
    }

    private func reloadIdentity(_ gateway: Gateway) async {
        guard let roster = try? await gateway.call("profiles.list", [String: String](), as: ProfileRoster.self),
              let bot = roster.profiles.first(where: { $0.name == name })
        else { return }
        meta = bot.meta
        revision = bot.metaRevision
        fields.identity = Identity(bot: bot)
        baseline.identity = fields.identity
        photo = bot.hasAvatar ? await fetchPhoto(gateway) : nil
        savedPhoto = photo
        photoChange = .unchanged
    }

    private func fetchPhoto(_ gateway: Gateway) async -> CGImage? {
        guard let reply = try? await gateway.call("profiles.get_asset", ["name": name, "asset": "avatar"], as: AssetReply.self),
              let url = reply.data, let comma = url.firstIndex(of: ","),
              let data = Data(base64Encoded: String(url[url.index(after: comma)...])),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

@concurrent
nonisolated private func avatarJPEG(from data: Data) async -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    for side in [1024, 768, 512] {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ] as CFDictionary
        let output = NSMutableData()
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        if output.length < 2_000_000 { return output as Data }
    }
    return nil
}
