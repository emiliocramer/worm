import CoreGraphics
import CoreLocation
import EventKit
import Foundation
import Observation

// MARK: - Lightweight in-memory models

struct CalendarSourceSnapshot: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let type: String
    let isDelegate: Bool
    let eventCalendarCount: Int
    let reminderCalendarCount: Int
}

struct CalendarListSnapshot: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let type: String
    let sourceID: String?
    let sourceTitle: String?
    let sourceType: String?
    let colorHex: String?
    let allowsContentModifications: Bool
    let isSubscribed: Bool
    let isImmutable: Bool
    let supportedEventAvailabilities: [String]
    let allowedEntityTypes: [String]
}

struct CalendarLocationSnapshot: Hashable, Codable {
    let title: String?
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let horizontalAccuracy: Double?
    let verticalAccuracy: Double?
    let radius: Double
}

struct CalendarParticipantSnapshot: Hashable, Codable {
    let url: String?
    let name: String?
    let status: String
    let role: String
    let type: String
    let isCurrentUser: Bool
    let hasContactMatch: Bool
}

struct CalendarAlarmSnapshot: Hashable, Codable {
    let triggerKind: String
    let relativeOffset: TimeInterval
    let absoluteDate: Date?
    let location: CalendarLocationSnapshot?
    let proximity: String
}

struct CalendarRecurrenceRuleSnapshot: Hashable, Codable {
    let calendarIdentifier: String
    let frequency: String
    let interval: Int
    let firstDayOfTheWeek: Int
    let endDate: Date?
    let occurrenceCount: Int
    let daysOfTheWeek: [String]
    let daysOfTheMonth: [Int]
    let daysOfTheYear: [Int]
    let weeksOfTheYear: [Int]
    let monthsOfTheYear: [Int]
    let setPositions: [Int]
}

struct CalendarDateComponentsSnapshot: Hashable, Codable {
    let calendarIdentifier: String?
    let timeZoneIdentifier: String?
    let era: Int?
    let year: Int?
    let month: Int?
    let day: Int?
    let hour: Int?
    let minute: Int?
    let second: Int?
    let nanosecond: Int?
    let weekday: Int?
    let weekdayOrdinal: Int?
    let weekOfMonth: Int?
    let weekOfYear: Int?
    let yearForWeekOfYear: Int?
    let quarter: Int?
    let isLeapMonth: Bool?
    let resolvedDate: Date?
}

struct CalendarEventItem: Identifiable, Hashable, Codable {
    let id: String
    let eventIdentifier: String
    let calendarItemIdentifier: String
    let calendarItemExternalIdentifier: String?
    let calendarID: String?
    let calendarTitle: String?
    let title: String
    let location: String?
    let notes: String?
    let url: String?
    let creationDate: Date?
    let lastModifiedDate: Date?
    let timeZoneIdentifier: String?
    let hasAlarms: Bool
    let hasRecurrenceRules: Bool
    let hasAttendees: Bool
    let hasNotes: Bool
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let structuredLocation: CalendarLocationSnapshot?
    let organizer: CalendarParticipantSnapshot?
    let attendees: [CalendarParticipantSnapshot]
    let alarms: [CalendarAlarmSnapshot]
    let recurrenceRules: [CalendarRecurrenceRuleSnapshot]
    let availability: String
    let status: String
    let isDetached: Bool
    let occurrenceDate: Date?
    let birthdayContactIdentifier: String?
}

struct CalendarReminderItem: Identifiable, Hashable, Codable {
    let id: String
    let calendarItemIdentifier: String
    let calendarItemExternalIdentifier: String?
    let calendarID: String?
    let calendarTitle: String?
    let title: String
    let location: String?
    let notes: String?
    let url: String?
    let creationDate: Date?
    let lastModifiedDate: Date?
    let timeZoneIdentifier: String?
    let hasAlarms: Bool
    let hasRecurrenceRules: Bool
    let hasAttendees: Bool
    let hasNotes: Bool
    let attendees: [CalendarParticipantSnapshot]
    let alarms: [CalendarAlarmSnapshot]
    let recurrenceRules: [CalendarRecurrenceRuleSnapshot]
    let startDateComponents: CalendarDateComponentsSnapshot?
    let dueDateComponents: CalendarDateComponentsSnapshot?
    let isCompleted: Bool
    let completionDate: Date?
    let priority: Int
}

struct CalendarNodeSnapshot: Codable {
    let eventAuthorizationStatusText: String
    let reminderAuthorizationStatusText: String
    let sources: [CalendarSourceSnapshot]
    let eventCalendars: [CalendarListSnapshot]
    let reminderCalendars: [CalendarListSnapshot]
    let events: [CalendarEventItem]
    let reminders: [CalendarReminderItem]
    let scanStartDate: Date?
    let scanEndDate: Date?
    let lastSyncedAt: Date?
}

private actor CalendarSyncWorker {
    private let eventStore = EKEventStore()

    func scan(progress: @escaping (String?) -> Void) async throws -> CalendarNodeSnapshot {
        let hasEventAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        let hasReminderAccess = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        let eventAuthorizationStatusText = CalendarNode.describe(authorizationStatus: EKEventStore.authorizationStatus(for: .event))
        let reminderAuthorizationStatusText = CalendarNode.describe(authorizationStatus: EKEventStore.authorizationStatus(for: .reminder))

        eventStore.refreshSourcesIfNecessary()
        let eventCalendarObjects = hasEventAccess ? eventStore.calendars(for: .event) : []
        let reminderCalendarObjects = hasReminderAccess ? eventStore.calendars(for: .reminder) : []

        progress("Reading accounts and calendars...")
        let sources = eventStore.sources.map { source in
            CalendarSourceSnapshot(
                id: source.sourceIdentifier,
                title: source.title,
                type: CalendarNode.describe(sourceType: source.sourceType),
                isDelegate: source.isDelegate,
                eventCalendarCount: source.calendars(for: .event).count,
                reminderCalendarCount: source.calendars(for: .reminder).count
            )
        }
        let eventCalendars = eventCalendarObjects.map(CalendarNode.makeCalendar)
        let reminderCalendars = reminderCalendarObjects.map(CalendarNode.makeCalendar)

        let events: [CalendarEventItem]
        let scanStartDate: Date?
        let scanEndDate: Date?
        if hasEventAccess {
            progress("Reading events...")
            let window = CalendarNode.scanWindow()
            scanStartDate = window.start
            scanEndDate = window.end
            events = CalendarNode.fetchEvents(
                from: eventStore,
                calendars: eventCalendarObjects,
                start: window.start,
                end: window.end
            )
        } else {
            events = []
            scanStartDate = nil
            scanEndDate = nil
        }

        let reminders: [CalendarReminderItem]
        if hasReminderAccess {
            progress("Reading reminders...")
            reminders = await fetchReminders(calendars: reminderCalendarObjects)
        } else {
            reminders = []
        }

        return CalendarNodeSnapshot(
            eventAuthorizationStatusText: eventAuthorizationStatusText,
            reminderAuthorizationStatusText: reminderAuthorizationStatusText,
            sources: sources,
            eventCalendars: eventCalendars,
            reminderCalendars: reminderCalendars,
            events: events,
            reminders: reminders,
            scanStartDate: scanStartDate,
            scanEndDate: scanEndDate,
            lastSyncedAt: Date()
        )
    }

    private func fetchReminders(calendars: [EKCalendar]) async -> [CalendarReminderItem] {
        await withCheckedContinuation { continuation in
            let predicate = eventStore.predicateForReminders(in: calendars)
            _ = eventStore.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? [])
                    .prefix(CalendarNode.maxReminders)
                    .map(CalendarNode.makeReminder)
                    .sorted {
                        ($0.dueDateComponents?.resolvedDate ?? $0.completionDate ?? Date.distantFuture)
                            < ($1.dueDateComponents?.resolvedDate ?? $1.completionDate ?? Date.distantFuture)
                    }
                continuation.resume(returning: items)
            }
        }
    }
}

/// The Calendar node: dense extraction from EventKit.
///
/// Events and reminders are separate permissions. The node captures whichever
/// side the user grants: sources/accounts, calendars/lists, event occurrences
/// across a broad window, reminder tasks, attendees, alarms, recurrence rules,
/// structured locations, notes, URLs, and every stable identifier EventKit
/// exposes. The result is persisted as JSON for instant restore.
@MainActor
@Observable
final class CalendarNode {
    fileprivate nonisolated static let maxEvents = 100_000
    fileprivate nonisolated static let maxReminders = 50_000
    fileprivate nonisolated static let pastYears = 20
    fileprivate nonisolated static let futureYears = 10
    fileprivate nonisolated static let chunkYears = 4

    // MARK: Observable state

    private(set) var isAuthorized = false
    private(set) var isAuthorizing = false
    private(set) var isSyncing = false
    private(set) var eventAuthorizationStatusText = "Not requested"
    private(set) var reminderAuthorizationStatusText = "Not requested"
    private(set) var syncProgress: String?
    private(set) var lastSyncedAt: Date?
    private(set) var lastErrorMessage: String?

    private(set) var sources: [CalendarSourceSnapshot] = []
    private(set) var eventCalendars: [CalendarListSnapshot] = []
    private(set) var reminderCalendars: [CalendarListSnapshot] = []
    private(set) var events: [CalendarEventItem] = []
    private(set) var reminders: [CalendarReminderItem] = []
    private(set) var scanStartDate: Date?
    private(set) var scanEndDate: Date?

    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private let syncWorker = CalendarSyncWorker()
    @ObservationIgnored private let snapshotStore = SnapshotStore<CalendarNodeSnapshot>(filename: "calendar-snapshot.json")

    init() {
        loadCachedSnapshot()
        if hasRestoredSnapshot {
            isAuthorized = true
        }
    }

    var statusSummary: String {
        if isAuthorizing { return "Requesting Calendar access..." }
        if isSyncing { return syncProgress ?? "Reading Calendar and Reminders..." }
        if hasEventAccess, hasReminderAccess { return "Connected to Calendar and Reminders" }
        if hasEventAccess { return "Connected to Calendar events" }
        if hasReminderAccess { return "Connected to Reminders" }
        if isAuthorized { return "Restored Calendar snapshot" }
        return "Calendar not connected."
    }

    // MARK: - Lifecycle

    func restoreSessionIfPossible() async {
        loadCachedSnapshot()
        updateAuthorizationStatus()
        isAuthorized = hasEventAccess || hasReminderAccess
        if !isAuthorized, hasRestoredSnapshot {
            isAuthorized = true
        }
        if isAuthorized, !hasRestoredSnapshot {
            await syncEverything()
        }
    }

    private func loadCachedSnapshot() {
        guard let snapshot = snapshotStore.load() else { return }
        apply(snapshot)
    }

    private func apply(_ snapshot: CalendarNodeSnapshot) {
        eventAuthorizationStatusText = snapshot.eventAuthorizationStatusText
        reminderAuthorizationStatusText = snapshot.reminderAuthorizationStatusText
        sources = snapshot.sources
        eventCalendars = snapshot.eventCalendars
        reminderCalendars = snapshot.reminderCalendars
        events = snapshot.events
        reminders = snapshot.reminders
        scanStartDate = snapshot.scanStartDate
        scanEndDate = snapshot.scanEndDate
        lastSyncedAt = snapshot.lastSyncedAt
        if hasRestoredSnapshot {
            isAuthorized = true
        }
    }

    private var hasRestoredSnapshot: Bool {
        lastSyncedAt != nil ||
            !sources.isEmpty ||
            !eventCalendars.isEmpty ||
            !reminderCalendars.isEmpty ||
            !events.isEmpty ||
            !reminders.isEmpty
    }

    private func saveCachedSnapshot() {
        snapshotStore.save(
            CalendarNodeSnapshot(
                eventAuthorizationStatusText: eventAuthorizationStatusText,
                reminderAuthorizationStatusText: reminderAuthorizationStatusText,
                sources: sources,
                eventCalendars: eventCalendars,
                reminderCalendars: reminderCalendars,
                events: events,
                reminders: reminders,
                scanStartDate: scanStartDate,
                scanEndDate: scanEndDate,
                lastSyncedAt: lastSyncedAt
            )
        )
    }

    func connect() async {
        lastErrorMessage = nil
        isAuthorizing = true
        defer { isAuthorizing = false }

        do {
            if !hasEventAccess {
                _ = try await requestFullEventAccess()
            }
            updateAuthorizationStatus()

            if !hasReminderAccess {
                _ = try await requestFullReminderAccess()
            }
            updateAuthorizationStatus()

            isAuthorized = hasEventAccess || hasReminderAccess
            if isAuthorized {
                await syncEverything()
            } else {
                lastErrorMessage = "Calendar and Reminders access was not granted."
            }
        } catch {
            updateAuthorizationStatus()
            isAuthorized = hasEventAccess || hasReminderAccess
            lastErrorMessage = error.localizedDescription
            if isAuthorized {
                await syncEverything()
            }
        }
    }

    /// Calendar/Reminders authorization can only be revoked from Settings, so
    /// this clears the node's local snapshot and resets connection state.
    func disconnect() {
        syncTask?.cancel()
        syncTask = nil
        isAuthorized = false
        isSyncing = false
        syncProgress = nil
        sources = []
        eventCalendars = []
        reminderCalendars = []
        events = []
        reminders = []
        scanStartDate = nil
        scanEndDate = nil
        lastSyncedAt = nil
        snapshotStore.delete()
    }

    func syncEverything() async {
        guard hasEventAccess || hasReminderAccess else { return }
        if let syncTask {
            await syncTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            isSyncing = true
            defer {
                isSyncing = false
                syncProgress = nil
                syncTask = nil
            }
            do {
                try await runFullSync()
            } catch is CancellationError {
                // User cancelled or disconnected mid-sync.
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
        syncTask = task
        await task.value
    }

    // MARK: - Full scan

    private func runFullSync() async throws {
        lastErrorMessage = nil
        updateAuthorizationStatus()

        report("Preparing Calendar scan...")
        let snapshot = try await syncWorker.scan { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.isSyncing else { return }
                self.report(message)
            }
        }

        apply(snapshot)
        isAuthorized = hasEventAccess || hasReminderAccess
        saveCachedSnapshot()
        report(nil)
    }

    fileprivate nonisolated static func scanWindow(now: Date = Date()) -> (start: Date, end: Date) {
        let calendar = Foundation.Calendar.current
        let start = calendar.date(byAdding: .year, value: -pastYears, to: now) ?? now.addingTimeInterval(-20 * 365 * 24 * 60 * 60)
        let end = calendar.date(byAdding: .year, value: futureYears, to: now) ?? now.addingTimeInterval(10 * 365 * 24 * 60 * 60)
        return (start, end)
    }

    fileprivate nonisolated static func fetchEvents(from store: EKEventStore, calendars: [EKCalendar], start: Date, end: Date) -> [CalendarEventItem] {
        let calendar = Foundation.Calendar.current
        var cursor = start
        var out: [CalendarEventItem] = []
        var seen = Set<String>()

        while cursor < end, out.count < maxEvents {
            let next = min(calendar.date(byAdding: .year, value: chunkYears, to: cursor) ?? end, end)
            let predicate = store.predicateForEvents(withStart: cursor, end: next, calendars: calendars)
            let chunk = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
            for event in chunk where out.count < maxEvents {
                let item = makeEvent(event)
                if seen.insert(item.id).inserted {
                    out.append(item)
                }
            }
            cursor = next.addingTimeInterval(1)
        }

        return out.sorted { $0.startDate < $1.startDate }
    }

    private func fetchReminders(calendars: [EKCalendar]) async -> [CalendarReminderItem] {
        await withCheckedContinuation { continuation in
            let predicate = eventStore.predicateForReminders(in: calendars)
            _ = eventStore.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? [])
                    .prefix(Self.maxReminders)
                    .map(Self.makeReminder)
                    .sorted {
                        ($0.dueDateComponents?.resolvedDate ?? $0.completionDate ?? Date.distantFuture)
                            < ($1.dueDateComponents?.resolvedDate ?? $1.completionDate ?? Date.distantFuture)
                    }
                continuation.resume(returning: items)
            }
        }
    }

    // MARK: - Authorization

    private var hasEventAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    private var hasReminderAccess: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    private func updateAuthorizationStatus() {
        eventAuthorizationStatusText = Self.describe(authorizationStatus: EKEventStore.authorizationStatus(for: .event))
        reminderAuthorizationStatusText = Self.describe(authorizationStatus: EKEventStore.authorizationStatus(for: .reminder))
    }

    private func requestFullEventAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func requestFullReminderAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Mapping

    fileprivate nonisolated static func makeCalendar(_ calendar: EKCalendar) -> CalendarListSnapshot {
        CalendarListSnapshot(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            type: describe(calendarType: calendar.type),
            sourceID: calendar.source?.sourceIdentifier,
            sourceTitle: calendar.source?.title,
            sourceType: calendar.source.map { describe(sourceType: $0.sourceType) },
            colorHex: hex(calendar.cgColor),
            allowsContentModifications: calendar.allowsContentModifications,
            isSubscribed: calendar.isSubscribed,
            isImmutable: calendar.isImmutable,
            supportedEventAvailabilities: describe(availabilityMask: calendar.supportedEventAvailabilities),
            allowedEntityTypes: describe(entityMask: calendar.allowedEntityTypes)
        )
    }

    fileprivate nonisolated static func makeEvent(_ event: EKEvent) -> CalendarEventItem {
        let occurrence = event.occurrenceDate ?? event.startDate
        let id = [event.eventIdentifier, occurrence?.timeIntervalSince1970.description]
            .compactMap { $0 }
            .joined(separator: "|")

        return CalendarEventItem(
            id: id.isEmpty ? event.calendarItemIdentifier : id,
            eventIdentifier: event.eventIdentifier,
            calendarItemIdentifier: event.calendarItemIdentifier,
            calendarItemExternalIdentifier: event.calendarItemExternalIdentifier,
            calendarID: event.calendar?.calendarIdentifier,
            calendarTitle: event.calendar?.title,
            title: event.title ?? "",
            location: event.location,
            notes: event.notes,
            url: event.url?.absoluteString,
            creationDate: event.creationDate,
            lastModifiedDate: event.lastModifiedDate,
            timeZoneIdentifier: event.timeZone?.identifier,
            hasAlarms: event.hasAlarms,
            hasRecurrenceRules: event.hasRecurrenceRules,
            hasAttendees: event.hasAttendees,
            hasNotes: event.hasNotes,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            structuredLocation: makeLocation(event.structuredLocation),
            organizer: event.organizer.map(makeParticipant),
            attendees: event.attendees?.map(makeParticipant) ?? [],
            alarms: event.alarms?.map(makeAlarm) ?? [],
            recurrenceRules: event.recurrenceRules?.map(makeRecurrenceRule) ?? [],
            availability: describe(availability: event.availability),
            status: describe(eventStatus: event.status),
            isDetached: event.isDetached,
            occurrenceDate: event.occurrenceDate,
            birthdayContactIdentifier: event.birthdayContactIdentifier
        )
    }

    fileprivate nonisolated static func makeReminder(_ reminder: EKReminder) -> CalendarReminderItem {
        CalendarReminderItem(
            id: reminder.calendarItemIdentifier,
            calendarItemIdentifier: reminder.calendarItemIdentifier,
            calendarItemExternalIdentifier: reminder.calendarItemExternalIdentifier,
            calendarID: reminder.calendar?.calendarIdentifier,
            calendarTitle: reminder.calendar?.title,
            title: reminder.title ?? "",
            location: reminder.location,
            notes: reminder.notes,
            url: reminder.url?.absoluteString,
            creationDate: reminder.creationDate,
            lastModifiedDate: reminder.lastModifiedDate,
            timeZoneIdentifier: reminder.timeZone?.identifier,
            hasAlarms: reminder.hasAlarms,
            hasRecurrenceRules: reminder.hasRecurrenceRules,
            hasAttendees: reminder.hasAttendees,
            hasNotes: reminder.hasNotes,
            attendees: reminder.attendees?.map(makeParticipant) ?? [],
            alarms: reminder.alarms?.map(makeAlarm) ?? [],
            recurrenceRules: reminder.recurrenceRules?.map(makeRecurrenceRule) ?? [],
            startDateComponents: reminder.startDateComponents.map(makeDateComponents),
            dueDateComponents: reminder.dueDateComponents.map(makeDateComponents),
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            priority: reminder.priority
        )
    }

    fileprivate nonisolated static func makeParticipant(_ participant: EKParticipant) -> CalendarParticipantSnapshot {
        CalendarParticipantSnapshot(
            url: participant.url.absoluteString,
            name: participant.name,
            status: describe(participantStatus: participant.participantStatus),
            role: describe(participantRole: participant.participantRole),
            type: describe(participantType: participant.participantType),
            isCurrentUser: participant.isCurrentUser,
            hasContactMatch: true
        )
    }

    fileprivate nonisolated static func makeAlarm(_ alarm: EKAlarm) -> CalendarAlarmSnapshot {
        CalendarAlarmSnapshot(
            triggerKind: alarm.absoluteDate == nil ? "Relative" : "Absolute",
            relativeOffset: alarm.relativeOffset,
            absoluteDate: alarm.absoluteDate,
            location: makeLocation(alarm.structuredLocation),
            proximity: describe(alarmProximity: alarm.proximity)
        )
    }

    fileprivate nonisolated static func makeLocation(_ location: EKStructuredLocation?) -> CalendarLocationSnapshot? {
        guard let location else { return nil }
        return CalendarLocationSnapshot(
            title: location.title,
            latitude: location.geoLocation?.coordinate.latitude,
            longitude: location.geoLocation?.coordinate.longitude,
            altitude: location.geoLocation?.altitude,
            horizontalAccuracy: location.geoLocation?.horizontalAccuracy,
            verticalAccuracy: location.geoLocation?.verticalAccuracy,
            radius: location.radius
        )
    }

    fileprivate nonisolated static func makeRecurrenceRule(_ rule: EKRecurrenceRule) -> CalendarRecurrenceRuleSnapshot {
        CalendarRecurrenceRuleSnapshot(
            calendarIdentifier: rule.calendarIdentifier,
            frequency: describe(recurrenceFrequency: rule.frequency),
            interval: rule.interval,
            firstDayOfTheWeek: rule.firstDayOfTheWeek,
            endDate: rule.recurrenceEnd?.endDate,
            occurrenceCount: rule.recurrenceEnd?.occurrenceCount ?? 0,
            daysOfTheWeek: rule.daysOfTheWeek?.map {
                "\($0.dayOfTheWeek.rawValue):\($0.weekNumber)"
            } ?? [],
            daysOfTheMonth: rule.daysOfTheMonth?.map(\.intValue) ?? [],
            daysOfTheYear: rule.daysOfTheYear?.map(\.intValue) ?? [],
            weeksOfTheYear: rule.weeksOfTheYear?.map(\.intValue) ?? [],
            monthsOfTheYear: rule.monthsOfTheYear?.map(\.intValue) ?? [],
            setPositions: rule.setPositions?.map(\.intValue) ?? []
        )
    }

    fileprivate nonisolated static func makeDateComponents(_ components: DateComponents) -> CalendarDateComponentsSnapshot {
        CalendarDateComponentsSnapshot(
            calendarIdentifier: components.calendar.map { String(describing: $0.identifier) },
            timeZoneIdentifier: components.timeZone?.identifier,
            era: components.era,
            year: components.year,
            month: components.month,
            day: components.day,
            hour: components.hour,
            minute: components.minute,
            second: components.second,
            nanosecond: components.nanosecond,
            weekday: components.weekday,
            weekdayOrdinal: components.weekdayOrdinal,
            weekOfMonth: components.weekOfMonth,
            weekOfYear: components.weekOfYear,
            yearForWeekOfYear: components.yearForWeekOfYear,
            quarter: components.quarter,
            isLeapMonth: components.isLeapMonth,
            resolvedDate: components.date
        )
    }

    // MARK: - Descriptions

    fileprivate nonisolated static func describe(authorizationStatus: EKAuthorizationStatus) -> String {
        switch authorizationStatus {
        case .notDetermined: return "Not determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .fullAccess: return "Full access"
        case .writeOnly: return "Write only"
        @unknown default: return "Unknown"
        }
    }

    fileprivate nonisolated static func describe(sourceType: EKSourceType) -> String {
        switch sourceType {
        case .local: return "Local"
        case .exchange: return "Exchange"
        case .calDAV: return "CalDAV"
        case .mobileMe: return "MobileMe"
        case .subscribed: return "Subscribed"
        case .birthdays: return "Birthdays"
        @unknown default: return "Unknown"
        }
    }

    fileprivate nonisolated static func describe(calendarType: EKCalendarType) -> String {
        switch calendarType {
        case .local: return "Local"
        case .calDAV: return "CalDAV"
        case .exchange: return "Exchange"
        case .subscription: return "Subscription"
        case .birthday: return "Birthday"
        @unknown default: return "Unknown"
        }
    }

    fileprivate nonisolated static func describe(availability: EKEventAvailability) -> String {
        switch availability {
        case .notSupported: return "Not supported"
        case .busy: return "Busy"
        case .free: return "Free"
        case .tentative: return "Tentative"
        case .unavailable: return "Unavailable"
        @unknown default: return "Unknown"
        }
    }

    fileprivate nonisolated static func describe(availabilityMask: EKCalendarEventAvailabilityMask) -> [String] {
        var out: [String] = []
        if availabilityMask.contains(.busy) { out.append("Busy") }
        if availabilityMask.contains(.free) { out.append("Free") }
        if availabilityMask.contains(.tentative) { out.append("Tentative") }
        if availabilityMask.contains(.unavailable) { out.append("Unavailable") }
        return out
    }

    fileprivate nonisolated static func describe(eventStatus: EKEventStatus) -> String {
        switch eventStatus {
        case .none: return "None"
        case .confirmed: return "Confirmed"
        case .tentative: return "Tentative"
        case .canceled: return "Canceled"
        @unknown default: return "Unknown"
        }
    }

    fileprivate nonisolated static func describe(entityMask: EKEntityMask) -> [String] {
        var out: [String] = []
        if entityMask.contains(.event) { out.append("Event") }
        if entityMask.contains(.reminder) { out.append("Reminder") }
        return out
    }

    fileprivate nonisolated static func describe(participantStatus: EKParticipantStatus) -> String {
        switch participantStatus {
        case .unknown: return "Unknown"
        case .pending: return "Pending"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .tentative: return "Tentative"
        case .delegated: return "Delegated"
        case .completed: return "Completed"
        case .inProcess: return "In process"
        @unknown default: return "Unknown"
        }
    }

    fileprivate nonisolated static func describe(participantRole: EKParticipantRole) -> String {
        switch participantRole {
        case .unknown: return "Unknown"
        case .required: return "Required"
        case .optional: return "Optional"
        case .chair: return "Chair"
        case .nonParticipant: return "Non-participant"
        @unknown default: return "Unknown"
        }
    }

    fileprivate nonisolated static func describe(participantType: EKParticipantType) -> String {
        switch participantType {
        case .unknown: return "Unknown"
        case .person: return "Person"
        case .room: return "Room"
        case .resource: return "Resource"
        case .group: return "Group"
        @unknown default: return "Unknown"
        }
    }

    fileprivate nonisolated static func describe(alarmProximity: EKAlarmProximity) -> String {
        switch alarmProximity {
        case .none: return "None"
        case .enter: return "Enter"
        case .leave: return "Leave"
        @unknown default: return "Unknown"
        }
    }

    fileprivate nonisolated static func describe(recurrenceFrequency: EKRecurrenceFrequency) -> String {
        switch recurrenceFrequency {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        @unknown default: return "Unknown"
        }
    }

    fileprivate nonisolated static func hex(_ color: CGColor?) -> String? {
        guard let color,
              let converted = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let components = converted.components else { return nil }

        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat
        if components.count >= 4 {
            r = components[0]; g = components[1]; b = components[2]; a = components[3]
        } else if components.count >= 2 {
            r = components[0]; g = components[0]; b = components[0]; a = components[1]
        } else {
            return nil
        }
        return String(
            format: "#%02X%02X%02X%02X",
            Int(r * 255),
            Int(g * 255),
            Int(b * 255),
            Int(a * 255)
        )
    }

    private func report(_ message: String?) {
        syncProgress = message
    }
}
