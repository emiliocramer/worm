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
        avoiding: [String] = []
    ) async throws -> SynthesisResult {
        let candidates = try await runHunts(context, mode: mode, kind: kind, avoiding: avoiding)
        if candidates.isEmpty {
            // Data too thin for a hunt to land anything: fall back to the direct
            // single-shot path rather than returning silence.
            return try await singleShot(context, mode: mode, kind: kind, avoiding: avoiding)
        }
        return try await judgeAndWrite(
            candidates,
            context: context,
            mode: mode,
            kind: kind,
            avoiding: avoiding
        )
    }

    private func runHunts(
        _ context: BrainContext,
        mode: BrainSynthesisMode,
        kind: BrainSynthesisKind,
        avoiding: [String]
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
                        return .success(try await self.hunt(context, mode: mode, kind: kind, avoiding: avoiding, emphasis: emphasis))
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
        emphasis: String?
    ) async throws -> [CandidateObservation] {
        var user = context.promptText
        if let emphasis { user += "\n\n\(emphasis)" }
        if !avoiding.isEmpty {
            user += "\n\nObservations already surfaced to the user. Do not re-derive these:\n"
                + avoiding.map { "- \($0)" }.joined(separator: "\n")
        }

        let text = try await client.structuredCompletion(
            system: BrainPromptLibrary.huntPrompt(kind: kind),
            user: user,
            schema: Self.huntSchema,
            effort: mode.huntEffort,
            maxTokens: 12288,
            speed: mode.speed
        )
        return (try JSONDecoder().decode(HuntResult.self, from: Data(text.utf8))).candidates
    }

    private func judgeAndWrite(
        _ candidates: [CandidateObservation],
        context: BrainContext,
        mode: BrainSynthesisMode,
        kind: BrainSynthesisKind,
        avoiding: [String]
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
            let text = try await client.structuredCompletion(
                system: BrainPromptLibrary.judgeWritePrompt(kind: kind),
                user: user,
                schema: Self.synthesisSchema,
                effort: mode.judgeEffort,
                speed: mode.speed
            )
            let result = try JSONDecoder().decode(SynthesisResult.self, from: Data(text.utf8))
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
        avoiding: [String]
    ) async throws -> SynthesisResult {
        var user = context.promptText
        if !avoiding.isEmpty {
            user += "\n\nAlready surfaced. Do not repeat or paraphrase these:\n"
                + avoiding.map { "- \($0)" }.joined(separator: "\n")
        }
        let text = try await client.structuredCompletion(
            system: BrainPromptLibrary.synthesisSystemPrompt(kind: kind),
            user: user,
            schema: Self.synthesisSchema,
            effort: mode.judgeEffort,
            speed: mode.speed
        )
        return try JSONDecoder().decode(SynthesisResult.self, from: Data(text.utf8))
    }

    // MARK: - Query

    func answer(_ query: BrainQuery, context: BrainContext) async throws -> BrainAnswer {
        let retrieved = BrainRetriever.retrieve(query: query.text, from: context)
        var user = """
        User question:
        \(query.text)

        \(retrieved.promptText)

        \(context.noveltyPromptSample())
        """
        if !query.rejectedRecommendations.isEmpty {
            user += "\n\nRejected because they failed local novelty or catalog-verification checks:\n"
                + query.rejectedRecommendations.map { "- \($0)" }.joined(separator: "\n")
        }

        // Recommendations are the product's proof point and have no latency
        // budget; give them the deepest reasoning tier.
        let effort = retrieved.intent == .musicRecommendation ? "xhigh" : "high"
        let text = try await client.structuredCompletion(
            system: BrainPromptLibrary.queryPrompt,
            user: user,
            schema: Self.querySchema,
            effort: effort
        )
        return try JSONDecoder()
            .decode(BrainAnswer.self, from: Data(text.utf8))
            .withRetrieval(retrieved)
    }

    // MARK: - Schemas

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
        "required": ["answer", "evidence", "confidence"],
    ]
}
