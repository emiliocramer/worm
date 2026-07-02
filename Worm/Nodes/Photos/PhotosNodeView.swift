import SwiftUI

/// Surfaces the Photos node: connect/disconnect, scan status, and a readout of
/// everything the node has pulled into memory — aggregate stats, albums, and
/// every photo with its complete captured metadata.
struct PhotosNodeView: View {
    @Environment(PhotosNode.self) private var node

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
        .navigationTitle("Photos")
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

    // MARK: Sections

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
                Label("Connect Photos", systemImage: "photo.on.rectangle.angled")
            }
            .disabled(node.isAuthorizing)
        } footer: {
            Text("Connecting grants read access to your photo library. Worm captures every available detail of each photo — dates, location, dimensions, file resources, and full embedded EXIF/GPS metadata.")
        }
    }

    private var snapshotSection: some View {
        Section("Snapshot") {
            metric("Photos & videos", node.photos.count)
            metric("With location", node.photos.lazy.filter { $0.latitude != nil }.count)
            metric("Favorites", node.photos.lazy.filter { $0.isFavorite }.count)
            metric("Hidden", node.photos.lazy.filter { $0.isHidden }.count)
            metric("Edited", node.photos.lazy.filter { $0.hasAdjustments }.count)
            metric("With recognized text", node.photos.lazy.filter { !$0.recognizedText.isEmpty }.count)
            metric("With faces", node.photos.lazy.filter { $0.faceCount > 0 }.count)
            metric("Videos with AV metadata", node.photos.lazy.filter { $0.video != nil }.count)
            metric("Video tracks", node.photos.lazy.compactMap { $0.video?.tracks.count }.reduce(0, +))
            metric("Albums", node.albums.count)
            labelled("Total size", formattedTotalSize)
        }
    }

    private var accountSection: some View {
        Section("Access") {
            labelled("Authorization", node.authorizationStatusText)
            labelled("Limited selection", node.isLimited ? "Yes" : "No")
        }
    }

    @ViewBuilder
    private var granularSections: some View {
        if !node.photos.isEmpty {
            Section {
                NavigationLink("All photos (\(node.photos.count))") {
                    PhotoListView(photos: node.photos)
                }
            }
        }

        if !node.albums.isEmpty {
            Section {
                NavigationLink("Albums (\(node.albums.count))") {
                    List(node.albums) { album in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(album.title)
                            Text("\(album.type) · \(album.subtype)\(album.estimatedAssetCount >= 0 ? " · ~\(album.estimatedAssetCount)" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                            if !album.locationNames.isEmpty {
                                Text(album.locationNames.joined(separator: ", "))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .navigationTitle("Albums")
                }
            }
        }

        Section {
            Button("Disconnect", role: .destructive) { node.disconnect() }
        }
    }

    // MARK: Helpers

    private var formattedTotalSize: String {
        let total = node.photos.compactMap { $0.totalFileSizeBytes }.reduce(Int64(0), +)
        guard total > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
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
}

/// A scrollable list of every captured photo. Lazily paginates so a library of
/// tens of thousands of items stays responsive.
private struct PhotoListView: View {
    let photos: [PhotoItem]
    @State private var visibleCount = 200

    var body: some View {
        List {
            ForEach(photos.prefix(visibleCount)) { photo in
                NavigationLink {
                    PhotoDetailView(photo: photo)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(photo.originalFilename ?? photo.id)
                            .lineLimit(1)
                        Text(subtitle(for: photo))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if visibleCount < photos.count {
                Button("Load more (\(photos.count - visibleCount) remaining)") {
                    visibleCount += 200
                }
            }
        }
        .navigationTitle("All photos")
    }

    private func subtitle(for photo: PhotoItem) -> String {
        var parts: [String] = [photo.mediaType]
        if let date = photo.creationDate {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        parts.append("\(photo.pixelWidth)×\(photo.pixelHeight)")
        if photo.latitude != nil { parts.append("📍") }
        return parts.joined(separator: " · ")
    }
}

/// The complete captured detail of a single photo, including every flattened
/// embedded-metadata key/value pair.
private struct PhotoDetailView: View {
    let photo: PhotoItem

    var body: some View {
        List {
            Section("Asset") {
                row("Filename", photo.originalFilename)
                row("Identifier", photo.id)
                row("Media type", photo.mediaType)
                if !photo.mediaSubtypes.isEmpty { row("Subtypes", photo.mediaSubtypes.joined(separator: ", ")) }
                row("Dimensions", "\(photo.pixelWidth)×\(photo.pixelHeight)")
                if photo.duration > 0 { row("Duration", String(format: "%.2fs", photo.duration)) }
                row("Playback style", photo.playbackStyle)
                row("Source", photo.sourceType)
                row("UTI", photo.uniformTypeIdentifier)
                row("Created", photo.creationDate?.formatted(date: .long, time: .standard))
                row("Modified", photo.modificationDate?.formatted(date: .long, time: .standard))
                row("Favorite", photo.isFavorite ? "Yes" : "No")
                row("Hidden", photo.isHidden ? "Yes" : "No")
                row("Edited", photo.hasAdjustments ? "Yes" : "No")
                if photo.representsBurst {
                    row("Burst", photo.burstIdentifier)
                    if !photo.burstSelectionTypes.isEmpty { row("Burst pick", photo.burstSelectionTypes.joined(separator: ", ")) }
                }
                if let size = photo.totalFileSizeBytes {
                    row("File size", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                }
            }

            if photo.latitude != nil {
                Section("Location") {
                    row("Latitude", photo.latitude.map { String($0) })
                    row("Longitude", photo.longitude.map { String($0) })
                    row("Altitude", photo.altitude.map { String(format: "%.1f m", $0) })
                    row("H. accuracy", photo.horizontalAccuracy.map { String(format: "%.1f m", $0) })
                    row("V. accuracy", photo.verticalAccuracy.map { String(format: "%.1f m", $0) })
                    row("Speed", photo.speed.map { String(format: "%.1f m/s", $0) })
                    row("Course", photo.course.map { String(format: "%.0f°", $0) })
                    row("Fix time", photo.locationTimestamp?.formatted(date: .abbreviated, time: .standard))
                }
            }

            if !photo.resources.isEmpty {
                Section("Resources (\(photo.resources.count))") {
                    ForEach(photo.resources, id: \.self) { resource in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(resource.type).font(.subheadline)
                            Text(resource.originalFilename).font(.caption).foregroundStyle(.secondary)
                            Text(resource.uniformTypeIdentifier).font(.caption2).foregroundStyle(.secondary)
                            if let size = resource.fileSizeBytes {
                                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !photo.classifications.isEmpty {
                Section("Scene & objects (\(photo.classifications.count))") {
                    Text(photo.classifications.joined(separator: " · "))
                        .font(.callout)
                }
            }

            if !photo.recognizedText.isEmpty {
                Section("Text in image (\(photo.recognizedText.count))") {
                    ForEach(Array(photo.recognizedText.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.callout)
                    }
                }
            }

            if photo.faceCount > 0 {
                Section("People") {
                    row("Faces detected", "\(photo.faceCount)")
                }
            }

            if let video = photo.video {
                Section("Video") {
                    row("Playable", video.isPlayable ? "Yes" : "No")
                    row("Exportable", video.isExportable ? "Yes" : "No")
                    row("Readable", video.isReadable ? "Yes" : "No")
                    row("Precise timing", video.providesPreciseDurationAndTiming ? "Yes" : "No")
                    row("Protected content", video.hasProtectedContent ? "Yes" : "No")
                    row("Duration", video.duration.map { String(format: "%.2fs", $0) })
                    row("Preferred rate", String(video.preferredRate))
                    row("Preferred volume", String(video.preferredVolume))
                    row("Metadata formats", video.availableMetadataFormats.joined(separator: ", "))
                    row("Chapter locales", video.availableChapterLocales.joined(separator: ", "))
                    row("Selectable characteristics", video.availableMediaCharacteristicsWithMediaSelectionOptions.joined(separator: ", "))
                }

                if !video.tracks.isEmpty {
                    Section("Video tracks (\(video.tracks.count))") {
                        ForEach(video.tracks, id: \.self) { track in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(track.mediaType) track \(track.id)")
                                    .font(.subheadline)
                                Text(videoTrackSubtitle(track))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !track.mediaCharacteristics.isEmpty {
                                    Text(track.mediaCharacteristics.joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !video.metadata.isEmpty {
                    Section("Video metadata (\(video.metadata.count))") {
                        ForEach(video.metadata.keys.sorted(), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key).font(.caption).foregroundStyle(.secondary)
                                Text(video.metadata[key] ?? "").font(.callout)
                            }
                        }
                    }
                }

                if !video.requestInfo.isEmpty {
                    Section("Video request info") {
                        ForEach(video.requestInfo.keys.sorted(), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key).font(.caption).foregroundStyle(.secondary)
                                Text(video.requestInfo[key] ?? "").font(.callout)
                            }
                        }
                    }
                }
            }

            if !photo.metadata.isEmpty {
                Section("Embedded metadata (\(photo.metadata.count))") {
                    ForEach(photo.metadata.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key).font(.caption).foregroundStyle(.secondary)
                            Text(photo.metadata[key] ?? "").font(.callout)
                        }
                    }
                }
            }
        }
        .navigationTitle(photo.originalFilename ?? "Photo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func videoTrackSubtitle(_ track: PhotoVideoTrack) -> String {
        var parts: [String] = []
        if let width = track.naturalWidth, let height = track.naturalHeight {
            parts.append("\(Int(width))x\(Int(height))")
        }
        if let duration = track.duration {
            parts.append(String(format: "%.2fs", duration))
        }
        if track.estimatedDataRate > 0 {
            parts.append(String(format: "%.0f kbps", track.estimatedDataRate / 1_000))
        }
        if let frameRate = track.nominalFrameRate {
            parts.append(String(format: "%.2f fps", frameRate))
        }
        if let language = track.extendedLanguageTag ?? track.languageCode {
            parts.append(language)
        }
        if !track.formatDescriptions.isEmpty {
            parts.append(track.formatDescriptions.map { $0.mediaSubType }.joined(separator: ", "))
        }
        return parts.isEmpty ? "Track" : parts.joined(separator: " | ")
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
}

#Preview {
    NavigationStack {
        PhotosNodeView()
    }
    .environment(PhotosNode())
}
