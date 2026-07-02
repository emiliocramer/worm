import Foundation

/// One thing the worm has noticed — a single observed line in the worm's voice,
/// synthesized from node data. *Observed, not summarized* (see `docs/vision.md`):
/// specific, surprising, true. If it could be said about anyone, it isn't one.
struct Insight: Identifiable, Hashable, Codable {
    enum Source: String, Codable {
        case spotify
        case appleMusic
        case photos
        case profile
    }

    /// Stable key derived from the line, so re-synthesis never duplicates or
    /// re-reveals the same observation.
    let id: String
    /// The worm's line, ready to surface verbatim.
    let line: String
    /// One short phrase of what in the data supports it (for evaluation/logging).
    let evidence: String
    /// The synthesizer's self-rated confidence, 0–1. The "silence beats a miss" gate.
    let confidence: Double
    let source: Source

    init(line rawLine: String, evidence: String, confidence: Double, source: Source) {
        let line = Insight.sanitize(rawLine)
        self.id = Insight.slug(line)
        self.line = line
        self.evidence = evidence
        self.confidence = confidence
        self.source = source
    }

    /// Structured output occasionally bleeds the next JSON field onto the end of
    /// the string with no space ("…no one's looking.confidence:0.8", "…home.evtwo").
    /// Strip a schema-key fragment glued to a terminal period/question/exclamation.
    private static func sanitize(_ raw: String) -> String {
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "([.!?])(confidence|evidence|line|ev\\w*)[\\w:.,\"'\\-]*\\s*$"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(line.startIndex..., in: line)
            line = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "$1")
        }
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func slug(_ line: String) -> String {
        line.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
            .split(separator: " ").prefix(6).joined(separator: "-")
    }
}
