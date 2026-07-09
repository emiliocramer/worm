import Foundation

/// Derives secondary effect nodes and ranked trails from typed seeds, with the
/// deterministic catalog queries that walk them. Pure and on-device: every
/// effect node cites the seeds that produced it, and every deterministic query
/// is built only from local metadata (labels, genres, eras, places). The leaps
/// that need world knowledge are left to the model's query proposal, whose
/// results the catalog still has to confirm.
enum BrainTrailBuilder {
    struct Output {
        let trails: [BrainTrail]
        let effectNodes: [SecondaryEffectNode]
    }

    /// Journeys below this evidence score build no trail.
    static let minimumJourneyScore = 0.35

    static func build(from seeds: [BrainSeed], maxTrails: Int = 4) -> Output {
        guard !seeds.isEmpty else { return Output(trails: [], effectNodes: []) }

        let scored = HeroJourney.allCases
            .map { (journey: $0, score: $0.score(seeds)) }
            .filter { $0.score >= minimumJourneyScore }
            .sorted { $0.score > $1.score }
            .prefix(maxTrails)

        var effects: [SecondaryEffectNode] = []
        var trails: [BrainTrail] = []
        for entry in scored {
            let built = trail(for: entry.journey, score: entry.score, seeds: seeds)
            trails.append(built.trail)
            effects.append(contentsOf: built.effects)
        }

        var seen = Set<String>()
        let uniqueEffects = effects.filter { seen.insert($0.id).inserted }
        return Output(trails: trails, effectNodes: uniqueEffects)
    }

    // MARK: - Per-journey trails

    private static func trail(
        for journey: HeroJourney,
        score: Double,
        seeds: [BrainSeed]
    ) -> (trail: BrainTrail, effects: [SecondaryEffectNode]) {
        let genres = strongest(seeds, .genre, limit: 3)
        let labels = strongest(seeds, .label, limit: 2)
        let places = strongest(seeds, .place, limit: 2)
        let routines = strongest(seeds, .routine, limit: 2)
        let creators = strongest(seeds, .creator, limit: 4)
        let era = strongest(seeds, .era, limit: 1).first
        let durableArtist = seeds
            .filter { $0.entityType == .artist }
            .max { $0.strength < $1.strength }

        var effects: [SecondaryEffectNode] = []
        var queries: [CatalogDigQuery] = []
        var usedSeeds: [BrainSeed] = []
        var summary = journey.title

        func addEffect(
            _ type: SecondaryEffectType,
            title: String,
            relation: String,
            sources: [BrainSeed],
            confidence: Double
        ) {
            effects.append(SecondaryEffectNode(
                id: "effect/\(type.rawValue)/\(BrainNoveltySet.normalized(title) ?? title.lowercased())",
                title: title,
                effectType: type,
                relation: relation,
                sourceSeedIDs: sources.map(\.id),
                evidence: sources.flatMap(\.evidence),
                provenance: .localNodeData,
                confidence: confidence,
                depth: type == .eraGap ? 2 : 1
            ))
            usedSeeds.append(contentsOf: sources)
        }

        func addQuery(_ query: String, _ rationale: String) {
            queries.append(CatalogDigQuery(query: query, rationale: rationale, provenance: .localNodeData))
        }

        switch journey {
        case .missedChapter:
            let anchor = durableArtist?.title ?? "a durable favorite"
            for label in labels {
                addEffect(.labelCatalog, title: label.title,
                          relation: "the label's catalog outside the library",
                          sources: [label], confidence: label.strength)
                if let gapRanges = eraGaps(era) {
                    for gap in gapRanges {
                        addQuery("label:\"\(label.title)\" year:\(gap.lowerBound)-\(gap.upperBound)",
                                 "\(label.title) signings in the years just outside the \(era?.title ?? "core") cluster")
                    }
                } else {
                    addQuery("label:\"\(label.title)\"", "the \(label.title) catalog beyond the saved albums")
                }
            }
            if labels.isEmpty, let era, let gapRanges = eraGaps(era), let genre = genres.first {
                addEffect(.eraGap, title: "outside \(era.title)",
                          relation: "the neglected years around the listening cluster",
                          sources: [era, genre], confidence: min(era.strength, genre.strength))
                for gap in gapRanges {
                    addQuery("genre:\"\(genre.title)\" year:\(gap.lowerBound)-\(gap.upperBound)",
                             "\(genre.title) records from the neglected years around \(era.title)")
                }
            }
            if let durableArtist { usedSeeds.append(durableArtist) }
            summary = "Durable interest in \(anchor); dig the gap next to it, never the artist's own catalog."

        case .sourceDNA:
            // Scan every genre seed, not the overall top-3: the sample-culture
            // genre is often not the loudest one in the profile.
            let cultureGenres = seeds
                .filter { seed in
                    seed.entityType == .genre &&
                        HeroJourney.sampleCultureGenres.contains(where: { seed.title.lowercased().contains($0) })
                }
                .sorted { $0.strength > $1.strength }
                .prefix(2)
            for genre in cultureGenres {
                let window = sourceWindow(era)
                addEffect(.genreScene, title: "\(genre.title) source records",
                          relation: "the older records the scene samples and repurposes",
                          sources: [genre], confidence: genre.strength)
                addQuery("genre:\"\(genre.title)\" year:\(window.lowerBound)-\(window.upperBound)",
                         "source-era \(genre.title) records behind the sample culture they live in")
            }
            summary = "Sample-culture taste; move backward into the source records."

        case .contextFlip:
            if let genre = genres.first {
                addEffect(.genreScene, title: "\(genre.title) recontextualized",
                          relation: "records that became something else in a new room",
                          sources: [genre], confidence: genre.strength)
            }
            summary = "A scene that repurposes older music; find the track that changed rooms."

        case .oneRecordForRightNow:
            for routine in routines {
                addEffect(.routineUseCase, title: routine.title,
                          relation: "a listening use case with a record shape",
                          sources: [routine], confidence: routine.strength)
            }
            summary = "A real routine (\(routines.map(\.title).joined(separator: ", "))); search by desired effect before genre."

        case .cheapRiskBin:
            for genre in genres.prefix(2) {
                addEffect(.genreScene, title: "\(genre.title) long tail",
                          relation: "the ignored pile inside a loved genre",
                          sources: [genre], confidence: genre.strength)
                addQuery("genre:\"\(genre.title)\" tag:hipster",
                         "lowest-popularity corner of \(genre.title)")
                if let era, let range = era.eraRange {
                    addQuery("genre:\"\(genre.title)\" year:\(range.lowerBound)-\(range.upperBound)",
                             "\(genre.title) records from their core years, filtered to the unheard")
                }
            }
            summary = "Comfort with low-popularity finds; simulate the bargain bin."

        case .localOddity:
            for place in places {
                addEffect(.placeScene, title: place.title,
                          relation: "a place anchor pointing at a local scene",
                          sources: [place], confidence: place.strength)
                if let genre = genres.first {
                    addQuery("\"\(place.title)\" genre:\"\(genre.title)\"",
                             "\(genre.title) records tied to \(place.title)")
                }
            }
            summary = "Place anchors (\(places.map(\.title).joined(separator: ", "))); search from place outward."

        case .ignoredOnlineCrate:
            for creator in creators {
                addEffect(.creatorLens, title: creator.title,
                          relation: "a trusted creator lens onto low-attention catalog",
                          sources: [creator], confidence: creator.strength)
            }
            summary = "Lives in digital discovery spaces; treat the internet like a messy shop."

        case .liveRoom:
            if let genre = genres.first {
                addQuery("genre:\"\(genre.title)\" \"live at\"",
                         "live rooms inside \(genre.title)")
            }
            if let era, let range = era.eraRange {
                addQuery("\"live at\" year:\(range.lowerBound)-\(range.upperBound)",
                         "live recordings from their core years")
            }
            if let live = seeds.first(where: { $0.entityType == .aesthetic && $0.title == HeroJourney.SignalSeed.liveRooms }) {
                addEffect(.textureRoute, title: "the live room",
                          relation: "recordings where the band breathes",
                          sources: [live], confidence: live.strength)
            }
            summary = "Live recordings keep recurring; dig sessions, concert sets, alternate takes."

        case .textureRoute:
            if let texture = seeds.first(where: { $0.entityType == .aesthetic && $0.title == HeroJourney.SignalSeed.textureEar }) {
                addEffect(.textureRoute, title: "recording character",
                          relation: "sound-object qualities worth searching by",
                          sources: [texture], confidence: texture.strength)
            }
            summary = "Responds to recording character; search by texture before composition."

        case .albumFirstDig:
            for label in labels {
                addEffect(.labelCatalog, title: label.title,
                          relation: "a label whose records they trust whole",
                          sources: [label], confidence: label.strength)
                addQuery("label:\"\(label.title)\"", "album-first entry points on \(label.title)")
            }
            summary = "Saves whole records; find the album path first, then the song."

        case .closedDoorArtist, .humanCuratorThread:
            summary = "\(journey.title) requires enrichment; dormant."
        }

        var seenSeedIDs = Set<String>()
        let seedIDs = usedSeeds.filter { seenSeedIDs.insert($0.id).inserted }.map(\.id)
        let evidence = usedSeeds.flatMap(\.evidence)

        let trail = BrainTrail(
            id: "trail/\(journey.rawValue)",
            journey: journey,
            seedIDs: seedIDs,
            effectNodeIDs: effects.map(\.id),
            routeSummary: summary,
            digQueries: queries,
            evidence: Array(evidence.prefix(8)),
            confidence: score,
            noveltyPolicy: .strict
        )
        return (trail, effects)
    }

    // MARK: - Helpers

    private static func strongest(_ seeds: [BrainSeed], _ type: SeedEntityType, limit: Int) -> [BrainSeed] {
        Array(seeds.filter { $0.entityType == type }.sorted { $0.strength > $1.strength }.prefix(limit))
    }

    /// The eight years on each side of an era cluster, clamped to plausible
    /// release years.
    private static func eraGaps(_ era: BrainSeed?) -> [ClosedRange<Int>]? {
        guard let range = era?.eraRange else { return nil }
        let currentYear = Calendar.current.component(.year, from: Date())
        var gaps: [ClosedRange<Int>] = []
        let before = (range.lowerBound - 8)...(range.lowerBound - 1)
        if before.lowerBound >= 1940 { gaps.append(before) }
        let after = (range.upperBound + 1)...min(range.upperBound + 8, currentYear)
        if after.lowerBound <= currentYear { gaps.append(after) }
        return gaps.isEmpty ? nil : gaps
    }

    /// Where the source records live: two to three decades before the era
    /// cluster, or the canonical crate window when no cluster exists.
    private static func sourceWindow(_ era: BrainSeed?) -> ClosedRange<Int> {
        guard let range = era?.eraRange else { return 1965...1979 }
        let upper = max(1955, range.lowerBound - 15)
        let lower = max(1945, range.lowerBound - 30)
        return lower...max(lower, upper)
    }
}
