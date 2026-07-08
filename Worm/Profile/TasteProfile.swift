import Foundation
import Observation

/// The durable brain entity. Nodes do not talk to Claude; they are reduced into
/// `NodeBrainSlice`s, then this type owns synthesis, query answering, confidence
/// gates, persistence, and the surfaced worm lines.
@MainActor
@Observable
final class TasteProfile {
    /// Private prose characterization. Not shown directly.
    private(set) var read: String?
    /// The worm's speakable observations, confidence-gated and de-duplicated.
    private(set) var insights: [Insight] = []
    /// Latest compact memories available to the brain.
    private(set) var slices: [NodeBrainSlice] = []
    /// Debug chat transcript for probing the brain.
    private(set) var chatHistory: [BrainChatMessage] = []
    private(set) var isSynthesizing = false
    private(set) var isAnswering = false
    private(set) var lastError: String?
    private(set) var lastSynthesizedAt: Date?
    private(set) var lastAnsweredAt: Date?

    /// Only surface insights the synthesizer is genuinely confident about.
    private static let minConfidence = 0.6
    /// Hard upper bound on length — a spoken aside, not a paragraph.
    private static let maxWords = 18

    @ObservationIgnored private let store = SnapshotStore<Snapshot>(filename: "taste-profile.json")
    @ObservationIgnored private let synthesizer = BrainSynthesizer()

    private struct Snapshot: Codable {
        let read: String?
        let insights: [Insight]
        let slices: [NodeBrainSlice]
        let chatHistory: [BrainChatMessage]
        let lastSynthesizedAt: Date?
        let lastAnsweredAt: Date?

        init(
            read: String?,
            insights: [Insight],
            slices: [NodeBrainSlice],
            chatHistory: [BrainChatMessage],
            lastSynthesizedAt: Date?,
            lastAnsweredAt: Date?
        ) {
            self.read = read
            self.insights = insights
            self.slices = slices
            self.chatHistory = chatHistory
            self.lastSynthesizedAt = lastSynthesizedAt
            self.lastAnsweredAt = lastAnsweredAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            read = try container.decodeIfPresent(String.self, forKey: .read)
            insights = try container.decodeIfPresent([Insight].self, forKey: .insights) ?? []
            slices = try container.decodeIfPresent([NodeBrainSlice].self, forKey: .slices) ?? []
            chatHistory = try container.decodeIfPresent([BrainChatMessage].self, forKey: .chatHistory) ?? []
            lastSynthesizedAt = try container.decodeIfPresent(Date.self, forKey: .lastSynthesizedAt)
            lastAnsweredAt = try container.decodeIfPresent(Date.self, forKey: .lastAnsweredAt)
        }
    }

    init() {
        if let snapshot = store.load() {
            read = snapshot.read
            insights = snapshot.insights
            slices = snapshot.slices
            chatHistory = snapshot.chatHistory
            lastSynthesizedAt = snapshot.lastSynthesizedAt
            lastAnsweredAt = snapshot.lastAnsweredAt
        }
    }

    var isEmpty: Bool { insights.isEmpty && read == nil }

    var currentContext: BrainContext {
        BrainContext(slices: slices, read: read, insights: insights)
    }

    var populatedSliceCount: Int {
        slices.filter(\.isPopulated).count
    }

    func ingest(_ newSlices: [NodeBrainSlice]) {
        guard !newSlices.isEmpty else { return }
        var byID = Dictionary(uniqueKeysWithValues: slices.map { ($0.nodeID, $0) })
        for slice in newSlices {
            byID[slice.nodeID] = slice
        }
        slices = BrainNodeID.allCases.compactMap { byID[$0] }
        save()
    }

    /// Synthesize from node slices. Onboarding may pass only Spotify; the full
    /// profile screen passes every available node. The brain owns Claude.
    @discardableResult
    func synthesize(
        slices newSlices: [NodeBrainSlice],
        mode: BrainSynthesisMode = .deep,
        kind: BrainSynthesisKind = .profile,
        useOnlyProvidedSlices: Bool = false,
        avoidExistingInsights: Bool = true
    ) async -> [Insight] {
        ingest(newSlices)
        let context = useOnlyProvidedSlices
            ? BrainContext(slices: newSlices, read: nil, insights: [])
            : currentContext
        guard context.hasSignal else { return [] }

        isSynthesizing = true
        defer { isSynthesizing = false }

        do {
            let result = try await synthesizer.synthesize(
                context,
                mode: mode,
                kind: kind,
                avoiding: avoidExistingInsights ? insights.map(\.line) : []
            )
            if !result.insights.isEmpty { read = result.read }
            let acceptedInsights = merge(result.insights, source: .profile)
            lastSynthesizedAt = Date()
            lastError = nil
            save()
            InsightLog.recordSynthesis(context: context, result: result)
            return acceptedInsights
        } catch {
            lastError = error.localizedDescription
            InsightLog.recordSynthesisError(error, context: context)
            return []
        }
    }

    /// Ask the brain a direct question. For music recommendations, returned
    /// candidates are checked locally against the full novelty memory in slices;
    /// if a candidate is too familiar or cannot be catalog-verified, the model
    /// gets a retry with that rejection.
    @discardableResult
    func answer(
        _ text: String,
        context inputContext: BrainContext,
        verifyRecommendation: ((BrainMusicRecommendation) async -> BrainCatalogVerification)? = nil
    ) async -> BrainAnswer? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        ingest(inputContext.slices)
        let context = BrainContext(slices: slices, read: read, insights: insights)
        chatHistory.append(BrainChatMessage(role: .user, text: trimmed))
        save()

        isAnswering = true
        defer { isAnswering = false }

        var rejected: [String] = []
        do {
            // Each model call returns a ranked candidate list; walk it through the
            // local novelty filter and catalog verification and surface the first
            // survivor. A fresh model call happens only when the whole list dies.
            for _ in 0..<2 {
                let query = BrainQuery(text: trimmed, rejectedRecommendations: rejected)
                var result = try await synthesizer.answer(query, context: context)
                let candidates = result.rankedCandidates

                if candidates.isEmpty {
                    result = result.choosing(nil)
                    append(answer: result)
                    InsightLog.recordQuery(query: query, context: context, result: result)
                    return result
                }

                for candidate in candidates {
                    if let issue = context.noveltyIssue(for: candidate) {
                        rejected.append("\(candidate.artist) - \(candidate.title): \(issue)")
                        continue
                    }
                    var chosen = result.choosing(candidate)
                    if let verifyRecommendation {
                        let verification = await verifyRecommendation(candidate)
                        guard verification.isVerified else {
                            rejected.append("\(candidate.artist) - \(candidate.title): \(verification.message)")
                            continue
                        }
                        chosen = chosen.withCatalogVerification(verification)
                    }
                    chosen = chosen.withNoveltyStatus("Passed local novelty filters.")
                    append(answer: chosen)
                    InsightLog.recordQuery(query: BrainQuery(text: trimmed, rejectedRecommendations: rejected), context: context, result: chosen)
                    return chosen
                }
            }

            let fallback = BrainAnswer(
                answer: "Everything I found was too familiar or failed catalog verification. I need a deeper catalog pass before I trust a pick.",
                evidence: rejected,
                confidence: 0.2,
                recommendation: nil
            )
            append(answer: fallback)
            InsightLog.recordQuery(query: BrainQuery(text: trimmed, rejectedRecommendations: rejected), context: context, result: fallback)
            return fallback
        } catch {
            lastError = error.localizedDescription
            let failure = BrainAnswer(
                answer: error.localizedDescription,
                evidence: [],
                confidence: 0,
                recommendation: nil
            )
            append(answer: failure)
            InsightLog.recordQueryError(error, query: BrainQuery(text: trimmed, rejectedRecommendations: rejected), context: context)
            return nil
        }
    }

    func clearChat() {
        chatHistory = []
        lastAnsweredAt = nil
        save()
    }

    func clear() {
        read = nil
        insights = []
        slices = []
        chatHistory = []
        lastSynthesizedAt = nil
        lastAnsweredAt = nil
        lastError = nil
        store.delete()
    }

    // MARK: - Private

    private func append(answer: BrainAnswer) {
        chatHistory.append(BrainChatMessage(role: .brain, text: answer.answer, answer: answer))
        lastAnsweredAt = Date()
        lastError = nil
        save()
    }

    private func merge(_ raw: [BrainSynthesizer.SynthesisResult.RawInsight], source: Insight.Source) -> [Insight] {
        var accepted: [Insight] = []
        for item in raw where item.confidence >= Self.minConfidence && Self.passesAudit(item.line) {
            let insight = Insight(line: item.line, evidence: item.evidence, confidence: item.confidence, source: source)
            accepted.append(insight)
            if !insights.contains(where: { $0.id == insight.id }) {
                insights.append(insight)
            }
        }
        return accepted
    }

    private static func passesAudit(_ line: String) -> Bool {
        if line.contains("—") || line.contains("–") { return false }
        if line.split(whereSeparator: { $0 == " " }).count > maxWords { return false }
        // A worm line is one second-person sentence, never an enumeration.
        // Colon/semicolon lines are evidence dumps wearing a line's clothes.
        if line.contains(":") || line.contains(";") { return false }
        if !line.lowercased().contains("you") { return false }
        return true
    }

    private func save() {
        store.save(Snapshot(
            read: read,
            insights: insights,
            slices: slices,
            chatHistory: chatHistory,
            lastSynthesizedAt: lastSynthesizedAt,
            lastAnsweredAt: lastAnsweredAt
        ))
    }
}
