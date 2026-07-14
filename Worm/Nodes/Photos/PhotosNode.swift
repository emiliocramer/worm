import AVFoundation
import CoreLocation
import Foundation
import ImageIO
import Observation
import Photos
import Vision

// MARK: - Lightweight in-memory models

/// One resource backing a photo/video (original, edited render, adjustment
/// data, paired live-photo movie, etc.). A single asset can have several.
struct PhotoResource: Hashable, Codable {
    let type: String
    let uniformTypeIdentifier: String
    let originalFilename: String
    let fileSizeBytes: Int64?
    let pixelWidth: Int?
    let pixelHeight: Int?
}

struct PhotoAffineTransform: Hashable, Codable {
    let a: Double
    let b: Double
    let c: Double
    let d: Double
    let tx: Double
    let ty: Double
}

struct PhotoVideoFormatDescription: Hashable, Codable {
    let mediaType: String
    let mediaSubType: String
    let videoWidth: Int?
    let videoHeight: Int?
    let audioSampleRate: Double?
    let audioChannelCount: UInt32?
    let audioBitsPerChannel: UInt32?
    let audioFramesPerPacket: UInt32?
    let extensions: [String: String]
}

struct PhotoVideoTrack: Hashable, Codable {
    let id: Int32
    let mediaType: String
    let isPlayable: Bool
    let isDecodable: Bool
    let isEnabled: Bool
    let isSelfContained: Bool
    let totalSampleDataLength: Int64
    let startTime: Double?
    let duration: Double?
    let naturalTimeScale: Int32
    let estimatedDataRate: Float
    let languageCode: String?
    let extendedLanguageTag: String?
    let naturalWidth: Double?
    let naturalHeight: Double?
    let preferredTransform: PhotoAffineTransform?
    let preferredVolume: Float?
    let nominalFrameRate: Float?
    let minFrameDuration: Double?
    let requiresFrameReordering: Bool?
    let mediaCharacteristics: [String]
    let formatDescriptions: [PhotoVideoFormatDescription]
    let metadata: [String: String]
}

struct PhotoVideoAnalysis: Hashable, Codable {
    let duration: Double?
    let preferredRate: Float
    let preferredVolume: Float
    let preferredTransform: PhotoAffineTransform
    let providesPreciseDurationAndTiming: Bool
    let isPlayable: Bool
    let isExportable: Bool
    let isReadable: Bool
    let isComposable: Bool
    let isCompatibleWithSavedPhotosAlbum: Bool
    let isCompatibleWithAirPlayVideo: Bool
    let hasProtectedContent: Bool
    let canContainFragments: Bool
    let containsFragments: Bool
    let availableMetadataFormats: [String]
    let availableChapterLocales: [String]
    let availableMediaCharacteristicsWithMediaSelectionOptions: [String]
    let metadata: [String: String]
    let tracks: [PhotoVideoTrack]
    let requestInfo: [String: String]
}

/// Everything the Photos framework will tell us about a single asset.
///
/// The structured fields cover the full `PHAsset` surface plus location and
/// resources; `metadata` is the complete embedded image metadata (EXIF, TIFF,
/// GPS, IPTC, maker notes, …) flattened to dotted keys so nothing is dropped.
struct PhotoItem: Identifiable, Hashable, Codable {
    let id: String                  // PHAsset.localIdentifier

    // Core asset
    let mediaType: String
    let mediaSubtypes: [String]
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let modificationDate: Date?
    let duration: Double
    let isFavorite: Bool
    let isHidden: Bool
    let sourceType: String
    let playbackStyle: String
    let representsBurst: Bool
    let burstIdentifier: String?
    let burstSelectionTypes: [String]
    let hasAdjustments: Bool

    // Location (from PHAsset.location)
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let horizontalAccuracy: Double?
    let verticalAccuracy: Double?
    let speed: Double?
    let course: Double?
    let locationTimestamp: Date?

    // Files
    let originalFilename: String?
    let uniformTypeIdentifier: String?
    let totalFileSizeBytes: Int64?
    let resources: [PhotoResource]

    // Complete embedded image metadata, flattened (e.g. "Exif.FNumber",
    // "GPS.Altitude", "TIFF.Model", "IPTC.Keywords").
    let metadata: [String: String]
    let video: PhotoVideoAnalysis?

    // On-device Vision analysis — the same kind of scene/object understanding
    // that powers the Photos app's content search ("lamp", "beach", "dog").
    let classifications: [String]   // e.g. "lamp (84%)", "indoor", "furniture"
    let recognizedText: [String]    // text read out of the image (OCR)
    let faceCount: Int              // detected faces
}

/// An album or smart album the library exposes.
struct PhotoAlbum: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let type: String
    let subtype: String
    let estimatedAssetCount: Int
    let startDate: Date?
    let endDate: Date?
    let locationNames: [String]
}

/// The full in-memory state of the Photos node, persisted to disk so a
/// returning user sees their data instantly instead of re-scanning the library.
struct PhotosNodeSnapshot: Codable {
    let accessLevelText: String
    let isLimited: Bool
    let photos: [PhotoItem]
    let albums: [PhotoAlbum]
    let lastSyncedAt: Date?
}

private let photosAnalysisQueue = DispatchQueue(label: "com.shibuya.worm.photos.analysis", qos: .utility)

private struct PhotoScanResult {
    let albums: [PhotoAlbum]
    let photos: [PhotoItem]
}

private actor PhotosAnalysisWorker {
    private let progressInterval = 25

    func scan(maxAssets: Int, progress: @escaping (Int, Int) -> Void) async throws -> PhotoScanResult {
        let albums = PhotosNode.fetchAlbums()
        let assets = PhotosNode.fetchAllAssets(maxAssets: maxAssets)
        let total = assets.count
        progress(0, total)

        var collected: [PhotoItem] = []
        collected.reserveCapacity(total)

        for (index, asset) in assets.enumerated() {
            try Task.checkCancellation()

            let analysis = await PhotosNode.analyze(asset)
            try Task.checkCancellation()
            collected.append(PhotosNode.makeItem(from: asset, analysis: analysis))

            let completed = index + 1
            if completed.isMultiple(of: progressInterval) || completed == total {
                progress(completed, total)
                await Task.yield()
            }
        }

        return PhotoScanResult(albums: albums, photos: collected)
    }
}

/// The Photos node — a personality node built on the Photos framework.
///
/// After the user grants photo-library access, it pulls the most complete
/// possible picture of every asset in the library: every `PHAsset` property,
/// full location, all backing resources with file sizes, album membership, and
/// the complete embedded EXIF/TIFF/GPS/IPTC metadata read from each photo's
/// image data. The result is persisted so the node never has to reconnect.
@MainActor
@Observable
final class PhotosNode {
    private static let maxAssets = 100_000

    // MARK: Observable state

    private(set) var isAuthorized = false
    private(set) var isAuthorizing = false
    private(set) var isSyncing = false
    private(set) var isLimited = false
    private(set) var authorizationStatusText = "Not requested"
    private(set) var syncProgress: String?
    private(set) var lastSyncedAt: Date?
    private(set) var lastErrorMessage: String?

    // The full in-memory snapshot.
    private(set) var photos: [PhotoItem] = []
    private(set) var albums: [PhotoAlbum] = []

    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private let analysisWorker = PhotosAnalysisWorker()
    @ObservationIgnored private let snapshotStore = SnapshotStore<PhotosNodeSnapshot>(filename: "photos-snapshot.json")

    init() {
        loadCachedSnapshot()
        if hasRestoredSnapshot {
            isAuthorized = true
        }
    }

    var statusSummary: String {
        if isAuthorizing { return "Requesting photo access…" }
        if isSyncing { return syncProgress ?? "Reading your photo library…" }
        if isAuthorized { return isLimited ? "Connected to Photos (limited selection)" : "Connected to Photos" }
        return "Photos not connected."
    }

    // MARK: - Lifecycle

    func restoreSessionIfPossible() async {
        // Show the last scanned snapshot immediately so a returning user sees
        // their data without waiting for a re-scan.
        loadCachedSnapshot()
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        updateAuthStatusText(status)
        if status == .authorized || status == .limited {
            isAuthorized = true
            isLimited = (status == .limited)
            // Only auto-scan the first time. Once a snapshot exists the node
            // stays set up and shows saved data instantly; rescanning is a
            // manual choice via the refresh button.
            if !hasRestoredSnapshot {
                await syncEverything()
            }
        } else if hasRestoredSnapshot {
            isAuthorized = true
        }
    }

    private func loadCachedSnapshot() {
        guard let snapshot = snapshotStore.load() else { return }
        authorizationStatusText = snapshot.accessLevelText
        isLimited = snapshot.isLimited
        photos = snapshot.photos
        albums = snapshot.albums
        lastSyncedAt = snapshot.lastSyncedAt
        if hasRestoredSnapshot {
            isAuthorized = true
        }
    }

    private var hasRestoredSnapshot: Bool {
        lastSyncedAt != nil || !photos.isEmpty || !albums.isEmpty
    }

    private func saveCachedSnapshot() {
        snapshotStore.save(
            PhotosNodeSnapshot(
                accessLevelText: authorizationStatusText,
                isLimited: isLimited,
                photos: photos,
                albums: albums,
                lastSyncedAt: lastSyncedAt
            )
        )
    }

    func connect() async {
        if await requestAccess() { await syncEverything() }
    }

    /// Request photo authorization only, without the follow-on sync. Returns
    /// whether the node ended up authorized. The feed flow uses this so the
    /// heavy sync can run in the background instead of blocking the UI;
    /// `connect()` = this + `syncEverything()`.
    @discardableResult
    func requestAccess() async -> Bool {
        lastErrorMessage = nil
        isAuthorizing = true
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        updateAuthStatusText(status)
        isAuthorizing = false

        switch status {
        case .authorized, .limited:
            isAuthorized = true
            isLimited = (status == .limited)
            return true
        case .denied:
            lastErrorMessage = "Photo access was denied. Enable it in Settings › Privacy & Security › Photos."
        case .restricted:
            lastErrorMessage = "Photo access is restricted on this device."
        case .notDetermined:
            lastErrorMessage = "Photo access was not determined."
        @unknown default:
            lastErrorMessage = "Unknown photo authorization status."
        }
        return false
    }

    /// Photo-library authorization can only be revoked from iOS Settings, so
    /// this clears the in-memory snapshot and resets connection state.
    func disconnect() {
        syncTask?.cancel()
        syncTask = nil
        isAuthorized = false
        isSyncing = false
        isLimited = false
        syncProgress = nil
        photos = []
        albums = []
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

    // MARK: - Full scan

    private func runFullSync() async throws {
        lastErrorMessage = nil

        report("Preparing photo scan…")
        let maxAssets = Self.maxAssets
        let result = try await analysisWorker.scan(maxAssets: maxAssets) { [weak self] completed, total in
            Task { @MainActor [weak self] in
                guard let self, self.isSyncing else { return }
                if total == 0 {
                    self.report("No local photos found.")
                } else if completed == 0 {
                    self.report("Queued \(total) photos for analysis…")
                } else {
                    self.report("Analyzing photo \(completed) of \(total)…")
                }
            }
        }

        albums = result.albums
        photos = result.photos
        lastSyncedAt = Date()
        saveCachedSnapshot()
        report(nil)
    }

    // MARK: - Asset fetching

    fileprivate nonisolated static func fetchAllAssets(maxAssets: Int) -> [PHAsset] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        options.includeAllBurstAssets = true
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: options)

        var assets: [PHAsset] = []
        assets.reserveCapacity(min(result.count, maxAssets))
        result.enumerateObjects { asset, index, stop in
            assets.append(asset)
            if assets.count >= maxAssets { stop.pointee = true }
        }
        return assets
    }

    fileprivate nonisolated static func fetchAlbums() -> [PhotoAlbum] {
        var out: [PhotoAlbum] = []
        let collect: (PHFetchResult<PHAssetCollection>) -> Void = { result in
            result.enumerateObjects { collection, _, _ in
                out.append(
                    PhotoAlbum(
                        id: collection.localIdentifier,
                        title: collection.localizedTitle ?? "Untitled",
                        type: Self.describe(collectionType: collection.assetCollectionType),
                        subtype: Self.describe(collectionSubtype: collection.assetCollectionSubtype),
                        estimatedAssetCount: collection.estimatedAssetCount == NSNotFound ? -1 : collection.estimatedAssetCount,
                        startDate: collection.startDate,
                        endDate: collection.endDate,
                        locationNames: collection.localizedLocationNames
                    )
                )
            }
        }
        collect(PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil))
        collect(PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil))
        return out
    }

    // MARK: - Per-asset mapping

    fileprivate nonisolated static func makeItem(from asset: PHAsset, analysis: AssetAnalysis) -> PhotoItem {
        let resources = PHAssetResource.assetResources(for: asset)
        let resourceModels = resources.map { resource -> PhotoResource in
            PhotoResource(
                type: describe(resourceType: resource.type),
                uniformTypeIdentifier: resource.uniformTypeIdentifier,
                originalFilename: resource.originalFilename,
                fileSizeBytes: (resource.value(forKey: "fileSize") as? Int64),
                pixelWidth: (resource.value(forKey: "pixelWidth") as? Int),
                pixelHeight: (resource.value(forKey: "pixelHeight") as? Int)
            )
        }
        let totalSize = resourceModels.compactMap { $0.fileSizeBytes }.reduce(0, +)
        let location = asset.location

        return PhotoItem(
            id: asset.localIdentifier,
            mediaType: describe(mediaType: asset.mediaType),
            mediaSubtypes: describe(mediaSubtypes: asset.mediaSubtypes),
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            duration: asset.duration,
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden,
            sourceType: describe(sourceType: asset.sourceType),
            playbackStyle: describe(playbackStyle: asset.playbackStyle),
            representsBurst: asset.representsBurst,
            burstIdentifier: asset.burstIdentifier,
            burstSelectionTypes: describe(burstSelectionTypes: asset.burstSelectionTypes),
            hasAdjustments: resources.contains { $0.type == .adjustmentData },
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            altitude: location?.altitude,
            horizontalAccuracy: location?.horizontalAccuracy,
            verticalAccuracy: location?.verticalAccuracy,
            speed: location.map { $0.speed >= 0 ? $0.speed : nil } ?? nil,
            course: location.map { $0.course >= 0 ? $0.course : nil } ?? nil,
            locationTimestamp: location?.timestamp,
            originalFilename: resources.first?.originalFilename,
            uniformTypeIdentifier: resources.first?.uniformTypeIdentifier,
            totalFileSizeBytes: totalSize > 0 ? totalSize : nil,
            resources: resourceModels,
            metadata: analysis.metadata,
            video: analysis.video,
            classifications: analysis.classifications,
            recognizedText: analysis.recognizedText,
            faceCount: analysis.faceCount
        )
    }

    // MARK: - Analysis (embedded metadata + Vision)

    /// Everything we squeeze out of a single asset's image data in one pass.
    fileprivate struct AssetAnalysis {
        var metadata: [String: String] = [:]
        var video: PhotoVideoAnalysis?
        var classifications: [String] = []
        var recognizedText: [String] = []
        var faceCount: Int = 0
    }

    /// Reads one asset's local backing data and extracts everything allowed by
    /// Photos without triggering iCloud downloads.
    fileprivate nonisolated static func analyze(_ asset: PHAsset) async -> AssetAnalysis {
        switch asset.mediaType {
        case .image:
            return await analyzeImage(asset)
        case .video:
            return await analyzeVideo(asset)
        default:
            return AssetAnalysis()
        }
    }

    /// Reads one asset's original image data once and extracts everything from
    /// it: the complete embedded metadata (ImageIO) plus on-device Vision
    /// understanding, scene/object classifications, recognized text, and face
    /// count.
    fileprivate nonisolated static func analyzeImage(_ asset: PHAsset) async -> AssetAnalysis {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.version = .original

        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, orientation, _ in
                if resumed { return }
                resumed = true
                photosAnalysisQueue.async {
                    let analysis = autoreleasepool {
                        Self.analyzeData(data, orientation: orientation)
                    }
                    continuation.resume(returning: analysis)
                }
            }
        }
    }

    /// Reads the local AVAsset for a video and captures container metadata,
    /// per-format metadata, and every track's media properties.
    fileprivate nonisolated static func analyzeVideo(_ asset: PHAsset) async -> AssetAnalysis {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.version = .original

        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if resumed { return }
                resumed = true
                photosAnalysisQueue.async {
                    let analysis = autoreleasepool {
                        var analysis = AssetAnalysis()
                        analysis.video = Self.analyzeAVAsset(avAsset, info: info)
                        return analysis
                    }
                    continuation.resume(returning: analysis)
                }
            }
        }
    }

    /// Pure, off-main parsing of one asset's image data. Runs on the dedicated
    /// Photos analysis queue so the heavy Vision work never blocks the UI.
    fileprivate nonisolated static func analyzeData(_ data: Data?, orientation: CGImagePropertyOrientation) -> AssetAnalysis {
        var analysis = AssetAnalysis()
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return analysis }

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            flatten(properties, into: &analysis.metadata, prefix: "")
        }

        // Decode a bounded-size image for Vision: big enough for solid OCR,
        // small enough to keep classification fast across a whole library.
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return analysis
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        let classify = VNClassifyImageRequest()
        let recognizeText = VNRecognizeTextRequest()
        recognizeText.recognitionLevel = .accurate
        recognizeText.usesLanguageCorrection = true
        let detectFaces = VNDetectFaceRectanglesRequest()

        try? handler.perform([classify, recognizeText, detectFaces])

        if let results = classify.results {
            analysis.classifications = results
                .filter { $0.confidence >= 0.1 }
                .sorted { $0.confidence > $1.confidence }
                .prefix(20)
                .map { "\($0.identifier) (\(Int(($0.confidence * 100).rounded()))%)" }
        }
        if let results = recognizeText.results {
            analysis.recognizedText = results.compactMap { $0.topCandidates(1).first?.string }
        }
        analysis.faceCount = detectFaces.results?.count ?? 0

        return analysis
    }

    fileprivate nonisolated static func analyzeAVAsset(_ asset: AVAsset?, info: [AnyHashable: Any]?) -> PhotoVideoAnalysis? {
        let requestInfo = flattenedInfo(info)
        guard let asset else {
            guard !requestInfo.isEmpty else { return nil }
            return PhotoVideoAnalysis(
                duration: nil,
                preferredRate: 0,
                preferredVolume: 0,
                preferredTransform: makeTransform(.identity),
                providesPreciseDurationAndTiming: false,
                isPlayable: false,
                isExportable: false,
                isReadable: false,
                isComposable: false,
                isCompatibleWithSavedPhotosAlbum: false,
                isCompatibleWithAirPlayVideo: false,
                hasProtectedContent: false,
                canContainFragments: false,
                containsFragments: false,
                availableMetadataFormats: [],
                availableChapterLocales: [],
                availableMediaCharacteristicsWithMediaSelectionOptions: [],
                metadata: [:],
                tracks: [],
                requestInfo: requestInfo
            )
        }

        return PhotoVideoAnalysis(
            duration: seconds(asset.duration),
            preferredRate: asset.preferredRate,
            preferredVolume: asset.preferredVolume,
            preferredTransform: makeTransform(asset.preferredTransform),
            providesPreciseDurationAndTiming: asset.providesPreciseDurationAndTiming,
            isPlayable: asset.isPlayable,
            isExportable: asset.isExportable,
            isReadable: asset.isReadable,
            isComposable: asset.isComposable,
            isCompatibleWithSavedPhotosAlbum: asset.isCompatibleWithSavedPhotosAlbum,
            isCompatibleWithAirPlayVideo: asset.isCompatibleWithAirPlayVideo,
            hasProtectedContent: asset.hasProtectedContent,
            canContainFragments: asset.canContainFragments,
            containsFragments: asset.containsFragments,
            availableMetadataFormats: asset.availableMetadataFormats.map { String(describing: $0) },
            availableChapterLocales: asset.availableChapterLocales.map { $0.identifier },
            availableMediaCharacteristicsWithMediaSelectionOptions: asset.availableMediaCharacteristicsWithMediaSelectionOptions.map {
                String(describing: $0)
            },
            metadata: videoMetadata(for: asset),
            tracks: asset.tracks.map(makeVideoTrack),
            requestInfo: requestInfo
        )
    }

    fileprivate nonisolated static func makeVideoTrack(_ track: AVAssetTrack) -> PhotoVideoTrack {
        let naturalSize = track.naturalSize
        return PhotoVideoTrack(
            id: track.trackID,
            mediaType: track.mediaType.rawValue,
            isPlayable: track.isPlayable,
            isDecodable: track.isDecodable,
            isEnabled: track.isEnabled,
            isSelfContained: track.isSelfContained,
            totalSampleDataLength: track.totalSampleDataLength,
            startTime: seconds(track.timeRange.start),
            duration: seconds(track.timeRange.duration),
            naturalTimeScale: track.naturalTimeScale,
            estimatedDataRate: track.estimatedDataRate,
            languageCode: track.languageCode,
            extendedLanguageTag: track.extendedLanguageTag,
            naturalWidth: naturalSize.width > 0 ? Double(naturalSize.width) : nil,
            naturalHeight: naturalSize.height > 0 ? Double(naturalSize.height) : nil,
            preferredTransform: makeTransform(track.preferredTransform),
            preferredVolume: track.mediaType == .audio ? track.preferredVolume : nil,
            nominalFrameRate: track.nominalFrameRate > 0 ? track.nominalFrameRate : nil,
            minFrameDuration: seconds(track.minFrameDuration),
            requiresFrameReordering: track.mediaType == .video ? track.requiresFrameReordering : nil,
            mediaCharacteristics: mediaCharacteristics(for: track),
            formatDescriptions: track.formatDescriptions.map {
                makeFormatDescription($0 as! CMFormatDescription)
            },
            metadata: videoMetadata(for: track)
        )
    }

    fileprivate nonisolated static func makeFormatDescription(_ description: CMFormatDescription) -> PhotoVideoFormatDescription {
        let mediaType = CMFormatDescriptionGetMediaType(description)
        let mediaSubType = CMFormatDescriptionGetMediaSubType(description)
        var videoWidth: Int?
        var videoHeight: Int?
        var audioSampleRate: Double?
        var audioChannelCount: UInt32?
        var audioBitsPerChannel: UInt32?
        var audioFramesPerPacket: UInt32?

        if mediaType == kCMMediaType_Video {
            let dimensions = CMVideoFormatDescriptionGetDimensions(description)
            videoWidth = Int(dimensions.width)
            videoHeight = Int(dimensions.height)
        }

        if mediaType == kCMMediaType_Audio,
           let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
            audioSampleRate = basicDescription.mSampleRate
            audioChannelCount = basicDescription.mChannelsPerFrame
            audioBitsPerChannel = basicDescription.mBitsPerChannel
            audioFramesPerPacket = basicDescription.mFramesPerPacket
        }

        var extensions: [String: String] = [:]
        if let rawExtensions = CMFormatDescriptionGetExtensions(description) {
            flattenDictionary(rawExtensions as NSDictionary, into: &extensions, prefix: "")
        }

        return PhotoVideoFormatDescription(
            mediaType: fourCharacterCode(mediaType),
            mediaSubType: fourCharacterCode(mediaSubType),
            videoWidth: videoWidth,
            videoHeight: videoHeight,
            audioSampleRate: audioSampleRate,
            audioChannelCount: audioChannelCount,
            audioBitsPerChannel: audioBitsPerChannel,
            audioFramesPerPacket: audioFramesPerPacket,
            extensions: extensions
        )
    }

    fileprivate nonisolated static func videoMetadata(for asset: AVAsset) -> [String: String] {
        var out: [String: String] = [:]
        addMetadata(asset.commonMetadata, prefix: "common", into: &out)
        addMetadata(asset.metadata, prefix: "all", into: &out)
        for format in asset.availableMetadataFormats {
            addMetadata(asset.metadata(forFormat: format), prefix: "format.\(String(describing: format))", into: &out)
        }
        return out
    }

    fileprivate nonisolated static func videoMetadata(for track: AVAssetTrack) -> [String: String] {
        var out: [String: String] = [:]
        addMetadata(track.commonMetadata, prefix: "common", into: &out)
        addMetadata(track.metadata, prefix: "all", into: &out)
        for format in track.availableMetadataFormats {
            addMetadata(track.metadata(forFormat: format), prefix: "format.\(String(describing: format))", into: &out)
        }
        return out
    }

    fileprivate nonisolated static func addMetadata(_ items: [AVMetadataItem], prefix: String, into out: inout [String: String]) {
        for (index, item) in items.enumerated() {
            let base = "\(prefix).\(index)"
            append(item.identifier.map { String(describing: $0) }, key: "\(base).identifier", into: &out)
            append(item.commonKey.map { String(describing: $0) }, key: "\(base).commonKey", into: &out)
            append(item.keySpace.map { String(describing: $0) }, key: "\(base).keySpace", into: &out)
            append(item.extendedLanguageTag, key: "\(base).extendedLanguageTag", into: &out)
            append(item.locale?.identifier, key: "\(base).locale", into: &out)
            append(seconds(item.time).map { String($0) }, key: "\(base).time", into: &out)
            append(seconds(item.duration).map { String($0) }, key: "\(base).duration", into: &out)
            append(item.startDate?.description, key: "\(base).startDate", into: &out)
            append(metadataValue(item), key: "\(base).value", into: &out)
            if let data = item.dataValue {
                append("\(data.count)", key: "\(base).dataByteCount", into: &out)
            }
            if let extraAttributes = item.extraAttributes {
                var flattened: [String: String] = [:]
                flattenDictionary(extraAttributes as NSDictionary, into: &flattened, prefix: "")
                for (key, value) in flattened {
                    append(value, key: "\(base).extra.\(key)", into: &out)
                }
            }
        }
    }

    fileprivate nonisolated static func metadataValue(_ item: AVMetadataItem) -> String? {
        if let string = item.stringValue, !string.isEmpty { return string }
        if let number = item.numberValue { return number.stringValue }
        if let date = item.dateValue { return date.description }
        if let data = item.dataValue { return "Data (\(data.count) bytes)" }
        return nil
    }

    fileprivate nonisolated static func mediaCharacteristics(for track: AVAssetTrack) -> [String] {
        var checks: [(AVMediaCharacteristic, String)] = [
            (.visual, "Visual"),
            (.audible, "Audible"),
            (.legible, "Legible"),
            (.frameBased, "Frame Based"),
            (.containsOnlyForcedSubtitles, "Only Forced Subtitles"),
        ]
        checks.append((.containsAlphaChannel, "Alpha Channel"))
        checks.append((.containsHDRVideo, "HDR Video"))
        checks.append((.containsStereoMultiviewVideo, "Stereo Multiview Video"))

        return checks.compactMap { characteristic, label in
            track.hasMediaCharacteristic(characteristic) ? label : nil
        }
    }

    fileprivate nonisolated static func flattenedInfo(_ info: [AnyHashable: Any]?) -> [String: String] {
        guard let info else { return [:] }
        var out: [String: String] = [:]
        flatten(info, into: &out, prefix: "")
        return out
    }

    fileprivate nonisolated static func seconds(_ time: CMTime) -> Double? {
        guard time.isValid, !time.isIndefinite else { return nil }
        let value = CMTimeGetSeconds(time)
        return value.isFinite ? value : nil
    }

    fileprivate nonisolated static func makeTransform(_ transform: CGAffineTransform) -> PhotoAffineTransform {
        PhotoAffineTransform(
            a: Double(transform.a),
            b: Double(transform.b),
            c: Double(transform.c),
            d: Double(transform.d),
            tx: Double(transform.tx),
            ty: Double(transform.ty)
        )
    }

    fileprivate nonisolated static func fourCharacterCode(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        if bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }),
           let string = String(bytes: bytes, encoding: .ascii) {
            return "\(string) (\(code))"
        }
        return "\(code)"
    }

    /// Recursively flattens a nested metadata dictionary into dotted keys.
    fileprivate nonisolated static func flatten(_ dict: [String: Any], into out: inout [String: String], prefix: String) {
        for (rawKey, value) in dict {
            let key = rawKey.hasPrefix("{") ? String(rawKey.dropFirst().dropLast()) : rawKey
            let full = prefix.isEmpty ? key : "\(prefix).\(key)"
            if let nested = value as? [String: Any] {
                flatten(nested, into: &out, prefix: full)
            } else if let array = value as? [Any] {
                out[full] = array.map { String(describing: $0) }.joined(separator: ", ")
            } else {
                out[full] = String(describing: value)
            }
        }
    }

    fileprivate nonisolated static func flatten(_ dict: [AnyHashable: Any], into out: inout [String: String], prefix: String) {
        for (rawKey, value) in dict {
            let key = String(describing: rawKey)
            let full = prefix.isEmpty ? key : "\(prefix).\(key)"
            flattenValue(value, key: full, into: &out)
        }
    }

    fileprivate nonisolated static func flattenDictionary(_ dict: NSDictionary, into out: inout [String: String], prefix: String) {
        dict.forEach { rawKey, value in
            let key = String(describing: rawKey)
            let full = prefix.isEmpty ? key : "\(prefix).\(key)"
            flattenValue(value, key: full, into: &out)
        }
    }

    fileprivate nonisolated static func flattenValue(_ value: Any, key: String, into out: inout [String: String]) {
        if let nested = value as? [String: Any] {
            flatten(nested, into: &out, prefix: key)
        } else if let nested = value as? [AnyHashable: Any] {
            flatten(nested, into: &out, prefix: key)
        } else if let nested = value as? NSDictionary {
            flattenDictionary(nested, into: &out, prefix: key)
        } else if let array = value as? [Any] {
            out[key] = array.map { String(describing: $0) }.joined(separator: ", ")
        } else if let error = value as? NSError {
            out[key] = "\(error.domain) \(error.code): \(error.localizedDescription)"
        } else {
            out[key] = String(describing: value)
        }
    }

    fileprivate nonisolated static func append(_ value: String?, key: String, into out: inout [String: String]) {
        guard let value, !value.isEmpty else { return }
        if out[key] == nil {
            out[key] = value
            return
        }

        var suffix = 2
        while out["\(key).\(suffix)"] != nil {
            suffix += 1
        }
        out["\(key).\(suffix)"] = value
    }

    // MARK: - Enum descriptions

    fileprivate nonisolated static func describe(mediaType: PHAssetMediaType) -> String {
        switch mediaType {
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .unknown: return "Unknown"
        @unknown default: return "Unknown"
        }
    }

    fileprivate nonisolated static func describe(mediaSubtypes: PHAssetMediaSubtype) -> [String] {
        var out: [String] = []
        if mediaSubtypes.contains(.photoPanorama) { out.append("Panorama") }
        if mediaSubtypes.contains(.photoHDR) { out.append("HDR") }
        if mediaSubtypes.contains(.photoScreenshot) { out.append("Screenshot") }
        if mediaSubtypes.contains(.photoLive) { out.append("Live Photo") }
        if mediaSubtypes.contains(.photoDepthEffect) { out.append("Depth Effect") }
        if mediaSubtypes.contains(.videoStreamed) { out.append("Streamed Video") }
        if mediaSubtypes.contains(.videoHighFrameRate) { out.append("Slo-mo") }
        if mediaSubtypes.contains(.videoTimelapse) { out.append("Time-lapse") }
        if #available(iOS 15, *), mediaSubtypes.contains(.videoCinematic) { out.append("Cinematic") }
        if #available(iOS 16, *), mediaSubtypes.contains(.spatialMedia) { out.append("Spatial") }
        return out
    }

    fileprivate nonisolated static func describe(sourceType: PHAssetSourceType) -> String {
        var out: [String] = []
        if sourceType.contains(.typeUserLibrary) { out.append("User Library") }
        if sourceType.contains(.typeCloudShared) { out.append("Cloud Shared") }
        if sourceType.contains(.typeiTunesSynced) { out.append("iTunes Synced") }
        return out.isEmpty ? "Unknown" : out.joined(separator: ", ")
    }

    fileprivate nonisolated static func describe(playbackStyle: PHAsset.PlaybackStyle) -> String {
        switch playbackStyle {
        case .unsupported: return "Unsupported"
        case .image: return "Image"
        case .imageAnimated: return "Animated Image"
        case .livePhoto: return "Live Photo"
        case .video: return "Video"
        case .videoLooping: return "Looping Video"
        @unknown default: return "Unknown"
        }
    }

    fileprivate nonisolated static func describe(burstSelectionTypes: PHAssetBurstSelectionType) -> [String] {
        var out: [String] = []
        if burstSelectionTypes.contains(.autoPick) { out.append("Auto Pick") }
        if burstSelectionTypes.contains(.userPick) { out.append("User Pick") }
        return out
    }

    fileprivate nonisolated static func describe(resourceType: PHAssetResourceType) -> String {
        switch resourceType {
        case .photo: return "Photo"
        case .video: return "Video"
        case .audio: return "Audio"
        case .alternatePhoto: return "Alternate Photo"
        case .fullSizePhoto: return "Full-size Photo"
        case .fullSizeVideo: return "Full-size Video"
        case .adjustmentData: return "Adjustment Data"
        case .adjustmentBasePhoto: return "Adjustment Base Photo"
        case .pairedVideo: return "Paired Video"
        case .fullSizePairedVideo: return "Full-size Paired Video"
        case .adjustmentBasePairedVideo: return "Adjustment Base Paired Video"
        case .adjustmentBaseVideo: return "Adjustment Base Video"
        default: return "Other"
        }
    }

    fileprivate nonisolated static func describe(collectionType: PHAssetCollectionType) -> String {
        switch collectionType {
        case .album: return "Album"
        case .smartAlbum: return "Smart Album"
        case .moment: return "Moment"
        @unknown default: return "Unknown"
        }
    }

    fileprivate nonisolated static func describe(collectionSubtype: PHAssetCollectionSubtype) -> String {
        switch collectionSubtype {
        case .albumRegular: return "User Album"
        case .albumSyncedEvent: return "Synced Event"
        case .albumSyncedFaces: return "Synced Faces"
        case .albumSyncedAlbum: return "Synced Album"
        case .albumImported: return "Imported"
        case .albumMyPhotoStream: return "My Photo Stream"
        case .albumCloudShared: return "Shared Album"
        case .smartAlbumGeneric: return "Generic"
        case .smartAlbumPanoramas: return "Panoramas"
        case .smartAlbumVideos: return "Videos"
        case .smartAlbumFavorites: return "Favorites"
        case .smartAlbumTimelapses: return "Time-lapses"
        case .smartAlbumAllHidden: return "Hidden"
        case .smartAlbumRecentlyAdded: return "Recently Added"
        case .smartAlbumBursts: return "Bursts"
        case .smartAlbumSlomoVideos: return "Slo-mo"
        case .smartAlbumUserLibrary: return "Camera Roll"
        case .smartAlbumSelfPortraits: return "Selfies"
        case .smartAlbumScreenshots: return "Screenshots"
        case .smartAlbumDepthEffect: return "Portrait"
        case .smartAlbumLivePhotos: return "Live Photos"
        case .smartAlbumAnimated: return "Animated"
        case .smartAlbumLongExposures: return "Long Exposures"
        case .smartAlbumUnableToUpload: return "Unable to Upload"
        case .any: return "Any"
        default: return "Other"
        }
    }

    private func updateAuthStatusText(_ status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined: authorizationStatusText = "Not determined"
        case .denied: authorizationStatusText = "Denied"
        case .restricted: authorizationStatusText = "Restricted"
        case .authorized: authorizationStatusText = "Authorized (full access)"
        case .limited: authorizationStatusText = "Authorized (limited selection)"
        @unknown default: authorizationStatusText = "Unknown"
        }
    }

    private func report(_ message: String?) {
        syncProgress = message
    }
}
