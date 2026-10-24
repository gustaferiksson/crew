import PhotosUI
import SwiftUI

let inspectorWidth = (min: 280.0, ideal: 340.0, max: 480.0)

enum InspectorTab: String, CaseIterable, Identifiable {
    case info, tasks, routines, passwords
    var id: Self { self }
}

struct BotInspector: View {
    let bot: Bot
    let models: ModelSwitcher
    @Binding var isPresented: Bool

    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var store
    @Environment(ChatSessions.self) private var chats
    @State private var tab: InspectorTab
    @State private var routines: RoutineStore
    @State private var isCreatingRoutine = false
    @State private var draft: ProfileDraft
    @State private var showsLook = false
    @State private var photoItem: PhotosPickerItem?
    @State private var capabilitySheet: CapabilityKind?
    @State private var deleting: Bot?
    @State private var pendingSave: Task<Void, Never>?
    @State private var showsSaved = false
    @State private var conversations: [Conversation]?
    @State private var conversationFailure: String?
    @State private var openedConversation: Conversation?
    private let shopsFixture: ShopList?
    @State private var vault: BotVault
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField {
        case name, role, description
    }

    init(bot: Bot, tab: InspectorTab = .info, routines: RoutineStore = RoutineStore(), draft: ProfileDraft? = nil, conversations: [Conversation]? = nil, shops: ShopList? = nil, vault: BotVault? = nil, models: ModelSwitcher, isPresented: Binding<Bool>) {
        self.bot = bot
        self.shopsFixture = shops
        self.models = models
        _isPresented = isPresented
        _tab = State(initialValue: tab)
        _routines = State(initialValue: routines)
        _draft = State(initialValue: draft ?? ProfileDraft(bot: bot))
        _conversations = State(initialValue: conversations)
        _vault = State(initialValue: vault ?? BotVault(profile: bot.name))
    }

    private var isEditable: Bool {
        draft.phase == .loaded
    }

    var body: some View {
        Form {
            Section {
                #if os(iOS)
                tabPicker
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                #endif
            } header: {
                header
            }
            if tab == .info {
                info
            } else if tab == .tasks {
                TaskList(bot: bot, todos: chats.sessions[bot.id]?.todos ?? [])
            } else if tab == .passwords {
                PasswordsTab(bot: bot, vault: vault, isBrowserOff: isBrowserOff, shops: shopsFixture)
            } else {
                RoutineList(bot: bot, store: routines) { isCreatingRoutine = true }
            }
        }
        .formStyle(.grouped)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .frame(minWidth: 0, maxWidth: .infinity)
        .contentMargins(.bottom, 24, for: .scrollIndicators)
        .toolbar {
            if isPresented {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { isPresented = false }
                }
            }
        }
        #endif
        .sheet(isPresented: $isCreatingRoutine) {
            RoutineEditor(bot: bot, store: routines)
        }
        .sheet(item: $capabilitySheet) { kind in
            CapabilityList(kind: kind, items: $draft.fields[dynamicMember: kind.items])
        }
        .sheet(item: $openedConversation) { conversation in
            ConversationTranscript(bot: bot, conversation: conversation)
        }
        .modifier(BotDeletion(bot: $deleting) { _ in isPresented = false })
        .task(id: "\(tab == .passwords) \(connection.gateway.map { "\(ObjectIdentifier($0))" } ?? "") \(connection.state == .connected)") {
            guard tab == .passwords, let link = connection.vaultLink else { return }
            await vault.load(link)
        }
        .onChange(of: draft.fields) { old, new in
            var typed = old
            typed.identity.title = new.identity.title
            typed.identity.role = new.identity.role
            typed.description = new.description
            typed.instructions = new.instructions
            typed.soul = new.soul
            scheduleSave(after: typed == new ? .milliseconds(600) : .zero)
        }
        .onChange(of: draft.photoChange) { scheduleSave(after: .zero) }
        .onChange(of: bot.metaRevision) { draft.adopt(bot) }
        .onDisappear {
            guard draft.isDirty else { return }
            pendingSave?.cancel()
            save()
        }
        .task(id: draft.savedAt) {
            guard draft.savedAt != nil else { return }
            showsSaved = true
            try? await Task.sleep(for: .seconds(2))
            showsSaved = false
        }
        .task(id: photoItem) {
            guard let item = photoItem else { return }
            photoItem = nil
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                draft.notice = String(localized: "Crew couldn't read that image. Try a JPEG, PNG or HEIC photo.")
                return
            }
            await draft.pickPhoto(data)
        }
        .task(id: [bot.id, connection.gateway.map { "\(ObjectIdentifier($0))" } ?? ""]) {
            guard let gateway = connection.gateway else { return }
            await routines.run(profile: bot.name, gateway: gateway, urlSession: connection.urlSession)
        }
        .task(id: connection.gateway.map(ObjectIdentifier.init)) {
            guard let gateway = connection.gateway else { return }
            await draft.load(gateway, urlSession: connection.urlSession)
            if draft.isDirty { save() }
        }
        .task(id: connection.gateway.map(ObjectIdentifier.init)) {
            guard connection.gateway != nil, let server = connection.session?.server else { return }
            do {
                conversations = try await otherConversations(of: bot, on: server, with: connection.urlSession)
            } catch {
                conversationFailure = error.localizedDescription
            }
        }
    }

    private var tabPicker: some View {
        Picker("View", selection: $tab.animation(.snappy)) {
            ForEach([(InspectorTab.info, LocalizedStringKey("Info"), "info.circle"), (.tasks, "Tasks", "checklist"), (.routines, "Routines", "calendar.badge.clock"), (.passwords, "Passwords", "key")], id: \.0) { item, title, systemImage in
                #if os(macOS)
                Label(title, systemImage: systemImage)
                    .labelStyle(.iconOnly)
                    .help(Text(title))
                    .tag(item)
                #else
                Text(title).tag(item)
                #endif
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var header: some View {
        VStack(spacing: 12) {
            avatar
            VStack(spacing: 4) {
                if isEditable {
                    nameFields
                } else {
                    Text(draft.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    if !draft.fields.identity.role.isEmpty {
                        Text(draft.fields.identity.role)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                }
                saveStatus
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ActionCircle(title: "Routine", systemImage: "calendar.badge.plus") {
                tab = .routines
                isCreatingRoutine = true
            }
            #if os(macOS)
            tabPicker
                .padding(.top, 4)
            #endif
        }
        .font(.body)
        .foregroundStyle(.primary)
        .textCase(nil)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var avatar: some View {
        let image = AvatarView(
            shape: draft.fields.identity.shape,
            color: draft.fields.identity.color,
            expression: draft.fields.identity.expression,
            photo: draft.photo.map { Image(decorative: $0, scale: 1) } ?? (isEditable ? nil : store.photos[bot.id]),
            seed: draft.name,
            size: 96
        )
        if isEditable {
            Button {
                showsLook = true
            } label: {
                image.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit Look")
            .popover(isPresented: $showsLook) {
                LookEditor(draft: draft, photoItem: $photoItem)
            }
        } else {
            image.accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var nameFields: some View {
        TextField("Name", text: $draft.fields.identity.title, prompt: Text(draft.fallbackTitle))
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(.title2.bold())
            .multilineTextAlignment(.center)
            .focused($focusedField, equals: .name)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.fill.quaternary.opacity(focusedField == .name ? 1 : 0), in: .rect(cornerRadius: 8))
            .submitLabel(.next)
            .onSubmit { focusedField = .role }
        TextField("Role", text: $draft.fields.identity.role, prompt: Text("Add Role"))
            .labelsHidden()
            .textFieldStyle(.plain)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .focused($focusedField, equals: .role)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.fill.quaternary.opacity(focusedField == .role ? 1 : 0), in: .rect(cornerRadius: 8))
            .onSubmit { focusedField = nil }
    }

    @ViewBuilder
    private var saveStatus: some View {
        if draft.isSaving {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Saving…")
            }
        } else if let notice = draft.notice {
            VStack(spacing: 4) {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    draft.notice = nil
                    save()
                }
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
                .disabled(connection.state != .connected)
            }
        } else if showsSaved {
            Label("Saved", systemImage: "checkmark")
        } else {
            Text(bot.name)
        }
    }

    private var isBrowserOff: Bool {
        isEditable && !draft.fields.toolsets.contains { $0.name == "browser" && $0.enabled }
    }

    @ViewBuilder
    private var info: some View {
        BotInfo(
            bot: bot,
            server: connection.session?.server.host(),
            providers: models.providers,
            model: Binding(get: { models.changing ?? models.current }, set: { if let choice = $0 { changeModel(to: choice) } }),
            isChangingModel: models.changing != nil
        )
        Section("Description") {
            if isEditable {
                TextField("Description", text: $draft.fields.description, prompt: Text("What this bot is for"), axis: .vertical)
                    .labelsHidden()
                    .focused($focusedField, equals: .description)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        Section {
            if isEditable {
                TextArea(text: $draft.fields.instructions, placeholder: "Extra instructions for every chat")
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        } header: {
            Text("Instructions")
        } footer: {
            Text("Added on top of the soul in every chat. A personality chosen on the server replaces them.")
        }
        Section {
            Toggle("Cards and Forms", isOn: $draft.fields.richUI)
                .toggleStyle(.switch)
                .disabled(!isEditable)
        } header: {
            Text("Rich UI")
        } footer: {
            Text("Lets this bot answer with cards, checklists and forms that Crew draws natively. Other apps show them as code.")
        }
        Section {
            if isEditable {
                TextArea(text: $draft.fields.soul, placeholder: "Who this bot is")
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        } header: {
            Text("Soul")
        } footer: {
            Text("The bot's identity, saved as SOUL.md. Saving replaces the whole file.")
        }
        Section("Capabilities") {
            ForEach(CapabilityKind.allCases) { kind in
                let items = draft.fields[keyPath: kind.items]
                Button {
                    capabilitySheet = kind
                } label: {
                    LabeledContent {
                        Text("\(items.filter(\.enabled).count)/\(items.count)")
                            .monospacedDigit()
                    } label: {
                        Label {
                            Text(kind.title)
                        } icon: {
                            Image(systemName: kind.systemImage)
                                .frame(width: 24)
                        }
                    }
                    .contentShape(.rect)
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #else
                .tint(.primary)
                #endif
                .disabled(!isEditable)
            }
        }
        Section {
            ConversationList(conversations: conversations, failure: conversationFailure) { openedConversation = $0 }
        } header: {
            Text("Other Conversations")
        } footer: {
            Text("Sessions from other apps, the server and routines. Read only.")
        }
        if !bot.isDefault {
            Section {
                Button("Delete Bot", role: .destructive) { deleting = bot }
                    #if os(macOS)
                    .foregroundStyle(.red)
                    #endif
                    .disabled(connection.state != .connected)
            }
        }
    }

    private func scheduleSave(after delay: Duration) {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        guard draft.isDirty, let gateway = connection.gateway else { return }
        Task {
            await draft.save(gateway, urlSession: connection.urlSession)
            guard draft.notice == nil else { return }
            await store.reload(gateway)
        }
    }

    private func changeModel(to choice: ModelChoice) {
        guard let gateway = connection.gateway else { return }
        Task {
            await models.change(to: choice, profile: bot.name, via: gateway)
            await store.reload(gateway)
        }
    }
}

struct LookEditor: View {
    @Bindable var draft: ProfileDraft
    @Binding var photoItem: PhotosPickerItem?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose Photo…", systemImage: "photo.on.rectangle")
                    }
                    if draft.photo != nil {
                        Button("Remove Photo", systemImage: "trash", role: .destructive) { draft.removePhoto() }
                    }
                }
                AvatarPicker(
                    shape: Binding(get: { draft.fields.identity.shape }, set: { draft.pickShape($0) }),
                    color: Binding(get: { draft.fields.identity.color }, set: { draft.pickColor($0) }),
                    expression: $draft.fields.identity.expression,
                    reset: draft.resetLook
                )
            }
            .formStyle(.grouped)
            .navigationTitle("Look")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: 340, height: 560)
        #endif
    }
}

private struct ActionCircle: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text(title))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(width: 64)
    }
}

private struct BotInfo: View {
    let bot: Bot
    let server: String?
    let providers: [ModelProvider]
    @Binding var model: ModelChoice?
    let isChangingModel: Bool

    @Environment(Connection.self) private var connection

    var body: some View {
        Section {
            LabeledContent("Model") {
                if providers.isEmpty {
                    Text(bot.model ?? String(localized: "Default"))
                } else {
                    HStack(spacing: 8) {
                        if isChangingModel {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Menu {
                            ModelPicker(providers: providers, selection: $model)
                                .pickerStyle(.inline)
                        } label: {
                            HStack(spacing: 4) {
                                Text(model?.model ?? bot.model ?? String(localized: "Default"))
                                    .multilineTextAlignment(.trailing)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.secondary)
                            .contentShape(.rect)
                        }
                        .menuIndicator(.hidden)
                        .buttonStyle(.plain)
                        .disabled(isChangingModel || connection.state != .connected)
                    }
                }
            }
            LabeledContent("Profile", value: bot.name)
            if let server {
                LabeledContent("Server", value: server)
            }
            if let session = bot.canonicalSession {
                LabeledContent("Messages") {
                    Text(session.messageCount ?? 0, format: .number)
                }
                if let lastActive = session.lastActive {
                    LabeledContent("Last Active") {
                        Text(lastActive, format: .relative(presentation: .named))
                    }
                }
            }
        }
    }
}

private struct TextArea: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, -5)
            #if os(iOS)
            .padding(.vertical, -8)
            #endif
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }
    }
}
