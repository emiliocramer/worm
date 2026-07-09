import SwiftUI
import UIKit

struct ProfileChatView: View {
    @Environment(SpotifyMusicNode.self) private var spotify
    @Environment(AppleMusicNode.self) private var appleMusic
    @Environment(YouTubeCultureNode.self) private var youtube
    @Environment(ContactsNode.self) private var contacts
    @Environment(PhotosNode.self) private var photos
    @Environment(CalendarNode.self) private var calendar
    @Environment(SelfieNode.self) private var selfie
    @Environment(TasteProfile.self) private var profile

    @State private var draft = "recommend me a new song"
    @State private var copiedMessageID: UUID?

    var body: some View {
        List {
            Section {
                TextField("Ask the brain", text: $draft, axis: .vertical)
                    .lineLimit(2...5)

                Button {
                    send()
                } label: {
                    Label(profile.isAnswering ? "Thinking" : "Ask Brain", systemImage: "paperplane")
                }
                .disabled(profile.isAnswering || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Ask")
            } footer: {
                Text("Debug surface. Answers use compact brain slices and local novelty checks, not raw node snapshots.")
            }

            if profile.isAnswering {
                Section("Thinking") {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(profile.liveTrace.last ?? "Reading the brain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if profile.liveTrace.count > 1 {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(profile.liveTrace.suffix(8).enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            if let error = profile.lastError {
                Section("Last Error") {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section("Transcript") {
                if profile.chatHistory.isEmpty {
                    Text("No questions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profile.chatHistory) { message in
                        chatRow(message)
                    }
                }
            }
        }
        .navigationTitle("Brain Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !profile.chatHistory.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        profile.clearChat()
                    }
                    .disabled(profile.isAnswering)
                }
            }
        }
        .task {
            refreshBrainSlices()
        }
    }

    @ViewBuilder
    private func chatRow(_ message: BrainChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(message.role == .user ? "You" : "Brain")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(message.text)
                .font(.body)

            if let recommendation = message.answer?.recommendation {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(recommendation.title) - \(recommendation.artist)")
                        .font(.headline)
                    if let album = recommendation.album, !album.isEmpty {
                        Text(album)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(recommendation.why)
                        .font(.subheadline)
                    Text(recommendation.noveltyStatus ?? recommendation.noveltyRationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let catalogStatus = recommendation.catalogStatus {
                        Text(catalogStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }

            if let answer = message.answer, !answer.evidence.isEmpty {
                Text("Evidence: \(answer.evidence.prefix(3).joined(separator: " | "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let answer = message.answer, answer.dig != nil || answer.trace?.isEmpty == false {
                DisclosureGroup("Under the hood") {
                    UnderTheHoodView(answer: answer)
                        .padding(.top, 4)
                }
                .font(.caption.weight(.semibold))
            }

            if let retrieval = message.answer?.retrieval, !retrieval.hits.isEmpty {
                DisclosureGroup("Retrieved \(retrieval.hits.count) memories") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(retrieval.hits.prefix(6))) { hit in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(hit.nodeTitle) / \(hit.kind) / \(String(format: "%.2f", hit.score))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(hit.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }

            if message.answer != nil {
                Button {
                    copyBrainBlock(for: message)
                } label: {
                    Label(copiedMessageID == message.id ? "Copied" : "Copy block", systemImage: copiedMessageID == message.id ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func send() {
        let text = draft
        draft = ""
        let context = liveContext()
        let digger = BrainDigger(searchCatalog: { [spotify] query, limit in
            await spotify.searchCatalogTracks(query: query, limit: limit)
        })
        Task {
            await profile.answer(text, context: context, digger: digger, verifyRecommendation: verifyRecommendation)
        }
    }

    private func refreshBrainSlices() {
        profile.ingest(liveContext().slices)
    }

    private func liveContext() -> BrainContext {
        brainInputs.context(read: profile.read, insights: profile.insights)
    }

    private var brainInputs: BrainInputSet {
        BrainInputSet(
            spotify: spotify,
            appleMusic: appleMusic,
            youtube: youtube,
            contacts: contacts,
            photos: photos,
            calendar: calendar,
            selfie: selfie
        )
    }

    private func copyBrainBlock(for message: BrainChatMessage) {
        UIPasteboard.general.string = brainBlock(for: message)
        copiedMessageID = message.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedMessageID == message.id {
                copiedMessageID = nil
            }
        }
    }

    private func brainBlock(for message: BrainChatMessage) -> String {
        guard let answer = message.answer else {
            return message.text
        }

        var lines: [String] = [
            "Worm Brain Debug Block",
            "Generated: \(message.createdAt.formatted(date: .abbreviated, time: .standard))",
            "",
        ]

        if let retrieval = answer.retrieval {
            lines.append("Question:")
            lines.append(retrieval.queryText)
            lines.append("")
        }

        lines.append("Brain Output:")
        lines.append(answer.answer)

        if let recommendation = answer.recommendation {
            lines.append("")
            lines.append("Recommendation:")
            lines.append("Title: \(recommendation.title)")
            lines.append("Artist: \(recommendation.artist)")
            if let album = recommendation.album, !album.isEmpty {
                lines.append("Album: \(album)")
            }
            lines.append("Why: \(recommendation.why)")
            lines.append("Novelty: \(recommendation.noveltyStatus ?? recommendation.noveltyRationale)")
            if let catalogStatus = recommendation.catalogStatus {
                lines.append("Catalog: \(catalogStatus)")
            }
            if let catalogURL = recommendation.catalogURL {
                lines.append("Catalog URL: \(catalogURL)")
            }
        }

        if !answer.evidence.isEmpty {
            lines.append("")
            lines.append("Evidence:")
            lines.append(contentsOf: answer.evidence.map { "- \($0)" })
        }

        if let trace = answer.trace, !trace.isEmpty {
            lines.append("")
            lines.append("Thinking:")
            lines.append(contentsOf: trace.enumerated().map { "\($0.offset + 1). \($0.element)" })
        }

        if let spend = answer.spend, !spend.isEmpty {
            let totalUSD = spend.reduce(0) { $0 + $1.costUSD }
            let totalIn = spend.reduce(0) { $0 + $1.inputTokens + $1.cacheReadTokens + $1.cacheWriteTokens }
            let totalOut = spend.reduce(0) { $0 + $1.outputTokens }
            lines.append("")
            lines.append("Spend: \(spend.count) calls, \(totalIn)→\(totalOut) tokens, $\(String(format: "%.4f", totalUSD))")
            lines.append(contentsOf: spend.map { "- \($0.traceLine) [effort \($0.effort)]" })
        }

        if let dig = answer.dig {
            lines.append("")
            lines.append("Dig:")
            lines.append("Seeds: \(dig.seedCount), trails: \(dig.trails.count), pool: \(dig.pool.count), rounds: \(dig.rounds ?? 1), stopped: \(dig.stopReason ?? "n/a")")
            for candidate in dig.pool {
                var meta: [String] = []
                if let year = candidate.releaseYear { meta.append(String(year)) }
                if let pop = candidate.popularity { meta.append("popularity \(pop)") }
                let suffix = meta.isEmpty ? "" : " (\(meta.joined(separator: ", ")))"
                lines.append("- \(candidate.title) by \(candidate.artist)\(suffix) [\(candidate.journey.title)] \(candidate.routeReason)")
            }
        }

        lines.append("")
        lines.append("Brain Trace:")
        if let retrieval = answer.retrieval {
            lines.append("Intent: \(retrieval.intent.title)")
            lines.append("")
            lines.append("Graph:")
            if retrieval.graphSummary.isEmpty {
                lines.append("- none")
            } else {
                lines.append(contentsOf: retrieval.graphSummary.map { "- \($0)" })
            }

            lines.append("")
            lines.append("Retrieved Memories:")
            if retrieval.hits.isEmpty {
                lines.append("- none")
            } else {
                lines.append(contentsOf: retrieval.hits.map { hit in
                    "- [\(hit.nodeTitle) / \(hit.kind) / score \(String(format: "%.2f", hit.score)) / confidence \(String(format: "%.2f", hit.confidence))] \(hit.text)"
                })
            }

            if let trails = retrieval.trails, !trails.isEmpty {
                lines.append("")
                lines.append("Digging Trails:")
                for trail in trails {
                    lines.append("- [\(trail.journey.title) / confidence \(String(format: "%.2f", trail.confidence)) / novelty \(trail.noveltyPolicy.rawValue)] \(trail.routeSummary)")
                    lines.append(contentsOf: trail.digQueries.map { "    query (\($0.provenance.rawValue)): \($0.query)" })
                }
            }
        } else {
            lines.append("No retrieval trace attached.")
        }

        lines.append("")
        lines.append("Confidence: \(String(format: "%.2f", answer.confidence))")
        return lines.joined(separator: "\n")
    }

    private func verifyRecommendation(_ recommendation: BrainMusicRecommendation) async -> BrainCatalogVerification {
        let spotifyResult = await spotify.verifyCatalogRecommendation(recommendation)
        if spotifyResult.isVerified {
            return spotifyResult
        }

        let appleMusicResult = await appleMusic.verifyCatalogRecommendation(recommendation)
        if appleMusicResult.isVerified {
            return appleMusicResult
        }

        if spotifyResult.canVerify || appleMusicResult.canVerify {
            let candidates = spotifyResult.candidates + appleMusicResult.candidates
            return BrainCatalogVerification(
                isVerified: false,
                canVerify: true,
                source: "Catalog",
                message: "\(spotifyResult.message) \(appleMusicResult.message)",
                match: nil,
                candidates: candidates
            )
        }

        return BrainCatalogVerification(
            isVerified: false,
            canVerify: false,
            source: "Catalog",
            message: "No catalog verifier was available. Spotify: \(spotifyResult.message) Apple Music: \(appleMusicResult.message)",
            match: nil,
            candidates: []
        )
    }
}

#Preview {
    NavigationStack {
        ProfileChatView()
    }
    .environment(SpotifyMusicNode())
    .environment(AppleMusicNode())
    .environment(YouTubeCultureNode())
    .environment(ContactsNode())
    .environment(PhotosNode())
    .environment(CalendarNode())
    .environment(SelfieNode())
    .environment(TasteProfile())
}
