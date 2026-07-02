import Foundation

enum BrainCatalogMatcher {
    static func verify(
        _ recommendation: BrainMusicRecommendation,
        candidates: [BrainCatalogCandidate],
        source: String
    ) -> BrainCatalogVerification {
        let title = key(recommendation.title)
        let artist = key(recommendation.artist)
        let exact = candidates.first { candidate in
            let candidateArtist = key(candidate.artist)
            return key(candidate.title) == title &&
                (candidateArtist == artist || candidateArtist.contains(artist) || artist.contains(candidateArtist))
        }

        if let exact {
            return BrainCatalogVerification(
                isVerified: true,
                canVerify: true,
                source: source,
                message: "Verified in \(source): \(exact.title) by \(exact.artist).",
                match: exact,
                candidates: candidates
            )
        }

        let top = candidates.prefix(3)
            .map { "\($0.title) by \($0.artist)" }
            .joined(separator: "; ")
        let suffix = top.isEmpty ? "No catalog results." : "Top results: \(top)."
        return BrainCatalogVerification(
            isVerified: false,
            canVerify: true,
            source: source,
            message: "No exact \(source) match for \(recommendation.title) by \(recommendation.artist). \(suffix)",
            match: nil,
            candidates: candidates
        )
    }

    private static func key(_ value: String?) -> String {
        BrainNoveltySet.normalized(value) ?? ""
    }
}
