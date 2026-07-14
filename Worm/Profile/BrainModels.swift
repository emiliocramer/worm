import Foundation

enum BrainNodeID: String, Codable, CaseIterable, Hashable, Identifiable {
    case spotify
    case appleMusic
    case youtube
    case contacts
    case photos
    case calendar
    case selfie
    case prompts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        case .youtube: return "YouTube"
        case .contacts: return "Contacts"
        case .photos: return "Photos"
        case .calendar: return "Calendar"
        case .selfie: return "Selfie"
        case .prompts: return "Prompts"
        }
    }
}

enum BrainSynthesisMode: String, Codable {
    case quick
    case deep

    /// Effort for the hunt stage. Hunting is coverage work under explicit
    /// instructions; `quick` (the ~20s onboarding budget) runs it at medium and
    /// lets the judge hold the quality bar.
    var huntEffort: String {
        switch self {
        case .quick: return "medium"
        case .deep: return "high"
        }
    }

    /// Effort for the judge+write stage. `deep` pulls are time-unbounded.
    var judgeEffort: String {
        switch self {
        case .quick: return "high"
        case .deep: return "xhigh"
        }
    }

    /// Fast mode (same model, up to 2.5x output speed, premium price) for the
    /// latency-bound first insight; deep pulls take the cheap slow path.
    var speed: String? {
        switch self {
        case .quick: return "fast"
        case .deep: return nil
        }
    }

    /// How many parallel hunt passes to run. Passes run concurrently, so the
    /// first insight gets both lens sets at no wall-clock cost.
    var huntPasses: Int {
        switch self {
        case .quick: return 2
        case .deep: return 2
        }
    }
}

enum BrainQueryIntent: String, Codable, Hashable {
    case musicRecommendation
    case music
    case visual
    case schedule
    case general

    var title: String {
        switch self {
        case .musicRecommendation: return "Music recommendation"
        case .music: return "Music"
        case .visual: return "Visual"
        case .schedule: return "Schedule"
        case .general: return "General"
        }
    }
}

struct BrainNoveltySet: Codable, Hashable {
    var knownTrackKeys: [String] = []
    var knownArtistKeys: [String] = []
    var knownAlbumKeys: [String] = []

    var isEmpty: Bool {
        knownTrackKeys.isEmpty && knownArtistKeys.isEmpty && knownAlbumKeys.isEmpty
    }

    var trackCount: Int { knownTrackKeys.count }
    var artistCount: Int { knownArtistKeys.count }
    var albumCount: Int { knownAlbumKeys.count }

    mutating func insertTrack(title: String?, artist: String?) {
        guard let key = Self.trackKey(title: title, artist: artist) else { return }
        knownTrackKeys.append(key)
    }

    mutating func insertArtist(_ name: String?) {
        guard let key = Self.normalized(name), !key.isEmpty else { return }
        knownArtistKeys.append(key)
    }

    mutating func insertAlbum(_ title: String?) {
        guard let key = Self.normalized(title), !key.isEmpty else { return }
        knownAlbumKeys.append(key)
    }

    func merged(with other: BrainNoveltySet) -> BrainNoveltySet {
        BrainNoveltySet(
            knownTrackKeys: Self.uniqued(knownTrackKeys + other.knownTrackKeys),
            knownArtistKeys: Self.uniqued(knownArtistKeys + other.knownArtistKeys),
            knownAlbumKeys: Self.uniqued(knownAlbumKeys + other.knownAlbumKeys)
        )
    }

    func noveltyIssue(for recommendation: BrainMusicRecommendation) -> String? {
        let trackKey = Self.trackKey(title: recommendation.title, artist: recommendation.artist)
        let artistKey = Self.normalized(recommendation.artist)
        let albumKey = Self.normalized(recommendation.album)
        if let trackKey, knownTrackKeys.contains(trackKey) {
            return "known track"
        }
        if let artistKey, knownArtistKeys.contains(artistKey) {
            return "known artist"
        }
        if let albumKey, knownAlbumKeys.contains(albumKey) {
            return "known album"
        }
        return nil
    }

    static func trackKey(title: String?, artist: String?) -> String? {
        guard let title = normalized(title), !title.isEmpty else { return nil }
        let artist = normalized(artist) ?? ""
        return "\(artist)|\(title)"
    }

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func uniqued(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }
}

struct BrainRetrievalHit: Codable, Hashable, Identifiable {
    let id: String
    let nodeID: BrainNodeID
    let kind: String
    let text: String
    let score: Double
    let confidence: Double

    var nodeTitle: String { nodeID.title }
}

struct BrainRetrievedContext: Codable, Hashable {
    let queryText: String
    let intent: BrainQueryIntent
    let graphSummary: [String]
    let hits: [BrainRetrievalHit]
    let generatedAt: Date
    /// Digging trails attached for music recommendation pulls. Optional so
    /// older persisted chat history decodes.
    var trails: [BrainTrail]? = nil

    var evidenceLines: [String] {
        hits.map { hit in
            "\(hit.nodeTitle) \(hit.kind): \(hit.text)"
        }
    }

    var promptText: String {
        var lines = [
            "Retrieved brain context generated at: \(generatedAt.formatted(date: .abbreviated, time: .shortened))",
            "Query intent: \(intent.title)",
            "Question: \(queryText)",
        ]

        if !graphSummary.isEmpty {
            lines.append("")
            lines.append("Graph summary:")
            lines.append(contentsOf: graphSummary.map { "- \($0)" })
        }

        if hits.isEmpty {
            lines.append("")
            lines.append("Retrieved memories: none")
        } else {
            lines.append("")
            lines.append("Retrieved memories:")
            lines.append(contentsOf: hits.map { hit in
                "- [\(hit.nodeTitle) / \(hit.kind) / score \(String(format: "%.2f", hit.score))] \(hit.text)"
            })
        }

        return lines.joined(separator: "\n")
    }
}

struct NodeBrainSlice: Codable, Hashable, Identifiable {
    let nodeID: BrainNodeID
    let isConnected: Bool
    let isPopulated: Bool
    let summary: String
    let facts: [String]
    let evidence: [String]
    let chunks: [String]
    let freshness: Date?
    let confidence: Double
    let health: String
    let novelty: BrainNoveltySet
    /// Item-level evidence document for synthesis (see `BrainDossier`). Optional so
    /// older persisted snapshots decode; retrieval keeps using facts/evidence/chunks.
    var dossier: String? = nil
    /// Typed entities for the digging layer (see `BrainSeedExtractor`). Optional
    /// for the same decode-compatibility reason as `dossier`.
    var seeds: [BrainSeed]? = nil

    var id: BrainNodeID { nodeID }
    var title: String { nodeID.title }

    var promptText: String {
        var lines = [
            "Node: \(title)",
            "Connected: \(isConnected ? "yes" : "no")",
            "Populated: \(isPopulated ? "yes" : "no")",
            "Health: \(health)",
            "Confidence: \(String(format: "%.2f", confidence))",
        ]
        if let freshness {
            lines.append("Freshness: \(freshness.formatted(date: .abbreviated, time: .shortened))")
        }
        if !summary.isEmpty { lines.append("Summary: \(summary)") }
        if !facts.isEmpty { lines.append("Facts: \(facts.joined(separator: " | "))") }
        if !evidence.isEmpty { lines.append("Evidence: \(evidence.joined(separator: " | "))") }
        if let dossier, !dossier.isEmpty {
            lines.append("Evidence dossier:")
            lines.append(dossier)
        } else if !chunks.isEmpty {
            lines.append("Memory chunks:")
            lines.append(contentsOf: chunks.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }
}

struct BrainContext: Codable, Hashable {
    var slices: [NodeBrainSlice]
    var read: String?
    var insights: [Insight]
    var generatedAt: Date = Date()

    var populatedSlices: [NodeBrainSlice] {
        slices.filter(\.isPopulated)
    }

    var hasSignal: Bool {
        populatedSlices.contains { !$0.summary.isEmpty || !$0.facts.isEmpty || !$0.chunks.isEmpty }
    }

    var novelty: BrainNoveltySet {
        slices.reduce(BrainNoveltySet()) { $0.merged(with: $1.novelty) }
    }

    /// Structured entities across every populated slice; the trail builder's input.
    var allSeeds: [BrainSeed] {
        slices.flatMap { $0.seeds ?? [] }
    }

    var promptText: String {
        var lines: [String] = [
            "Brain context generated at: \(generatedAt.formatted(date: .abbreviated, time: .shortened))",
            "Populated nodes: \(populatedSlices.count)/\(BrainNodeID.allCases.count)",
        ]
        if let read, !read.isEmpty {
            lines.append("Existing private read: \(read)")
        }
        if !insights.isEmpty {
            lines.append("Existing surfaced insights: \(insights.map(\.line).joined(separator: " | "))")
        }
        lines.append("")
        lines.append("Node slices:")
        lines.append(slices.map(\.promptText).joined(separator: "\n\n"))
        return lines.joined(separator: "\n")
    }

    func noveltyIssue(for recommendation: BrainMusicRecommendation) -> String? {
        novelty.noveltyIssue(for: recommendation)
    }

    func noveltyPromptSample(limit: Int = 80) -> String {
        let novelty = novelty
        let artists = novelty.knownArtistKeys.prefix(limit).joined(separator: ", ")
        let tracks = novelty.knownTrackKeys.prefix(limit).joined(separator: ", ")
        var lines = [
            "Known music exclusion counts: \(novelty.trackCount) tracks, \(novelty.artistCount) artists, \(novelty.albumCount) albums."
        ]
        if !artists.isEmpty { lines.append("Known artist sample to avoid: \(artists)") }
        if !tracks.isEmpty { lines.append("Known track sample to avoid: \(tracks)") }
        return lines.joined(separator: "\n")
    }
}

struct BrainQuery: Codable, Hashable {
    let text: String
    var rejectedRecommendations: [String] = []
}

struct BrainMusicRecommendation: Codable, Hashable {
    let title: String
    let artist: String
    let album: String?
    let why: String
    let noveltyRationale: String
    var noveltyStatus: String?
    var catalogStatus: String?
    var catalogURL: String?
}

struct BrainCatalogCandidate: Codable, Hashable, Identifiable {
    let source: String
    let title: String
    let artist: String
    let album: String?
    let url: String?

    var id: String {
        "\(source)|\(title)|\(artist)|\(album ?? "")"
    }
}

struct BrainCatalogVerification: Codable, Hashable {
    let isVerified: Bool
    let canVerify: Bool
    let source: String
    let message: String
    let match: BrainCatalogCandidate?
    let candidates: [BrainCatalogCandidate]

    static func unavailable(_ source: String, message: String) -> BrainCatalogVerification {
        BrainCatalogVerification(
            isVerified: false,
            canVerify: false,
            source: source,
            message: message,
            match: nil,
            candidates: []
        )
    }
}

struct BrainAnswer: Codable, Hashable {
    let answer: String
    let evidence: [String]
    let confidence: Double
    /// The surfaced pick after novelty + catalog checks.
    var recommendation: BrainMusicRecommendation?
    /// Ranked candidates from the model, best first. The brain walks this list
    /// through local novelty and catalog verification before surfacing one.
    var recommendations: [BrainMusicRecommendation]? = nil
    var retrieval: BrainRetrievedContext? = nil
    /// The full dig behind a music recommendation: seeds, trails, queries, and
    /// the verified pool. Persists with the chat message for the debug surface.
    var dig: DigResult? = nil
    /// The step-by-step pipeline trace shown live while answering and kept on
    /// the message afterward.
    var trace: [String]? = nil
    /// Every priced model call behind this answer (dig fleet + shortlist +
    /// judge). Persists with the message for the Spend debug surface.
    var spend: [ModelCallRecord]? = nil

    /// All candidates worth checking, in rank order.
    var rankedCandidates: [BrainMusicRecommendation] {
        if let recommendations, !recommendations.isEmpty { return recommendations }
        return recommendation.map { [$0] } ?? []
    }

    func choosing(_ pick: BrainMusicRecommendation?) -> BrainAnswer {
        var copy = self
        copy.recommendation = pick
        return copy
    }

    func withNoveltyStatus(_ status: String) -> BrainAnswer {
        var copy = self
        copy.recommendation?.noveltyStatus = status
        return copy
    }

    func withCatalogVerification(_ verification: BrainCatalogVerification) -> BrainAnswer {
        var copy = self
        copy.recommendation?.catalogStatus = verification.message
        copy.recommendation?.catalogURL = verification.match?.url
        return copy
    }

    func withRetrieval(_ retrieval: BrainRetrievedContext) -> BrainAnswer {
        var copy = self
        copy.retrieval = retrieval
        return copy
    }
}

struct BrainChatMessage: Codable, Hashable, Identifiable {
    enum Role: String, Codable {
        case user
        case brain
    }

    let id: UUID
    let role: Role
    let text: String
    let answer: BrainAnswer?
    let createdAt: Date

    init(role: Role, text: String, answer: BrainAnswer? = nil, createdAt: Date = Date()) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.answer = answer
        self.createdAt = createdAt
    }
}
