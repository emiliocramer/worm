import Contacts
import Foundation
import Observation

// MARK: - Lightweight in-memory models

struct ContactDateComponentsSnapshot: Hashable, Codable {
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

struct ContactLabeledString: Hashable, Codable, Identifiable {
    let id: String
    let label: String?
    let localizedLabel: String?
    let value: String
}

struct ContactLabeledDate: Hashable, Codable, Identifiable {
    let id: String
    let label: String?
    let localizedLabel: String?
    let value: ContactDateComponentsSnapshot
}

struct ContactPostalAddressSnapshot: Hashable, Codable, Identifiable {
    let id: String
    let label: String?
    let localizedLabel: String?
    let street: String
    let subLocality: String
    let city: String
    let subAdministrativeArea: String
    let state: String
    let postalCode: String
    let country: String
    let isoCountryCode: String
}

struct ContactRelationSnapshot: Hashable, Codable, Identifiable {
    let id: String
    let label: String?
    let localizedLabel: String?
    let name: String
}

struct ContactSocialProfileSnapshot: Hashable, Codable, Identifiable {
    let id: String
    let label: String?
    let localizedLabel: String?
    let urlString: String?
    let username: String
    let userIdentifier: String?
    let service: String?
}

struct ContactInstantMessageSnapshot: Hashable, Codable, Identifiable {
    let id: String
    let label: String?
    let localizedLabel: String?
    let username: String
    let service: String
}

struct ContactImageSnapshot: Hashable, Codable {
    let imageDataAvailable: Bool
    let imageData: Data?
    let thumbnailImageData: Data?

    var imageBytes: Int { imageData?.count ?? 0 }
    var thumbnailBytes: Int { thumbnailImageData?.count ?? 0 }
}

struct ContactItem: Identifiable, Hashable, Codable {
    let id: String
    let contactType: String
    let namePrefix: String
    let givenName: String
    let middleName: String
    let familyName: String
    let previousFamilyName: String
    let nameSuffix: String
    let nickname: String
    let phoneticGivenName: String
    let phoneticMiddleName: String
    let phoneticFamilyName: String
    let organizationName: String
    let phoneticOrganizationName: String
    let departmentName: String
    let jobTitle: String
    let birthday: ContactDateComponentsSnapshot?
    let nonGregorianBirthday: ContactDateComponentsSnapshot?
    let phoneNumbers: [ContactLabeledString]
    let emailAddresses: [ContactLabeledString]
    let postalAddresses: [ContactPostalAddressSnapshot]
    let urlAddresses: [ContactLabeledString]
    let dates: [ContactLabeledDate]
    let contactRelations: [ContactRelationSnapshot]
    let socialProfiles: [ContactSocialProfileSnapshot]
    let instantMessageAddresses: [ContactInstantMessageSnapshot]
    let image: ContactImageSnapshot

    var displayName: String {
        let person = [givenName, middleName, familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !person.isEmpty { return person }
        if !organizationName.isEmpty { return organizationName }
        if !nickname.isEmpty { return nickname }
        return id
    }
}

struct ContactContainerSnapshot: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let type: String
}

struct ContactGroupSnapshot: Identifiable, Hashable, Codable {
    let id: String
    let name: String
}

struct ContactsNodeSnapshot: Codable {
    let authorizationStatusText: String
    let contacts: [ContactItem]
    let containers: [ContactContainerSnapshot]
    let groups: [ContactGroupSnapshot]
    let contactIDsByContainerID: [String: [String]]
    let contactIDsByGroupID: [String: [String]]
    let apiLimitations: [String]
    let lastSyncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case authorizationStatusText
        case contacts
        case containers
        case groups
        case contactIDsByContainerID
        case contactIDsByGroupID
        case apiLimitations
        case lastSyncedAt
    }

    init(
        authorizationStatusText: String,
        contacts: [ContactItem],
        containers: [ContactContainerSnapshot],
        groups: [ContactGroupSnapshot],
        contactIDsByContainerID: [String: [String]],
        contactIDsByGroupID: [String: [String]],
        apiLimitations: [String],
        lastSyncedAt: Date?
    ) {
        self.authorizationStatusText = authorizationStatusText
        self.contacts = contacts
        self.containers = containers
        self.groups = groups
        self.contactIDsByContainerID = contactIDsByContainerID
        self.contactIDsByGroupID = contactIDsByGroupID
        self.apiLimitations = apiLimitations
        self.lastSyncedAt = lastSyncedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authorizationStatusText = try container.decodeIfPresent(String.self, forKey: .authorizationStatusText) ?? "Unknown"
        contacts = try container.decodeIfPresent([ContactItem].self, forKey: .contacts) ?? []
        containers = try container.decodeIfPresent([ContactContainerSnapshot].self, forKey: .containers) ?? []
        groups = try container.decodeIfPresent([ContactGroupSnapshot].self, forKey: .groups) ?? []
        contactIDsByContainerID = try container.decodeIfPresent([String: [String]].self, forKey: .contactIDsByContainerID) ?? [:]
        contactIDsByGroupID = try container.decodeIfPresent([String: [String]].self, forKey: .contactIDsByGroupID) ?? [:]
        apiLimitations = try container.decodeIfPresent([String].self, forKey: .apiLimitations) ?? []
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
    }
}

private actor ContactsSyncWorker {
    private let store = CNContactStore()

    func scan(progress: @escaping (String?) -> Void) async throws -> ContactsNodeSnapshot {
        var limitations = [
            "Contact notes are not requested because CNContactNoteKey requires a special Apple entitlement in modern iOS builds.",
        ]
        let statusText = ContactsNode.describe(authorizationStatus: CNContactStore.authorizationStatus(for: .contacts))

        progress("Reading contact accounts...")
        let containerObjects = (try? store.containers(matching: nil)) ?? []
        let containers = containerObjects.map(ContactsNode.makeContainer)
        let groupObjects = (try? store.groups(matching: nil)) ?? []
        let groups = groupObjects.map(ContactsNode.makeGroup)

        progress("Reading all contacts...")
        let contacts = try fetchAllContacts()
        let contactsByID = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, $0) })

        progress("Reading contact memberships...")
        var contactIDsByContainerID: [String: [String]] = [:]
        for container in containers {
            if Task.isCancelled { break }
            let predicate = CNContact.predicateForContactsInContainer(withIdentifier: container.id)
            let ids = ((try? store.unifiedContacts(matching: predicate, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])) ?? [])
                .map(\.identifier)
                .filter { contactsByID[$0] != nil }
                .sorted()
            contactIDsByContainerID[container.id] = ids
        }

        var contactIDsByGroupID: [String: [String]] = [:]
        for group in groups {
            if Task.isCancelled { break }
            let predicate = CNContact.predicateForContactsInGroup(withIdentifier: group.id)
            let ids = ((try? store.unifiedContacts(matching: predicate, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])) ?? [])
                .map(\.identifier)
                .filter { contactsByID[$0] != nil }
                .sorted()
            contactIDsByGroupID[group.id] = ids
        }

        if contacts.isEmpty, ContactsNode.canReadContacts(status: CNContactStore.authorizationStatus(for: .contacts)) {
            limitations.append("Contacts permission allows reads, but the store returned zero contacts.")
        }

        return ContactsNodeSnapshot(
            authorizationStatusText: statusText,
            contacts: contacts,
            containers: containers,
            groups: groups,
            contactIDsByContainerID: contactIDsByContainerID,
            contactIDsByGroupID: contactIDsByGroupID,
            apiLimitations: Array(Set(limitations)).sorted(),
            lastSyncedAt: Date()
        )
    }

    private func fetchAllContacts() throws -> [ContactItem] {
        let request = CNContactFetchRequest(keysToFetch: ContactsNode.fetchKeys)
        request.sortOrder = .userDefault
        request.unifyResults = false
        request.mutableObjects = false

        var contacts: [ContactItem] = []
        try store.enumerateContacts(with: request) { contact, stop in
            if Task.isCancelled {
                stop.pointee = true
                return
            }
            contacts.append(ContactsNode.makeContact(contact))
        }
        return contacts.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}

/// The Contacts node captures the user's address-book graph: people,
/// organizations, relationship labels, contact methods, accounts, groups, and
/// birthdays. It does not infer anything by itself; the brain decides what is
/// taste-relevant from compact slices.
@MainActor
@Observable
final class ContactsNode {
    nonisolated static let fetchKeys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactTypeKey as CNKeyDescriptor,
        CNContactNamePrefixKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactMiddleNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactPreviousFamilyNameKey as CNKeyDescriptor,
        CNContactNameSuffixKey as CNKeyDescriptor,
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactPhoneticGivenNameKey as CNKeyDescriptor,
        CNContactPhoneticMiddleNameKey as CNKeyDescriptor,
        CNContactPhoneticFamilyNameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactPhoneticOrganizationNameKey as CNKeyDescriptor,
        CNContactDepartmentNameKey as CNKeyDescriptor,
        CNContactJobTitleKey as CNKeyDescriptor,
        CNContactBirthdayKey as CNKeyDescriptor,
        CNContactNonGregorianBirthdayKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor,
        CNContactUrlAddressesKey as CNKeyDescriptor,
        CNContactDatesKey as CNKeyDescriptor,
        CNContactRelationsKey as CNKeyDescriptor,
        CNContactSocialProfilesKey as CNKeyDescriptor,
        CNContactInstantMessageAddressesKey as CNKeyDescriptor,
        CNContactImageDataAvailableKey as CNKeyDescriptor,
        CNContactImageDataKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
    ]

    private(set) var isAuthorized = false
    private(set) var isAuthorizing = false
    private(set) var isSyncing = false
    private(set) var authorizationStatusText = "Not requested"
    private(set) var syncProgress: String?
    private(set) var lastSyncedAt: Date?
    private(set) var lastErrorMessage: String?

    private(set) var contacts: [ContactItem] = []
    private(set) var containers: [ContactContainerSnapshot] = []
    private(set) var groups: [ContactGroupSnapshot] = []
    private(set) var contactIDsByContainerID: [String: [String]] = [:]
    private(set) var contactIDsByGroupID: [String: [String]] = [:]
    private(set) var apiLimitations: [String] = []

    @ObservationIgnored private let store = CNContactStore()
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private let syncWorker = ContactsSyncWorker()
    @ObservationIgnored private let snapshotStore = SnapshotStore<ContactsNodeSnapshot>(filename: "contacts-snapshot.json")

    init() {
        loadCachedSnapshot()
        if hasRestoredSnapshot {
            isAuthorized = true
        }
    }

    var statusSummary: String {
        if isAuthorizing { return "Requesting Contacts access..." }
        if isSyncing { return syncProgress ?? "Reading Contacts..." }
        if hasContactAccess { return "Connected to Contacts" }
        if isAuthorized { return "Restored Contacts snapshot" }
        return "Contacts not connected."
    }

    func restoreSessionIfPossible() async {
        loadCachedSnapshot()
        updateAuthorizationStatus()
        isAuthorized = hasContactAccess
        if !isAuthorized, hasRestoredSnapshot {
            isAuthorized = true
        }
        if isAuthorized, !hasRestoredSnapshot {
            await syncEverything()
        }
    }

    func connect() async {
        lastErrorMessage = nil
        isAuthorizing = true
        let granted: Bool
        do {
            granted = try await store.requestAccess(for: .contacts)
        } catch {
            granted = false
            lastErrorMessage = error.localizedDescription
        }
        isAuthorizing = false
        updateAuthorizationStatus()
        isAuthorized = granted || hasContactAccess

        if isAuthorized {
            await syncEverything()
        } else if lastErrorMessage == nil {
            lastErrorMessage = "Contacts access was denied. Enable it in Settings > Privacy & Security > Contacts."
        }
    }

    func disconnect() {
        syncTask?.cancel()
        syncTask = nil
        isAuthorized = false
        isAuthorizing = false
        isSyncing = false
        syncProgress = nil
        contacts = []
        containers = []
        groups = []
        contactIDsByContainerID = [:]
        contactIDsByGroupID = [:]
        apiLimitations = []
        lastSyncedAt = nil
        snapshotStore.delete()
    }

    func syncEverything() async {
        guard isAuthorized else { return }
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
                // User cancelled or disconnected mid-scan.
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
        syncTask = task
        await task.value
    }

    private func runFullSync() async throws {
        updateAuthorizationStatus()
        guard hasContactAccess else {
            isAuthorized = hasRestoredSnapshot
            throw ContactsNodeError.notAuthorized
        }
        let snapshot = try await syncWorker.scan { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.isSyncing else { return }
                self.syncProgress = message
            }
        }
        try Task.checkCancellation()
        apply(snapshot)
        saveCachedSnapshot()
        lastErrorMessage = nil
    }

    private func loadCachedSnapshot() {
        guard let snapshot = snapshotStore.load() else { return }
        apply(snapshot)
    }

    private func apply(_ snapshot: ContactsNodeSnapshot) {
        authorizationStatusText = snapshot.authorizationStatusText
        contacts = snapshot.contacts
        containers = snapshot.containers
        groups = snapshot.groups
        contactIDsByContainerID = snapshot.contactIDsByContainerID
        contactIDsByGroupID = snapshot.contactIDsByGroupID
        apiLimitations = snapshot.apiLimitations
        lastSyncedAt = snapshot.lastSyncedAt
        if hasRestoredSnapshot {
            isAuthorized = true
        }
    }

    private func saveCachedSnapshot() {
        snapshotStore.save(
            ContactsNodeSnapshot(
                authorizationStatusText: authorizationStatusText,
                contacts: contacts,
                containers: containers,
                groups: groups,
                contactIDsByContainerID: contactIDsByContainerID,
                contactIDsByGroupID: contactIDsByGroupID,
                apiLimitations: apiLimitations,
                lastSyncedAt: lastSyncedAt
            )
        )
    }

    private var hasRestoredSnapshot: Bool {
        lastSyncedAt != nil ||
            !contacts.isEmpty ||
            !containers.isEmpty ||
            !groups.isEmpty
    }

    private var hasContactAccess: Bool {
        Self.canReadContacts(status: CNContactStore.authorizationStatus(for: .contacts))
    }

    private func updateAuthorizationStatus() {
        authorizationStatusText = Self.describe(authorizationStatus: CNContactStore.authorizationStatus(for: .contacts))
    }

    nonisolated static func makeContact(_ contact: CNContact) -> ContactItem {
        ContactItem(
            id: contact.identifier,
            contactType: describe(contactType: contact.contactType),
            namePrefix: contact.namePrefix,
            givenName: contact.givenName,
            middleName: contact.middleName,
            familyName: contact.familyName,
            previousFamilyName: contact.previousFamilyName,
            nameSuffix: contact.nameSuffix,
            nickname: contact.nickname,
            phoneticGivenName: contact.phoneticGivenName,
            phoneticMiddleName: contact.phoneticMiddleName,
            phoneticFamilyName: contact.phoneticFamilyName,
            organizationName: contact.organizationName,
            phoneticOrganizationName: contact.phoneticOrganizationName,
            departmentName: contact.departmentName,
            jobTitle: contact.jobTitle,
            birthday: contact.birthday.map(makeDateComponents),
            nonGregorianBirthday: contact.nonGregorianBirthday.map(makeDateComponents),
            phoneNumbers: labeled(contact.phoneNumbers) { $0.stringValue },
            emailAddresses: labeled(contact.emailAddresses) { String($0) },
            postalAddresses: contact.postalAddresses.enumerated().map { index, value in
                let address = value.value
                return ContactPostalAddressSnapshot(
                    id: "\(index)|\(value.label ?? "")|\(address.street)|\(address.city)",
                    label: value.label,
                    localizedLabel: localizedLabel(value.label),
                    street: address.street,
                    subLocality: address.subLocality,
                    city: address.city,
                    subAdministrativeArea: address.subAdministrativeArea,
                    state: address.state,
                    postalCode: address.postalCode,
                    country: address.country,
                    isoCountryCode: address.isoCountryCode
                )
            },
            urlAddresses: labeled(contact.urlAddresses) { String($0) },
            dates: contact.dates.enumerated().map { index, value in
                ContactLabeledDate(
                    id: "\(index)|\(value.label ?? "")|\(value.value)",
                    label: value.label,
                    localizedLabel: localizedLabel(value.label),
                    value: makeDateComponents(value.value as DateComponents)
                )
            },
            contactRelations: contact.contactRelations.enumerated().map { index, value in
                ContactRelationSnapshot(
                    id: "\(index)|\(value.label ?? "")|\(value.value.name)",
                    label: value.label,
                    localizedLabel: localizedLabel(value.label),
                    name: value.value.name
                )
            },
            socialProfiles: contact.socialProfiles.enumerated().map { index, value in
                ContactSocialProfileSnapshot(
                    id: "\(index)|\(value.label ?? "")|\(value.value.service)|\(value.value.username)",
                    label: value.label,
                    localizedLabel: localizedLabel(value.label),
                    urlString: value.value.urlString,
                    username: value.value.username,
                    userIdentifier: value.value.userIdentifier,
                    service: value.value.service
                )
            },
            instantMessageAddresses: contact.instantMessageAddresses.enumerated().map { index, value in
                ContactInstantMessageSnapshot(
                    id: "\(index)|\(value.label ?? "")|\(value.value.service)|\(value.value.username)",
                    label: value.label,
                    localizedLabel: localizedLabel(value.label),
                    username: value.value.username,
                    service: value.value.service
                )
            },
            image: ContactImageSnapshot(
                imageDataAvailable: contact.imageDataAvailable,
                imageData: contact.imageData,
                thumbnailImageData: contact.thumbnailImageData
            )
        )
    }

    nonisolated static func makeContainer(_ container: CNContainer) -> ContactContainerSnapshot {
        ContactContainerSnapshot(
            id: container.identifier,
            name: container.name,
            type: describe(containerType: container.type)
        )
    }

    nonisolated static func makeGroup(_ group: CNGroup) -> ContactGroupSnapshot {
        ContactGroupSnapshot(id: group.identifier, name: group.name)
    }

    nonisolated static func describe(authorizationStatus: CNAuthorizationStatus) -> String {
        switch authorizationStatus {
        case .notDetermined: return "Not requested"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .limited: return "Limited"
        @unknown default: return "Unknown"
        }
    }

    nonisolated static func canReadContacts(status: CNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .limited:
            return true
        default:
            return false
        }
    }

    private nonisolated static func describe(contactType: CNContactType) -> String {
        switch contactType {
        case .person: return "Person"
        case .organization: return "Organization"
        @unknown default: return "Unknown"
        }
    }

    private nonisolated static func describe(containerType: CNContainerType) -> String {
        switch containerType {
        case .local: return "Local"
        case .exchange: return "Exchange"
        case .cardDAV: return "CardDAV"
        case .unassigned: return "Unassigned"
        @unknown default: return "Unknown"
        }
    }

    private nonisolated static func makeDateComponents(_ components: DateComponents) -> ContactDateComponentsSnapshot {
        ContactDateComponentsSnapshot(
            calendarIdentifier: components.calendar.map { "\($0.identifier)" },
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

    private nonisolated static func localizedLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        return CNLabeledValue<NSString>.localizedString(forLabel: label)
    }

    private nonisolated static func labeled<Value>(_ values: [CNLabeledValue<Value>], transform: (Value) -> String) -> [ContactLabeledString] {
        values.enumerated().map { index, item in
            let value = transform(item.value)
            return ContactLabeledString(
                id: "\(index)|\(item.label ?? "")|\(value)",
                label: item.label,
                localizedLabel: localizedLabel(item.label),
                value: value
            )
        }
    }
}

private enum ContactsNodeError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Contacts access is not authorized."
        }
    }
}
