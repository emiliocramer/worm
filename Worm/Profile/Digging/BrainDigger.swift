import Foundation

/// Runs a digging expedition: trails from local seeds, then rounds of
/// scout -> catalog search -> assay -> foreman until the pool clears a quality
/// bar or the money budget runs out. Time is never the constraint; dollars are.
///
/// Delegation is cost-routed: scouts and assayers run on the cheap tier,
/// the foreman on the mid tier. Every cheap-model failure is recoverable — a
/// bad query costs one empty catalog response, a wrong grade demotes a
/// candidate the shortlist can rescue. The output pool contains only tracks
/// that exist in the catalog and are brand new to the user.
struct BrainDigger {
    /// Catalog track search; wired to `SpotifyMusicNode.searchCatalogTracks`.
    /// Returns an empty array when the catalog is unavailable.
    let searchCatalog: @MainActor (String, Int) async -> [SpotifyTrack]

    /// Hard ceiling on total expedition rounds.
    var maxRounds = 3
    /// Hard money ceiling per pull, checked between rounds against the ledger.
    var budgetUSD = 0.35
    /// Pool quality bar: this many candidates at or above the score bar,
    /// spread across at least two trails (when two exist).
    var qualityBarCount = 12
    var qualityBarScore = 0.6
    var maxQueriesPerRound = 8
    var resultsPerQuery = 20
    var maxPool = 24
    /// Above this the pick is what a normal recommender would surface anyway.
    var popularityCeiling = 62
    var perArtistCap = 2

    @MainActor
    func dig(
        context: BrainContext,
        question: String,
        synthesizer: BrainSynthesizer?,
        memory: DigMemorySnapshot? = nil,
        ledger: SpendLedger? = nil,
        progress: ((String) -> Void)? = nil
    ) async -> DigResult {
        var log: [String] = []
        func emit(_ line: String) {
            log.append(line)
            progress?(line)
        }
        let ledgerStartCount = ledger?.records.count ?? 0
        func digSpend() -> [ModelCallRecord] {
            guard let ledger else { return [] }
            return Array(ledger.records.dropFirst(ledgerStartCount))
        }
        func result(trails: [BrainTrail], effects: [SecondaryEffectNode], pool: [DugCandidate], seedCount: Int, rounds: Int, stop: String, leads: [DigLead]) -> DigResult {
            DigResult(
                seedCount: seedCount,
                trails: trails,
                effectNodes: effects,
                pool: pool,
                log: log,
                generatedAt: Date(),
                rounds: rounds,
                stopReason: stop,
                leads: leads,
                spend: digSpend()
            )
        }

        let seeds = context.allSeeds
        guard !seeds.isEmpty else {
            emit("No seeds on any slice; nothing to dig. Falling back to propose-then-verify.")
            return result(trails: [], effects: [], pool: [], seedCount: 0, rounds: 0, stop: "no seeds", leads: [])
        }
        emit("Seeds: \(seeds.count) across \(Set(seeds.map(\.sourceNode)).count) nodes.")

        let built = BrainTrailBuilder.build(from: seeds)
        guard !built.trails.isEmpty else {
            emit("No hero journey cleared the evidence bar (\(BrainTrailBuilder.minimumJourneyScore)).")
            return result(trails: [], effects: [], pool: [], seedCount: seeds.count, rounds: 0, stop: "no trails", leads: [])
        }

        // Memory: journeys that won before rank first; graded leads from past
        // expeditions seed round 1 so the dig starts from proven ground.
        var trails = built.trails
        if let wins = memory?.journeyWins, !wins.isEmpty {
            trails.sort { lhs, rhs in
                let l = lhs.confidence + 0.05 * Double(min(wins[lhs.journey.rawValue] ?? 0, 4))
                let r = rhs.confidence + 0.05 * Double(min(wins[rhs.journey.rawValue] ?? 0, 4))
                return l > r
            }
        }
        emit("Trails: " + trails.map { "\($0.journey.title) (\(String(format: "%.2f", $0.confidence)))" }.joined(separator: ", "))

        var effects = built.effectNodes
        var allLeads: [DigLead] = []
        var seenLeadIDs = Set<String>()

        // Round-1 query plan: deterministic queries + scouts + memory leads.
        var pending: [(trail: BrainTrail, query: CatalogDigQuery)] = []
        for trail in trails {
            for query in trail.digQueries {
                pending.append((trail, query))
            }
        }
        if let synthesizer {
            for trail in trails {
                do {
                    let scouted = try await synthesizer.scoutQueries(question: question, trail: trail, context: context, ledger: ledger)
                    pending.append(contentsOf: scouted.map { (trail, $0) })
                    emit("Scout[\(trail.journey.title)] proposed \(scouted.count) queries.")
                } catch {
                    emit("Scout[\(trail.journey.title)] failed (\(error.localizedDescription)); trail digs deterministic queries only.")
                }
            }
        }
        if let memoryLeads = memory?.leads, !memoryLeads.isEmpty {
            let remembered = memoryLeads.sorted { $0.score > $1.score }.prefix(3)
            for lead in remembered where seenLeadIDs.insert(lead.id).inserted {
                allLeads.append(lead)
                pending.append((trails[0], CatalogDigQuery(
                    query: lead.queryHint,
                    rationale: "remembered lead: \(lead.title)",
                    provenance: .catalogSearch
                )))
            }
            emit("Memory seeded \(remembered.count) proven leads into round 1.")
        }

        let novelty = KnownMusic(context.novelty)
        var pool: [DugCandidate] = []
        var seenTracks = Set<String>()
        var artistCounts: [String: Int] = [:]
        var roundsRun = 0
        var stopReason = "round cap"

        expedition: for round in 1...maxRounds {
            roundsRun = round
            if pending.isEmpty {
                stopReason = round == 1 ? "no dig queries produced" : "no leads"
                emit("Round \(round): no queries to run; stopping.")
                break
            }
            var batch = pending
            if batch.count > maxQueriesPerRound {
                emit("Round \(round): capping \(batch.count) queries to \(maxQueriesPerRound).")
                batch = Array(batch.prefix(maxQueriesPerRound))
            }
            pending = []

            // Dig: run the round's queries and filter what comes back.
            var rejected: [String: Int] = [:]
            var newCandidates: [DugCandidate] = []
            for entry in batch {
                // Sanitize model-authored syntax, then chase zero-result
                // queries with progressive relaxation — catalog calls are free.
                var tracks: [SpotifyTrack] = []
                let variants = Self.sanitizedQueries(entry.query.query).prefix(2)
                for variant in variants {
                    var current = variant
                    var found = await searchCatalog(current, resultsPerQuery)
                    emit("\(current) -> \(found.count) results (\(entry.query.provenance.rawValue))")
                    var relaxations = 0
                    while found.isEmpty, relaxations < 3, let next = Self.relaxedQuery(current) {
                        relaxations += 1
                        current = next
                        found = await searchCatalog(current, resultsPerQuery)
                        emit("  relaxed -> \(current) -> \(found.count) results")
                    }
                    tracks.append(contentsOf: found)
                }
                for track in tracks {
                    guard let key = BrainNoveltySet.trackKey(title: track.name, artist: track.primaryArtist),
                          seenTracks.insert(key).inserted else { continue }
                    if let reason = rejectionReason(track, novelty: novelty) {
                        rejected[reason, default: 0] += 1
                        continue
                    }
                    let artistKey = BrainNoveltySet.normalized(track.primaryArtist) ?? track.primaryArtist
                    guard artistCounts[artistKey, default: 0] < perArtistCap else {
                        rejected["per-artist cap", default: 0] += 1
                        continue
                    }
                    artistCounts[artistKey, default: 0] += 1
                    newCandidates.append(DugCandidate(
                        id: track.id,
                        trailID: entry.trail.id,
                        journey: entry.trail.journey,
                        source: "Spotify",
                        title: track.name,
                        artist: track.primaryArtist,
                        album: track.album?.name,
                        releaseYear: track.album?.releaseDate.flatMap { Int($0.prefix(4)) },
                        popularity: track.popularity,
                        url: track.externalUrls?.spotify,
                        routeReason: entry.query.rationale
                    ))
                }
            }
            if !rejected.isEmpty {
                emit("Round \(round) rejected: " + rejected.sorted { $0.value > $1.value }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", "))
            }

            // Assay: grade the new candidates, drop the famous, extract leads.
            if let synthesizer, !newCandidates.isEmpty {
                do {
                    let assay = try await synthesizer.assay(candidates: newCandidates, round: round, context: context, ledger: ledger)
                    var famousDropped = 0
                    for grade in assay.grades where newCandidates.indices.contains(grade.index) {
                        newCandidates[grade.index].assayScore = min(max(grade.score, 0), 1)
                        newCandidates[grade.index].fameFlag = grade.famous
                        if grade.famous { famousDropped += 1 }
                    }
                    newCandidates.removeAll { $0.fameFlag == true }
                    if famousDropped > 0 {
                        emit("Assay dropped \(famousDropped) famous-artist candidates the data-only novelty filter missed.")
                    }
                    var freshLeads = 0
                    for raw in assay.leads {
                        let lead = DigLead(
                            title: raw.title,
                            kind: raw.kind,
                            entities: raw.entities,
                            queryHint: raw.queryHint,
                            evidence: "round \(round): \(raw.evidence)",
                            score: min(max(raw.score, 0), 1)
                        )
                        if seenLeadIDs.insert(lead.id).inserted {
                            allLeads.append(lead)
                            freshLeads += 1
                        }
                    }
                    emit("Assay r\(round): graded \(assay.grades.count), extracted \(freshLeads) fresh leads.")
                } catch {
                    emit("Assay r\(round) failed (\(error.localizedDescription)); candidates carry no grades this round.")
                }
            }
            pool.append(contentsOf: newCandidates)

            // Stopping rules, in order: quality bar, budget, round cap, foreman.
            let graded = pool.filter { ($0.assayScore ?? 0.55) >= qualityBarScore }
            let trailsRepresented = Set(graded.map(\.trailID)).count
            let barMet = graded.count >= qualityBarCount && trailsRepresented >= min(2, trails.count)
            if barMet {
                stopReason = "quality bar met"
                emit("Quality bar met: \(graded.count) graded candidates across \(trailsRepresented) trails.")
                break expedition
            }
            if let ledger, ledger.totalUSD >= budgetUSD {
                stopReason = "budget ceiling"
                emit("Budget ceiling hit: $\(String(format: "%.2f", ledger.totalUSD)) of $\(String(format: "%.2f", budgetUSD)).")
                break expedition
            }
            if round == maxRounds {
                stopReason = "round cap"
                emit("Round cap (\(maxRounds)) reached.")
                break expedition
            }
            guard let synthesizer else {
                stopReason = "single round (no delegated agents)"
                break expedition
            }

            // Foreman decides whether depth is worth the money.
            do {
                let summaryTop = pool.sorted { ($0.assayScore ?? 0.55) > ($1.assayScore ?? 0.55) }.prefix(10)
                    .map { candidate -> String in
                        let grade = candidate.assayScore.map { String(format: "assay %.2f", $0) } ?? "ungraded"
                        return "- \(candidate.title) by \(candidate.artist) [\(candidate.journey.title), \(grade)]"
                    }
                    .joined(separator: "\n")
                let ungraded = pool.filter { $0.assayScore == nil }.count
                let poolSummary = "\(pool.count) candidates (\(ungraded) ungraded — treat ungraded as unknown quality, not zero), \(graded.count) graded at/above \(qualityBarScore) across \(trailsRepresented) trails. Top:\n\(summaryTop)"
                let remaining = max(0, budgetUSD - (ledger?.totalUSD ?? 0))
                let decision = try await synthesizer.foreman(
                    poolSummary: poolSummary,
                    leads: allLeads,
                    trails: trails,
                    budgetRemainingUSD: remaining,
                    round: round,
                    context: context,
                    ledger: ledger
                )
                guard decision.continueDigging, !decision.followUps.isEmpty else {
                    stopReason = "foreman: \(decision.reason)"
                    emit("Foreman stopped the dig: \(decision.reason)")
                    break expedition
                }
                emit("Foreman digs deeper: \(decision.reason)")
                let trailsByID = Dictionary(uniqueKeysWithValues: trails.map { ($0.id, $0) })
                for followUp in decision.followUps.prefix(4) {
                    let trail = trailsByID[followUp.trailID] ?? trails[0]
                    pending.append((trail, CatalogDigQuery(
                        query: followUp.query,
                        rationale: followUp.rationale,
                        provenance: .catalogSearch
                    )))
                    // The chased lead becomes a depth-2/3 effect node with
                    // catalogSearch provenance: the relation came out of real
                    // catalog responses, and the foreman promoted it.
                    let matched = allLeads.first { followUp.query.localizedCaseInsensitiveContains($0.queryHint) || $0.queryHint.localizedCaseInsensitiveContains(followUp.query) }
                    effects.append(Self.effectNode(
                        forLead: matched,
                        followUp: followUp,
                        depth: min(3, round + 1)
                    ))
                }
            } catch {
                stopReason = "foreman failed"
                emit("Foreman failed (\(error.localizedDescription)); stopping with the current pool.")
                break expedition
            }
        }

        let assembled = assemblePool(pool, trailOrder: trails.map(\.id))
        emit("Pool: \(assembled.count) verified brand-new candidates after \(roundsRun) round\(roundsRun == 1 ? "" : "s") (\(stopReason)).")
        if let ledger {
            emit("Dig spend: \(ledger.summaryLine).")
        }
        return result(
            trails: trails,
            effects: dedupeEffects(effects),
            pool: assembled,
            seedCount: seeds.count,
            rounds: roundsRun,
            stop: stopReason,
            leads: allLeads
        )
    }

    // MARK: - Query hygiene

    /// Spotify search has no boolean operators and only two real tags; a
    /// single invalid token zeroes the whole query. Split ORs into separate
    /// queries and strip made-up tags before anything hits the catalog.
    static func sanitizedQueries(_ raw: String) -> [String] {
        let parts = raw
            .replacingOccurrences(of: " OR ", with: "\u{1}", options: [.caseInsensitive])
            .split(separator: "\u{1}")
            .map { String($0) }
        return parts.compactMap { part -> String? in
            let cleaned = collapsed(removing(pattern: "tag:(?!hipster\\b|new\\b)\\S+", from: part))
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    /// Progressive relaxation for a query that returned zero results: drop the
    /// popularity tag, turn `genre:` into plain words (Spotify's track-search
    /// genre taxonomy misses most scene names), drop the year window, then
    /// strip remaining field prefixes. Returns nil when nothing is left to try.
    static func relaxedQuery(_ query: String) -> String? {
        let steps: [(String) -> String] = [
            { removing(pattern: "tag:\\S+", from: $0) },
            { removing(pattern: "genre:", from: $0) },
            { removing(pattern: "year:\\S+", from: $0) },
            { removing(pattern: "(label|artist|album|track):", from: $0) },
        ]
        for step in steps {
            let candidate = collapsed(step(query))
            if !candidate.isEmpty, candidate != query {
                return candidate
            }
        }
        return nil
    }

    private static func removing(pattern: String, from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
    }

    private static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - Depth-2/3 effect nodes

    /// Maps an assayer lead (or a bare foreman follow-up) to a derived effect
    /// node. Exposed for tests.
    static func effectNode(forLead lead: DigLead?, followUp: BrainSynthesizer.ForemanDecision.FollowUp, depth: Int) -> SecondaryEffectNode {
        let type: SecondaryEffectType
        switch lead?.kind {
        case "labelRoster": type = .labelCatalog
        case "eraCluster": type = .eraGap
        case "scene": type = .placeScene
        default: type = .genreScene
        }
        let title = lead?.title ?? followUp.rationale
        return SecondaryEffectNode(
            id: "effect/\(type.rawValue)/\(BrainNoveltySet.normalized(title) ?? title.lowercased())",
            title: title,
            effectType: type,
            relation: followUp.rationale,
            sourceSeedIDs: [],
            evidence: [lead?.evidence ?? "foreman follow-up: \(followUp.query)"] + (lead?.entities.prefix(6).map { "seen in results: \($0)" } ?? []),
            provenance: .catalogSearch,
            confidence: lead?.score ?? 0.5,
            depth: depth
        )
    }

    private func dedupeEffects(_ effects: [SecondaryEffectNode]) -> [SecondaryEffectNode] {
        var seen = Set<String>()
        return effects.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Filters

    private struct KnownMusic {
        let tracks: Set<String>
        let artists: Set<String>
        let albums: Set<String>

        init(_ novelty: BrainNoveltySet) {
            tracks = Set(novelty.knownTrackKeys)
            artists = Set(novelty.knownArtistKeys)
            albums = Set(novelty.knownAlbumKeys)
        }
    }

    /// Karaoke farms, tribute factories, and functional-audio spam that field
    /// searches drag in.
    private static let junkMarkers: [String] = [
        "karaoke", "tribute", "originally performed", "made famous",
        "in the style of", "lullaby", "8-bit", "8 bit", "kidz",
        "workout remix", "sleep baby", "music box version",
    ]

    private func rejectionReason(_ track: SpotifyTrack, novelty: KnownMusic) -> String? {
        if let key = BrainNoveltySet.trackKey(title: track.name, artist: track.primaryArtist),
           novelty.tracks.contains(key) {
            return "known track"
        }
        for artist in track.artists {
            if let key = BrainNoveltySet.normalized(artist.name), novelty.artists.contains(key) {
                return "known artist"
            }
        }
        if let album = track.album?.name,
           let key = BrainNoveltySet.normalized(album), novelty.albums.contains(key) {
            return "known album"
        }
        let haystack = [track.name, track.album?.name ?? "", track.artistLine].joined(separator: " ").lowercased()
        if Self.junkMarkers.contains(where: { haystack.contains($0) }) {
            return "junk"
        }
        if let popularity = track.popularity, popularity > popularityCeiling {
            return "too popular"
        }
        return nil
    }

    /// Interleave trails round-robin so one loud route cannot drown the pool.
    /// Within a trail, assay grades rank first, obscurity breaks ties.
    private func assemblePool(_ pool: [DugCandidate], trailOrder: [String]) -> [DugCandidate] {
        var byTrail: [String: [DugCandidate]] = [:]
        for candidate in pool {
            byTrail[candidate.trailID, default: []].append(candidate)
        }
        var queues = trailOrder.compactMap { id -> [DugCandidate]? in
            guard var candidates = byTrail[id], !candidates.isEmpty else { return nil }
            candidates.sort { rank($0) > rank($1) }
            return candidates
        }
        var assembled: [DugCandidate] = []
        while assembled.count < maxPool, !queues.isEmpty {
            for index in queues.indices.reversed() {
                guard assembled.count < maxPool else { break }
                assembled.append(queues[index].removeFirst())
                if queues[index].isEmpty { queues.remove(at: index) }
            }
        }
        return assembled
    }

    private func rank(_ candidate: DugCandidate) -> Double {
        (candidate.assayScore ?? 0.55) * 2 + obscurityScore(candidate)
    }

    /// The sweet spot is real-but-unheard: mid-low popularity beats both the
    /// chart and the noise floor (popularity 0 is often junk metadata).
    private func obscurityScore(_ candidate: DugCandidate) -> Double {
        guard let popularity = candidate.popularity else { return 0.5 }
        switch popularity {
        case 6...45: return 1.0
        case 0...5: return 0.6
        default: return 0.7 - Double(popularity - 45) / 100
        }
    }
}
