import SwiftUI

struct RoutineList: View {
    let bot: Bot
    let store: RoutineStore
    let onCreate: () -> Void
    let onEdit: (RoutineJob) -> Void
    @Environment(GroupStore.self) private var groups
    @State private var pendingDeletion: RoutineJob?

    var body: some View {
        Group {
            if !store.isLoaded, let error = store.loadError {
                Section {} header: {
                    ContentUnavailableView("Couldn't Load Routines", systemImage: "exclamationmark.triangle", description: Text(error))
                }
            } else if !store.isLoaded {
                Section {} header: {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                }
            } else if store.jobs.isEmpty {
                Section {} header: {
                    ContentUnavailableView {
                        Label("No Routines", systemImage: "calendar.badge.clock")
                    } description: {
                        Text("Schedule \(bot.title) to run a prompt on its own.")
                    }
                }
            } else {
                Section {
                    ForEach(store.jobs) { job in
                        RoutineRow(job: job, room: roomLabel(job.destination), isRunning: store.isRunning(job), isStopping: store.stopping.contains(job.id), isBusy: store.inFlight.contains(job.id)) {
                            Task { await store.stop(job) }
                        } actions: {
                            actions(job)
                        }
                            .contextMenu { actions(job) }
                            #if os(iOS)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", systemImage: "trash") { pendingDeletion = job }
                                    .tint(.red)
                            }
                            .swipeActions(edge: .leading) {
                                Button(job.isPaused ? "Resume" : "Pause", systemImage: job.isPaused ? "play.circle" : "pause.circle") {
                                    Task { await store.toggle(job) }
                                }
                            }
                            #endif
                    }
                    Button("New Routine", systemImage: "plus", action: onCreate)
                }
            }
        }
        .confirmationDialog("Delete \(pendingDeletion?.title ?? "")?", isPresented: Binding { pendingDeletion != nil } set: { if !$0 { pendingDeletion = nil } }, presenting: pendingDeletion) { job in
            Button("Delete Routine", role: .destructive) { Task { await store.delete(job) } }
        } message: { _ in
            Text("It stops running and is removed from the server.")
        }
        .alert(store.alert?.title ?? "", isPresented: Binding { store.alert != nil } set: { if !$0 { store.alert = nil } }, presenting: store.alert) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    @ViewBuilder
    private func actions(_ job: RoutineJob) -> some View {
        if store.isRunning(job), job.tracksRuns {
            Button("Stop", systemImage: "stop.circle") { Task { await store.stop(job) } }
        } else {
            Button("Run Now", systemImage: "play") { Task { await store.trigger(job) } }
                .disabled(store.isRunning(job))
        }
        Button(job.isPaused ? "Resume" : "Pause", systemImage: job.isPaused ? "play.circle" : "pause.circle") {
            Task { await store.toggle(job) }
        }
        Button("Edit…", systemImage: "pencil") { onEdit(job) }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) { pendingDeletion = job }
    }

    private func roomLabel(_ destination: RoutineDestination) -> String? {
        guard case .room(let id) = destination else { return nil }
        if let room = groups.rooms.first(where: { $0.id == id }) { return String(localized: "Posts to \(room.name)") }
        return groups.isLoaded ? String(localized: "Posts to a removed room") : String(localized: "Posts to a room")
    }
}

private struct RoutineRow<Actions: View>: View {
    let job: RoutineJob
    let room: String?
    let isRunning: Bool
    let isStopping: Bool
    let isBusy: Bool
    let onStop: () -> Void
    @ViewBuilder let actions: Actions

    #if os(iOS)
    private let actionSize = 44.0
    #else
    private let actionSize = 28.0
    #endif

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(job.title.isEmpty ? String(localized: "Untitled") : job.title)
                        .font(.headline)
                        .lineLimit(1)
                    if job.isPaused {
                        Text("Paused")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.fill.tertiary, in: .capsule)
                    }
                }
                Text(describeSchedule(job.schedule))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let room {
                    Label(room, systemImage: "bubble.left.and.bubble.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isStopping {
                    Label("Stopping…", systemImage: "stop.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isRunning {
                    Label {
                        Text("Running")
                    } icon: {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityHidden(true)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if !job.isPaused, let next = job.nextRun {
                    Label {
                        Text("Next run \(next, format: .relative(presentation: .named))")
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let lastRun = job.lastRun {
                    let result = job.result
                    Label {
                        Text("\(result.text) \(lastRun, format: .relative(presentation: .named))")
                    } icon: {
                        Image(systemName: result.symbol)
                    }
                    .font(.caption)
                    .foregroundStyle(result.tint)
                }
                if let issue = job.issue {
                    Text(issue)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: actionSize, height: actionSize)
            } else {
                HStack(spacing: 12) {
                    if isRunning, job.tracksRuns {
                        Button(action: onStop) {
                            Label("Stop", systemImage: "stop.circle")
                                .labelStyle(.iconOnly)
                                .frame(width: actionSize, height: actionSize)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.borderless)
                    }
                    Menu {
                        actions
                    } label: {
                        Label("Actions", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                            .frame(width: actionSize, height: actionSize)
                            .contentShape(.rect)
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.borderless)
                    .fixedSize()
                }
            }
        }
        .opacity(job.isPaused ? 0.7 : 1)
    }
}

extension RoutineJob {
    var result: (text: String, symbol: String, tint: Color) {
        if lastStatus == "ok" { return (String(localized: "Succeeded"), "checkmark.circle.fill", .green) }
        if lastStatus == "error" { return (String(localized: "Failed"), "xmark.octagon.fill", .red) }
        if lastStatus == "delivery_failed" { return (String(localized: "Delivery failed"), "exclamationmark.triangle.fill", .orange) }
        if lastStatus == "blocked_config" { return (String(localized: "Blocked by config"), "exclamationmark.triangle.fill", .orange) }
        if lastStatus == "cancelled" { return (String(localized: "Stopped"), "stop.circle", .secondary) }
        if lastStatus == "missed" {
            let runs = missedRuns ?? 1
            return (runs == 1 ? String(localized: "Missed 1 run") : String(localized: "Missed \(runs) runs"), "calendar.badge.exclamationmark", .orange)
        }
        return (lastStatus.map { String(localized: "Ran (\($0))") } ?? String(localized: "Ran"), "clock.arrow.circlepath", .secondary)
    }
}

struct RoutineEditor: View {
    let bot: Bot
    let store: RoutineStore
    let job: RoutineJob?
    @Environment(\.dismiss) private var dismiss
    @Environment(GroupStore.self) private var groups
    @State private var title: String
    @State private var prompt: String
    @State private var frequency: Frequency
    @State private var time: Date
    @State private var weekday: Int
    @State private var expression: String
    @State private var destination: RoutineDestination
    @State private var error: String?
    @State private var isSaving = false

    enum Frequency: String, CaseIterable, Identifiable {
        case hourly, daily, weekdays, weekly, custom
        var id: Self { self }
    }

    init(bot: Bot, store: RoutineStore, job: RoutineJob? = nil) {
        self.bot = bot
        self.store = store
        self.job = job
        let fields = job?.schedule.split(separator: " ").map(String.init) ?? []
        let preset: (frequency: Frequency, hour: Int, minute: Int, weekday: Int)? = if fields.count == 5, fields[2...3] == ["*", "*"],
            let minute = Int(fields[0]), (0..<60).contains(minute), let hour = Int(fields[1]), (0..<24).contains(hour) {
            if fields[4] == "*" { (.daily, hour, minute, 1) }
            else if fields[4] == "1-5" { (.weekdays, hour, minute, 1) }
            else if let day = Int(fields[4]), (0..<7).contains(day) { (.weekly, hour, minute, day) }
            else { nil }
        } else { nil }
        _title = State(initialValue: job?.title ?? "")
        _prompt = State(initialValue: job?.prompt ?? "")
        _frequency = State(initialValue: job == nil ? .daily : preset?.frequency ?? .custom)
        _time = State(initialValue: Calendar.current.date(from: DateComponents(hour: preset?.hour ?? 9, minute: preset?.minute ?? 0)) ?? .now)
        _weekday = State(initialValue: preset?.weekday ?? 1)
        _expression = State(initialValue: preset == nil ? job?.schedule ?? "" : "")
        _destination = State(initialValue: job?.destination ?? .history)
    }

    var body: some View {
        let clock = Calendar.current.dateComponents([.hour, .minute], from: time)
        let at = "\(clock.minute ?? 0) \(clock.hour ?? 9)"
        let schedule = [
            .hourly: "every 1h", .daily: "\(at) * * *", .weekdays: "\(at) * * 1-5", .weekly: "\(at) * * \(weekday)",
        ][frequency] ?? expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let isComplete = !title.trimmingCharacters(in: .whitespaces).isEmpty && (!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || job?.prompt.isEmpty == true) && !schedule.isEmpty
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $title, prompt: Text("Morning briefing"))
                    TextField("Prompt", text: $prompt, prompt: Text("What should \(bot.title) do?"), axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Picker("Repeat", selection: $frequency) {
                        ForEach(Frequency.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    if frequency == .weekly {
                        Picker("Day", selection: $weekday) {
                            ForEach(0..<7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0]).tag($0) }
                        }
                    }
                    if [.daily, .weekdays, .weekly].contains(frequency) {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }
                    if frequency == .custom {
                        TextField("Schedule", text: $expression, prompt: Text("0 9 * * 1-5 or every 2h"))
                            .autocorrectionDisabled()
                            .monospaced()
                    }
                } footer: {
                    Text(schedule.isEmpty ? "Use a cron expression, an interval like every 30m, or a phrase like every monday 9am." : "\(describeSchedule(schedule)), on the server's clock.")
                }
                if groups.isSupported || destination != .history {
                    destinationSection
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(job == nil ? "New Routine" : "Edit Routine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(job == nil ? "Create" : "Save", role: .confirm) {
                        Task {
                            isSaving = true
                            let title = title.trimmingCharacters(in: .whitespaces)
                            let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                            do {
                                if let job {
                                    try await store.update(job, title: title, prompt: prompt, schedule: schedule, destination: destination)
                                } else {
                                    try await store.create(title: title, prompt: prompt, schedule: schedule, destination: destination)
                                }
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                            isSaving = false
                        }
                    }
                    .disabled(!isComplete || isSaving)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 440)
        #endif
    }

    private var destinationSection: some View {
        let rooms = groups.rooms(with: bot)
        let saved = job?.destination ?? .history
        let isListed = saved == .history || rooms.contains { .room($0.id) == saved }
        return Section {
            Picker("Post To", selection: $destination) {
                Text("Don't Post").tag(RoutineDestination.history)
                Divider()
                ForEach(rooms) { room in
                    Text(room.name).tag(RoutineDestination.room(room.id))
                }
                if !isListed {
                    Text(name(of: saved)).tag(saved)
                }
            }
        } footer: {
            if case .room = destination {
                Text("Each run posts its result in \(name(of: destination)). Members answer only when the result @mentions them or @all.")
            } else if destination == .history, rooms.isEmpty {
                Text("Each run's result stays in its own conversation under Conversations. Create a room with \(bot.title) to post results there.")
            } else if destination == .history {
                Text("Each run's result stays in its own conversation under Conversations.")
            }
        }
    }

    private func name(of destination: RoutineDestination) -> String {
        if case .room(let id) = destination {
            return groups.rooms.first { $0.id == id }?.name ?? (groups.isLoaded ? String(localized: "Removed Room") : String(localized: "Room"))
        }
        if case .other(let raw) = destination {
            return raw == "bot-chat" ? String(localized: "Bot Chat") : raw
        }
        return String(localized: "Don't Post")
    }
}
