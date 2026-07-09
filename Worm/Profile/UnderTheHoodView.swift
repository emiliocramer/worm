import SwiftUI

/// The debug visualization of one brain pull: the pipeline shape, the live
/// trace that produced it, the trails with their queries, and the verified
/// candidate pool. Rendered inside the chat's "Under the hood" disclosure.
struct UnderTheHoodView: View {
    let answer: BrainAnswer

    private var pickedKey: String? {
        guard let recommendation = answer.recommendation else { return nil }
        return BrainNoveltySet.trackKey(title: recommendation.title, artist: recommendation.artist)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let dig = answer.dig {
                pipeline(dig)
            }

            if let trace = answer.trace, !trace.isEmpty {
                section("Thinking") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(trace.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 6) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                Text(line)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let dig = answer.dig {
                if !dig.trails.isEmpty {
                    section("Trails") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(dig.trails) { trail in
                                trailCard(trail)
                            }
                        }
                    }
                }

                if !dig.pool.isEmpty {
                    section("Verified pool (\(dig.pool.count))") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(dig.pool) { candidate in
                                poolRow(candidate)
                            }
                        }
                    }
                }

                if let leads = dig.leads, !leads.isEmpty {
                    section("Leads (\(leads.count))") {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(leads) { lead in
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Text(lead.kind)
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                                        Text(lead.title)
                                            .font(.caption.weight(.medium))
                                        Spacer()
                                        Text(String(format: "%.2f", lead.score))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("\(lead.queryHint) · \(lead.evidence)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }

                if let stop = dig.stopReason {
                    Text("Expedition stopped: \(stop)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let spend = answer.spend, !spend.isEmpty {
                spendSection(spend)
            }
        }
    }

    // MARK: - Spend

    private func spendSection(_ spend: [ModelCallRecord]) -> some View {
        let totalUSD = spend.reduce(0) { $0 + $1.costUSD }
        let totalIn = spend.reduce(0) { $0 + $1.inputTokens + $1.cacheReadTokens + $1.cacheWriteTokens }
        let totalOut = spend.reduce(0) { $0 + $1.outputTokens }
        return section("Spend — \(spend.count) calls · \(ModelCallRecord.compact(totalIn))→\(ModelCallRecord.compact(totalOut)) · $\(String(format: "%.3f", totalUSD))") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(spend) { record in
                    HStack(spacing: 6) {
                        Text(record.stage)
                            .font(.caption2.monospaced())
                            .lineLimit(1)
                        Text(record.shortModel)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(modelTint(record.shortModel)))
                        Spacer()
                        Text("\(ModelCallRecord.compact(record.inputTokens + record.cacheReadTokens + record.cacheWriteTokens))→\(ModelCallRecord.compact(record.outputTokens))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("$\(String(format: "%.3f", record.costUSD))")
                            .font(.caption2.monospacedDigit().weight(.medium))
                        Text("\(String(format: "%.1f", Double(record.durationMs) / 1000))s")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func modelTint(_ shortModel: String) -> Color {
        switch shortModel {
        case "haiku": return Color.green.opacity(0.18)
        case "sonnet": return Color.blue.opacity(0.15)
        default: return Color.purple.opacity(0.15)
        }
    }

    // MARK: - Pipeline

    private func pipeline(_ dig: DigResult) -> some View {
        let queryCount = dig.trails.reduce(0) { $0 + $1.digQueries.count }
        var stages: [(String, String)] = [
            ("Seeds", "\(dig.seedCount)"),
            ("Trails", "\(dig.trails.count)"),
            ("Queries", "\(queryCount)"),
        ]
        if let rounds = dig.rounds, rounds > 1 {
            stages.append(("Rounds", "\(rounds)"))
        }
        stages.append(("Pool", "\(dig.pool.count)"))
        stages.append(("Pick", answer.recommendation == nil ? "—" : "1"))
        if let spend = answer.spend, !spend.isEmpty {
            let total = spend.reduce(0) { $0 + $1.costUSD }
            stages.append(("Spend", "$\(String(format: "%.2f", total))"))
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    if index > 0 {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    VStack(spacing: 1) {
                        Text(stage.1)
                            .font(.caption.weight(.bold).monospacedDigit())
                        Text(stage.0)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.quaternary.opacity(0.5)))
                }
            }
        }
    }

    // MARK: - Trails

    private func trailCard(_ trail: BrainTrail) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(trail.journey.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                confidenceBar(trail.confidence)
                Text(String(format: "%.2f", trail.confidence))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(trail.routeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(trail.digQueries, id: \.self) { query in
                HStack(alignment: .top, spacing: 6) {
                    Text(query.provenance == .modelHypothesis ? "model" : "local")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(query.provenance == .modelHypothesis
                                ? Color.purple.opacity(0.18)
                                : Color.teal.opacity(0.18))
                        )
                    Text(query.query)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.35)))
    }

    private func confidenceBar(_ value: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(.teal)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(width: 48, height: 4)
    }

    // MARK: - Pool

    private func poolRow(_ candidate: DugCandidate) -> some View {
        let isPick = candidate.trackKey != nil && candidate.trackKey == pickedKey
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if isPick {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.teal)
                }
                Text("\(candidate.title) — \(candidate.artist)")
                    .font(.caption.weight(isPick ? .bold : .regular))
                Spacer()
                if let year = candidate.releaseYear {
                    Text(String(year))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                popularityDots(candidate.popularity)
            }
            Text("\(candidate.journey.title) · \(candidate.routeReason)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    /// Five dots, filled by popularity band. Fewer filled dots = deeper find.
    private func popularityDots(_ popularity: Int?) -> some View {
        let filled = popularity.map { min(5, max(0, ($0 + 19) / 20)) } ?? 0
        return HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(index < filled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
                    .frame(width: 4, height: 4)
            }
        }
    }

    // MARK: - Layout helper

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            content()
        }
    }
}
