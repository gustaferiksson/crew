import SwiftUI

#if os(macOS)
private let tileAvatarSize: CGFloat = 56
#else
private let tileAvatarSize: CGFloat = 80
#endif

struct BotsView: View {
    @Environment(Connection.self) private var connection
    @Environment(BotStore.self) private var store
    @Environment(GroupStore.self) private var groups
    @Environment(ChatSessions.self) private var chats
    @Environment(PushCenter.self) private var push
    @Environment(ChatDrafts.self) private var drafts
    @Environment(Scenes.self) private var scenes
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appearsActive) private var appearsActive
    #else
    @Environment(UpdateCheck.self) private var updates
    @State private var showsNotifications = false
    #endif
    @State private var selection = Snapshot.requested?.selectedBot
    @State private var query = Snapshot.requested?.searchQuery ?? ""
    @State private var search = MessageSearch(fixture: Snapshot.requested?.searchHits)
    @State private var searchAttempt = 0
    @State private var focus = Snapshot.requested?.searchFocus
    @State private var reading: MessageHit?
    @State private var isCreating = Snapshot.requested == .newBot
    @State private var isCreatingGroup = false
    @State private var deleting: Bot?
    @State private var filing: Bot?
    @State private var sectionName = ""
    @State private var failure: String?
    @State private var showsConnectionPill = false
    @State private var showsBot = Snapshot.requested == .layoutInspector
    @State private var models = ModelSwitcher()
    @State private var modelsBot: Bot.ID?
    @State private var isStrip = false

    var body: some View {
        let selected = store.bots.first { $0.id == selection }
        let selectedRoom = groups.rooms.first { $0.selectionID == selection }
        #if os(macOS)
        let inspector: Binding<Bool>? = selected == nil && selectedRoom == nil ? nil : $showsBot
        #endif
        NavigationSplitView {
            sidebar
                .toolbar(removing: .sidebarToggle)
        } detail: {
            NavigationStack {
                Group {
                    if let selected {
                        ChatScreen(bot: selected, models: models, showsBot: $showsBot, focus: focus) { selection = $0 }
                    } else if let selectedRoom {
                        GroupChatScreen(room: selectedRoom, showsInspector: $showsBot) { selection = $0 }
                    } else {
                        ContentUnavailableView("No Bot Selected", systemImage: "bubble.left.and.bubble.right", description: Text("Choose a bot to start chatting."))
                    }
                }
                #if os(macOS)
                .toolbar {
                    ToolbarItem(placement: .navigation) { newChatButton }
                }
                #endif
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 640)
        }
        #if os(macOS)
        .inspector(isPresented: Binding(get: { showsBot && (selected != nil || selectedRoom != nil) }, set: { showsBot = $0 })) {
            Group {
                if let selected {
                    BotInspector(bot: selected, models: models, isPresented: $showsBot)
                        .id(selected.id)
                } else if let selectedRoom {
                    GroupInspector(room: selectedRoom, isPresented: $showsBot) { selection = $0 }
                        .id(selectedRoom.id)
                }
            }
            .inspectorColumnWidth(min: inspectorWidth.min, ideal: inspectorWidth.ideal, max: inspectorWidth.max)
        }
        .onReceive(NotificationCenter.default.publisher(for: .measureInspector)) { showsBot = $0.object as? Bool ?? false }
        #endif
        .sheet(isPresented: $isCreating) {
            NewBotSheet { selection = $0 }
        }
        .sheet(isPresented: $isCreatingGroup) {
            NewGroupSheet { selection = $0.selectionID }
        }
        .modifier(BotDeletion(bot: $deleting) { id in
            drafts.clear(id)
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
            if store.isLoaded, let selection, !ids.contains(selection), selectedRoom == nil { self.selection = nil }
        }
        .onChange(of: groups.rooms.map(\.selectionID)) { _, ids in
            if let selection, selection.hasPrefix("group:"), !ids.contains(selection) { self.selection = nil }
        }
        .onChange(of: selected) { _, bot in
            if let bot { store.markSeen(bot) }
        }
        .onChange(of: selection, initial: true) {
            push.show(selection)
            if focus?.bot != selection { focus = nil }
        }
        #if os(macOS)
        .onChange(of: appearsActive) {
            if appearsActive { push.show(selection) }
        }
        .focusedSceneValue(\.selectedBot, selected?.id)
        .focusedSceneValue(\.inspector, inspector)
        .onChange(of: scenes.newChat, initial: true, presentNewChat)
        #endif
        .sheet(item: $reading) { hit in
            if let bot = store.bots.first(where: { $0.id == hit.bot }) {
                ConversationTranscript(
                    bot: bot,
                    conversation: Conversation(id: hit.session, title: hit.title, source: nil, startedAt: hit.conversationDate.timeIntervalSince1970, lastActive: nil),
                    focus: hit.snippet
                )
            }
        }
        .onChange(of: push.pendingRoute, initial: true) { _, route in
            guard let route, !scenes.chatWindows.contains(route.profile) else { return }
            push.pendingRoute = nil
            #if os(macOS)
            openWindow(id: "main")
            #endif
            selection = route.profile
            if route.kind == "payment", let requestID = route.requestID { chats.expectPayment(requestID, for: route.profile) }
        }
        #if os(iOS)
        .sheet(isPresented: $showsNotifications) {
            NotificationSettings()
        }
        #endif
        .task(id: [selected?.id, selected?.model, connection.gateway.map { "\(ObjectIdentifier($0))" }]) {
            if modelsBot != selected?.id {
                models = ModelSwitcher()
                modelsBot = selected?.id
            }
            guard let selected, let gateway = connection.gateway else { return }
            await models.load(profile: selected.name, via: gateway)
        }
    }

    private var sidebar: some View {
        Group {
            if isStrip {
                sidebarList
                    .frame(width: stripWidth)
                    .scrollIndicators(.never)
            } else {
                sidebarList
                    .searchable(text: $query, placement: .sidebar, prompt: "Search")
            }
        }
        .frame(maxWidth: .infinity)
        #if os(macOS)
        .onGeometryChange(for: Bool.self) { $0.size.width < stripThreshold } action: { isStrip = $0 }
        #endif
        .task(id: [query, "\(connection.state == .connected)", "\(searchAttempt)", "\(store.bots.count)", "\(isStrip)"]) {
            guard !isStrip else { return }
            await search.run(query, in: store.bots, on: connection.state == .connected ? connection.session?.server : nil, with: connection.urlSession)
        }
        .task(id: connection.state == .connected) {
            showsConnectionPill = false
            guard connection.state != .connected else { return }
            try? await Task.sleep(for: .seconds(2))
            showsConnectionPill = !Task.isCancelled
        }
        .navigationTitle("Crew")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: stripWidth, ideal: 320, max: 400)
        #else
        .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 400)
        #endif
    }

    private var sidebarList: some View {
        List(selection: $selection) {
            if isStrip {
                ForEach(store.favourites) { stripTile(for: $0) }
                ForEach(store.sections) { section in
                    ForEach(rows(in: section)) { row in
                        if case .bot(let bot) = row {
                            stripTile(for: bot)
                        } else if case .group(let room) = row {
                            stripTile(for: room)
                        }
                    }
                }
                if !store.sections.contains(where: { $0.id.isEmpty }) {
                    ForEach(groups.rooms) { stripTile(for: $0) }
                }
            } else if query.isEmpty {
                if !store.favourites.isEmpty {
                    favourites
                }
                ForEach(store.sections) { section in
                    Section {
                        ForEach(rows(in: section)) { row in
                            if case .bot(let bot) = row {
                                self.row(for: bot)
                            } else if case .group(let room) = row {
                                groupRow(for: room)
                            }
                        }
                    } header: {
                        if let name = section.name { Text(name) }
                    }
                    .listSectionSeparator(.hidden, edges: .top)
                }
                if !store.sections.contains(where: { $0.id.isEmpty }) && !groups.rooms.isEmpty {
                    Section {
                        ForEach(groups.rooms) { groupRow(for: $0) }
                    } header: {
                        if !store.sections.isEmpty { Text("Other") }
                    }
                    .listSectionSeparator(.hidden, edges: .top)
                }
            } else if !MessageSearch.isSearchable(query) {
                ForEach((store.favourites + store.sections.flatMap(\.bots)).filter {
                    $0.title.localizedStandardContains(query) || $0.name.localizedStandardContains(query)
                        || $0.role?.localizedStandardContains(query) == true
                        || $0.canonicalSession?.preview?.localizedStandardContains(query) == true
                }) { bot in
                    row(for: bot)
                }
                ForEach(groups.rooms.filter { $0.name.localizedStandardContains(query) }) { groupRow(for: $0) }
            } else {
                if !matchingBots.isEmpty || !matchingRooms.isEmpty {
                    Section("Conversations") {
                        ForEach(matchingBots) { row(for: $0) }
                        ForEach(matchingRooms) { groupRow(for: $0) }
                    }
                    .listSectionSeparator(.hidden, edges: .top)
                }
                if !search.hits.isEmpty || search.phase != .done || search.failed > 0 {
                    Section("Messages") { messageResults }
                        .listSectionSeparator(.hidden, edges: .top)
                }
            }
        }
        .overlay {
            if store.isLoaded && store.bots.isEmpty {
                ContentUnavailableView("No Bots", systemImage: "person.2", description: Text("This server has no profiles yet."))
            } else if !store.isLoaded && connection.state == .connecting {
                ProgressView()
            } else if !isStrip && MessageSearch.isSearchable(query) && search.phase == .done && search.hits.isEmpty && search.failed == 0 && matchingBots.isEmpty && matchingRooms.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        #if os(iOS)
        .listStyle(.plain)
        #else
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let bot = ids.first.flatMap({ id in store.bots.first { $0.id == id } }) { menu(for: bot) }
        } primaryAction: { ids in
            if ids.count == 1, let id = ids.first, store.bots.contains(where: { $0.id == id }) { openWindow(value: id) }
        }
        #endif
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
                if showsConnectionPill && isStrip {
                    ConnectionBadge()
                } else if showsConnectionPill {
                    ConnectionPill()
                }
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { newChatButton }
            ToolbarItem(placement: .primaryAction) {
                Menu("Account", systemImage: "person.crop.circle") {
                    Section(connection.session?.server.host() ?? "") {
                        Button("Notifications…", systemImage: "bell.badge") { showsNotifications = true }
                        Button(updates.isChecking ? "Checking for Updates…" : "Check for Updates", systemImage: "arrow.down.circle") {
                            Task { await updates.checkNow() }
                        }
                        .disabled(updates.isChecking)
                        Text("Crew \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                        Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            Task {
                                await push.unregister(on: connection)
                                await connection.signOut()
                                drafts.reset()
                            }
                        }
                    }
                }
            }
        }
        #endif
    }

    @ViewBuilder
    private var newChatButton: some View {
        if groups.isSupported {
            Menu("New Chat", systemImage: "square.and.pencil") {
                Button("New Bot", systemImage: "person.crop.circle.badge.plus") { isCreating = true }
                Button("New Group", systemImage: "person.2") { isCreatingGroup = true }
            }
            .disabled(connection.state != .connected)
        } else {
            Button("New Bot", systemImage: "square.and.pencil") { isCreating = true }
                .disabled(connection.state != .connected)
        }
    }

    #if os(macOS)
    private func presentNewChat() {
        guard let kind = scenes.takeNewChat(), !isCreating, !isCreatingGroup, reading == nil, deleting == nil, filing == nil, failure == nil else { return }
        if kind == .bot { isCreating = true } else { isCreatingGroup = true }
    }
    #endif

    private var matchingBots: [Bot] {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return (store.favourites + store.sections.flatMap(\.bots)).filter {
            $0.title.localizedStandardContains(name) || $0.name.localizedStandardContains(name) || $0.role?.localizedStandardContains(name) == true
        }
    }

    private var matchingRooms: [Room] {
        groups.rooms.filter { $0.name.localizedStandardContains(query.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    @ViewBuilder
    private var messageResults: some View {
        ForEach(search.hits) { hit in
            if let bot = store.bots.first(where: { $0.id == hit.bot }) {
                Button {
                    focus = hit.isInBotChat ? SearchFocus(bot: hit.bot, snippet: hit.snippet) : nil
                    selection = hit.bot
                    if !hit.isInBotChat { reading = hit }
                } label: {
                    MessageHitRow(hit: hit, bot: bot, photo: store.photos[bot.id], query: query)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: rowPadding, leading: 0, bottom: rowPadding, trailing: 12))
            }
        }
        Group {
            if search.phase == .searching && search.hits.isEmpty {
                Label {
                    Text("Searching…")
                } icon: {
                    ProgressView()
                        .controlSize(.small)
                }
            } else if search.phase == .offline {
                Text("Connect to search messages.")
            } else if search.phase == .done && search.failed > 0 && search.failed == search.searched {
                HStack(spacing: 8) {
                    Text("Couldn't search messages.")
                    Button("Try Again") { searchAttempt += 1 }
                        .buttonStyle(.borderless)
                }
            } else if search.phase == .done && search.failed > 0 {
                Text("Some bots couldn't be searched.")
                    .font(.footnote)
            }
        }
        .foregroundStyle(.secondary)
        .listRowSeparator(.hidden)
        .selectionDisabled()
    }

    private func rows(in section: BotSection) -> [ListRow] {
        var rows = section.bots.map(ListRow.bot)
        guard section.id.isEmpty else { return rows }
        for room in groups.rooms {
            let index = rows.firstIndex { row in
                guard case .bot(let bot) = row else { return false }
                return [BotStatus.idle, .failed].contains(store.statuses[bot.id] ?? .idle) && (bot.canonicalSession?.lastActive ?? .distantPast) < room.updatedAt
            }
            rows.insert(.group(room), at: index ?? rows.endIndex)
        }
        return rows
    }

    private func groupRow(for room: Room) -> some View {
        GroupRow(room: room, isOpen: selection == room.selectionID)
            .tag(room.selectionID)
            .listRowInsets(EdgeInsets(top: rowPadding, leading: 0, bottom: rowPadding, trailing: 12))
    }

    private func stripTile(for bot: Bot) -> some View {
        BotStripTile(bot: bot, photo: store.photos[bot.id], isOpen: selection == bot.id)
            .tag(bot.id)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
    }

    private func stripTile(for room: Room) -> some View {
        StripTile(name: room.name) {
            GroupAvatar(members: room.members.compactMap { member in store.bots.first { $0.name == member.profile } }, size: rowAvatarSize)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: room.name))
        .help(room.name)
        .accessibilityValue(selection != room.selectionID && drafts.preview(for: room.selectionID) != nil ? "Draft" : "")
        .tag(room.selectionID)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
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
                #if os(macOS)
                .simultaneousGesture(TapGesture(count: 2).onEnded { openWindow(value: bot.id) })
                #endif
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
        BotRow(bot: bot, photo: store.photos[bot.id], isOpen: selection == bot.id)
            .tag(bot.id)
            .listRowInsets(EdgeInsets(top: rowPadding, leading: 0, bottom: rowPadding, trailing: 12))
            #if os(iOS)
            .contextMenu { menu(for: bot) }
            #endif
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
        #if os(macOS)
        Button("Open in New Window", systemImage: "macwindow.badge.plus") { openWindow(value: bot.id) }
        Divider()
        #endif
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

private struct MessageHitRow: View {
    let hit: MessageHit
    let bot: Bot
    let photo: Image?
    let query: String
    @Environment(\.displayScale) private var displayScale
    @Environment(BotStore.self) private var store
    @Environment(ChatSessions.self) private var chats

    @State private var matchedDate: Date?

    private var date: Date? {
        hit.isInBotChat ? matchedDate : hit.conversationDate
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: dotGutter, height: 8)
            BotAvatar(bot: bot, status: chats.status(of: bot.id, in: store), photo: photo, size: rowAvatarSize)
                .padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(bot.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let date {
                        Text(date.rowLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if !hit.isInBotChat {
                    Text("in \(hit.title ?? String(localized: "Untitled"))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(hit.highlighted(query))
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
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .task(id: [hit.id, "\(chats.sessions[bot.id]?.transcript.turns.count ?? 0)"]) {
            guard hit.isInBotChat else { return }
            matchedDate = chats.sessions[bot.id]?.transcript.turn(matching: hit.snippet).map { $0.prompt?.sentAt ?? $0.finishedAt ?? $0.startedAt }
        }
    }
}

private enum ListRow: Identifiable {
    case bot(Bot)
    case group(Room)

    var id: String {
        switch self {
        case .bot(let bot): bot.id
        case .group(let room): room.selectionID
        }
    }
}

private struct GroupRow: View {
    let room: Room
    let isOpen: Bool
    @Environment(\.displayScale) private var displayScale
    @Environment(BotStore.self) private var store
    @Environment(ChatDrafts.self) private var drafts

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: dotGutter, height: 8)
            GroupAvatar(members: room.members.compactMap { member in store.bots.first { $0.name == member.profile } }, size: rowAvatarSize)
                .padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(room.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(room.updatedAt.rowLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Group {
                    if !isOpen, let draft = drafts.preview(for: room.selectionID) {
                        Text("\(Text("Draft:").foregroundStyle(.red)) \(draft)")
                    } else {
                        Text(room.members.map { $0.displayName ?? $0.memberID }.formatted(.list(type: .and)))
                    }
                }
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
                } else if let role = bot.role {
                    Text(role).fontWeight(.regular).foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
            .font(.caption2.weight(.medium))
            .lineLimit(1)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.fill.quaternary.opacity(isSelected ? 1 : 0), in: .rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [bot.title, bot.role].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityValue(statusValue)
    }

    private var statusValue: Text {
        if case .waiting = status { return Text("Waiting") }
        if status == .working { return Text("Working") }
        if status == .unread { return Text("Unread") }
        return Text(verbatim: "")
    }
}
