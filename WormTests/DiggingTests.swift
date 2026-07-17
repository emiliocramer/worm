import XCTest
@testable import Worm

final class DiggingTests: XCTestCase {

    // MARK: - Fixtures

    private func artist(_ name: String, genres: [String] = [], popularity: Int? = 50) -> SpotifyArtist {
        SpotifyArtist(
            id: name.lowercased(),
            name: name,
            href: nil,
            type: "artist",
            uri: nil,
            genres: genres,
            popularity: popularity,
            followers: nil,
            images: nil,
            externalUrls: nil
        )
    }

    private func album(
        _ name: String,
        label: String? = nil,
        releaseDate: String? = nil,
        artists: [SpotifyArtist] = []
    ) -> SpotifyAlbum {
        SpotifyAlbum(
            id: name.lowercased(),
            name: name,
            href: nil,
            type: "album",
            albumType: "album",
            albumGroup: nil,
            totalTracks: nil,
            availableMarkets: nil,
            releaseDate: releaseDate,
            releaseDatePrecision: releaseDate.map { _ in "year" },
            label: label,
            genres: nil,
            popularity: nil,
            copyrights: nil,
            externalIds: nil,
            restrictions: nil,
            artists: artists,
            images: [],
            uri: nil,
            externalUrls: nil
        )
    }

    private func track(
        _ name: String,
        artist artistName: String,
        album trackAlbum: SpotifyAlbum? = nil,
        popularity: Int? = 40
    ) -> SpotifyTrack {
        SpotifyTrack(
            id: "\(artistName)-\(name)".lowercased(),
            name: name,
            href: nil,
            type: "track",
            artists: [artist(artistName)],
            album: trackAlbum,
            availableMarkets: nil,
            durationMs: nil,
            explicit: nil,
            externalIds: nil,
            isLocal: nil,
            popularity: popularity,
            restrictions: nil,
            trackNumber: nil,
            discNumber: nil,
            previewUrl: nil,
            uri: nil,
            externalUrls: nil
        )
    }

    private func seed(
        _ type: SeedEntityType,
        _ title: String,
        strength: Double,
        node: BrainNodeID = .spotify
    ) -> BrainSeed {
        BrainSeed(
            sourceNode: node,
            entityType: type,
            title: title,
            evidence: ["test evidence for \(title)"],
            strength: strength
        )
    }

    // MARK: - Seed extraction

    func testSpotifyArtistSeedsGradeDurability() {
        let durable = artist("The Church", genres: ["neo-psychedelia"])
        let recent = artist("Fresh Act")
        let seeds = BrainSeedExtractor.spotifySeeds(
            topArtistsShort: [durable, recent],
            topArtistsMedium: [durable],
            topArtistsLong: [durable],
            topTracksShort: [],
            topTracksLong: [],
            savedAlbums: [],
            savedTrackCount: 0,
            playlists: [],
            freshness: nil
        )

        let church = seeds.first { $0.entityType == .artist && $0.title == "The Church" }
        let fresh = seeds.first { $0.entityType == .artist && $0.title == "Fresh Act" }
        XCTAssertEqual(church?.strength, 0.9)
        XCTAssertEqual(fresh?.strength, 0.5)
    }

    func testLabelSeedsSkipMajorsAndCountAlbums() {
        let saved = [
            SpotifySavedAlbum(addedAt: nil, album: album("A Love Supreme", label: "Impulse!")),
            SpotifySavedAlbum(addedAt: nil, album: album("Karma", label: "Impulse!")),
            SpotifySavedAlbum(addedAt: nil, album: album("Big Pop Record", label: "Columbia Records")),
        ]
        let seeds = BrainSeedExtractor.spotifySeeds(
            topArtistsShort: [],
            topArtistsMedium: [],
            topArtistsLong: [],
            topTracksShort: [],
            topTracksLong: [],
            savedAlbums: saved,
            savedTrackCount: 0,
            playlists: [],
            freshness: nil
        )

        let labels = seeds.filter { $0.entityType == .label }
        XCTAssertEqual(labels.map(\.title), ["Impulse!"])
        XCTAssertTrue(labels[0].evidence[0].contains("A Love Supreme"))
    }

    func testEraClusterFindsTightSpan() {
        let tracks = (0..<8).map { index in
            track("Song \(index)", artist: "Artist", album: album("Album", releaseDate: "\(1996 + index % 4)"))
        } + (0..<4).map { index in
            track("Outlier \(index)", artist: "Artist", album: album("Old", releaseDate: "\(1960 + index)"))
        }

        let era = BrainSeedExtractor.eraCluster(tracks)
        XCTAssertNotNil(era)
        XCTAssertEqual(era?.range, 1996...1999)
        XCTAssertEqual(era?.share, 66)
    }

    func testCrateDiggerSeedFiresOnLowPopularity() {
        let obscure = (0..<10).map { track("Deep \($0)", artist: "Nobody \($0)", popularity: 12) }
        let seeds = BrainSeedExtractor.spotifySeeds(
            topArtistsShort: [],
            topArtistsMedium: [],
            topArtistsLong: [],
            topTracksShort: obscure,
            topTracksLong: [],
            savedAlbums: [],
            savedTrackCount: 0,
            playlists: [],
            freshness: nil
        )
        XCTAssertTrue(seeds.contains { $0.entityType == .aesthetic && $0.title == HeroJourney.SignalSeed.crateDigger })
    }

    // MARK: - Hero journeys

    func testEnrichmentGatedJourneysScoreZero() {
        let loaded = [
            seed(.artist, "The Black Keys", strength: 0.9),
            seed(.label, "Nonesuch", strength: 0.9),
            seed(.genre, "blues rock", strength: 0.9),
            seed(.place, "Brooklyn", strength: 0.9, node: .photos),
        ]
        XCTAssertEqual(HeroJourney.closedDoorArtist.score(loaded), 0)
        XCTAssertEqual(HeroJourney.humanCuratorThread.score(loaded), 0)
    }

    func testMissedChapterNeedsDurableArtistAndGap() {
        let noGap = [seed(.artist, "The Church", strength: 0.9)]
        XCTAssertEqual(HeroJourney.missedChapter.score(noGap), 0)

        let withLabel = noGap + [seed(.label, "Arista", strength: 0.7)]
        XCTAssertGreaterThan(HeroJourney.missedChapter.score(withLabel), 0.5)

        let weakArtist = [seed(.artist, "Fresh Act", strength: 0.5), seed(.label, "Arista", strength: 0.7)]
        XCTAssertEqual(HeroJourney.missedChapter.score(weakArtist), 0)
    }

    func testLocalOddityNeedsPlaceAndGenre() {
        let placeOnly = [seed(.place, "Kyoto", strength: 0.8, node: .photos)]
        XCTAssertEqual(HeroJourney.localOddity.score(placeOnly), 0)

        let both = placeOnly + [seed(.genre, "city pop", strength: 0.6)]
        XCTAssertGreaterThan(HeroJourney.localOddity.score(both), 0.5)
    }

    // MARK: - Trail builder

    func testMissedChapterTrailDigsLabelYearGaps() {
        let seeds = [
            seed(.artist, "The Church", strength: 0.9),
            seed(.label, "Impulse!", strength: 0.8),
            BrainSeed(
                sourceNode: .spotify,
                entityType: .era,
                title: "1996-2004",
                evidence: ["66% of top-track release years fall in 1996-2004"],
                strength: 0.7
            ),
            seed(.genre, "spiritual jazz", strength: 0.7),
        ]

        let output = BrainTrailBuilder.build(from: seeds)
        let trail = output.trails.first { $0.journey == .missedChapter }
        XCTAssertNotNil(trail)
        XCTAssertEqual(trail?.noveltyPolicy, .strict)
        XCTAssertTrue(trail?.digQueries.contains { $0.query == "label:\"Impulse!\" year:1988-1995" } ?? false)
        XCTAssertTrue(trail?.digQueries.contains { $0.query.hasPrefix("label:\"Impulse!\" year:2005-") } ?? false)
        XCTAssertTrue(trail?.digQueries.allSatisfy { $0.provenance == .localNodeData } ?? false)

        let labelEffect = output.effectNodes.first { $0.effectType == .labelCatalog }
        XCTAssertEqual(labelEffect?.provenance, .localNodeData)
        XCTAssertFalse(labelEffect?.evidence.isEmpty ?? true)
    }

    func testSourceDNADigsQuieterSampleCultureGenres() {
        // The sample-culture genre is not in the top-3 by strength; the branch
        // must still find it among all genre seeds.
        let seeds = [
            seed(.genre, "folk rock", strength: 0.9),
            seed(.genre, "classic rock", strength: 0.85),
            seed(.genre, "singer-songwriter", strength: 0.8),
            seed(.genre, "retro soul", strength: 0.6),
        ]
        let output = BrainTrailBuilder.build(from: seeds)
        let trail = output.trails.first { $0.journey == .sourceDNA }
        XCTAssertNotNil(trail)
        XCTAssertTrue(trail?.digQueries.contains { $0.query.hasPrefix("genre:\"retro soul\" year:") } ?? false)
    }

    func testNoSeedsBuildsNoTrails() {
        let output = BrainTrailBuilder.build(from: [])
        XCTAssertTrue(output.trails.isEmpty)
        XCTAssertTrue(output.effectNodes.isEmpty)
    }

    // MARK: - Digger filtering

    @MainActor
    func testDigPoolRejectsKnownJunkAndPopular() async {
        var novelty = BrainNoveltySet()
        novelty.insertArtist("Radiohead")
        novelty.insertTrack(title: "Known Song", artist: "Someone")

        let slice = NodeBrainSlice(
            nodeID: .spotify,
            isConnected: true,
            isPopulated: true,
            summary: "test",
            facts: [],
            evidence: [],
            chunks: [],
            freshness: nil,
            confidence: 0.9,
            health: "ready",
            novelty: novelty,
            dossier: nil,
            seeds: [
                seed(.genre, "hip hop", strength: 0.9),
                seed(.artist, "Radiohead", strength: 0.9),
            ]
        )
        let context = BrainContext(slices: [slice], read: nil, insights: [])

        let results = [
            track("Creep Rarity", artist: "Radiohead", popularity: 30),
            track("Song (Karaoke Version)", artist: "Karaoke Kings", popularity: 10),
            track("Chart Smash", artist: "Megastar", popularity: 90),
            track("Buried Gem", artist: "Unknown Quartet", album: album("Lost Record", releaseDate: "1972"), popularity: 21),
        ]

        let digger = BrainDigger(searchCatalog: { _, _ in results })
        let dig = await digger.dig(context: context, question: "recommend me a new song", synthesizer: nil)

        XCTAssertEqual(dig.pool.map(\.title), ["Buried Gem"])
        XCTAssertEqual(dig.pool.first?.releaseYear, 1972)
        XCTAssertFalse(dig.trails.isEmpty)
        XCTAssertTrue(dig.log.contains { $0.contains("known artist") })
    }

    @MainActor
    func testDigWithoutSeedsFallsBackHonestly() async {
        let context = BrainContext(slices: [], read: nil, insights: [])
        let digger = BrainDigger(searchCatalog: { _, _ in
            XCTFail("No search should run without seeds")
            return []
        })
        let dig = await digger.dig(context: context, question: "recommend a song", synthesizer: nil)
        XCTAssertTrue(dig.pool.isEmpty)
        XCTAssertTrue(dig.trails.isEmpty)
        XCTAssertEqual(dig.seedCount, 0)
    }

    @MainActor
    func testDigPoolCapsPerArtist() async {
        let slice = NodeBrainSlice(
            nodeID: .spotify,
            isConnected: true,
            isPopulated: true,
            summary: "test",
            facts: [],
            evidence: [],
            chunks: [],
            freshness: nil,
            confidence: 0.9,
            health: "ready",
            novelty: BrainNoveltySet(),
            dossier: nil,
            seeds: [seed(.genre, "hip hop", strength: 0.9)]
        )
        let context = BrainContext(slices: [slice], read: nil, insights: [])
        let results = (0..<5).map { track("Cut \($0)", artist: "One Band", popularity: 20) }

        let digger = BrainDigger(searchCatalog: { _, _ in results })
        let dig = await digger.dig(context: context, question: "recommend a new track", synthesizer: nil)
        XCTAssertEqual(dig.pool.count, 2)
    }

    // MARK: - Spend ledger and pricing

    func testModelPricingTiers() {
        XCTAssertEqual(ModelPricing.rate(for: "claude-haiku-4-5").inputPerMTok, 1)
        XCTAssertEqual(ModelPricing.rate(for: "claude-sonnet-5").outputPerMTok, 15)
        XCTAssertEqual(ModelPricing.rate(for: "claude-opus-4-8").outputPerMTok, 25)
        // Unknown models price at the top tier so estimates err high.
        XCTAssertEqual(ModelPricing.rate(for: "mystery-model").inputPerMTok, 5)

        let usage = ClaudeUsage(inputTokens: 1_000_000, outputTokens: 100_000)
        XCTAssertEqual(ModelPricing.costUSD(model: "claude-opus-4-8", usage: usage), 7.5, accuracy: 0.0001)
    }

    func testCacheTokensPriceAtWriteAndReadRates() {
        let usage = ClaudeUsage(inputTokens: 0, outputTokens: 0, cacheCreationInputTokens: 1_000_000, cacheReadInputTokens: 1_000_000)
        // Haiku input $1/MTok: write 1.25x + read 0.1x = $1.35.
        XCTAssertEqual(ModelPricing.costUSD(model: "claude-haiku-4-5", usage: usage), 1.35, accuracy: 0.0001)
    }

    func testSpendLedgerAccumulatesAndPrices() {
        let ledger = SpendLedger()
        ledger.record(stage: "scout:sourceDNA", effort: "low", completion: ClaudeCompletion(
            text: "{}",
            usage: ClaudeUsage(inputTokens: 1000, outputTokens: 500),
            model: "claude-haiku-4-5",
            durationMs: 800
        ))
        ledger.record(stage: "judge", effort: "xhigh", completion: ClaudeCompletion(
            text: "{}",
            usage: ClaudeUsage(inputTokens: 2000, outputTokens: 1000),
            model: "claude-opus-4-8",
            durationMs: 12000
        ))

        XCTAssertEqual(ledger.records.count, 2)
        XCTAssertEqual(ledger.totalInputTokens, 3000)
        XCTAssertEqual(ledger.totalOutputTokens, 1500)
        // (1000*1 + 500*5 + 2000*5 + 1000*25) / 1M = 0.0385
        XCTAssertEqual(ledger.totalUSD, 0.0385, accuracy: 0.000001)
        XCTAssertTrue(ledger.records[0].traceLine.contains("haiku"))
        XCTAssertTrue(ledger.records[1].traceLine.contains("opus"))
    }

    // MARK: - Decode compatibility

    func testDigResultDecodesWithoutRevisionBFields() throws {
        // A Revision A message persisted before rounds/stopReason/leads/spend existed.
        let json = """
        {"seedCount": 5, "trails": [], "effectNodes": [], "pool": [], "log": ["x"], "generatedAt": 0}
        """
        let dig = try JSONDecoder().decode(DigResult.self, from: Data(json.utf8))
        XCTAssertEqual(dig.seedCount, 5)
        XCTAssertNil(dig.rounds)
        XCTAssertNil(dig.stopReason)
        XCTAssertNil(dig.leads)
        XCTAssertNil(dig.spend)
    }

    // MARK: - Depth-2 effect nodes from leads

    func testChasedLeadBecomesCatalogSearchEffectNode() {
        let lead = DigLead(
            title: "KPM library roster",
            kind: "labelRoster",
            entities: ["Alan Hawkshaw", "Keith Mansfield"],
            queryHint: "label:\"KPM\"",
            evidence: "round 1: label:\"KPM\" year:1970-1978",
            score: 0.85
        )
        let followUp = BrainSynthesizer.ForemanDecision.FollowUp(
            trailID: "trail/contextFlip",
            query: "label:\"KPM\" year:1965-1969",
            rationale: "chase the earlier KPM years the roster points at"
        )
        let node = BrainDigger.effectNode(forLead: lead, followUp: followUp, depth: 2)
        XCTAssertEqual(node.effectType, .labelCatalog)
        XCTAssertEqual(node.provenance, .catalogSearch)
        XCTAssertEqual(node.depth, 2)
        XCTAssertTrue(node.evidence.contains { $0.contains("round 1") })

        let bare = BrainDigger.effectNode(forLead: nil, followUp: followUp, depth: 3)
        XCTAssertEqual(bare.effectType, .genreScene)
        XCTAssertEqual(bare.depth, 3)
    }

    // MARK: - Revision C journeys and variety

    func testDevotionSeedsFromPlaylistTitles() {
        let seeds = BrainSeedExtractor.devotionSeeds(
            playlists: ["MAC MILLER", "road trip emilio", "Deftones", "boosie"],
            artistNames: ["Mac Miller", "Deftones", "Fleetwood Mac"],
            node: .spotify,
            freshness: nil
        )
        XCTAssertEqual(Set(seeds.map(\.title)), ["Mac Miller", "Deftones"])
        XCTAssertTrue(seeds.allSatisfy { $0.entityType == .devotion && $0.strength == 0.85 })
    }

    func testPhotoAlbumTitlesCollapseToPlaces() {
        XCTAssertEqual(BrainSeedExtractor.placeName(fromAlbumTitle: "Mexxiiicooooo"), "Mexico")
        XCTAssertEqual(BrainSeedExtractor.placeName(fromAlbumTitle: "Morocco"), "Morocco")
        XCTAssertNil(BrainSeedExtractor.placeName(fromAlbumTitle: "Pari"))
        XCTAssertNil(BrainSeedExtractor.placeName(fromAlbumTitle: "Fulton dump"))

        let seeds = BrainSeedExtractor.photosSeeds(
            locationNames: [],
            albumTitles: ["Mexxiiicooooo", "Morocco", "WhatsApp", "NFTs"],
            freshness: nil
        )
        XCTAssertEqual(Set(seeds.map(\.title)), ["Mexico", "Morocco"])
        XCTAssertTrue(seeds.allSatisfy { $0.entityType == .place })
    }

    func testNewJourneyPredicates() {
        let devotion = [seed(.devotion, "Deftones", strength: 0.85)]
        XCTAssertEqual(HeroJourney.aliasSideDoor.score(devotion), 0.85 * 0.95, accuracy: 0.0001)

        let trap = [seed(.genre, "atl trap", strength: 0.8)]
        XCTAssertGreaterThan(HeroJourney.producerChain.score(trap), 0.5)

        let folk = [seed(.genre, "singer-songwriter", strength: 0.7)]
        XCTAssertGreaterThan(HeroJourney.songwriterShadow.score(folk), 0.5)

        let reggae = [seed(.genre, "roots reggae", strength: 0.7)]
        XCTAssertGreaterThan(HeroJourney.versionChain.score(reggae), 0.5)

        // Open crate always clears the bar when any seed exists, and every
        // evidenced journey outranks it.
        XCTAssertEqual(HeroJourney.openCrate.score(devotion), 0.36)
        XCTAssertEqual(HeroJourney.openCrate.score([]), 0)
    }

    func testStoryJourneyPredicates() {
        // Diaspora: heritage genre carries it, a place seed strengthens it.
        let latin = [seed(.genre, "latin", strength: 0.8)]
        let base = HeroJourney.diasporaThread.score(latin)
        XCTAssertGreaterThan(base, 0.5)
        let withPlace = latin + [seed(.place, "Mexico", strength: 0.6, node: .photos)]
        XCTAssertGreaterThan(HeroJourney.diasporaThread.score(withPlace), base)

        let hardcore = [seed(.genre, "post-hardcore", strength: 0.7)]
        XCTAssertGreaterThan(HeroJourney.splitAndDemo.score(hardcore), 0.5)

        let classical = [seed(.genre, "baroque", strength: 0.7)]
        XCTAssertGreaterThan(HeroJourney.interpretationChain.score(classical), 0.5)

        // None of the three fire without their genre signal.
        let soul = [seed(.genre, "retro soul", strength: 0.9)]
        XCTAssertEqual(HeroJourney.diasporaThread.score(soul), 0)
        XCTAssertEqual(HeroJourney.splitAndDemo.score(soul), 0)
        XCTAssertEqual(HeroJourney.interpretationChain.score(soul), 0)
    }

    func testIdiomMenuCoversEveryJourney() {
        let menu = HeroJourney.idiomMenu
        for journey in HeroJourney.allCases {
            XCTAssertTrue(menu.contains(journey.title), "menu missing \(journey.title)")
        }
    }

    func testOpenCrateGuaranteesTheExpeditionRuns() {
        // A profile with no journey-triggering signal at all: one weak seed.
        let seeds = [seed(.topic, "vlogging", strength: 0.4, node: .youtube)]
        let output = BrainTrailBuilder.build(from: seeds)
        XCTAssertEqual(output.trails.map(\.journey), [.openCrate])
    }

    func testJourneyBiasPenalizesRecentRoutes() {
        // "hip hop" fires sourceDNA (0.855), producerChain (0.81), and
        // contextFlip (0.765). A recent-route penalty on sourceDNA must
        // demote it from the top slot.
        let seeds = [seed(.genre, "hip hop", strength: 0.9)]
        let unbiased = BrainTrailBuilder.build(from: seeds)
        XCTAssertEqual(unbiased.trails.first?.journey, .sourceDNA)

        let biased = BrainTrailBuilder.build(from: seeds, journeyBias: ["sourceDNA": -0.16])
        XCTAssertEqual(biased.trails.first?.journey, .producerChain)
        XCTAssertTrue(biased.trails.contains { $0.journey == .sourceDNA })
    }

    // MARK: - Query hygiene

    func testSanitizerSplitsORsAndStripsFakeTags() {
        let queries = BrainDigger.sanitizedQueries(
            "label:\"Hi Records\" OR label:\"Stax Records\" genre:\"soul\" year:1970-1976 tag:live"
        )
        XCTAssertEqual(queries.count, 2)
        XCTAssertEqual(queries[0], "label:\"Hi Records\"")
        XCTAssertEqual(queries[1], "label:\"Stax Records\" genre:\"soul\" year:1970-1976")
        XCTAssertFalse(queries[1].contains("tag:live"))

        // Real tags survive.
        XCTAssertEqual(BrainDigger.sanitizedQueries("genre:\"soul\" tag:hipster"), ["genre:\"soul\" tag:hipster"])
    }

    func testRelaxationProgressivelyBroadensZeroResultQueries() {
        // Step 1: drop the tag.
        let step1 = BrainDigger.relaxedQuery("genre:\"soul\" year:1972-1978 tag:hipster")
        XCTAssertEqual(step1, "genre:\"soul\" year:1972-1978")
        // Step 2: genre: becomes plain quoted words.
        let step2 = BrainDigger.relaxedQuery(step1!)
        XCTAssertEqual(step2, "\"soul\" year:1972-1978")
        // Step 3: the year window goes.
        let step3 = BrainDigger.relaxedQuery(step2!)
        XCTAssertEqual(step3, "\"soul\"")
        // Nothing left to relax.
        XCTAssertNil(BrainDigger.relaxedQuery(step3!))
    }

    @MainActor
    func testZeroResultQueryGetsRelaxedUntilCatalogAnswers() async {
        let slice = NodeBrainSlice(
            nodeID: .spotify,
            isConnected: true,
            isPopulated: true,
            summary: "test",
            facts: [],
            evidence: [],
            chunks: [],
            freshness: nil,
            confidence: 0.9,
            health: "ready",
            novelty: BrainNoveltySet(),
            dossier: nil,
            seeds: [seed(.genre, "hip hop", strength: 0.9)]
        )
        let context = BrainContext(slices: [slice], read: nil, insights: [])
        // The deterministic sourceDNA query carries genre: + year:. Answer
        // nothing until the query loses its genre: filter.
        let digger = BrainDigger(searchCatalog: { query, _ in
            query.contains("genre:") ? [] : [self.track("Found It", artist: "Deep Act", popularity: 20)]
        })
        let dig = await digger.dig(context: context, question: "recommend a new song", synthesizer: nil)
        XCTAssertEqual(dig.pool.map(\.title), ["Found It"])
        XCTAssertTrue(dig.log.contains { $0.contains("relaxed ->") })
    }

    // MARK: - Assay-graded pool ordering

    @MainActor
    func testAssemblePoolPrefersAssayGrades() async {
        let slice = NodeBrainSlice(
            nodeID: .spotify,
            isConnected: true,
            isPopulated: true,
            summary: "test",
            facts: [],
            evidence: [],
            chunks: [],
            freshness: nil,
            confidence: 0.9,
            health: "ready",
            novelty: BrainNoveltySet(),
            dossier: nil,
            seeds: [seed(.genre, "hip hop", strength: 0.9)]
        )
        let context = BrainContext(slices: [slice], read: nil, insights: [])
        // Without a synthesizer nothing is graded; ordering falls back to
        // obscurity and the dig stops after one honest round.
        let results = [
            track("Mid", artist: "Artist A", popularity: 30),
            track("Floor", artist: "Artist B", popularity: 2),
        ]
        let digger = BrainDigger(searchCatalog: { _, _ in results })
        let dig = await digger.dig(context: context, question: "recommend a new song", synthesizer: nil)
        XCTAssertEqual(dig.pool.first?.title, "Mid")
        XCTAssertEqual(dig.rounds, 1)
        XCTAssertEqual(dig.stopReason, "single round (no delegated agents)")
    }

    // MARK: - Answer-text salvage

    @MainActor
    func testSalvageRecoversPicksNamedOnlyInProse() {
        func poolEntry(_ title: String, _ artist: String) -> DugCandidate {
            DugCandidate(
                id: title, trailID: "trail/sourceDNA", journey: .sourceDNA, source: "Spotify",
                title: title, artist: artist, album: nil, releaseYear: 1974,
                popularity: 25, url: nil, routeReason: "source-era dig"
            )
        }
        let pool = [
            poolEntry("Can't Live Without You", "Connie Laverne"),
            poolEntry("Let Them Talk", "Gwen McCrae"),
            poolEntry("Moroccan Soul", "Mehdi Yakin"),
        ]
        // The observed failure: picks named in prose, empty recommendations array.
        let text = "Start with Connie Laverne, the buried 1974 soul you actually dig for. Gwen McCrae holds the same heat if the first is spoken for."
        let salvaged = TasteProfile.salvageCandidates(fromAnswerText: text, pool: pool)
        XCTAssertEqual(salvaged.map(\.artist), ["Connie Laverne", "Gwen McCrae"])
        XCTAssertEqual(salvaged.first?.title, "Can't Live Without You")

        // Prose naming nothing from the pool salvages nothing.
        XCTAssertTrue(TasteProfile.salvageCandidates(fromAnswerText: "The dig came back empty.", pool: pool).isEmpty)
    }

    // MARK: - Pool matching keys

    func testDugCandidateTrackKeyMatchesNoveltyNormalization() {
        let candidate = DugCandidate(
            id: "x",
            trailID: "trail/cheapRiskBin",
            journey: .cheapRiskBin,
            source: "Spotify",
            title: "Buried Gem",
            artist: "Unknown Quartet",
            album: nil,
            releaseYear: nil,
            popularity: nil,
            url: nil,
            routeReason: "test"
        )
        XCTAssertEqual(candidate.trackKey, BrainNoveltySet.trackKey(title: "buried gem", artist: "UNKNOWN quartet"))
    }

    // MARK: - Live digging log

    func testDigLogNearbyStartTimesDoNotCollapseToOneJourney() {
        var firstDraws = Set<Int>()
        let seed: UInt64 = 800_000_000_000
        for offset in 0..<24 {
            var rng = DigRNG(seed: seed + UInt64(offset))
            firstDraws.insert(Int.random(in: DiggingLog.journeys.indices, using: &rng))
        }
        XCTAssertGreaterThan(firstDraws.count, 6)
    }

    func testDigLogCyclesEveryAuthoredJourneyBeforeRepeating() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000.123)
        let entries = DiggingLogView.schedule(
            digStart: start,
            delivery: start.addingTimeInterval(3_600)
        )
        let originDescriptions = Set(DiggingLog.journeys.compactMap { $0.steps.first?.desc })
        let origins = entries
            .map(\.step.desc)
            .filter { expanded in
                originDescriptions.contains { expanded.hasPrefix($0 + " >") }
            }

        XCTAssertGreaterThanOrEqual(origins.count, DiggingLog.journeys.count)
        XCTAssertEqual(Set(origins.prefix(DiggingLog.journeys.count)).count, DiggingLog.journeys.count)

        let firstFiveMinutes = entries
            .filter { $0.date >= start && $0.date <= start.addingTimeInterval(300) }
            .map(\.date)
        let largestGap = zip(firstFiveMinutes, firstFiveMinutes.dropFirst())
            .map { $1.timeIntervalSince($0) }
            .max() ?? .infinity
        XCTAssertLessThanOrEqual(largestGap, 25)
    }

    func testDigLogMostLinesCarryResearchDetail() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000.123)
        let entries = DiggingLogView.schedule(
            digStart: start,
            delivery: start.addingTimeInterval(900)
        )
        let detailed = entries.filter { $0.step.desc.contains(" > ") }

        XCTAssertFalse(entries.isEmpty)
        XCTAssertGreaterThanOrEqual(
            Double(detailed.count) / Double(entries.count),
            0.95
        )
        XCTAssertTrue(entries.contains {
            $0.step.verb == "OPENING" && $0.step.desc.components(separatedBy: " > ").count >= 2
        })
    }

    func testDailyRecommendationDecodesEditorialJourney() throws {
        let data = Data("""
        {
          "ready": true,
          "cycleDate": "2026-07-19",
          "deliveryHour": 9,
          "deliveryMinute": 0,
          "recommendations": [{
            "rank": 1,
            "title": "A Song",
            "artist": "An Artist",
            "album": "An Album",
            "spotifyId": "track-1",
            "spotifyUrl": "https://open.spotify.com/track/track-1",
            "previewUrl": "https://cdn.shibuyaaa.com/preview.m4a",
            "artworkUrl": "https://cdn.shibuyaaa.com/cover.jpg",
            "why": "The source trail fits the way you listen.",
            "editorial": {
              "journeyId": "sourceDNA",
              "journeyTitle": "Source DNA",
              "routeSummary": "Move backward into the records beneath a loved scene.",
              "scoutQuery": "deep soul source records year:1968-1974",
              "scoutReason": "The trail points behind the revival into its source era.",
              "evidence": ["soul is a durable genre signal"],
              "confidence": 0.86,
              "assayScore": 0.91
            }
          }]
        }
        """.utf8)

        let response = try JSONDecoder().decode(WormAPI.TodayResponse.self, from: data)
        let editorial = try XCTUnwrap(response.recommendations.first?.editorial)
        XCTAssertEqual(editorial.journeyId, "sourceDNA")
        XCTAssertEqual(editorial.journeyTitle, "Source DNA")
        XCTAssertEqual(editorial.assayScore, 0.91)
    }
}
