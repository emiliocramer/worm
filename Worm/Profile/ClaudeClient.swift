import Foundation

/// Token usage reported by the Messages API for one call.
struct ClaudeUsage: Codable, Hashable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationInputTokens: Int = 0
    var cacheReadInputTokens: Int = 0
}

/// One completed model call: the JSON text plus everything the spend ledger
/// needs to price it.
struct ClaudeCompletion {
    let text: String
    let usage: ClaudeUsage
    let model: String
    let durationMs: Int
}

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

    /// High-effort synthesis calls routinely think past URLSession's default
    /// 60-second request timeout; give the brain room to finish.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }()

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
    ///
    /// `model` overrides the client default per call — the dig routes cheap
    /// mechanical hops to Haiku/Sonnet and keeps the judge on Opus.
    func structuredCompletion(system: String, user: String, schema: [String: Any], effort: String = "high", maxTokens: Int = 8192, speed: String? = nil, model: String? = nil) async throws -> ClaudeCompletion {
        try await send(system: system, content: user, schema: schema, effort: effort, maxTokens: maxTokens, speed: speed, model: model)
    }

    /// Same as `structuredCompletion`, but the user turn carries an image (as a
    /// base64 block) alongside the text prompt — for reading a photo/selfie into
    /// structured JSON. Kept behind the brain layer like every other model call.
    func structuredVisionCompletion(system: String, user: String, imageData: Data, mediaType: String = "image/jpeg", schema: [String: Any], effort: String = "high", maxTokens: Int = 8192) async throws -> String {
        let content: [[String: Any]] = [
            ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": imageData.base64EncodedString()]],
            ["type": "text", "text": user],
        ]
        return try await send(system: system, content: content, schema: schema, effort: effort, maxTokens: maxTokens).text
    }

    /// Shared request path. `content` is whatever the Messages API accepts for a
    /// user turn's `content`: a plain string, or an array of content blocks.
    private func send(system: String, content: Any, schema: [String: Any], effort: String, maxTokens: Int, speed: String? = nil, model modelOverride: String? = nil) async throws -> ClaudeCompletion {
        guard apiKey != nil || !requiresDirectAnthropicKey else { throw ClaudeError.missingKey }
        let requestedModel = modelOverride ?? model

        // Haiku 4.5 predates adaptive thinking and the effort parameter; both
        // return a 400 there. The cheap tier runs bare structured output.
        let supportsAdaptive = !requestedModel.lowercased().contains("haiku")

        func makeRequest(fast: Bool) throws -> URLRequest {
            var outputConfig: [String: Any] = ["format": ["type": "json_schema", "schema": schema]]
            if supportsAdaptive { outputConfig["effort"] = effort }
            var body: [String: Any] = [
                "model": requestedModel,
                "max_tokens": maxTokens,
                // System goes as a block with a cache breakpoint: the stable
                // prompt + taste brief is shared across the dig's fleet of
                // calls, so repeat sends bill at cache-read rates once the
                // prefix clears the model's cacheable minimum.
                "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
                "messages": [["role": "user", "content": content]],
                "output_config": outputConfig,
            ]
            if supportsAdaptive { body["thinking"] = ["type": "adaptive"] }
            if fast, let speed { body["speed"] = speed }

            var request = URLRequest(url: baseURL.appending(path: "v1/messages"))
            request.httpMethod = "POST"
            if let apiKey {
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            if fast, speed != nil {
                request.setValue("fast-mode-2026-02-01", forHTTPHeaderField: "anthropic-beta")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            return request
        }

        // 429 (rate limit), 529 (overloaded), and 5xx are transient; one blip
        // must not kill a whole synthesis. Retry with exponential backoff,
        // honoring retry-after when the server sends one. Fast mode has its own
        // rate-limit pool (and its own failure modes), so retries after a fast
        // attempt fall back to standard speed.
        let maxAttempts = 6
        var lastError: Error = ClaudeError.malformedResponse
        let startedAt = Date()
        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                let delay = min(pow(2.0, Double(attempt - 1)) * 1.5, 20) + Double.random(in: 0...1.0)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            let request = try makeRequest(fast: attempt == 0)
            do {
                let (data, response) = try await Self.session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw ClaudeError.malformedResponse }
                guard http.statusCode == 200 else {
                    let error = ClaudeError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
                    // A failed fast-mode attempt (unsupported proxy, fast-pool
                    // limit) always gets one standard-speed retry.
                    if attempt == 0, speed != nil {
                        lastError = error
                        continue
                    }
                    if Self.isRetryable(status: http.statusCode) {
                        lastError = error
                        if let after = http.value(forHTTPHeaderField: "retry-after").flatMap(Double.init), after <= 30 {
                            try await Task.sleep(nanoseconds: UInt64(after * 1_000_000_000))
                        }
                        continue
                    }
                    throw error
                }

                let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
                guard let text = decoded.content.first(where: { $0.type == "text" })?.text, !text.isEmpty else {
                    throw ClaudeError.malformedResponse
                }
                return ClaudeCompletion(
                    text: text,
                    usage: ClaudeUsage(
                        inputTokens: decoded.usage?.inputTokens ?? 0,
                        outputTokens: decoded.usage?.outputTokens ?? 0,
                        cacheCreationInputTokens: decoded.usage?.cacheCreationInputTokens ?? 0,
                        cacheReadInputTokens: decoded.usage?.cacheReadInputTokens ?? 0
                    ),
                    model: decoded.model ?? requestedModel,
                    durationMs: Int(Date().timeIntervalSince(startedAt) * 1000)
                )
            } catch let error as URLError where Self.isRetryable(urlError: error) {
                lastError = error
            }
        }
        throw lastError
    }

    private static func isRetryable(status: Int) -> Bool {
        status == 429 || status == 529 || (500...599).contains(status)
    }

    private static func isRetryable(urlError: URLError) -> Bool {
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private struct MessagesResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheCreationInputTokens: Int?
            let cacheReadInputTokens: Int?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case cacheCreationInputTokens = "cache_creation_input_tokens"
                case cacheReadInputTokens = "cache_read_input_tokens"
            }
        }

        let content: [Block]
        let usage: Usage?
        let model: String?
    }
}
