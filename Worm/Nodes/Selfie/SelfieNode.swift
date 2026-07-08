import Foundation
import Observation
import UIKit

/// What the worm reads off a single selfie: a private prose read, one surprising
/// true observation, and concrete observed attributes / aesthetic signals that
/// feed the taste profile. Produced by the brain layer, persisted with the node.
struct SelfieAnalysis: Codable, Hashable {
    /// Two plain private sentences: who this person seems to be. Not shown raw.
    let read: String
    /// One specific, surprising, *true* observation in the worm's voice.
    let oneLiner: String
    /// Concrete observed attributes: presentation, expression, styling, setting,
    /// grooming, accessories, energy — never flattery, never generic.
    let observations: [String]
    /// Aesthetic / taste keywords implied by how they present themselves.
    let aesthetics: [String]
    let confidence: Double
    var analyzedAt: Date

    init(read: String, oneLiner: String, observations: [String], aesthetics: [String], confidence: Double, analyzedAt: Date = Date()) {
        self.read = read
        self.oneLiner = oneLiner
        self.observations = observations
        self.aesthetics = aesthetics
        self.confidence = confidence
        self.analyzedAt = analyzedAt
    }

    // The model's JSON omits `analyzedAt` (we stamp it after the read); persisted
    // snapshots include it. Tolerate both.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        read = try c.decode(String.self, forKey: .read)
        oneLiner = try c.decode(String.self, forKey: .oneLiner)
        observations = try c.decodeIfPresent([String].self, forKey: .observations) ?? []
        aesthetics = try c.decodeIfPresent([String].self, forKey: .aesthetics) ?? []
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.6
        analyzedAt = try c.decodeIfPresent(Date.self, forKey: .analyzedAt) ?? Date()
    }
}

/// The selfie node — the worm's first look at the person's face.
///
/// It owns the captured selfie image (persisted by `SelfieStore`) and a rich
/// vision read of it (a "who is this, really" profile), persisted alongside as a
/// snapshot. Like every node it stays set up once connected: on relaunch it
/// shows the saved read instantly and only re-reads when asked. The image never
/// leaves the device except as the one vision request that produces the read.
@MainActor
@Observable
final class SelfieNode {
    private(set) var isAnalyzing = false
    private(set) var analysis: SelfieAnalysis?
    private(set) var lastAnalyzedAt: Date?
    private(set) var lastErrorMessage: String?
    private(set) var hasSelfie = false

    @ObservationIgnored private var imageData: Data?
    @ObservationIgnored private let reader = SelfieVisionReader()
    @ObservationIgnored private let snapshotStore = SnapshotStore<SelfieAnalysis>(filename: "selfie-analysis.json")

    init() {
        loadCached()
    }

    var image: UIImage? { imageData.flatMap(UIImage.init(data:)) }

    // The graph/profile talk to nodes through a shared shape. A selfie has no
    // OAuth; "authorized" means one has been captured, "syncing" means reading.
    var isAuthorized: Bool { hasSelfie }
    var isAuthorizing: Bool { false }
    var isSyncing: Bool { isAnalyzing }
    var lastSyncedAt: Date? { lastAnalyzedAt }

    var statusSummary: String {
        if isAnalyzing { return "Reading your face…" }
        if let error = lastErrorMessage { return error }
        if analysis != nil { return "Read from your selfie" }
        if hasSelfie { return "Selfie saved, not yet read" }
        return "No selfie yet."
    }

    // MARK: - Lifecycle

    func restoreSessionIfPossible() async {
        loadCached()
        // A selfie captured before we could read it (offline, killed) still gets
        // its read on the next launch — but a saved read is never redone.
        if hasSelfie, analysis == nil, !isAnalyzing {
            await analyzeStored()
        }
    }

    /// Called right after the onboarding capture: the image is already on disk,
    /// so pick it up and produce the read.
    func ingestCapturedSelfie() async {
        loadCached()
        guard hasSelfie else { return }
        await analyzeStored()
    }

    /// Re-read the stored selfie (the node's "refresh").
    func syncEverything() async {
        await analyzeStored()
    }

    /// Capture happens in the onboarding camera flow, not here.
    func connect() async {}

    func disconnect() {
        analysis = nil
        lastAnalyzedAt = nil
        lastErrorMessage = nil
        hasSelfie = false
        imageData = nil
        snapshotStore.delete()
        SelfieStore.delete()
    }

    // MARK: - Private

    private func loadCached() {
        imageData = SelfieStore.loadData()
        hasSelfie = imageData != nil
        if analysis == nil, let cached = snapshotStore.load() {
            analysis = cached
            lastAnalyzedAt = cached.analyzedAt
        }
    }

    private func analyzeStored() async {
        guard !isAnalyzing else { return }
        imageData = imageData ?? SelfieStore.loadData()
        guard let data = imageData else { return }
        hasSelfie = true

        isAnalyzing = true
        lastErrorMessage = nil
        defer { isAnalyzing = false }

        do {
            var result = try await reader.analyze(imageData: data)
            result.analyzedAt = Date()
            analysis = result
            lastAnalyzedAt = result.analyzedAt
            snapshotStore.save(result)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}

/// Where the worm keeps your face, and how the node reads it back. One file,
/// overwritten on re-snap. `SelfieCaptureView` writes it during capture.
extension SelfieStore {
    static func loadData() -> Data? {
        try? Data(contentsOf: url)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
