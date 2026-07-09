import Foundation

/// The digging patterns from `docs/digging-journeys/hero-journeys.md`, as code.
/// Each case carries an evidence predicate over typed seeds; a journey with no
/// provable brain signal scores zero and builds no trail. Journeys that need
/// credit or person-to-music relations stay dormant until V1 enrichment: no
/// local data, no journey.
enum HeroJourney: String, Codable, CaseIterable, Hashable, Identifiable {
    case closedDoorArtist
    case missedChapter
    case sourceDNA
    case contextFlip
    case oneRecordForRightNow
    case cheapRiskBin
    case localOddity
    case ignoredOnlineCrate
    case liveRoom
    case textureRoute
    case albumFirstDig
    case humanCuratorThread

    var id: String { rawValue }

    var title: String {
        switch self {
        case .closedDoorArtist: return "The Closed Door Artist"
        case .missedChapter: return "The Missed Chapter"
        case .sourceDNA: return "Source DNA"
        case .contextFlip: return "The Context Flip"
        case .oneRecordForRightNow: return "One Record For Right Now"
        case .cheapRiskBin: return "The Cheap-Risk Bin"
        case .localOddity: return "The Local Oddity"
        case .ignoredOnlineCrate: return "The Ignored Online Crate"
        case .liveRoom: return "The Live Room"
        case .textureRoute: return "The Texture Route"
        case .albumFirstDig: return "The Album-First Dig"
        case .humanCuratorThread: return "The Human Curator Thread"
        }
    }

    /// Producer credits and person-to-music links have no local proof; these
    /// activate when the enrichment service exists.
    var requiresEnrichment: Bool {
        switch self {
        case .closedDoorArtist, .humanCuratorThread: return true
        default: return false
        }
    }

    /// Canonical aesthetic-seed titles the extractor emits and predicates read.
    enum SignalSeed {
        static let crateDigger = "crate digger"
        static let liveRooms = "live rooms"
        static let albumListener = "album listener"
        static let textureEar = "texture ear"
    }

    /// Genres whose culture repurposes and samples older records.
    static let sampleCultureGenres: Set<String> = [
        "hip hop", "hip-hop", "rap", "trip hop", "breakbeat", "drum and bass",
        "house", "techno", "disco", "funk", "soul", "neo soul", "r&b",
        "electronic", "edm", "lo-fi", "lofi", "boom bap", "plunderphonics",
    ]

    /// How strongly the local evidence supports this dig pattern, 0...1.
    func score(_ seeds: [BrainSeed]) -> Double {
        guard !requiresEnrichment else { return 0 }

        func best(_ type: SeedEntityType, titled: String? = nil) -> Double {
            var maxStrength = 0.0
            for seed in seeds where seed.entityType == type {
                if let titled, seed.title != titled { continue }
                maxStrength = max(maxStrength, seed.strength)
            }
            return maxStrength
        }

        switch self {
        case .closedDoorArtist, .humanCuratorThread:
            return 0
        case .missedChapter:
            // A durable obsession plus a diggable gap next to it: a label or an era cluster.
            var durableArtist = 0.0
            for seed in seeds where seed.entityType == .artist && seed.strength >= 0.75 {
                durableArtist = max(durableArtist, seed.strength)
            }
            guard durableArtist > 0 else { return 0 }
            let gap = max(best(.label), best(.era))
            guard gap > 0 else { return 0 }
            return min(1, 0.5 * durableArtist + 0.5 * gap)
        case .sourceDNA, .contextFlip:
            // Sample-culture genres open the backward/sideways dig into source eras.
            var culture = 0.0
            for seed in seeds where seed.entityType == .genre {
                let lower = seed.title.lowercased()
                if Self.sampleCultureGenres.contains(where: { lower.contains($0) }) {
                    culture = max(culture, seed.strength)
                }
            }
            guard culture > 0 else { return 0 }
            return min(1, culture * (self == .sourceDNA ? 0.95 : 0.85))
        case .oneRecordForRightNow:
            return best(.routine) * 0.9
        case .cheapRiskBin:
            return best(.aesthetic, titled: SignalSeed.crateDigger)
        case .localOddity:
            let place = best(.place)
            guard place > 0, best(.genre) > 0 else { return 0 }
            return place * 0.9
        case .ignoredOnlineCrate:
            let creators = seeds.filter { $0.entityType == .creator }
            guard creators.count >= 3 else { return 0 }
            let strength = creators.map(\.strength).max() ?? 0
            return min(1, 0.4 + strength * 0.5)
        case .liveRoom:
            return best(.aesthetic, titled: SignalSeed.liveRooms)
        case .textureRoute:
            return best(.aesthetic, titled: SignalSeed.textureEar)
        case .albumFirstDig:
            let albums = best(.aesthetic, titled: SignalSeed.albumListener)
            guard albums > 0, best(.label) > 0 else { return 0 }
            return albums
        }
    }
}
