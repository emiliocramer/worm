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
    // Journeys 13-18, derived from real digging stories 008-012 plus the
    // always-runs floor. See docs/digging-journeys/hero-journeys.md.
    case aliasSideDoor
    case producerChain
    case songwriterShadow
    case versionChain
    case anonymousDrop
    case openCrate
    // Journeys 19-21, from sourced stories 013-015.
    case diasporaThread
    case splitAndDemo
    case interpretationChain

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
        case .aliasSideDoor: return "The Alias & Side Door"
        case .producerChain: return "The Producer Chain"
        case .songwriterShadow: return "The Songwriter's Shadow"
        case .versionChain: return "The Version Chain"
        case .anonymousDrop: return "The Anonymous Drop"
        case .openCrate: return "The Open Crate"
        case .diasporaThread: return "The Diaspora Thread"
        case .splitAndDemo: return "The Split & Demo"
        case .interpretationChain: return "The Interpretation Chain"
        }
    }

    /// One-line digging idiom. The Open Crate scout and the foreman see the
    /// full menu, so every idiom is available to every profile even when its
    /// evidence gate did not fire — idioms are moves, not claims.
    var idiom: String {
        switch self {
        case .closedDoorArtist: return "skip the obvious artist's hits; enter through producers, side players, and collaborators"
        case .missedChapter: return "dig the neglected years and labelmates just outside a loved era"
        case .sourceDNA: return "move backward into the source records a scene samples and repurposes"
        case .contextFlip: return "find the track that became something else in a new room, country, or scene"
        case .oneRecordForRightNow: return "search by desired effect before genre; one record for the current state"
        case .cheapRiskBin: return "simulate the bargain bin: overstock, odd labels, poor sellers, forgotten comps"
        case .localOddity: return "search from a place outward: regional labels, city scenes, imported sounds"
        case .ignoredOnlineCrate: return "treat the internet like a messy shop: tiny labels, old uploads, weak metadata"
        case .liveRoom: return "live versions, radio sessions, archival sets where the band breathes"
        case .textureRoute: return "search by recording character: tape, room, crackle, remaster clarity"
        case .albumFirstDig: return "find the album path first, then the entrance track"
        case .humanCuratorThread: return "follow a trusted person, not a genre"
        case .aliasSideDoor: return "follow the person out of the band: side projects, aliases, label-evasion drops"
        case .producerChain: return "follow the beat tag into the producer's own records"
        case .songwriterShadow: return "follow the writing credit into the songwriter's own catalog"
        case .versionChain: return "find the riddim under the tune and walk everyone who voiced it"
        case .anonymousDrop: return "releases that evade the promo machine: surprise drops, anonymous collectives"
        case .openCrate: return "read the whole brief and pick the corner worth digging"
        case .diasporaThread: return "follow a heritage lineage: the canon that crossed over and the scenes that reworked it"
        case .splitAndDemo: return "dig the DIY formats: the other side of the split, the demo before the album"
        case .interpretationChain: return "same work, different hands: the reading that disagrees with the famous one"
        }
    }

    /// The full idiom menu handed to open-ended scouts and the foreman.
    static var idiomMenu: String {
        allCases.map { "- \($0.title): \($0.idiom)" }.joined(separator: "\n")
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

    /// Producer-driven scenes where the beat tag is half the identity.
    static let producerCultureGenres: Set<String> = [
        "trap", "hip hop", "hip-hop", "rap", "drill", "grime", "plugg",
        "rage", "cloud rap", "boom bap", "atl", "southern hip hop",
    ]

    /// Written-song scenes where following the credit lands in a
    /// songwriter's own catalog.
    static let songwriterGenres: Set<String> = [
        "country", "folk", "singer-songwriter", "singer songwriter",
        "americana", "alt-country", "bluegrass", "nashville",
    ]

    /// Version-culture scenes built on riddims, dubs, and recuts.
    static let versionCultureGenres: Set<String> = [
        "reggae", "dub", "dancehall", "ska", "rocksteady", "roots reggae",
        "lovers rock",
    ]

    /// Heritage-lineage genres: music that travels through families and
    /// migrations rather than charts.
    static let heritageGenres: Set<String> = [
        "cumbia", "corridos", "corrido", "banda", "norteño", "norteno",
        "regional mexican", "mariachi", "ranchera", "bolero", "salsa",
        "bachata", "merengue", "vallenato", "latin", "musica mexicana",
        "highlife", "afrobeats", "amapiano", "soukous", "rai", "fado",
        "rebetiko", "bollywood", "ghazal",
    ]

    /// DIY-scene genres where splits, demos, and EPs are the discovery format.
    static let diyGenres: Set<String> = [
        "hardcore", "punk", "metalcore", "screamo", "emo", "grindcore",
        "powerviolence", "crust", "d-beat", "death metal", "black metal",
        "thrash", "sludge", "doom", "post-hardcore", "noise rock",
    ]

    /// Work-first scenes where the performer is the discovery axis.
    static let classicalGenres: Set<String> = [
        "classical", "baroque", "opera", "orchestral", "chamber", "symphony",
        "early music", "contemporary classical", "romantic era", "choral",
        "piano", "cello", "violin",
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
        case .aliasSideDoor:
            // A playlist named after an artist is the loudest local devotion
            // signal there is (the Deftones -> Team Sleep shape).
            return best(.devotion) * 0.95
        case .producerChain:
            return genreMatch(Self.producerCultureGenres, in: seeds) * 0.9
        case .songwriterShadow:
            return genreMatch(Self.songwriterGenres, in: seeds) * 0.85
        case .versionChain:
            return genreMatch(Self.versionCultureGenres, in: seeds) * 0.9
        case .anonymousDrop:
            return best(.aesthetic, titled: SignalSeed.crateDigger) * 0.8
        case .openCrate:
            // The floor: barely clears the bar so the expedition always runs,
            // and every evidenced journey outranks it.
            return seeds.isEmpty ? 0 : 0.36
        case .diasporaThread:
            // Heritage genres carry it; a place seed strengthens the lineage.
            let heritage = genreMatch(Self.heritageGenres, in: seeds)
            guard heritage > 0 else { return 0 }
            let placeAssist = best(.place) > 0 ? 0.05 : 0
            return min(1, heritage * 0.85 + placeAssist)
        case .splitAndDemo:
            return genreMatch(Self.diyGenres, in: seeds) * 0.9
        case .interpretationChain:
            return genreMatch(Self.classicalGenres, in: seeds) * 0.9
        }
    }

    private func genreMatch(_ vocabulary: Set<String>, in seeds: [BrainSeed]) -> Double {
        var strongest = 0.0
        for seed in seeds where seed.entityType == .genre {
            let lower = seed.title.lowercased()
            if vocabulary.contains(where: { lower.contains($0) }) {
                strongest = max(strongest, seed.strength)
            }
        }
        return strongest
    }
}
