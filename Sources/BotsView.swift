import SwiftUI

#if os(macOS)
private let tileAvatarSize: CGFloat = 56
private let rowAvatarSize: CGFloat = 40
private let rowPadding: CGFloat = 14
private let dotGutter: CGFloat = 10
#else
private let tileAvatarSize: CGFloat = 80
private let rowAvatarSize: CGFloat = 52
private let rowPadding: CGFloat = 8
private let dotGutter: CGFloat = 12
#endif

struct BotsView: View {
    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var store
    @Environment(PushCenter.self) private var push
    #if os(macOS)
    @Environment(AppUpdater.self) private var updater
    #else
    @Environment(UpdateCheck.self) private var updates
    #endif
    @State private var selection = Snapshot.requested?.selectedBot
    @State private var showsNotifications = false
    @State private var query = ""
    @State private var isCreating = Snapshot.requested == .newBot
    @State private var deleting: Bot?
    @State private var filing: Bot?
    @State private var sectionName = ""
    @State private var failure: String?
    @State private var showsConnectionPill = false
    @State private var showsBot = Snapshot.requested == .layoutInspector
    @State private var models = ModelSwitcher()

    var body: some View {
        let selected = store.bots.first { $0.id == selection }
        NavigationSplitView {
            List(selection: $selection) {
                if query.isEmpty {
                    if !store.favourites.isEmpty {
                        favourites
                    }
                    ForEach(store.sections) { section in
                        Section {
                            ForEach(section.bots) { bot in
                                row(for: bot)
                            }
                        } header: {
                            if let name = section.name { Text(name) }
                        }
                        .listSectionSeparator(.hidden, edges: .top)
                    }
                } else {
                    ForEach((store.favourites + store.sections.flatMap(\.bots)).filter {
                        $0.title.localizedStandardContains(query) || $0.name.localizedStandardContains(query)
                            || $0.canonicalSession?.preview?.localizedStandardContains(query) == true
                    }) { bot in
                        row(for: bot)
                    }
                }
            }
            .overlay {
                if store.isLoaded && store.bots.isEmpty {
                    ContentUnavailableView("No Bots", systemImage: "person.2", description: Text("This server has no profiles yet."))
                } else if !store.isLoaded && connection.state == .connecting {
                    ProgressView()
                }
            }
            #if os(iOS)
            .listStyle(.plain)
            #endif
            .searchable(text: $query, placement: .sidebar, prompt: "Search")
            .safeAreaBar(edge: .bottom) {
                VStack(spacing: 8) {
                    #if os(iOS)
                    if let version = updates.available, let url = updates.installURL {
                        Link(destination: url) {
                            Label("Install Crew \(version)", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.glassProminent)
                    }
                    #endif
                    if showsConnectionPill {
                        ConnectionPill()
                    }
                }
            }
            .task(id: connection.state == .connected) {
                showsConnectionPill = false
                guard connection.state != .connected else { return }
                try? await Task.sleep(for: .seconds(2))
                showsConnectionPill = !Task.isCancelled
            }
            .navigationTitle("Bots")
            .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 400)
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) { newBotButton }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Menu("Account", systemImage: "person.crop.circle") {
                        Section(connection.session?.server.host() ?? "") {
                            Button("Notifications…", systemImage: "bell.badge") { showsNotifications = true }
                            #if os(macOS)
                            UpdateMenuItems(updater: updater)
                            #else
                            Button(updates.isChecking ? "Checking for Updates…" : "Check for Updates", systemImage: "arrow.down.circle") {
                                Task { await updates.checkNow() }
                            }
                            .disabled(updates.isChecking)
                            #endif
                            Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                Task {
                                    await push.unregister(on: connection)
                                    await connection.signOut()
                                }
                            }
                        }
                    }
                }
            }
        } detail: {
            NavigationStack {
                Group {
                    if let selected {
                        ChatScreen(bot: selected, models: models, showsBot: $showsBot)
                    } else {
                        ContentUnavailableView("No Bot Selected", systemImage: "bubble.left.and.bubble.right", description: Text("Choose a bot to start chatting."))
                    }
                }
                #if os(macOS)
                .toolbar {
                    ToolbarItem(placement: .navigation) { newBotButton }
                }
                #endif
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 640)
        }
        #if os(macOS)
        .inspector(isPresented: Binding(get: { showsBot && selected != nil }, set: { showsBot = $0 })) {
            if let selected {
                BotInspector(bot: selected, models: models, isPresented: $showsBot)
                    .id(selected.id)
                    .inspectorColumnWidth(min: inspectorWidth.min, ideal: inspectorWidth.ideal, max: inspectorWidth.max)
            }
        }
        #endif
        .sheet(isPresented: $isCreating) {
            NewBotSheet { selection = $0 }
        }
        .modifier(BotDeletion(bot: $deleting) { id in
            if selection == id { selection = nil }
        })
        .alert("New Section", isPresented: Binding(get: { filing != nil }, set: { if !$0 { filing = nil } })) {
            TextField("Name", text: $sectionName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = sectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let bot = filing, !name.isEmpty else { return }
                let id = "sec-\(String(Int(Date.now.timeIntervalSince1970 * 1000), radix: 36))-\(String(Int.random(in: 0..<36 * 36 * 36 * 36 * 36), radix: 36))"
                perform { try await store.move(bot, to: SectionTag(id: id, name: name), via: $0) }
            }
        } message: {
            Text("Move \(filing?.title ?? "") to a new section.")
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        #if os(iOS)
        .alert("Software Update", isPresented: Binding(get: { updates.note != nil }, set: { if !$0 { updates.note = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(updates.note ?? "")
        }
        #endif
        .onChange(of: store.bots.map(\.id)) { _, ids in
            if store.isLoaded, let selection, !ids.contains(selection) { self.selection = nil }
        }
        .onChange(of: selected) { _, bot in
            if let bot { store.markSeen(bot) }
        }
        .onChange(of: selection, initial: true) {
            push.show(selection)
        }
        .onChange(of: push.pendingRoute, initial: true) {
            guard let route = push.pendingRoute else { return }
            push.pendingRoute = nil
            selection = route.profile
        }
        .sheet(isPresented: $showsNotifications) {
            NotificationSettings()
        }
        .task(id: connection.gateway.map(ObjectIdentifier.init)) {
            guard let gateway = connection.gateway else { return }
            await store.run(gateway)
        }
        .task(id: [selected?.id, connection.gateway.map { "\(ObjectIdentifier($0))" }]) {
            let switcher = ModelSwitcher()
            models = switcher
            guard let selected, let gateway = connection.gateway else { return }
            await switcher.load(profile: selected.name, via: gateway)
        }
    }

    private var newBotButton: some View {
        Button("New Bot", systemImage: "square.and.pencil") { isCreating = true }
            .disabled(connection.state != .connected)
    }

    private var favourites: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 12) {
            ForEach(store.favourites) { bot in
                Button {
                    selection = bot.id
                } label: {
                    FavouriteTile(bot: bot, photo: store.photos[bot.id], isSelected: selection == bot.id)
                }
                .buttonStyle(.plain)
                .contextMenu { menu(for: bot) }
            }
        }
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        .selectionDisabled()
    }

    private func row(for bot: Bot) -> some View {
        BotRow(bot: bot, photo: store.photos[bot.id])
            .tag(bot.id)
            .listRowInsets(EdgeInsets(top: rowPadding, leading: 0, bottom: rowPadding, trailing: 12))
            .contextMenu { menu(for: bot) }
            .swipeActions(edge: .leading) {
                pinButton(for: bot)
                    .labelStyle(.iconOnly)
                    .tint(.orange)
            }
    }

    private func pinButton(for bot: Bot) -> some View {
        Button(bot.meta.pinned == true ? "Unpin" : "Pin", systemImage: bot.meta.pinned == true ? "pin.slash.fill" : "pin.fill") {
            perform { try await store.togglePin(bot, via: $0) }
        }
        .disabled(connection.state != .connected)
    }

    @ViewBuilder
    private func menu(for bot: Bot) -> some View {
        pinButton(for: bot)
        Group {
            Button("Duplicate", systemImage: "plus.square.on.square") {
                perform { selection = try await store.duplicate(bot, via: $0) }
            }
            Menu("Move to Section", systemImage: "folder") {
                ForEach(store.sectionTags, id: \.self) { section in
                    Button(section.name) {
                        perform { try await store.move(bot, to: section, via: $0) }
                    }
                    .disabled(section.id == bot.meta.sectionID)
                }
                Button("New Section…", systemImage: "folder.badge.plus") {
                    sectionName = ""
                    filing = bot
                }
                if bot.meta.sectionID != nil {
                    Divider()
                    Button("Remove from Section", systemImage: "folder.badge.minus") {
                        perform { try await store.move(bot, to: nil, via: $0) }
                    }
                }
            }
            if !bot.isDefault {
                Divider()
                Button("Delete…", systemImage: "trash", role: .destructive) { deleting = bot }
            }
        }
        .disabled(connection.state != .connected)
    }

    private func perform(_ action: @escaping (Gateway) async throws -> Void) {
        guard let gateway = connection.gateway else { return }
        Task {
            do {
                try await action(gateway)
            } catch {
                failure = if case GatewayError.rpc(_, let message) = error { message } else { error.localizedDescription }
            }
        }
    }
}

private struct BotRow: View {
    let bot: Bot
    let photo: Image?
    @Environment(\.displayScale) private var displayScale
    @Environment(BotStore.self) private var store
    @Environment(ChatSessions.self) private var chats

    private var status: BotStatus {
        chats.status(of: bot.id, in: store)
    }

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(.tint)
                .frame(width: 8, height: 8)
                .opacity(status == .unread ? 1 : 0)
                .frame(width: dotGutter)
                .accessibilityLabel("Unread")
                .accessibilityHidden(status != .unread)
            BotAvatar(bot: bot, status: status, photo: photo, size: rowAvatarSize)
                .padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(bot.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    trailingLabel
                        .font(.subheadline)
                        .lineLimit(1)
                }
                Text(bot.canonicalSession?.preview.flatMap { $0.isEmpty ? nil : $0 } ?? bot.description ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            #if os(macOS)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.separator)
                    .frame(height: 1 / displayScale)
                    .padding(.trailing, -12)
                    .offset(y: rowPadding)
            }
            #endif
        }
    }

    @ViewBuilder
    private var trailingLabel: some View {
        if case .waiting(let kind) = status {
            Text(kind == .approval ? "Needs approval" : "Waiting for you")
                .foregroundStyle(.orange)
        } else if status == .working {
            Label("Working", systemImage: "ellipsis")
                .symbolEffect(.variableColor.iterative)
                .foregroundStyle(.green)
        } else if status == .failed {
            Text("Failed")
                .foregroundStyle(.red)
        } else if let timeLabel {
            Text(timeLabel)
                .foregroundStyle(.secondary)
        }
    }

    private var timeLabel: String? {
        guard let date = bot.canonicalSession?.lastActive else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? .max
        if days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) { return date.formatted(.dateTime.day().month(.abbreviated)) }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

private struct FavouriteTile: View {
    let bot: Bot
    let photo: Image?
    let isSelected: Bool
    @Environment(BotStore.self) private var store
    @Environment(ChatSessions.self) private var chats

    private var status: BotStatus {
        chats.status(of: bot.id, in: store)
    }

    var body: some View {
        VStack(spacing: 4) {
            BotAvatar(bot: bot, status: status, photo: photo, size: tileAvatarSize)
                .overlay(alignment: .topLeading) {
                    if status == .unread {
                        Circle()
                            .fill(.tint)
                            .frame(width: 12, height: 12)
                            .padding(2)
                            .background(.background, in: .circle)
                    }
                }
            Text(bot.title)
                .font(.caption)
                .fontWeight(status == .unread ? .semibold : .regular)
                .lineLimit(1)
            Group {
                if case .waiting = status {
                    Text("Waiting").foregroundStyle(.orange)
                } else if status == .working {
                    Text("Working").foregroundStyle(.green)
                } else {
                    Text(" ")
                }
            }
            .font(.caption2.weight(.medium))
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.fill.quaternary.opacity(isSelected ? 1 : 0), in: .rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
    }
}
