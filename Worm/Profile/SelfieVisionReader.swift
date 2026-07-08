import Foundation

/// Reads one selfie into a structured `SelfieAnalysis`. This is the only place a
/// selfie image reaches a model — the node hands over bytes, this owns the
/// ClaudeClient, exactly like `BrainSynthesizer` owns synthesis. Nodes never
/// call the model client themselves.
struct SelfieVisionReader {
    var client = ClaudeClient.fromInfoPlist()

    func analyze(imageData: Data) async throws -> SelfieAnalysis {
        let text = try await client.structuredVisionCompletion(
            system: Self.prompt,
            user: Self.instruction,
            imageData: imageData,
            mediaType: "image/jpeg",
            schema: Self.schema,
            effort: "high"
        )
        return try JSONDecoder().decode(SelfieAnalysis.self, from: Data(text.utf8))
    }

    // MARK: - Prompt

    private static let prompt = """
    You are the eyes of Worm. You are shown one selfie and you read the person in
    it the way a sharp, warm friend would after really looking — not a security
    camera, not a flatterer.

    Read who this person seems to be from what is actually visible: their
    expression and what it's doing, how they've chosen to present themselves
    (styling, grooming, clothing, accessories, hair), the setting and light, the
    energy they're putting out, small deliberate choices. Push from what you see
    to who they are, but never invent specifics the image doesn't support.

    Produce:
    1. "read": 2 plain private sentences on who this person seems to be.
    2. "oneLiner": one specific, surprising, TRUE observation in the worm's voice
       (terse, second-person, observed).
    3. "observations": 4-7 concrete observed attributes. Each must be something
       you can actually see.
    4. "aesthetics": a few taste/aesthetic keywords implied by their presentation.
    5. "confidence": how well-supported the read is (a plain snapshot supports
       less; lower it honestly).

    Hard rules:
    - Only what the image supports. No guessing name, age to the year, ethnicity,
      health, or wealth. Apparent, hedged, visible only.
    - Anti-slop: if it could be said about anyone, cut it. No horoscopes, no
      flattery, no "you have great style".
    - Never use the "—" or "–" character. No "not X, it's Y" reframes.
    - Second person, terse, specific.
    - Be kind. This is the first thing the worm ever says about them.
    """

    private static let instruction = """
    Read this selfie. Return the structured JSON only.
    """

    private static let schema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "properties": [
            "read": ["type": "string"],
            "oneLiner": ["type": "string"],
            "observations": ["type": "array", "items": ["type": "string"]],
            "aesthetics": ["type": "array", "items": ["type": "string"]],
            "confidence": ["type": "number"],
            "analyzedAt": ["type": "string"],
        ],
        "required": ["read", "oneLiner", "observations", "aesthetics", "confidence"],
    ]
}
