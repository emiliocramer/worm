import SwiftUI
import UIKit

struct ProfileChatView: View {
    @Environment(SpotifyMusicNode.self) private var spotify
    @Environment(AppleMusicNode.self) private var appleMusic
    @Environment(YouTubeCultureNode.self) private var youtube
    @Environment(ContactsNode.self) private var contacts
    @Environment(PhotosNode.self) private var photos
    @Environment(CalendarNode.self) private var calendar
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
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading the brain")
                            .foregroundStyle(.secondary)
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
        Task {
            await profile.answer(text, context: context, verifyRecommendation: verifyRecommendation)
        }
    }

    private func refreshBrainSlices() {
        profile.ingest(liveContext().slices)
    }

    private func liveContext() -> BrainContext {
        BrainSliceBuilder.context(
            spotify: spotify,
            appleMusic: appleMusic,
            youtube: youtube,
            contacts: contacts,
            photos: photos,
            calendar: calendar,
            read: profile.read,
            insights: profile.insights
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
    .environment(TasteProfile())
}
