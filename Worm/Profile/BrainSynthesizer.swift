import Foundation

/// The only model-facing synthesis/query layer. Nodes feed evidence dossiers and
/// compact slices into `BrainContext`; this type runs the staged pipeline —
/// hunt candidates, then adversarially judge and voice them — and answers direct
/// queries. It never talks to node managers directly.
struct BrainSynthesizer {
    struct SynthesisResult: Codable {
        struct RawInsight: Codable {
            let line: String
            let evidence: String
            let confidence: Double
        }

        let read: String
        let insights: [RawInsight]
    }

    /// One observation from the hunt stage: a claim with cited evidence, before
    /// any voice or confidence is applied. The judge grades these, not the hunter.
    struct CandidateObservation: Codable {
        let claim: String
        let evidence: String
        let lens: String
        let whyNotGeneric: String
    }

    private struct HuntResult: Codable {
        let candidates: [CandidateObservation]
    }

    var client = ClaudeClient.fromInfoPlist()

    // MARK: - Synthesis (hunt -> judge+write)

    func synthesize(
        _ context: BrainContext,
        mode: BrainSynthesisMode,
        kind: BrainSynthesisKind = .profile,
        avoiding: [String] = [],
        ledger: SpendLedger? = nil
    ) async throws -> SynthesisResult {
        let candidates = try await runHunts(context, mode: mode, kind: kind, avoiding: avoiding, ledger: ledger)
        if candidates.isEmpty {
            // Data too thin for a hunt to land anything: fall back to the direct
            // single-shot path rather than returning silence.
            return try await singleShot(context, mode: mode, kind: kind, avoiding: avoiding, ledger: ledger)
        }
        return try await judgeAndWrite(
            candidates,
            context: context,
            mode: mode,
            kind: kind,
            avoiding: avoiding,
            ledger: ledger
        )
    }

    private func runHunts(
        _ context: BrainContext,
        mode: BrainSynthesisMode,
        kind: BrainSynthesisKind,
        avoiding: [String],
        ledger: SpendLedger? = nil
    ) async throws -> [CandidateObservation] {
        // Deep pulls run two hunts with different emphasis so the judge sees
        // observations from independent angles; quick (first insight) runs one.
        let emphases: [String?] = mode.huntPasses >= 2
            ? [
                "Emphasize the time, durability, and ritual lenses.",
                "Emphasize the depth, contradiction, and world-crossing lenses.",
            ]
            : [nil]

        // Hunts are independent; one surviving pass is enough to judge from.
        // Collect per-task results so a transient failure (overload, timeout)
        // in one pass cannot discard the other's candidates.
        let outcomes = await withTaskGroup(of: Result<[CandidateObservation], Error>.self) { group in
            for emphasis in emphases {
                group.addTask {
                    do {
                        return .success(try await self.hunt(context, mode: mode, kind: kind, avoiding: avoiding, emphasis: emphasis, ledger: ledger))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var collected: [Result<[CandidateObservation], Error>] = []
            for await outcome in group { collected.append(outcome) }
            return collected
        }

        var results: [CandidateObservation] = []
        var lastError: Error?
        for outcome in outcomes {
            switch outcome {
            case .success(let batch): results.append(contentsOf: batch)
            case .failure(let error): lastError = error
            }
        }
        if results.isEmpty, let lastError { throw lastError }

        // Dedupe near-identical claims across passes.
        var seen = Set<String>()
        return results.filter { candidate in
            let key = BrainNoveltySet.normalized(candidate.claim) ?? candidate.claim
            return seen.insert(key).inserted
        }
    }

    private func hunt(
        _ context: BrainContext,
        mode: BrainSynthesisMode,
        kind: BrainSynthesisKind,
        avoiding: [String],
        emphasis: String?,
        ledger: SpendLedger? = nil
    ) async throws -> [CandidateObservation] {
        var user = context.promptText
        if let emphasis { user += "\n\n\(emphasis)" }
        if !avoiding.isEmpty {
            user += "\n\nObservations already surfaced to the user. Do not re-derive these:\n"
                + avoiding.map { "- \($0)" }.joined(separator: "\n")
        }

        let completion = try await client.structuredCompletion(
            system: BrainPromptLibrary.huntPrompt(kind: kind),
            user: user,
            schema: Self.huntSchema,
            effort: mode.huntEffort,
            maxTokens: 12288,
            speed: mode.speed
        )
        ledger?.record(stage: "hunt", effort: mode.huntEffort, completion: completion)
        return (try JSONDecoder().decode(HuntResult.self, from: Data(completion.text.utf8))).candidates
    }

    private func judgeAndWrite(
        _ candidates: [CandidateObservation],
        context: BrainContext,
        mode: BrainSynthesisMode,
        kind: BrainSynthesisKind,
        avoiding: [String],
        ledger: SpendLedger? = nil
    ) async throws -> SynthesisResult {
        let candidateText = candidates.enumerated().map { index, candidate in
            """
            Candidate \(index + 1) [\(candidate.lens)]
            Claim: \(candidate.claim)
            Evidence: \(candidate.evidence)
            Why not generic: \(candidate.whyNotGeneric)
            """
        }.joined(separator: "\n\n")

        var user = """
        \(context.promptText)

        Candidate observations from the hunting pass:

        \(candidateText)
        """
        if !avoiding.isEmpty {
            user += "\n\nAlready surfaced. Do not repeat or paraphrase these:\n"
                + avoiding.map { "- \($0)" }.joined(separator: "\n")
        }

        var fallback: SynthesisResult?
        for _ in 0..<2 {
            let completion = try await client.structuredCompletion(
                system: BrainPromptLibrary.judgeWritePrompt(kind: kind),
                user: user,
                schema: Self.synthesisSchema,
                effort: mode.judgeEffort,
                speed: mode.speed
            )
            ledger?.record(stage: "judge+write", effort: mode.judgeEffort, completion: completion)
            let result = try JSONDecoder().decode(SynthesisResult.self, from: Data(completion.text.utf8))
            if !result.insights.isEmpty { return result }
            fallback = fallback ?? result
        }
        return fallback ?? SynthesisResult(read: "", insights: [])
    }

    /// The pre-harness single-shot path, kept as the thin-data fallback.
    private func singleShot(
        _ context: BrainContext,
        mode: BrainSynthesisMode,
        kind: BrainSynthesisKind,
        avoiding: [String],
        ledger: SpendLedger? = nil
    ) async throws -> SynthesisResult {
        var user = context.promptText
        if !avoiding.isEmpty {
            user += "\n\nAlready surfaced. Do not repeat or paraphrase these:\n"
                + avoiding.map { "- \($0)" }.joined(separator: "\n")
        }
        let completion = try await client.structuredCompletion(
            system: BrainPromptLibrary.synthesisSystemPrompt(kind: kind),
            user: user,
            schema: Self.synthesisSchema,
            effort: mode.judgeEffort,
            speed: mode.speed
        )
        ledger?.record(stage: "single-shot", effort: mode.judgeEffort, completion: completion)
        return try JSONDecoder().decode(SynthesisResult.self, from: Data(completion.text.utf8))
    }

    // MARK: - Taste brief

    /// The compact profile every delegated dig agent reads: the read, the
    /// surfaced insights, and each populated slice's summary line. A couple of
    /// kilotokens, not the full retrieval dump.
    static func tasteBrief(_ context: BrainContext) -> String {
        var lines: [String] = []
        if let read = context.read, !read.isEmpty { lines.append("Read: \(read)") }
        if !context.insights.isEmpty {
            lines.append("Surfaced insights: \(context.insights.prefix(6).map(\.line).joined(separator: " | "))")
        }
        for slice in context.populatedSlices where !slice.summary.isEmpty {
            lines.append("\(slice.title): \(slice.summary)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Digging agents (delegated tiers)

    struct ScoutQuery: Codable {
        let query: String
        let rationale: String
    }

    private struct ScoutResult: Codable { let queries: [ScoutQuery] }

    /// Scout (Haiku): one trail in, 1-3 catalog query hypotheses out.
    func scoutQueries(
        question: String,
        trail: BrainTrail,
        context: BrainContext,
        ledger: SpendLedger? = nil
    ) async throws -> [CatalogDigQuery] {
        var user = """
        User question: \(question)

        Taste brief:
        \(Self.tasteBrief(context))

        Trail:
        Journey: \(trail.journey.title)
        Route: \(trail.routeSummary)
        Evidence: \(trail.evidence.joined(separator: " | "))
        Deterministic queries already planned: \(trail.digQueries.map(\.query).joined(separator: " ; "))

        \(context.noveltyPromptSample(limit: 25))
        """
        if trail.journey == .openCrate {
            // The open crate carries no idiom of its own: hand the scout the
            // full menu so every digging move is available to every profile,
            // whether or not its evidence gate fired.
            user += "\n\nDigging idioms menu — pick whichever fits this taste brief best and name it in each rationale:\n\(HeroJourney.idiomMenu)"
        }
        let completion = try await client.structuredCompletion(
            system: BrainPromptLibrary.scoutPrompt,
            user: user,
            schema: Self.scoutSchema,
            effort: "low",
            maxTokens: 2048,
            model: BrainModel.cheap
        )
        ledger?.record(stage: "scout:\(trail.journey.rawValue)", effort: "low", completion: completion)
        let result = try JSONDecoder().decode(ScoutResult.self, from: Data(completion.text.utf8))
        return result.queries.prefix(3).map {
            CatalogDigQuery(query: $0.query, rationale: $0.rationale, provenance: .modelHypothesis)
        }
    }

    struct AssayGrade: Codable {
        let index: Int
        let score: Double
        let famous: Bool
    }

    struct AssayResult: Codable {
        let grades: [AssayGrade]
        let leads: [AssayLead]
    }

    struct AssayLead: Codable {
        let title: String
        let kind: String
        let entities: [String]
        let queryHint: String
        let evidence: String
        let score: Double
    }

    /// Assayer (Haiku): grade a batch of dug candidates and extract leads.
    func assay(
        candidates: [DugCandidate],
        round: Int,
        context: BrainContext,
        ledger: SpendLedger? = nil
    ) async throws -> AssayResult {
        let rows = candidates.enumerated().map { index, candidate in
            var meta: [String] = []
            if let album = candidate.album, !album.isEmpty { meta.append(album) }
            if let year = candidate.releaseYear { meta.append(String(year)) }
            if let pop = candidate.popularity { meta.append("popularity \(pop)") }
            let suffix = meta.isEmpty ? "" : " (\(meta.joined(separator: ", ")))"
            return "\(index). \(candidate.title) by \(candidate.artist)\(suffix) [route: \(candidate.journey.title), via: \(candidate.routeReason)]"
        }.joined(separator: "\n")

        let user = """
        Taste brief:
        \(Self.tasteBrief(context))

        Round \(round) catalog results to grade (0-indexed):
        \(rows)
        """
        let completion = try await client.structuredCompletion(
            system: BrainPromptLibrary.assayPrompt,
            user: user,
            schema: Self.assaySchema,
            effort: "low",
            maxTokens: 6144,
            model: BrainModel.cheap
        )
        ledger?.record(stage: "assay:r\(round)", effort: "low", completion: completion)
        return try JSONDecoder().decode(AssayResult.self, from: Data(completion.text.utf8))
    }

    struct ForemanDecision: Codable {
        struct FollowUp: Codable {
            let trailID: String
            let query: String
            let rationale: String
        }

        let continueDigging: Bool
        let reason: String
        let followUps: [FollowUp]
    }

    /// Foreman (Sonnet): decide whether the expedition digs another round.
    func foreman(
        poolSummary: String,
        leads: [DigLead],
        trails: [BrainTrail],
        budgetRemainingUSD: Double,
        round: Int,
        context: BrainContext,
        ledger: SpendLedger? = nil
    ) async throws -> ForemanDecision {
        let leadLines = leads.isEmpty
            ? "none"
            : leads.map { "- [\($0.kind), score \(String(format: "%.2f", $0.score))] \($0.title): \($0.entities.prefix(6).joined(separator: ", ")) | queryHint: \($0.queryHint) | \($0.evidence)" }.joined(separator: "\n")
        let trailLines = trails.map { "- \($0.id): \($0.journey.title)" }.joined(separator: "\n")

        let user = """
        Taste brief:
        \(Self.tasteBrief(context))

        After round \(round), graded pool:
        \(poolSummary)

        Leads extracted this expedition:
        \(leadLines)

        Trails (use these ids on follow-ups):
        \(trailLines)

        Budget remaining: $\(String(format: "%.2f", budgetRemainingUSD)). A follow-up round costs roughly $0.05.

        Digging idioms menu (framings you may borrow for follow-up queries):
        \(HeroJourney.idiomMenu)
        """
        let completion = try await client.structuredCompletion(
            system: BrainPromptLibrary.foremanPrompt,
            user: user,
            schema: Self.foremanSchema,
            effort: "medium",
            maxTokens: 2048,
            model: BrainModel.mid
        )
        ledger?.record(stage: "foreman:r\(round)", effort: "medium", completion: completion)
        return try JSONDecoder().decode(ForemanDecision.self, from: Data(completion.text.utf8))
    }

    struct ShortlistResult: Codable {
        struct Pick: Codable {
            let index: Int
            let reason: String
        }

        let picks: [Pick]
    }

    /// Shortlist (Sonnet): score the graded pool down to 5-7 for the judge.
    func shortlist(
        pool: [DugCandidate],
        question: String,
        context: BrainContext,
        recent: [String] = [],
        ledger: SpendLedger? = nil
    ) async throws -> [(candidate: DugCandidate, reason: String)] {
        let rows = pool.enumerated().map { index, candidate in
            var meta: [String] = []
            if let album = candidate.album, !album.isEmpty { meta.append(album) }
            if let year = candidate.releaseYear { meta.append(String(year)) }
            if let pop = candidate.popularity { meta.append("popularity \(pop)") }
            if let score = candidate.assayScore { meta.append("assay \(String(format: "%.2f", score))") }
            return "\(index). \(candidate.title) by \(candidate.artist) (\(meta.joined(separator: ", "))) [route: \(candidate.journey.title), via: \(candidate.routeReason)]"
        }.joined(separator: "\n")

        var user = """
        User question: \(question)

        Taste brief:
        \(Self.tasteBrief(context))

        Graded pool (0-indexed):
        \(rows)
        """
        if !recent.isEmpty {
            user += "\n\nRecently surfaced picks (keep the shortlist varied against these; prefer candidates opening a different corner):\n"
                + recent.map { "- \($0)" }.joined(separator: "\n")
        }
        let completion = try await client.structuredCompletion(
            system: BrainPromptLibrary.shortlistPrompt,
            user: user,
            schema: Self.shortlistSchema,
            effort: "high",
            maxTokens: 4096,
            model: BrainModel.mid
        )
        ledger?.record(stage: "shortlist", effort: "high", completion: completion)
        let result = try JSONDecoder().decode(ShortlistResult.self, from: Data(completion.text.utf8))
        return result.picks.compactMap { pick in
            guard pool.indices.contains(pick.index) else { return nil }
            return (pool[pick.index], pick.reason)
        }
    }

    // MARK: - Query

    func answer(_ query: BrainQuery, context: BrainContext, dig: DigResult? = nil, ledger: SpendLedger? = nil) async throws -> BrainAnswer {
        var retrieved = BrainRetriever.retrieve(query: query.text, from: context)
        if let dig { retrieved.trails = dig.trails }

        // Judge split: with a dug pool, the judge gets a Sonnet-graded
        // shortlist plus the compact taste brief instead of the full retrieval
        // dump plus the raw pool. Ranking a small vetted plate is the explicit
        // only task, which is both cheaper and sturdier than the old path.
        var user: String
        if let dig, dig.hasPool {
            var plate = dig.pool
            do {
                let picks = try await shortlist(pool: dig.pool, question: query.text, context: context, recent: dig.recentPicks ?? [], ledger: ledger)
                if !picks.isEmpty {
                    plate = picks.map { pick in
                        let candidate = pick.candidate
                        // Carry the shortlist reason forward as the route line.
                        return DugCandidate(
                            id: candidate.id,
                            trailID: candidate.trailID,
                            journey: candidate.journey,
                            source: candidate.source,
                            title: candidate.title,
                            artist: candidate.artist,
                            album: candidate.album,
                            releaseYear: candidate.releaseYear,
                            popularity: candidate.popularity,
                            url: candidate.url,
                            routeReason: pick.reason,
                            assayScore: candidate.assayScore,
                            fameFlag: candidate.fameFlag
                        )
                    }
                }
            } catch {
                // Shortlist failure is recoverable: the judge sees the full pool.
            }

            let plateLines = plate.enumerated().map { index, candidate -> String in
                var meta: [String] = []
                if let album = candidate.album, !album.isEmpty { meta.append(album) }
                if let year = candidate.releaseYear { meta.append(String(year)) }
                if let pop = candidate.popularity { meta.append("popularity \(pop)") }
                let suffix = meta.isEmpty ? "" : " (\(meta.joined(separator: ", ")))"
                return "\(index + 1). \(candidate.title) by \(candidate.artist)\(suffix) — \(candidate.routeReason) [route: \(candidate.journey.title)]"
            }.joined(separator: "\n")

            let routeLines = dig.trails.map { "- [\($0.journey.title)] \($0.routeSummary)" }.joined(separator: "\n")

            user = """
            User question:
            \(query.text)

            Taste brief:
            \(Self.tasteBrief(context))

            Digging routes:
            \(routeLines)

            Verified candidate shortlist. Every entry is a real catalog track that already passed the user's full novelty memory and a grading pass:
            \(plateLines)
            """
            if let recent = dig.recentPicks, !recent.isEmpty {
                user += "\n\nRecently surfaced picks. Vary the angle: a pick that repeats the same artist, scene, or genre as these must clear a much higher bar than one that opens a new corner of the taste brief:\n"
                    + recent.map { "- \($0)" }.joined(separator: "\n")
            }
        } else {
            user = """
            User question:
            \(query.text)

            \(retrieved.promptText)

            \(context.noveltyPromptSample())
            """
            if let dig {
                user += "\n\n\(dig.promptText)"
            }
        }

        if !query.rejectedRecommendations.isEmpty {
            user += "\n\nRejected because they failed local novelty or catalog-verification checks:\n"
                + query.rejectedRecommendations.map { "- \($0)" }.joined(separator: "\n")
        }

        // Recommendations are the product's proof point and have no latency
        // budget; give them the deepest reasoning tier. Adaptive thinking
        // shares max_tokens with the answer, and a heavy prompt starving the
        // budget produces degenerate empty JSON.
        let effort = retrieved.intent == .musicRecommendation ? "xhigh" : "high"
        let completion = try await client.structuredCompletion(
            system: BrainPromptLibrary.queryPrompt,
            user: user,
            schema: Self.querySchema,
            effort: effort,
            maxTokens: retrieved.intent == .musicRecommendation ? 20000 : 8192,
            model: BrainModel.judge
        )
        ledger?.record(stage: "judge", effort: effort, completion: completion)
        return try JSONDecoder()
            .decode(BrainAnswer.self, from: Data(completion.text.utf8))
            .withRetrieval(retrieved)
    }

    // MARK: - Schemas

    private static let scoutSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "properties": [
            "queries": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "query": ["type": "string"],
                        "rationale": ["type": "string"],
                    ],
                    "required": ["query", "rationale"],
                ],
            ],
        ],
        "required": ["queries"],
    ]

    private static let assaySchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "properties": [
            "grades": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "index": ["type": "integer"],
                        "score": ["type": "number"],
                        "famous": ["type": "boolean"],
                    ],
                    "required": ["index", "score", "famous"],
                ],
            ],
            "leads": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "title": ["type": "string"],
                        "kind": ["type": "string"],
                        "entities": ["type": "array", "items": ["type": "string"]],
                        "queryHint": ["type": "string"],
                        "evidence": ["type": "string"],
                        "score": ["type": "number"],
                    ],
                    "required": ["title", "kind", "entities", "queryHint", "evidence", "score"],
                ],
            ],
        ],
        "required": ["grades", "leads"],
    ]

    private static let foremanSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "properties": [
            "continueDigging": ["type": "boolean"],
            "reason": ["type": "string"],
            "followUps": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "trailID": ["type": "string"],
                        "query": ["type": "string"],
                        "rationale": ["type": "string"],
                    ],
                    "required": ["trailID", "query", "rationale"],
                ],
            ],
        ],
        "required": ["continueDigging", "reason", "followUps"],
    ]

    private static let shortlistSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "properties": [
            "picks": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "index": ["type": "integer"],
                        "reason": ["type": "string"],
                    ],
                    "required": ["index", "reason"],
                ],
            ],
        ],
        "required": ["picks"],
    ]

    private static let huntSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "properties": [
            "candidates": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "claim": ["type": "string"],
                        "evidence": ["type": "string"],
                        "lens": ["type": "string"],
                        "whyNotGeneric": ["type": "string"],
                    ],
                    "required": ["claim", "evidence", "lens", "whyNotGeneric"],
                ],
            ],
        ],
        "required": ["candidates"],
    ]

    private static let synthesisSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "properties": [
            "read": ["type": "string"],
            "insights": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "line": ["type": "string"],
                        "evidence": ["type": "string"],
                        "confidence": ["type": "number"],
                        // Forces the judge to articulate the simulated snob
                        // reaction per line; decoded nowhere, load-bearing anyway.
                        "snobReaction": ["type": "string"],
                    ],
                    "required": ["line", "evidence", "confidence", "snobReaction"],
                ],
            ],
        ],
        "required": ["read", "insights"],
    ]

    private static let recommendationSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "properties": [
            "title": ["type": "string"],
            "artist": ["type": "string"],
            "album": ["type": "string"],
            "why": ["type": "string"],
            "noveltyRationale": ["type": "string"],
            "noveltyStatus": ["type": "string"],
        ],
        "required": ["title", "artist", "album", "why", "noveltyRationale"],
    ]

    private static let querySchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "properties": [
            "answer": ["type": "string"],
            "evidence": [
                "type": "array",
                "items": ["type": "string"],
            ],
            "confidence": ["type": "number"],
            "recommendations": [
                "type": "array",
                "items": recommendationSchema,
            ],
        ],
        // recommendations is required so the model must emit the key: the
        // observed failure mode was naming picks in the answer text while
        // omitting the array entirely.
        "required": ["answer", "evidence", "confidence", "recommendations"],
    ]
}
