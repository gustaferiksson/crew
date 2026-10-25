import SwiftUI

struct RoutineList: View {
    let bot: Bot
    let store: RoutineStore
    let onCreate: () -> Void
    @State private var pendingDeletion: RoutineJob?

    var body: some View {
        Group {
            if !store.isLoaded, let error = store.loadError {
                Section {
                    ContentUnavailableView("Couldn't Load Routines", systemImage: "exclamationmark.triangle", description: Text(error))
                        .listRowBackground(Color.clear)
                }
            } else if !store.isLoaded {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .listRowBackground(Color.clear)
                }
            } else if store.jobs.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Routines", systemImage: "calendar.badge.clock")
                    } description: {
                        Text("Schedule \(bot.title) to run a prompt on its own.")
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(store.jobs) { job in
                        RoutineRow(job: job, isBusy: store.inFlight.contains(job.id)) { actions(job) }
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
        .alert("Couldn't Update Routine", isPresented: Binding { store.failure != nil } set: { if !$0 { store.failure = nil } }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.failure ?? "")
        }
    }

    @ViewBuilder
    private func actions(_ job: RoutineJob) -> some View {
        Button("Run Now", systemImage: "play") { Task { await store.trigger(job) } }
        Button(job.isPaused ? "Resume" : "Pause", systemImage: job.isPaused ? "play.circle" : "pause.circle") {
            Task { await store.toggle(job) }
        }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) { pendingDeletion = job }
    }
}

private struct RoutineRow<Actions: View>: View {
    let job: RoutineJob
    let isBusy: Bool
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
                if !job.isPaused, let next = job.nextRun {
                    Label {
                        Text("Next run \(next, format: .relative(presentation: .named))")
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let lastRun = job.lastRun {
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
        .opacity(job.isPaused ? 0.7 : 1)
    }

    private var result: (text: String, symbol: String, tint: Color) {
        if job.lastStatus == "ok" { return (String(localized: "Succeeded"), "checkmark.circle.fill", .green) }
        if job.lastStatus == "error" { return (String(localized: "Failed"), "xmark.octagon.fill", .red) }
        if job.lastStatus == "delivery_failed" { return (String(localized: "Delivery failed"), "exclamationmark.triangle.fill", .orange) }
        if job.lastStatus == "blocked_config" { return (String(localized: "Blocked by config"), "exclamationmark.triangle.fill", .orange) }
        return (job.lastStatus.map { String(localized: "Ran (\($0))") } ?? String(localized: "Ran"), "clock.arrow.circlepath", .secondary)
    }
}

struct RoutineEditor: View {
    let bot: Bot
    let store: RoutineStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var prompt = ""
    @State private var frequency = Frequency.daily
    @State private var time = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? .now
    @State private var weekday = 1
    @State private var expression = ""
    @State private var error: String?
    @State private var isSaving = false

    enum Frequency: String, CaseIterable, Identifiable {
        case hourly, daily, weekdays, weekly, custom
        var id: Self { self }
    }

    var body: some View {
        let clock = Calendar.current.dateComponents([.hour, .minute], from: time)
        let at = "\(clock.minute ?? 0) \(clock.hour ?? 9)"
        let schedule = [
            .hourly: "every 1h", .daily: "\(at) * * *", .weekdays: "\(at) * * 1-5", .weekly: "\(at) * * \(weekday)",
        ][frequency] ?? expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let isComplete = !title.trimmingCharacters(in: .whitespaces).isEmpty && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !schedule.isEmpty
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
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Routine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", role: .confirm) {
                        Task {
                            isSaving = true
                            do {
                                try await store.create(
                                    title: title.trimmingCharacters(in: .whitespaces),
                                    prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                                    schedule: schedule
                                )
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
}
