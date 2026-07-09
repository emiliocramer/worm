import Foundation

/// The model routing table. The taste-critical judgment never leaves the top
/// tier; coverage and mechanical work route to the cheapest model that can
/// survive its own failure mode.
enum BrainModel {
    /// The pick and the voice. Never routed down.
    static let judge = "claude-opus-4-8"
    /// Budgeted decisions and scoring against the taste brief.
    static let mid = "claude-sonnet-5"
    /// Query synthesis, grading, entity extraction.
    static let cheap = "claude-haiku-4-5"
}

/// Prices per million tokens. Cache reads bill at ~0.1x input, cache writes
/// at 1.25x input. Update alongside the published price list.
enum ModelPricing {
    struct Rate {
        let inputPerMTok: Double
        let outputPerMTok: Double
    }

    static func rate(for model: String) -> Rate {
        let lower = model.lowercased()
        if lower.contains("haiku") { return Rate(inputPerMTok: 1, outputPerMTok: 5) }
        if lower.contains("sonnet") { return Rate(inputPerMTok: 3, outputPerMTok: 15) }
        // Opus and anything unknown price at the top tier so estimates err high.
        return Rate(inputPerMTok: 5, outputPerMTok: 25)
    }

    static func costUSD(model: String, usage: ClaudeUsage) -> Double {
        let rate = rate(for: model)
        let input = Double(usage.inputTokens) * rate.inputPerMTok
        let cacheWrite = Double(usage.cacheCreationInputTokens) * rate.inputPerMTok * 1.25
        let cacheRead = Double(usage.cacheReadInputTokens) * rate.inputPerMTok * 0.1
        let output = Double(usage.outputTokens) * rate.outputPerMTok
        return (input + cacheWrite + cacheRead + output) / 1_000_000
    }
}

/// One priced model call. Persists with the chat message so the debug surface
/// can show exactly where every cent of a pull went.
struct ModelCallRecord: Codable, Hashable, Identifiable {
    let stage: String
    let model: String
    let effort: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let costUSD: Double
    let durationMs: Int
    let startedAt: Date

    var id: String { "\(stage)|\(startedAt.timeIntervalSince1970)" }

    /// Compact line for the live trace and logs.
    var traceLine: String {
        let tokens = "\(Self.compact(inputTokens + cacheReadTokens + cacheWriteTokens))→\(Self.compact(outputTokens))"
        return "\(stage) \(shortModel) \(tokens) $\(String(format: "%.3f", costUSD)) in \(String(format: "%.1f", Double(durationMs) / 1000))s"
    }

    var shortModel: String {
        let lower = model.lowercased()
        if lower.contains("haiku") { return "haiku" }
        if lower.contains("sonnet") { return "sonnet" }
        if lower.contains("opus") { return "opus" }
        return model
    }

    static func compact(_ tokens: Int) -> String {
        tokens >= 1000 ? String(format: "%.1fk", Double(tokens) / 1000) : "\(tokens)"
    }
}

/// Per-pull accumulator for model spend. A reference type so one ledger can be
/// threaded through the answer path, the dig, and every delegated agent call.
/// Lock-protected: the hunt fan-out and the dig's parallel agents record from
/// concurrent tasks.
final class SpendLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ModelCallRecord] = []
    /// Called as each record lands; the live trace subscribes here.
    var onRecord: ((ModelCallRecord) -> Void)?

    var records: [ModelCallRecord] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(stage: String, effort: String, completion: ClaudeCompletion) {
        let record = ModelCallRecord(
            stage: stage,
            model: completion.model,
            effort: effort,
            inputTokens: completion.usage.inputTokens,
            outputTokens: completion.usage.outputTokens,
            cacheReadTokens: completion.usage.cacheReadInputTokens,
            cacheWriteTokens: completion.usage.cacheCreationInputTokens,
            costUSD: ModelPricing.costUSD(model: completion.model, usage: completion.usage),
            durationMs: completion.durationMs,
            startedAt: Date()
        )
        lock.lock()
        storage.append(record)
        lock.unlock()
        onRecord?(record)
    }

    var totalUSD: Double { records.reduce(0) { $0 + $1.costUSD } }
    var totalInputTokens: Int { records.reduce(0) { $0 + $1.inputTokens + $1.cacheReadTokens + $1.cacheWriteTokens } }
    var totalOutputTokens: Int { records.reduce(0) { $0 + $1.outputTokens } }

    var summaryLine: String {
        "\(records.count) calls · \(ModelCallRecord.compact(totalInputTokens))→\(ModelCallRecord.compact(totalOutputTokens)) · $\(String(format: "%.2f", totalUSD))"
    }
}
