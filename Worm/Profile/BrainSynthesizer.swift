import Foundation

/// The only model-facing synthesis/query layer. Nodes feed compact slices into
/// `BrainContext`; this type turns that context into profile reads, worm
/// insights, and direct answers. It never talks to node managers directly.
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

    var client = ClaudeClient.fromInfoPlist()

    func synthesize(
        _ context: BrainContext,
        mode: BrainSynthesisMode,
        avoiding: [String] = []
    ) async throws -> SynthesisResult {
        var user = context.promptText
        user += "\n\nSynthesis mode: \(mode.rawValue)."
        if !avoiding.isEmpty {
            user += "\n\nAlready surfaced. Do not repeat or paraphrase these:\n"
                + avoiding.map { "- \($0)" }.joined(separator: "\n")
        }

        var fallback: SynthesisResult?
        for _ in 0..<2 {
            let text = try await client.structuredCompletion(
                system: Self.synthesisPrompt,
                user: user,
                schema: Self.synthesisSchema,
                effort: mode.effort
            )
            let result = try JSONDecoder().decode(SynthesisResult.self, from: Data(text.utf8))
            if !result.insights.isEmpty { return result }
            fallback = fallback ?? result
        }
        return fallback ?? SynthesisResult(read: "", insights: [])
    }

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

        let text = try await client.structuredCompletion(
            system: Self.queryPrompt,
            user: user,
            schema: Self.querySchema,
            effort: "high"
        )
        return try JSONDecoder()
            .decode(BrainAnswer.self, from: Data(text.utf8))
            .withRetrieval(retrieved)
    }

    // MARK: - Prompts

    private static let synthesisPrompt = """
    You are the brain of Worm. You synthesize a person from compact node slices:
    music, photos, calendar, and future nodes. The raw data is not present. Treat
    every slice as evidence, weigh confidence, and say less when evidence is weak.

    Produce:
    1. "read": 2 plain private sentences about who this person is.
    2. "insights": 3-4 short worm lines, each with evidence and confidence.

    The worm's voice is terse, second-person, specific, and observed. Do not
    summarize data. Push from pattern to person, but never fabricate concrete
    facts the slices do not support.

    Hard rules:
    - Never use the "—" or "–" character.
    - Never use a "not X, it's Y" reframe.
    - No rule-of-three lists.
    - No data-source preambles like "based on Spotify".
    - Lines under 14 words whenever possible.
    - Confidence above 0.7 only when the read is specific and well supported.
    """

    private static let queryPrompt = """
    You are the query interface to Worm's brain. Answer from the retrieved brain
    context, not from raw node data. Be direct, useful, and evidence-aware. Treat
    retrieved memories as the active working set and do not invent facts outside
    them. The YouTube node is a culture/media taste source, not a music-only
    source.

    For music recommendation requests:
    - Recommend exactly one song.
    - Recommend only a real released song that should be findable in Spotify or
      Apple Music catalog search.
    - Use the whole taste profile, not only music memories. Music is the output;
      cross-node taste is the reason.
    - It must be plausibly brand new to the user.
    - Avoid known artists, known tracks, obvious adjacent hits, and anything too
      close to the exclusion sample.
    - Prefer a specific, defensible recommendation over a popular one.
    - Include a concise reason tied to the brain context.
    - Do not invent plausible titles, albums, or label lore. If you are unsure a
      track exists, choose a different track.

    Return structured JSON only. If the context is too weak, say so plainly and
    set confidence low.
    """

    // MARK: - Schemas

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
                    ],
                    "required": ["line", "evidence", "confidence"],
                ],
            ],
        ],
        "required": ["read", "insights"],
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
            "recommendation": [
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
            ],
        ],
        "required": ["answer", "evidence", "confidence"],
    ]
}
