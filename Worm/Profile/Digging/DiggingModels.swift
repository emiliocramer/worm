import Foundation

/// Typed entities the digging layer works over. Seeds are extracted from the
/// nodes' structured data (never re-parsed from slice prose), effect nodes and
/// trails are derived on demand, and dug candidates only ever come from real
/// catalog responses. See `docs/secondary-effect-nodes.md`.

enum SeedEntityType: String, Codable, Hashable {
    case artist
    case album
    case label
    case genre
    case era
    case creator
    case topic
    case place
    case routine
    case aesthetic
}

/// A directly observed, evidence-backed entity from a primary node.
struct BrainSeed: Codable, Hashable, Identifiable {
    let id: String
    let sourceNode: BrainNodeID
    let entityType: SeedEntityType
    let title: String
    let subtitle: String?
    let evidence: [String]
    /// 0...1, how load-bearing this seed is for the profile.
    let strength: Double
    let freshness: Date?

    init(
        sourceNode: BrainNodeID,
        entityType: SeedEntityType,
        title: String,
        subtitle: String? = nil,
        evidence: [String],
        strength: Double,
        freshness: Date? = nil
    ) {
        self.id = Self.makeID(sourceNode, entityType, title)
        self.sourceNode = sourceNode
        self.entityType = entityType
        self.title = title
        self.subtitle = subtitle
        self.evidence = evidence
        self.strength = min(max(strength, 0), 1)
        self.freshness = freshness
    }

    static func makeID(_ node: BrainNodeID, _ type: SeedEntityType, _ title: String) -> String {
        "\(node.rawValue)/\(type.rawValue)/\(BrainNoveltySet.normalized(title) ?? title.lowercased())"
    }

    /// Era seeds carry their span in the title ("1996-2004").
    var eraRange: ClosedRange<Int>? {
        let parts = title.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, parts[0] <= parts[1] else { return nil }
        return parts[0]...parts[1]
    }
}

/// Only relations local node data can prove. Credit-shaped types
/// (producerCredit, sideProject, sampleSource, …) arrive with V1 enrichment —
/// an effect node that cannot cite local evidence may not exist.
enum SecondaryEffectType: String, Codable, Hashable {
    case labelCatalog
    case eraGap
    case genreScene
    case placeScene
    case routineUseCase
    case creatorLens
    case textureRoute
}

enum EffectProvenance: String, Codable, Hashable {
    case localNodeData
    case modelHypothesis
    case catalogSearch
    case metadataEnrichment
    case userConfirmed
}

/// A derived relation between seeds and a diggable direction.
struct SecondaryEffectNode: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let effectType: SecondaryEffectType
    let relation: String
    let sourceSeedIDs: [String]
    let evidence: [String]
    let provenance: EffectProvenance
    let confidence: Double
    let depth: Int
}

/// The single deliberate novelty stance. Relaxing it for side-project or
/// live-version digs means adding a case here and amending the vision doc,
/// not loosening a filter somewhere.
enum NoveltyPolicy: String, Codable, Hashable {
    case strict
}

/// One concrete catalog search that walks a trail. Deterministic queries carry
/// `localNodeData` provenance; model-proposed ones carry `modelHypothesis` —
/// either way only the catalog response promotes results to facts.
struct CatalogDigQuery: Codable, Hashable {
    let query: String
    let rationale: String
    let provenance: EffectProvenance
}

/// An ordered rabbit-hole path with the queries that dig it.
struct BrainTrail: Codable, Hashable, Identifiable {
    let id: String
    let journey: HeroJourney
    let seedIDs: [String]
    let effectNodeIDs: [String]
    let routeSummary: String
    var digQueries: [CatalogDigQuery]
    let evidence: [String]
    let confidence: Double
    let noveltyPolicy: NoveltyPolicy
}

/// A real catalog track that survived novelty, junk, and obviousness filters.
/// These are the only candidates the model is allowed to rank.
struct DugCandidate: Codable, Hashable, Identifiable {
    let id: String
    let trailID: String
    let journey: HeroJourney
    let source: String
    let title: String
    let artist: String
    let album: String?
    let releaseYear: Int?
    let popularity: Int?
    let url: String?
    let routeReason: String
    /// Assayer grade, 0...1: fit against the taste brief, judged cheaply
    /// before the shortlist ever sees the pool. Optional so pre-assay digs decode.
    var assayScore: Double? = nil
    /// Assayer's fame check: plausibly world-famous even though absent from
    /// the user's data. Fame-flagged candidates are dropped from the pool.
    var fameFlag: Bool? = nil

    var trackKey: String? {
        BrainNoveltySet.trackKey(title: title, artist: artist)
    }
}

/// A thread worth pulling, extracted by an assayer from real catalog
/// responses: a label roster, an era cluster, an artist network. Leads become
/// depth-2/3 effect nodes and follow-up queries when the foreman accepts
/// them, and persist in `DigMemorySnapshot` so future digs start deeper.
struct DigLead: Codable, Hashable, Identifiable {
    let title: String
    /// "labelRoster" | "eraCluster" | "artistNetwork" | "scene"
    let kind: String
    let entities: [String]
    /// The catalog query that would chase this lead.
    let queryHint: String
    /// Which round/query surfaced it — provenance for the depth-2 node.
    let evidence: String
    let score: Double

    var id: String { "\(kind)/\(BrainNoveltySet.normalized(title) ?? title.lowercased())" }
}

/// Winning journeys and graded leads carried across pulls. Each dig starts
/// from what previous expeditions already proved instead of re-discovering it.
struct DigMemorySnapshot: Codable, Hashable {
    var journeyWins: [String: Int] = [:]
    var leads: [DigLead] = []
    var updatedAt: Date? = nil
}

/// Everything one dig produced, attached to the answer path and the brain log.
struct DigResult: Codable, Hashable {
    let seedCount: Int
    let trails: [BrainTrail]
    let effectNodes: [SecondaryEffectNode]
    let pool: [DugCandidate]
    let log: [String]
    let generatedAt: Date
    /// How many expedition rounds ran. Optional so Revision A messages decode.
    var rounds: Int? = nil
    /// Why the expedition stopped: "quality bar met" | "budget ceiling" |
    /// "round cap" | "no leads" | error text.
    var stopReason: String? = nil
    /// Leads extracted from catalog responses (accepted or not) this dig.
    var leads: [DigLead]? = nil
    /// Priced model calls made inside the dig (scouts, assayers, foreman).
    var spend: [ModelCallRecord]? = nil

    var hasPool: Bool { !pool.isEmpty }

    /// The section the answer prompt reads. Routes first, then the verified
    /// pool the model must pick from.
    var promptText: String {
        var lines: [String] = []
        if !trails.isEmpty {
            lines.append("Digging routes derived from local evidence:")
            for trail in trails {
                lines.append("- [\(trail.journey.title)] \(trail.routeSummary) (confidence \(String(format: "%.2f", trail.confidence)))")
            }
        }
        if pool.isEmpty {
            lines.append("")
            lines.append("Verified candidate pool: empty. The dig found nothing that cleared novelty and catalog filters.")
        } else {
            lines.append("")
            lines.append("Verified candidate pool. Every entry is a real catalog track that already passed the user's full novelty memory:")
            for (index, candidate) in pool.enumerated() {
                var meta: [String] = []
                if let album = candidate.album, !album.isEmpty { meta.append(album) }
                if let year = candidate.releaseYear { meta.append(String(year)) }
                if let pop = candidate.popularity { meta.append("popularity \(pop)") }
                let suffix = meta.isEmpty ? "" : " (\(meta.joined(separator: ", ")))"
                lines.append("\(index + 1). \(candidate.title) by \(candidate.artist)\(suffix) — \(candidate.routeReason) [route: \(candidate.journey.title)]")
            }
        }
        return lines.joined(separator: "\n")
    }
}
