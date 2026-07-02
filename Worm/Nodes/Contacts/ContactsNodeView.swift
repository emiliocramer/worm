import SwiftUI

struct ContactsNodeView: View {
    @Environment(ContactsNode.self) private var node

    var body: some View {
        List {
            statusSection

            if node.isAuthorized {
                snapshotSection
                accountSection
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
        .navigationTitle("Contacts")
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
                Label("Connect Contacts", systemImage: "person.2")
            }
            .disabled(node.isAuthorizing)
        } footer: {
            Text("Connect Contacts to add social context, relationship labels, birthdays, organizations, and communication surfaces to the taste graph.")
        }
    }

    private var snapshotSection: some View {
        Section("Snapshot") {
            metric("Contacts", node.contacts.count)
            metric("Accounts", node.containers.count)
            metric("Groups", node.groups.count)
            metric("Phones", node.contacts.reduce(0) { $0 + $1.phoneNumbers.count })
            metric("Emails", node.contacts.reduce(0) { $0 + $1.emailAddresses.count })
            metric("Postal addresses", node.contacts.reduce(0) { $0 + $1.postalAddresses.count })
            metric("URLs", node.contacts.reduce(0) { $0 + $1.urlAddresses.count })
            metric("Dates", node.contacts.reduce(0) { $0 + $1.dates.count })
            metric("Relations", node.contacts.reduce(0) { $0 + $1.contactRelations.count })
            metric("Social profiles", node.contacts.reduce(0) { $0 + $1.socialProfiles.count })
            metric("IM addresses", node.contacts.reduce(0) { $0 + $1.instantMessageAddresses.count })
            metric("Images", node.contacts.lazy.filter(\.image.imageDataAvailable).count)
        }
    }

    private var accountSection: some View {
        Section("Account") {
            labelled("Authorization", node.authorizationStatusText)
            if !node.apiLimitations.isEmpty {
                NavigationLink("API limitations / misses (\(node.apiLimitations.count))") {
                    List(node.apiLimitations, id: \.self) { Text($0) }
                        .navigationTitle("Contacts Notes")
                }
            }
        }
    }

    @ViewBuilder
    private var granularSections: some View {
        if !node.containers.isEmpty {
            Section {
                NavigationLink("Accounts (\(node.containers.count))") {
                    List(node.containers) { container in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(container.name)
                            Text(containerSubtitle(container))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Accounts")
                }
            }
        }

        if !node.groups.isEmpty {
            Section {
                NavigationLink("Groups (\(node.groups.count))") {
                    List(node.groups) { group in
                        HStack {
                            Text(group.name)
                            Spacer()
                            Text("\(node.contactIDsByGroupID[group.id]?.count ?? 0)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .navigationTitle("Groups")
                }
            }
        }

        if !node.contacts.isEmpty {
            Section {
                NavigationLink("Contacts (\(node.contacts.count))") {
                    List(node.contacts) { contact in
                        NavigationLink {
                            ContactDetailSnapshotView(contact: contact)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.displayName)
                                Text(contactSubtitle(contact))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .navigationTitle("Contacts")
                }
            }
        }

        Section {
            Button("Disconnect", role: .destructive) { node.disconnect() }
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
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func containerSubtitle(_ container: ContactContainerSnapshot) -> String {
        let count = node.contactIDsByContainerID[container.id]?.count ?? 0
        return "\(container.type) | \(count) contacts"
    }

    private func contactSubtitle(_ contact: ContactItem) -> String {
        var parts: [String] = []
        if !contact.organizationName.isEmpty { parts.append(contact.organizationName) }
        if !contact.jobTitle.isEmpty { parts.append(contact.jobTitle) }
        if !contact.nickname.isEmpty { parts.append(contact.nickname) }
        let methods = contact.phoneNumbers.count
            + contact.emailAddresses.count
            + contact.urlAddresses.count
            + contact.socialProfiles.count
            + contact.instantMessageAddresses.count
        if methods > 0 { parts.append("\(methods) methods") }
        if !contact.contactRelations.isEmpty { parts.append("\(contact.contactRelations.count) relations") }
        return parts.isEmpty ? contact.contactType : parts.joined(separator: " | ")
    }
}

private struct ContactDetailSnapshotView: View {
    let contact: ContactItem

    var body: some View {
        List {
            Section("Identity") {
                labelled("Type", contact.contactType)
                labelled("Name", contact.displayName)
                labelled("Prefix", contact.namePrefix)
                labelled("Suffix", contact.nameSuffix)
                labelled("Nickname", contact.nickname)
                labelled("Organization", contact.organizationName)
                labelled("Department", contact.departmentName)
                labelled("Job title", contact.jobTitle)
            }

            labeledStringSection("Phones", contact.phoneNumbers)
            labeledStringSection("Emails", contact.emailAddresses)
            labeledStringSection("URLs", contact.urlAddresses)

            if !contact.postalAddresses.isEmpty {
                Section("Postal Addresses") {
                    ForEach(contact.postalAddresses) { address in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(address.localizedLabel ?? address.label ?? "Address")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(addressLine(address))
                        }
                    }
                }
            }

            if !contact.contactRelations.isEmpty {
                Section("Relations") {
                    ForEach(contact.contactRelations) { relation in
                        labelled(relation.localizedLabel ?? relation.label ?? "Relation", relation.name)
                    }
                }
            }

            if !contact.socialProfiles.isEmpty {
                Section("Social Profiles") {
                    ForEach(contact.socialProfiles) { profile in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.localizedLabel ?? profile.label ?? profile.service ?? "Social")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text([profile.service, profile.username].compactMap { $0 }.joined(separator: " | "))
                            if let url = profile.urlString, !url.isEmpty {
                                Text(url).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !contact.instantMessageAddresses.isEmpty {
                Section("Instant Message") {
                    ForEach(contact.instantMessageAddresses) { item in
                        labelled(item.localizedLabel ?? item.label ?? item.service, item.username)
                    }
                }
            }

            if contact.birthday != nil || contact.nonGregorianBirthday != nil || !contact.dates.isEmpty {
                Section("Dates") {
                    if let birthday = contact.birthday {
                        labelled("Birthday", dateLine(birthday))
                    }
                    if let birthday = contact.nonGregorianBirthday {
                        labelled("Non-Gregorian birthday", dateLine(birthday))
                    }
                    ForEach(contact.dates) { date in
                        labelled(date.localizedLabel ?? date.label ?? "Date", dateLine(date.value))
                    }
                }
            }

            Section("Images") {
                labelled("Image available", contact.image.imageDataAvailable ? "Yes" : "No")
                labelled("Image bytes", "\(contact.image.imageBytes)")
                labelled("Thumbnail bytes", "\(contact.image.thumbnailBytes)")
            }
        }
        .navigationTitle(contact.displayName)
    }

    @ViewBuilder
    private func labeledStringSection(_ title: String, _ values: [ContactLabeledString]) -> some View {
        if !values.isEmpty {
            Section(title) {
                ForEach(values) { item in
                    labelled(item.localizedLabel ?? item.label ?? title, item.value)
                }
            }
        }
    }

    private func labelled(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "Empty" : value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func addressLine(_ address: ContactPostalAddressSnapshot) -> String {
        [
            address.street,
            address.subLocality,
            address.city,
            address.subAdministrativeArea,
            address.state,
            address.postalCode,
            address.country,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    private func dateLine(_ date: ContactDateComponentsSnapshot) -> String {
        if let resolvedDate = date.resolvedDate {
            return resolvedDate.formatted(date: .abbreviated, time: .omitted)
        }
        return [
            date.year.map { "\($0)" },
            date.month.map { "\($0)" },
            date.day.map { "\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: "-")
    }
}

#Preview {
    NavigationStack {
        ContactsNodeView()
    }
    .environment(ContactsNode())
}
