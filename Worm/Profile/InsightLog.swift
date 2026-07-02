import Foundation

/// Dev-time logging for the brain layer. Writes compact JSON reports to
/// Application Support and prints the same path to the console.
@MainActor
enum InsightLog {
    private struct Report: Codable {
        let generatedAt: String
        let kind: String
        let context: String
        let query: BrainQuery?
        let read: String?
        let insights: [BrainSynthesizer.SynthesisResult.RawInsight]
        let answer: BrainAnswer?
        let retrieval: BrainRetrievedContext?
        let error: String?
    }

    static func recordSynthesis(context: BrainContext, result: BrainSynthesizer.SynthesisResult) {
        write(Report(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            kind: "synthesis",
            context: context.promptText,
            query: nil,
            read: result.read,
            insights: result.insights,
            answer: nil,
            retrieval: nil,
            error: nil
        ))
    }

    static func recordSynthesisError(_ error: Error, context: BrainContext) {
        write(Report(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            kind: "synthesis_error",
            context: context.promptText,
            query: nil,
            read: nil,
            insights: [],
            answer: nil,
            retrieval: nil,
            error: error.localizedDescription
        ))
    }

    static func recordQuery(query: BrainQuery, context: BrainContext, result: BrainAnswer) {
        write(Report(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            kind: "query",
            context: context.promptText,
            query: query,
            read: nil,
            insights: [],
            answer: result,
            retrieval: result.retrieval,
            error: nil
        ))
    }

    static func recordQueryError(_ error: Error, query: BrainQuery, context: BrainContext) {
        write(Report(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            kind: "query_error",
            context: context.promptText,
            query: query,
            read: nil,
            insights: [],
            answer: nil,
            retrieval: nil,
            error: error.localizedDescription
        ))
    }

    private static func write(_ report: Report) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report),
              let json = String(data: data, encoding: .utf8) else { return }

        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("worm-brain.json")
        try? data.write(to: url, options: .atomic)

        print("Worm brain log -> \(url.path)\n\(json)")
    }
}
