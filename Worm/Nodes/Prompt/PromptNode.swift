import Foundation
import Observation

/// A single self-report prompt answer. Text/choice prompts carry their answer in
/// `text`; photo prompts carry signal via on-device `visionKeywords` (the actual
/// vision read is wired in a later task, this just holds what it's given).
struct PromptAnswer: Codable, Hashable {
    let entryID: String
    let title: String
    var text: String
    var visionKeywords: [String] = []
    var capturedAt: Date
}

/// The prompts node: everything the person told the worm directly, across every
/// self-report prompt. One generic node owns all answers, persists them, and
/// reduces them into a single `.prompts` brain slice. Like every node it stays
/// set up once answered and shows its cached answers instantly on relaunch.
@MainActor
@Observable
final class PromptNode {
    private(set) var answers: [PromptAnswer] = []

    @ObservationIgnored private let store: SnapshotStore<[PromptAnswer]>

    init(storeFilename: String = "prompt-answers.json") {
        store = SnapshotStore<[PromptAnswer]>(filename: storeFilename)
        loadCached()
    }

    var hasAnswers: Bool { !answers.isEmpty }

    // MARK: - Recording

    /// Record a text/choice answer, upserting on `entryID`.
    func record(entryID: String, title: String, answer: String) {
        upsert(entryID: entryID, title: title) { existing in
            existing.text = answer
            existing.capturedAt = Date()
        } make: {
            PromptAnswer(entryID: entryID, title: title, text: answer, capturedAt: Date())
        }
    }

    /// Record a photo prompt as on-device vision keywords, upserting on `entryID`.
    func recordPhoto(entryID: String, title: String, visionKeywords: [String]) {
        upsert(entryID: entryID, title: title) { existing in
            existing.visionKeywords = visionKeywords
            existing.capturedAt = Date()
        } make: {
            PromptAnswer(entryID: entryID, title: title, text: "", visionKeywords: visionKeywords, capturedAt: Date())
        }
    }

    // MARK: - Lifecycle

    /// Mirrors the other nodes' lifecycle entry point so WormApp can call it later.
    func restoreSessionIfPossible() async {
        loadCached()
    }

    // MARK: - Brain slice

    func brainSlice() -> NodeBrainSlice? {
        guard !answers.isEmpty else { return nil }
        let lines = answers.map { "\($0.title): \(displayValue(for: $0))" }
        let freshness = answers.map(\.capturedAt).max()
        let confidence = min(0.9, 0.5 + 0.1 * Double(answers.count))
        return NodeBrainSlice(
            nodeID: .prompts,
            isConnected: true,
            isPopulated: true,
            summary: "\(answers.count) things you told me directly.",
            facts: lines,
            evidence: lines,
            chunks: lines,
            freshness: freshness,
            confidence: confidence,
            health: "ready",
            novelty: BrainNoveltySet()
        )
    }

    // MARK: - Private

    private func displayValue(for answer: PromptAnswer) -> String {
        answer.text.isEmpty ? answer.visionKeywords.joined(separator: ", ") : answer.text
    }

    private func upsert(entryID: String, title: String,
                        update: (inout PromptAnswer) -> Void,
                        make: () -> PromptAnswer) {
        if let index = answers.firstIndex(where: { $0.entryID == entryID }) {
            update(&answers[index])
        } else {
            answers.append(make())
        }
        persist()
    }

    private func loadCached() {
        if let cached = store.load() {
            answers = cached
        }
    }

    private func persist() {
        store.save(answers)
    }
}
