import Foundation

/// Minimal client for the Claude Messages API (`/v1/messages`) with structured
/// JSON output. Swift has no official Anthropic SDK, so this is a thin raw-HTTP
/// wrapper.
///
/// The API key is read from `Info.plist` (`WormAnthropicAPIKey`) for local
/// direct-Anthropic development only. A shipped app must not hold that key:
/// set `WormAnthropicBaseURL` to a server-side proxy and leave the key empty.
struct ClaudeClient {
    var apiKey: String?
    var baseURL: URL
    var model = "claude-opus-4-8"

    enum ClaudeError: LocalizedError {
        case missingKey
        case http(status: Int, body: String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "No Anthropic API key. Set WORM_ANTHROPIC_API_KEY for direct Anthropic development, or set WORM_ANTHROPIC_BASE_URL to a server-side proxy."
            case let .http(status, body):
                return "Claude API error \(status): \(body)"
            case .malformedResponse:
                return "Unexpected response shape from Claude API."
            }
        }
    }

    static func fromInfoPlist(bundle: Bundle = .main) -> ClaudeClient {
        // Defensive: take only the first non-empty line and strip whitespace, so
        // a stray paste (trailing newline, an env block) can't smuggle invalid
        // bytes into the x-api-key header. An API key is a single token.
        let raw = bundle.object(forInfoDictionaryKey: "WormAnthropicAPIKey") as? String
        let key = raw?
            .split(whereSeparator: \.isNewline)
            .first?
            .trimmingCharacters(in: .whitespaces)
        let urlString = (bundle.object(forInfoDictionaryKey: "WormAnthropicBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (urlString.flatMap(URL.init(string:))) ?? URL(string: "https://api.anthropic.com")!
        return ClaudeClient(apiKey: (key?.isEmpty == false) ? key : nil, baseURL: base)
    }

    private var requiresDirectAnthropicKey: Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return host == "api.anthropic.com" || host.hasSuffix(".anthropic.com")
    }

    /// Sends one request constrained to `schema` and returns the model's JSON
    /// text (the first text block), ready to decode against your output type.
    ///
    /// Adaptive thinking is on: without it, a constrained structured-output task
    /// with a heavy instruction set tends to loop and produce degenerate output.
    /// `maxTokens` must leave room for thinking *and* the answer.
    func structuredCompletion(system: String, user: String, schema: [String: Any], effort: String = "high", maxTokens: Int = 8192) async throws -> String {
        try await send(system: system, content: user, schema: schema, effort: effort, maxTokens: maxTokens)
    }

    /// Same as `structuredCompletion`, but the user turn carries an image (as a
    /// base64 block) alongside the text prompt — for reading a photo/selfie into
    /// structured JSON. Kept behind the brain layer like every other model call.
    func structuredVisionCompletion(system: String, user: String, imageData: Data, mediaType: String = "image/jpeg", schema: [String: Any], effort: String = "high", maxTokens: Int = 8192) async throws -> String {
        let content: [[String: Any]] = [
            ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": imageData.base64EncodedString()]],
            ["type": "text", "text": user],
        ]
        return try await send(system: system, content: content, schema: schema, effort: effort, maxTokens: maxTokens)
    }

    /// Shared request path. `content` is whatever the Messages API accepts for a
    /// user turn's `content`: a plain string, or an array of content blocks.
    private func send(system: String, content: Any, schema: [String: Any], effort: String, maxTokens: Int) async throws -> String {
        guard apiKey != nil || !requiresDirectAnthropicKey else { throw ClaudeError.missingKey }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "thinking": ["type": "adaptive"],
            "system": system,
            "messages": [["role": "user", "content": content]],
            "output_config": ["format": ["type": "json_schema", "schema": schema], "effort": effort],
        ]

        var request = URLRequest(url: baseURL.appending(path: "v1/messages"))
        request.httpMethod = "POST"
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.malformedResponse }
        guard http.statusCode == 200 else {
            throw ClaudeError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text, !text.isEmpty else {
            throw ClaudeError.malformedResponse
        }
        return text
    }

    private struct MessagesResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
    }
}
