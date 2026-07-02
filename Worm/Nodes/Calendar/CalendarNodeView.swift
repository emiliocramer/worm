import SwiftUI

/// Surfaces the Calendar node: connect/disconnect, sync status, and a readout
/// of the EventKit snapshot that will feed the brain layer.
struct CalendarNodeView: View {
    @Environment(CalendarNode.self) private var node

    var body: some View {
        List {
            statusSection

            if node.isAuthorized {
                snapshotSection
                accessSection
                granularSections
            } else {
                connectSection
            }

            if let error = node.lastErrorMessage {
                Section("Last error") {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Calendar")
        .toolbar {
            if node.isAuthorized {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await node.syncEverything() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(node.isSyncing)
                }
            }
        }
    }

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                if node.isSyncing || node.isAuthorizing {
                    ProgressView()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.statusSummary).font(.headline)
                    if let progress = node.syncProgress {
                        Text(progress).font(.caption).foregroundStyle(.secondary)
                    } else if let synced = node.lastSyncedAt {
                        Text("Last synced \(synced.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private var connectSection: some View {
        Section {
            Button {
                Task { await node.connect() }
            } label: {
                Label("Connect Calendar", systemImage: "calendar")
            }
            .disabled(node.isAuthorizing)
        } footer: {
            Text("Connecting grants read access to Calendar events and Reminders. Worm captures accounts, calendars, event details, attendees, alarms, recurrence rules, locations, notes, URLs, and reminder task state.")
        }
    }

    private var snapshotSection: some View {
        Section("Snapshot") {
            metric("Sources", node.sources.count)
            metric("Event calendars", node.eventCalendars.count)
            metric("Reminder lists", node.reminderCalendars.count)
            metric("Events", node.events.count)
            metric("Reminders", node.reminders.count)
            metric("Events with attendees", node.events.lazy.filter { !$0.attendees.isEmpty }.count)
            metric("Events with location", node.events.lazy.filter { $0.location != nil || $0.structuredLocation != nil }.count)
            metric("Recurring events", node.events.lazy.filter { !$0.recurrenceRules.isEmpty }.count)
            metric("Completed reminders", node.reminders.lazy.filter { $0.isCompleted }.count)
            if let start = node.scanStartDate, let end = node.scanEndDate {
                labelled("Event window", "\(start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))")
            }
        }
    }

    private var accessSection: some View {
        Section("Access") {
            labelled("Events", node.eventAuthorizationStatusText)
            labelled("Reminders", node.reminderAuthorizationStatusText)
        }
    }

    @ViewBuilder
    private var granularSections: some View {
        if !node.sources.isEmpty {
            Section {
                NavigationLink("Sources (\(node.sources.count))") {
                    List(node.sources) { source in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title)
                            Text("\(source.type) | \(source.eventCalendarCount) event | \(source.reminderCalendarCount) reminder")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Sources")
                }
            }
        }

        calendarNav("Event calendars", node.eventCalendars)
        calendarNav("Reminder lists", node.reminderCalendars)

        if !node.events.isEmpty {
            Section {
                NavigationLink("Events (\(node.events.count))") {
                    EventListView(events: node.events)
                }
            }
        }

        if !node.reminders.isEmpty {
            Section {
                NavigationLink("Reminders (\(node.reminders.count))") {
                    ReminderListView(reminders: node.reminders)
                }
            }
        }

        Section {
            Button("Disconnect", role: .destructive) { node.disconnect() }
        }
    }

    @ViewBuilder
    private func calendarNav(_ title: String, _ calendars: [CalendarListSnapshot]) -> some View {
        if !calendars.isEmpty {
            Section {
                NavigationLink("\(title) (\(calendars.count))") {
                    List(calendars) { calendar in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calendar.title)
                            Text([calendar.type, calendar.sourceTitle].compactMap { $0 }.joined(separator: " | "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle(title)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)").foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func labelled(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}

private struct EventListView: View {
    let events: [CalendarEventItem]
    @State private var visibleCount = 200

    var body: some View {
        List {
            ForEach(events.prefix(visibleCount)) { event in
                NavigationLink {
                    EventDetailView(event: event)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title.isEmpty ? "(Untitled)" : event.title)
                            .lineLimit(1)
                        Text(eventSubtitle(event))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if visibleCount < events.count {
                Button("Load more (\(events.count - visibleCount) remaining)") {
                    visibleCount += 200
                }
            }
        }
        .navigationTitle("Events")
    }

    private func eventSubtitle(_ event: CalendarEventItem) -> String {
        var parts: [String] = [
            event.startDate.formatted(date: .abbreviated, time: event.isAllDay ? .omitted : .shortened)
        ]
        if let calendar = event.calendarTitle { parts.append(calendar) }
        if !event.attendees.isEmpty { parts.append("\(event.attendees.count) people") }
        if event.location != nil || event.structuredLocation != nil { parts.append("location") }
        return parts.joined(separator: " | ")
    }
}

private struct ReminderListView: View {
    let reminders: [CalendarReminderItem]
    @State private var visibleCount = 200

    var body: some View {
        List {
            ForEach(reminders.prefix(visibleCount)) { reminder in
                NavigationLink {
                    ReminderDetailView(reminder: reminder)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.title.isEmpty ? "(Untitled)" : reminder.title)
                            .lineLimit(1)
                        Text(reminderSubtitle(reminder))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if visibleCount < reminders.count {
                Button("Load more (\(reminders.count - visibleCount) remaining)") {
                    visibleCount += 200
                }
            }
        }
        .navigationTitle("Reminders")
    }

    private func reminderSubtitle(_ reminder: CalendarReminderItem) -> String {
        var parts: [String] = []
        if reminder.isCompleted {
            parts.append("completed")
        }
        if let due = reminder.dueDateComponents?.resolvedDate {
            parts.append(due.formatted(date: .abbreviated, time: .shortened))
        }
        if let calendar = reminder.calendarTitle {
            parts.append(calendar)
        }
        if reminder.priority > 0 {
            parts.append("priority \(reminder.priority)")
        }
        return parts.isEmpty ? "Reminder" : parts.joined(separator: " | ")
    }
}

private struct EventDetailView: View {
    let event: CalendarEventItem

    var body: some View {
        List {
            Section("Event") {
                row("Title", event.title)
                row("Calendar", event.calendarTitle)
                row("Status", event.status)
                row("Availability", event.availability)
                row("All day", event.isAllDay ? "Yes" : "No")
                row("Detached", event.isDetached ? "Yes" : "No")
                row("Start", event.startDate.formatted(date: .long, time: .standard))
                row("End", event.endDate.formatted(date: .long, time: .standard))
                row("Location", event.location)
                row("URL", event.url)
                row("Notes", event.notes)
            }

            if !event.attendees.isEmpty {
                Section("Attendees (\(event.attendees.count))") {
                    participantRows(event.attendees)
                }
            }

            if !event.alarms.isEmpty {
                Section("Alarms (\(event.alarms.count))") {
                    alarmRows(event.alarms)
                }
            }

            if !event.recurrenceRules.isEmpty {
                Section("Recurrence") {
                    recurrenceRows(event.recurrenceRules)
                }
            }

            Section("Identifiers") {
                row("Event ID", event.eventIdentifier)
                row("Item ID", event.calendarItemIdentifier)
                row("External ID", event.calendarItemExternalIdentifier)
                row("Calendar ID", event.calendarID)
            }
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReminderDetailView: View {
    let reminder: CalendarReminderItem

    var body: some View {
        List {
            Section("Reminder") {
                row("Title", reminder.title)
                row("List", reminder.calendarTitle)
                row("Completed", reminder.isCompleted ? "Yes" : "No")
                row("Completion", reminder.completionDate?.formatted(date: .long, time: .standard))
                row("Priority", "\(reminder.priority)")
                row("Location", reminder.location)
                row("URL", reminder.url)
                row("Notes", reminder.notes)
            }

            if !reminder.alarms.isEmpty {
                Section("Alarms (\(reminder.alarms.count))") {
                    alarmRows(reminder.alarms)
                }
            }

            if !reminder.recurrenceRules.isEmpty {
                Section("Recurrence") {
                    recurrenceRows(reminder.recurrenceRules)
                }
            }

            Section("Identifiers") {
                row("Item ID", reminder.calendarItemIdentifier)
                row("External ID", reminder.calendarItemExternalIdentifier)
                row("Calendar ID", reminder.calendarID)
            }
        }
        .navigationTitle("Reminder")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@ViewBuilder
private func participantRows(_ participants: [CalendarParticipantSnapshot]) -> some View {
    ForEach(Array(participants.enumerated()), id: \.offset) { _, participant in
        VStack(alignment: .leading, spacing: 2) {
            Text(participant.name ?? participant.url ?? "Participant")
            Text("\(participant.role) | \(participant.status) | \(participant.type)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

@ViewBuilder
private func alarmRows(_ alarms: [CalendarAlarmSnapshot]) -> some View {
    ForEach(Array(alarms.enumerated()), id: \.offset) { _, alarm in
        VStack(alignment: .leading, spacing: 2) {
            Text(alarm.absoluteDate?.formatted(date: .abbreviated, time: .shortened) ?? "\(Int(alarm.relativeOffset / 60)) min")
            Text("\(alarm.triggerKind) | \(alarm.proximity)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

@ViewBuilder
private func recurrenceRows(_ rules: [CalendarRecurrenceRuleSnapshot]) -> some View {
    ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
        VStack(alignment: .leading, spacing: 2) {
            Text(rule.frequency)
            Text("Every \(rule.interval) | ends \(rule.endDate?.formatted(date: .abbreviated, time: .omitted) ?? "\(rule.occurrenceCount) occurrences")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

@ViewBuilder
private func row(_ title: String, _ value: String?) -> some View {
    if let value, !value.isEmpty {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NavigationStack {
        CalendarNodeView()
    }
    .environment(CalendarNode())
}
