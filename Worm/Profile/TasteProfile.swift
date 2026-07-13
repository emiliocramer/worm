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
    /// Live pipeline trace while a question is being answered; persisted onto
    /// the finished message as `BrainAnswer.trace`.
    private(set) var liveTrace: [String] = []
    private(set) var lastError: String?
    private(set) var lastSynthesizedAt: Date?
    private(set) var lastAnsweredAt: Date?

    /// Only surface insights the synthesizer is genuinely confident about.
    private static let minConfidence = 0.6
    /// Hard upper bound on length — a spoken aside, not a paragraph.
    private static let maxWords = 18

    @ObservationIgnored private let store = SnapshotStore<Snapshot>(filename: "taste-profile.json")
    @ObservationIgnored private let synthesizer = BrainSynthesizer()
    /// Winning journeys and graded leads carried across pulls, so every dig
    /// starts from what previous expeditions proved.
    @ObservationIgnored private let digMemoryStore = SnapshotStore<DigMemorySnapshot>(filename: "dig-memory.json")
    @ObservationIgnored private var digMemory: DigMemorySnapshot?

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
        digMemory = digMemoryStore.load()
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

    /// Ask the brain a direct question. Music recommendation pulls dig first:
    /// seeds -> trails -> catalog searches -> a novelty-filtered pool of real
    /// tracks the model ranks. Candidates are still walked through the local
    /// novelty filter, and pool picks are verified by construction; anything
    /// off-pool goes through catalog verification as before.
    @discardableResult
    func answer(
        _ text: String,
        context inputContext: BrainContext,
        digger: BrainDigger? = nil,
        verifyRecommendation: ((BrainMusicRecommendation) async -> BrainCatalogVerification)? = nil
    ) async -> BrainAnswer? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        ingest(inputContext.slices)
        let context = BrainContext(slices: slices, read: read, insights: insights)
        chatHistory.append(BrainChatMessage(role: .user, text: trimmed))
        save()

        isAnswering = true
        liveTrace = []
        defer { isAnswering = false }

        func trace(_ line: String) {
            liveTrace.append(line)
        }

        let intent = BrainRetriever.classifyIntent(trimmed)
        trace("Intent: \(intent.title).")

        // One priced ledger per pull. Every model call — scouts, assayers,
        // foreman, shortlist, judge — lands here and streams into the trace.
        let ledger = SpendLedger()
        ledger.onRecord = { record in
            Task { @MainActor [weak self] in
                self?.liveTrace.append("$ \(record.traceLine)")
            }
        }

        var dig: DigResult?
        if let digger, intent == .musicRecommendation {
            trace("Digging before asking… (budget $\(String(format: "%.2f", digger.budgetUSD)))")
            dig = await digger.dig(
                context: context,
                question: trimmed,
                synthesizer: synthesizer,
                memory: digMemory,
                ledger: ledger
            ) { line in
                trace(line)
            }
        } else if intent == .musicRecommendation {
            trace("No digger wired; propose-then-verify path.")
        }

        func finish(_ answer: BrainAnswer) -> BrainAnswer {
            var finished = answer
            finished.dig = dig
            finished.spend = ledger.records
            finished.trace = liveTrace
            if finished.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // A blank line must never reach the transcript, whatever the
                // model did under token pressure.
                finished = BrainAnswer(
                    answer: finished.recommendation == nil
                        ? "I came back empty on that one. The dig detail below shows how far I got."
                        : "Here is the one that survived the dig.",
                    evidence: finished.evidence,
                    confidence: finished.confidence,
                    recommendation: finished.recommendation,
                    recommendations: finished.recommendations,
                    retrieval: finished.retrieval,
                    dig: finished.dig,
                    trace: finished.trace,
                    spend: finished.spend
                )
            }
            return finished
        }

        var rejected: [String] = []
        do {
            // Each model call returns a ranked candidate list; walk it through the
            // local novelty filter and catalog verification and surface the first
            // survivor. A fresh model call happens only when the whole list dies.
            for attempt in 0..<2 {
                trace(attempt == 0 ? "Asking the brain (effort \(intent == .musicRecommendation ? "xhigh" : "high"))…" : "Whole list died; asking again with \(rejected.count) rejections…")
                let query = BrainQuery(text: trimmed, rejectedRecommendations: rejected)
                var result = try await synthesizer.answer(query, context: context, dig: dig, ledger: ledger)
                var candidates = result.rankedCandidates
                trace("Model returned \(candidates.count) candidate\(candidates.count == 1 ? "" : "s").")

                // Salvage: the observed judge failure mode is naming picks in
                // the answer prose while returning an empty array. Pool titles
                // are verified facts, so matching them against the text is safe.
                if candidates.isEmpty, let dig, dig.hasPool {
                    let salvaged = Self.salvageCandidates(fromAnswerText: result.answer, pool: dig.pool)
                    if !salvaged.isEmpty {
                        trace("Salvaged \(salvaged.count) pick\(salvaged.count == 1 ? "" : "s") named in the answer text but missing from the recommendations array.")
                        candidates = salvaged
                    }
                }

                if candidates.isEmpty {
                    // Zero candidates against a non-empty verified pool is a model
                    // failure (usually token pressure), not an answer. Retry once
                    // with the failure named.
                    if attempt == 0, dig?.hasPool == true {
                        trace("Model returned nothing despite a \(dig?.pool.count ?? 0)-track verified pool; retrying.")
                        rejected.append("(previous attempt returned zero recommendations; rank the verified candidate pool)")
                        continue
                    }
                    result = finish(result.choosing(nil))
                    append(answer: result)
                    InsightLog.recordQuery(query: query, context: context, result: result, dig: dig)
                    return result
                }

                for candidate in candidates {
                    if let issue = context.noveltyIssue(for: candidate) {
                        trace("Novelty rejected \(candidate.title) by \(candidate.artist): \(issue).")
                        rejected.append("\(candidate.artist) - \(candidate.title): \(issue)")
                        continue
                    }
                    var chosen = result.choosing(candidate)
                    if let match = dig?.pool.first(where: { $0.trackKey == BrainNoveltySet.trackKey(title: candidate.title, artist: candidate.artist) }) {
                        // The candidate came out of a real catalog response; it is
                        // verified by construction and carries its dig provenance.
                        trace("\(candidate.title) matched the dig pool; verified by construction (route: \(match.journey.title)).")
                        chosen = chosen.withCatalogVerification(BrainCatalogVerification(
                            isVerified: true,
                            canVerify: true,
                            source: match.source,
                            message: "Verified by catalog dig (\(match.source) search result, route: \(match.journey.title)).",
                            match: BrainCatalogCandidate(
                                source: match.source,
                                title: match.title,
                                artist: match.artist,
                                album: match.album,
                                url: match.url
                            ),
                            candidates: []
                        ))
                    } else if let verifyRecommendation {
                        trace("\(candidate.title) is off-pool; verifying against live catalog…")
                        let verification = await verifyRecommendation(candidate)
                        guard verification.isVerified else {
                            trace("Catalog rejected \(candidate.title): \(verification.message)")
                            rejected.append("\(candidate.artist) - \(candidate.title): \(verification.message)")
                            continue
                        }
                        chosen = chosen.withCatalogVerification(verification)
                    }
                    trace("Surfacing \(candidate.title) by \(candidate.artist). Total spend \(ledger.summaryLine).")
                    chosen = finish(chosen.withNoveltyStatus("Passed local novelty filters."))
                    recordDigOutcome(dig: dig, pick: candidate)
                    append(answer: chosen)
                    InsightLog.recordQuery(query: BrainQuery(text: trimmed, rejectedRecommendations: rejected), context: context, result: chosen, dig: dig)
                    return chosen
                }
            }

            trace("Both attempts exhausted; surfacing honest failure.")
            let fallback = finish(BrainAnswer(
                answer: "Everything I found was too familiar or failed catalog verification. I need a deeper catalog pass before I trust a pick.",
                evidence: rejected,
                confidence: 0.2,
                recommendation: nil
            ))
            append(answer: fallback)
            InsightLog.recordQuery(query: BrainQuery(text: trimmed, rejectedRecommendations: rejected), context: context, result: fallback, dig: dig)
            return fallback
        } catch {
            lastError = error.localizedDescription
            trace("Error: \(error.localizedDescription)")
            let failure = finish(BrainAnswer(
                answer: error.localizedDescription,
                evidence: [],
                confidence: 0,
                recommendation: nil
            ))
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
        digMemory = nil
        digMemoryStore.delete()
    }

    // MARK: - Private

    /// Pool candidates whose artist appears in the answer prose, ordered by
    /// first mention. Only verified pool entries qualify, so this can never
    /// introduce an unvetted pick. Exposed for tests.
    static func salvageCandidates(fromAnswerText text: String, pool: [DugCandidate]) -> [BrainMusicRecommendation] {
        guard let normalizedText = BrainNoveltySet.normalized(text), !normalizedText.isEmpty else { return [] }
        let haystack = " \(normalizedText) "
        var matches: [(position: String.Index, candidate: DugCandidate)] = []
        var seenArtists = Set<String>()
        for candidate in pool {
            guard let artistKey = BrainNoveltySet.normalized(candidate.artist), !artistKey.isEmpty,
                  seenArtists.insert(artistKey).inserted,
                  let range = haystack.range(of: " \(artistKey) ") else { continue }
            matches.append((range.lowerBound, candidate))
        }
        return matches
            .sorted { $0.position < $1.position }
            .prefix(3)
            .map { entry in
                BrainMusicRecommendation(
                    title: entry.candidate.title,
                    artist: entry.candidate.artist,
                    album: entry.candidate.album,
                    why: entry.candidate.routeReason,
                    noveltyRationale: "Salvaged from the answer text; verified dig-pool entry."
                )
            }
    }

    /// A surfaced pick teaches the dig memory: the winning journey ranks
    /// higher next time, and this expedition's graded leads persist so the
    /// next dig starts from proven ground instead of re-discovering it.
    private func recordDigOutcome(dig: DigResult?, pick: BrainMusicRecommendation) {
        guard let dig else { return }
        var memory = digMemory ?? DigMemorySnapshot()
        let match = dig.pool.first { $0.trackKey == BrainNoveltySet.trackKey(title: pick.title, artist: pick.artist) }
        if let match {
            memory.journeyWins[match.journey.rawValue, default: 0] += 1
        }
        // Variety pressure inputs: the surfaced route and pick both count as
        // "recent" for the next few pulls, whether on-pool or off-pool.
        var journeys = memory.recentJourneys ?? []
        if let journey = match?.journey ?? dig.trails.first?.journey {
            journeys.append(journey.rawValue)
        }
        memory.recentJourneys = Array(journeys.suffix(5))
        var picks = memory.recentPicks ?? []
        picks.append("\(pick.title) by \(pick.artist)\(match.map { " (route: \($0.journey.title))" } ?? "")")
        memory.recentPicks = Array(picks.suffix(5))
        if let leads = dig.leads, !leads.isEmpty {
            var byID = Dictionary(uniqueKeysWithValues: memory.leads.map { ($0.id, $0) })
            for lead in leads where byID[lead.id] == nil {
                byID[lead.id] = lead
            }
            memory.leads = Array(byID.values.sorted { $0.score > $1.score }.prefix(40))
        }
        memory.updatedAt = Date()
        digMemory = memory
        digMemoryStore.save(memory)
    }

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
