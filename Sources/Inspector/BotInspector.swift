import PhotosUI
import SwiftUI

let inspectorWidth = (min: 280.0, ideal: 340.0, max: 480.0)

enum InspectorTab: String, CaseIterable, Identifiable {
    case info, tasks, routines
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
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField {
        case name, description
    }

    init(bot: Bot, tab: InspectorTab = .info, routines: RoutineStore = RoutineStore(), draft: ProfileDraft? = nil, models: ModelSwitcher, isPresented: Binding<Bool>) {
        self.bot = bot
        self.models = models
        _isPresented = isPresented
        _tab = State(initialValue: tab)
        _routines = State(initialValue: routines)
        _draft = State(initialValue: draft ?? ProfileDraft(bot: bot))
    }

    private var isEditable: Bool {
        draft.phase == .loaded
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                tabs
                if tab == .info {
                    info
                } else if tab == .tasks {
                    TaskList(bot: bot, todos: chats.sessions[bot.id]?.todos ?? [])
                } else {
                    RoutineList(bot: bot, store: routines) { isCreatingRoutine = true }
                }
            }
            .padding(16)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .overlay(alignment: .topLeading) {
            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .frame(width: 36, height: 36)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Close")
            .padding(.leading, 12)
            .padding(.top, 7)
            .ignoresSafeArea(edges: .top)
        }
        #endif
        .sheet(isPresented: $isCreatingRoutine) {
            RoutineEditor(bot: bot, store: routines)
        }
        .sheet(item: $capabilitySheet) { kind in
            CapabilityList(kind: kind, items: $draft.fields[dynamicMember: kind.items])
        }
        .modifier(BotDeletion(bot: $deleting) { _ in isPresented = false })
        .onChange(of: draft.fields) { old, new in
            var typed = old
            typed.identity.title = new.identity.title
            typed.description = new.description
            typed.instructions = new.instructions
            typed.soul = new.soul
            scheduleSave(after: typed == new ? .milliseconds(600) : .zero)
        }
        .onChange(of: draft.photoChange) { scheduleSave(after: .zero) }
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
    }

    private var header: some View {
        VStack(spacing: 12) {
            Button {
                showsLook = true
            } label: {
                AvatarView(
                    shape: draft.fields.identity.shape,
                    color: draft.fields.identity.color,
                    expression: draft.fields.identity.expression,
                    photo: draft.photo.map { Image(decorative: $0, scale: 1) } ?? (isEditable ? nil : store.photos[bot.id]),
                    seed: draft.name,
                    size: 96
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!isEditable)
            .accessibilityLabel("Edit Look")
            .popover(isPresented: $showsLook) {
                LookEditor(draft: draft, photoItem: $photoItem)
            }
            VStack(spacing: 4) {
                TextField("Name", text: $draft.fields.identity.title, prompt: Text(draft.fallbackTitle))
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .focused($focusedField, equals: .name)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.fill.quaternary.opacity(focusedField == .name ? 1 : 0), in: .rect(cornerRadius: 8))
                    .disabled(!isEditable)
                    .onSubmit { focusedField = nil }
                saveStatus
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ActionCircle(title: "Routine", systemImage: "calendar.badge.plus") {
                tab = .routines
                isCreatingRoutine = true
            }
        }
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

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach([(InspectorTab.info, LocalizedStringKey("Info")), (.tasks, "Tasks"), (.routines, "Routines")], id: \.0) { item, title in
                Button {
                    withAnimation(.snappy) { tab = item }
                } label: {
                    Text(title)
                        .fontWeight(tab == item ? .semibold : .regular)
                        .foregroundStyle(tab == item ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(tab == item ? .regular : .identity, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        Card(title: "Description") {
            if isEditable {
                TextField("Description", text: $draft.fields.description, prompt: Text("What this bot is for"), axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .description)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        Card(title: "Instructions", footer: "Added on top of the soul in every chat. A personality chosen on the server replaces them.") {
            if isEditable {
                TextArea(text: $draft.fields.instructions, placeholder: "Extra instructions for every chat")
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        Card(title: "Soul", footer: "The bot's identity, saved as SOUL.md. Saving replaces the whole file.") {
            if isEditable {
                TextArea(text: $draft.fields.soul, placeholder: "Who this bot is")
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        Card(title: "Capabilities") {
            VStack(spacing: 8) {
                ForEach(CapabilityKind.allCases) { kind in
                    let items = draft.fields[keyPath: kind.items]
                    if kind != CapabilityKind.allCases.first {
                        Divider()
                    }
                    Button {
                        capabilitySheet = kind
                    } label: {
                        HStack(spacing: 8) {
                            Label {
                                Text(kind.title)
                            } icon: {
                                Image(systemName: kind.systemImage)
                                    .frame(width: 24)
                            }
                            Spacer(minLength: 8)
                            Text("\(items.filter(\.enabled).count)/\(items.count)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEditable)
                }
            }
        }
        if !bot.isDefault {
            Button(role: .destructive) {
                deleting = bot
            } label: {
                Text("Delete Bot")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(.fill.quaternary, in: .rect(cornerRadius: 16))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(connection.state != .connected)
            .padding(.top, 16)
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
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Model").foregroundStyle(.secondary)
                if providers.isEmpty {
                    Text(bot.model ?? String(localized: "Default"))
                } else {
                    HStack(spacing: 8) {
                        Menu {
                            ModelPicker(providers: providers, selection: $model)
                                .pickerStyle(.inline)
                        } label: {
                            HStack(spacing: 4) {
                                Text(model?.model ?? bot.model ?? String(localized: "Default"))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(.rect)
                        }
                        .menuIndicator(.hidden)
                        .buttonStyle(.plain)
                        .disabled(isChangingModel || connection.state != .connected)
                        if isChangingModel {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            }
            Divider()
            GridRow {
                Text("Profile").foregroundStyle(.secondary)
                Text(bot.name)
            }
            if let server {
                Divider()
                GridRow {
                    Text("Server").foregroundStyle(.secondary)
                    Text(server)
                }
            }
            if let session = bot.canonicalSession {
                Divider()
                GridRow {
                    Text("Messages").foregroundStyle(.secondary)
                    Text(session.messageCount ?? 0, format: .number)
                }
                if let lastActive = session.lastActive {
                    Divider()
                    GridRow {
                        Text("Last Active").foregroundStyle(.secondary)
                        Text(lastActive, format: .relative(presentation: .named))
                    }
                }
            }
        }
        .lineLimit(nil)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
    }
}

private struct Card<Content: View>: View {
    let title: LocalizedStringKey
    var footer: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.fill.quaternary, in: .rect(cornerRadius: 16))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
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
