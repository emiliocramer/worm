import Foundation

/// Deterministic, local retrieval over compact node slices.
///
/// This is intentionally small for v1: no embeddings, no fake graph database,
/// and no additional network call. The goal is to cheaply select the best
/// evidence before the model sees the prompt.
enum BrainRetriever {
    private struct Candidate {
        let nodeID: BrainNodeID
        let kind: String
        let text: String
        let kindWeight: Double
        let confidence: Double
        let freshness: Date?
    }

    static func retrieve(
        query: String,
        from context: BrainContext,
        limit: Int = 12
    ) -> BrainRetrievedContext {
        let intent = classify(query)
        let queryTerms = expandedTerms(for: intent, base: terms(in: query))
        var graphSummary = context.slices.map { slice in
            "\(slice.title): \(slice.health), populated \(slice.isPopulated ? "yes" : "no"), confidence \(String(format: "%.2f", slice.confidence))"
        }
        if let read = context.read, !read.isEmpty {
            graphSummary.append("Profile read: \(read)")
        }
        if !context.insights.isEmpty {
            graphSummary.append("Surfaced insights: \(context.insights.prefix(6).map(\.line).joined(separator: " | "))")
        }

        let graphEdges = graphEdgeCandidates(from: context)
        graphSummary.append(contentsOf: graphEdges.prefix(8).map(\.text))

        let scored = (candidates(from: context) + graphEdges)
            .map { candidate -> BrainRetrievalHit? in
                let score = score(candidate, queryTerms: queryTerms, intent: intent)
                guard score > 0 else { return nil }
                return BrainRetrievalHit(
                    id: hitID(candidate),
                    nodeID: candidate.nodeID,
                    kind: candidate.kind,
                    text: candidate.text,
                    score: rounded(score),
                    confidence: candidate.confidence
                )
            }
            .compactMap { $0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.text < rhs.text
                }
                return lhs.score > rhs.score
            }

        return BrainRetrievedContext(
            queryText: query,
            intent: intent,
            graphSummary: graphSummary,
            hits: Array(unique(scored).prefix(limit)),
            generatedAt: Date()
        )
    }

    // MARK: - Classification

    /// Exposed so the answer path can decide to dig before the model is called.
    static func classifyIntent(_ query: String) -> BrainQueryIntent {
        classify(query)
    }

    private static func classify(_ query: String) -> BrainQueryIntent {
        let normalized = BrainNoveltySet.normalized(query) ?? ""
        let queryTerms = Set(normalized.split(separator: " ").map(String.init))

        if queryTerms.intersects(["recommend", "recommendation", "song", "track", "artist", "album", "playlist", "music"]) {
            if queryTerms.intersects(["recommend", "recommendation", "new", "song", "track"]) {
                return .musicRecommendation
            }
            return .music
        }
        if queryTerms.intersects(["photo", "photos", "image", "images", "visual", "place", "places", "travel", "face", "faces"]) {
            return .visual
        }
        if queryTerms.intersects(["calendar", "schedule", "event", "events", "meeting", "meetings", "reminder", "reminders", "time"]) {
            return .schedule
        }
        return .general
    }

    private static func expandedTerms(for intent: BrainQueryIntent, base: Set<String>) -> Set<String> {
        switch intent {
        case .musicRecommendation, .music:
            return base.union([
                "music", "song", "songs", "track", "tracks", "artist", "artists",
                "album", "albums", "playlist", "playlists", "genre", "genres",
                "listening", "recent", "favorite", "favorites", "saved",
                "culture", "creator", "creators", "video", "videos", "youtube",
                "watch", "watched", "liked", "subscription", "subscriptions",
                "visual", "place", "places", "routine", "calendar", "photos",
                "contacts", "people", "friends", "family", "social", "community",
                "relationship", "relationships", "organization", "organizations",
                "work", "school", "city", "cities",
            ])
        case .visual:
            return base.union([
                "photo", "photos", "image", "images", "visual", "album", "albums",
                "location", "locations", "face", "faces", "favorite", "favorites",
            ])
        case .schedule:
            return base.union([
                "calendar", "schedule", "event", "events", "meeting", "meetings",
                "reminder", "reminders", "attendees", "location", "recurring",
            ])
        case .general:
            return base
        }
    }

    // MARK: - Candidate Scoring

    private static func candidates(from context: BrainContext) -> [Candidate] {
        context.slices.flatMap { slice -> [Candidate] in
            guard slice.isPopulated else { return [] }

            var result: [Candidate] = []
            if !slice.summary.isEmpty {
                result.append(candidate(slice, kind: "summary", text: slice.summary, kindWeight: 1.2))
            }
            result.append(contentsOf: slice.facts.map {
                candidate(slice, kind: "fact", text: $0, kindWeight: 1.0)
            })
            result.append(contentsOf: slice.evidence.map {
                candidate(slice, kind: "evidence", text: $0, kindWeight: 1.4)
            })
            result.append(contentsOf: slice.chunks.map {
                candidate(slice, kind: "chunk", text: $0, kindWeight: 1.7)
            })
            return result
        }
    }

    private static func graphEdgeCandidates(from context: BrainContext) -> [Candidate] {
        let slices = context.populatedSlices
        guard slices.count >= 2 else { return [] }

        var result: [Candidate] = []
        for leftIndex in slices.indices {
            for rightIndex in slices.indices where rightIndex > leftIndex {
                let left = slices[leftIndex]
                let right = slices[rightIndex]
                let text = edgeText(left, right)
                guard !text.isEmpty else { continue }
                result.append(Candidate(
                    nodeID: left.nodeID,
                    kind: "graph-edge/\(right.title)",
                    text: text,
                    kindWeight: 1.9,
                    confidence: min(left.confidence, right.confidence),
                    freshness: newer(left.freshness, right.freshness)
                ))
            }
        }
        return result
    }

    private static func candidate(
        _ slice: NodeBrainSlice,
        kind: String,
        text: String,
        kindWeight: Double
    ) -> Candidate {
        Candidate(
            nodeID: slice.nodeID,
            kind: kind,
            text: text,
            kindWeight: kindWeight,
            confidence: slice.confidence,
            freshness: slice.freshness
        )
    }

    private static func score(
        _ candidate: Candidate,
        queryTerms: Set<String>,
        intent: BrainQueryIntent
    ) -> Double {
        let candidateTerms = terms(in: candidate.text)
        guard !candidateTerms.isEmpty else { return 0 }

        let overlap = Double(candidateTerms.intersection(queryTerms).count)
        let normalizedOverlap = overlap / Double(max(3, queryTerms.count))
        let intentWeight = nodeWeight(candidate.nodeID, intent: intent)
        let confidence = max(0.15, candidate.confidence)
        let freshness = freshnessWeight(candidate.freshness)
        let baseline = intentWeight > 1 ? 0.35 : 0.08

        return (baseline + normalizedOverlap) *
            candidate.kindWeight *
            intentWeight *
            confidence *
            freshness
    }

    private static func nodeWeight(_ nodeID: BrainNodeID, intent: BrainQueryIntent) -> Double {
        switch (intent, nodeID) {
        case (.musicRecommendation, .spotify), (.musicRecommendation, .appleMusic):
            return 2.2
        case (.musicRecommendation, .youtube):
            return 2.05
        case (.musicRecommendation, .contacts):
            return 1.45
        case (.musicRecommendation, .photos):
            return 1.35
        case (.musicRecommendation, .calendar):
            return 1.15
        case (.musicRecommendation, .selfie):
            return 1.25
        case (.music, .spotify), (.music, .appleMusic):
            return 2.0
        case (.music, .youtube):
            return 1.45
        case (.music, .contacts):
            return 1.25
        case (.music, .selfie):
            return 0.9
        case (.visual, .photos):
            return 2.2
        case (.visual, .selfie):
            return 2.15
        case (.visual, .contacts):
            return 0.9
        case (.visual, .youtube):
            return 1.25
        case (.schedule, .calendar):
            return 2.2
        case (.schedule, .contacts):
            return 1.2
        case (.general, _):
            return 1.0
        default:
            return 0.45
        }
    }

    private static func freshnessWeight(_ date: Date?) -> Double {
        guard let date else { return 0.92 }
        let age = Date().timeIntervalSince(date)
        let day: TimeInterval = 60 * 60 * 24
        if age < 7 * day { return 1.1 }
        if age < 45 * day { return 1.0 }
        if age < 180 * day { return 0.92 }
        return 0.82
    }

    private static func edgeText(_ left: NodeBrainSlice, _ right: NodeBrainSlice) -> String {
        let leftSignal = compactSignal(left)
        let rightSignal = compactSignal(right)
        guard !leftSignal.isEmpty, !rightSignal.isEmpty else { return "" }
        return "Connection: \(left.title) + \(right.title): \(leftSignal) | \(rightSignal)"
    }

    private static func compactSignal(_ slice: NodeBrainSlice) -> String {
        var parts: [String] = []
        if !slice.summary.isEmpty {
            parts.append(slice.summary)
        }
        parts.append(contentsOf: slice.chunks.prefix(2))
        if parts.isEmpty {
            parts.append(contentsOf: slice.evidence.prefix(2))
        }
        return parts
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func newer(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    // MARK: - Text Helpers

    private static func terms(in text: String) -> Set<String> {
        guard let normalized = BrainNoveltySet.normalized(text) else { return [] }
        return Set(normalized
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) }
        )
    }

    private static let stopWords: Set<String> = [
        "about", "after", "again", "all", "and", "any", "are", "ask", "but",
        "can", "could", "for", "from", "has", "have", "how", "into", "just",
        "new", "not", "now", "one", "please", "recommend", "recommendation",
        "should", "show", "that", "the", "their", "them", "this", "too", "use",
        "was", "what", "when", "where", "who", "why", "with", "you", "your",
    ]

    private static func hitID(_ candidate: Candidate) -> String {
        let key = "\(candidate.nodeID.rawValue)|\(candidate.kind)|\(candidate.text)"
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func unique(_ hits: [BrainRetrievalHit]) -> [BrainRetrievalHit] {
        var seen: Set<String> = []
        var result: [BrainRetrievalHit] = []
        for hit in hits {
            let key = BrainNoveltySet.normalized(hit.text) ?? hit.text
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(hit)
        }
        return result
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

private extension Set where Element == String {
    func intersects(_ values: [String]) -> Bool {
        !intersection(values).isEmpty
    }
}
