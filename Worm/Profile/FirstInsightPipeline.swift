import Foundation

/// The single path for the onboarding Spotify reveal.
///
/// Keep this small: it defines the data surface, synthesis kind, and fallback
/// ordering for "first insight". Onboarding and profile simulation both call it.
@MainActor
enum FirstInsightPipeline {
    static func runSpotifyFirstInsight(
        spotify: SpotifyMusicNode,
        profile: TasteProfile,
        selfie: SelfieNode? = nil,
        startFullSync: Bool = true
    ) async -> Insight? {
        await spotify.syncOnboardingTastePreview()
        if startFullSync {
            _ = Task { await spotify.syncEverything() }
        }

        let generated = await profile.synthesize(
            slices: [BrainSliceBuilder.spotifySlice(from: spotify)],
            mode: .quick,
            kind: .firstInsight,
            useOnlyProvidedSlices: true,
            avoidExistingInsights: false
        )

        if let selfie {
            profile.ingest([BrainSliceBuilder.selfieSlice(from: selfie)])
        }

        // The judge ranks by how biographical the observation is, which is the
        // product's bar; confidence already gated acceptance upstream. Do not
        // re-sort by confidence here or recency wins again.
        return generated.first ?? spotifyFallbackInsight(from: spotify)
    }

    private static func spotifyFallbackInsight(from spotify: SpotifyMusicNode) -> Insight? {
        let features = SpotifyFeatureExtractor.extract(from: spotify)
        if let artist = features.rideOrDie.first {
            return Insight(
                line: "You keep coming back to \(artist).",
                evidence: "\(artist) appears across Spotify time ranges",
                confidence: 0.7,
                source: .spotify
            )
        }
        if features.recentTopArtists.count >= 2 {
            return Insight(
                line: "\(features.recentTopArtists[0]) and \(features.recentTopArtists[1]) are your current lane.",
                evidence: "Recent Spotify top artists: \(features.recentTopArtists[0]), \(features.recentTopArtists[1])",
                confidence: 0.68,
                source: .spotify
            )
        }
        if let genre = features.topGenres.first {
            return Insight(
                line: "\(genreLabel(genre)) is still easy for you.",
                evidence: "Dominant Spotify genre: \(genreLabel(genre))",
                confidence: 0.64,
                source: .spotify
            )
        }
        if let track = spotify.topTracksShort.first {
            return Insight(
                line: "\(track.name) has probably done repeat duty.",
                evidence: "Recent Spotify top track: \(track.name)",
                confidence: 0.62,
                source: .spotify
            )
        }
        return nil
    }

    private static func genreLabel(_ raw: String) -> String {
        raw.split(separator: "(").first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? raw.lowercased()
    }
}
