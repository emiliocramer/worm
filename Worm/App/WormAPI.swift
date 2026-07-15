import Foundation

/// Thin client for the Worm dig backend (shibuya-api `/worm`). The app uploads its
/// delivery time + taste profile (and the Spotify refresh token so the server can
/// re-sync headless), triggers/reads the dig, and shows server-computed picks.
///
/// Base URL comes from Info.plist `WormBackendBaseURL` (defaults to the production
/// api.shibuyaaa.com). Identity is a persisted install id (`deviceId`).
enum WormAPI {
    // MARK: Config

    static var baseURL: URL {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "WormBackendBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty, let url = URL(string: raw) { return url }
        return URL(string: "https://api.shibuyaaa.com")!
    }

    static var deviceID: String {
        let key = "worm.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 120   // the dig can take a while server-side
        c.timeoutIntervalForResource = 180
        return URLSession(configuration: c)
    }()

    // MARK: Models

    struct TextSlice: Codable { let node: String; let summary: String }

    // Structured per-node facts the server dig extracts seeds from — the same
    // fields the on-device `BrainSeedExtractor` reads. Mirrors the backend
    // `dig/context.ts` `WormNodes`. Sensitive nodes stay device-reduced to these
    // small fact arrays; raw media never leaves the device.
    struct ArtistLite: Codable { let name: String; let genres: [String]? }
    struct AlbumLite: Codable { let name: String; let releaseDate: String? }
    struct TrackLite: Codable { let name: String; let artist: String?; let popularity: Int?; let album: AlbumLite? }
    struct SavedAlbumInner: Codable { let name: String; let label: String? }
    struct SavedAlbumLite: Codable { let album: SavedAlbumInner }
    struct SpotifyNodePayload: Codable {
        let topArtistsShort: [ArtistLite]
        let topArtistsMedium: [ArtistLite]
        let topArtistsLong: [ArtistLite]
        let topTracksShort: [TrackLite]
        let topTracksLong: [TrackLite]
        let savedAlbums: [SavedAlbumLite]
        let savedTrackCount: Int
        let playlists: [String]
        let lastSyncedAt: String?
    }
    struct MostPlayedLite: Codable { let artist: String; let playCount: Int }
    struct AppleMusicNodePayload: Codable {
        let genreNames: [String]
        let mostPlayed: [MostPlayedLite]
        let playlists: [String]
        let artistNames: [String]
        let lastSyncedAt: String?
    }
    struct YouTubeNodePayload: Codable {
        let creatorNames: [String]
        let topicCategories: [String]
        let lastSyncedAt: String?
    }
    struct PhotosNodePayload: Codable {
        let locationNames: [String]
        let albumTitles: [String]
        let lastSyncedAt: String?
    }
    struct RecurringEventLite: Codable { let title: String; let hour: Int; let isAllDay: Bool }
    struct CalendarNodePayload: Codable {
        let recurringEvents: [RecurringEventLite]
        let lastSyncedAt: String?
    }
    struct ContactsNodePayload: Codable {
        let cities: [String]
        let lastSyncedAt: String?
    }
    struct SelfieNodePayload: Codable {
        let aesthetics: [String]
        let confidence: Double
        let lastAnalyzedAt: String?
    }
    struct WormNodesPayload: Codable {
        var spotify: SpotifyNodePayload?
        var appleMusic: AppleMusicNodePayload?
        var youtube: YouTubeNodePayload?
        var photos: PhotosNodePayload?
        var calendar: CalendarNodePayload?
        var contacts: ContactsNodePayload?
        var selfie: SelfieNodePayload?

        var isEmpty: Bool {
            spotify == nil && appleMusic == nil && youtube == nil
                && photos == nil && calendar == nil && contacts == nil && selfie == nil
        }
    }

    struct TodayRec: Codable {
        let rank: Int
        let title: String
        let artist: String
        let album: String?
        let spotifyId: String?
        let spotifyUrl: String?
        let artworkUrl: String?
        let why: String?
    }
    struct TodayResponse: Codable {
        let ready: Bool
        let cycleDate: String?         // reveal date (YYYY-MM-DD) of the upcoming batch
        let deliveryHour: Int?
        let deliveryMinute: Int?
        let recommendations: [TodayRec]
    }
    struct DigRunResponse: Codable {
        let ok: Bool?
        let cycleDate: String?
        let recommendations: [TodayRec]?
    }
    struct Insight: Codable {
        let id: Int
        let line: String
        let evidence: String?
        let cycleDate: String?
    }
    private struct InsightsResponse: Codable { let insights: [Insight] }

    // MARK: Calls

    /// Upload delivery time, timezone, name, the structured per-node facts, and
    /// the prose taste slices. `nodes` are what the server dig extracts seeds from
    /// (the whole profile, not just Spotify); `textSlices` feed the taste brief.
    static func putProfile(
        deliveryHour: Int,
        deliveryMinute: Int,
        wormName: String?,
        nodes: WormNodesPayload?,
        textSlices: [TextSlice]
    ) async {
        var body: [String: Any] = [
            "deviceId": deviceID,
            "deliveryHour": deliveryHour,
            "deliveryMinute": deliveryMinute,
            "timezone": TimeZone.current.identifier,
        ]
        if let wormName, !wormName.isEmpty { body["wormName"] = wormName }
        if let nodes, !nodes.isEmpty,
           let data = try? JSONEncoder().encode(nodes),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            body["nodes"] = obj
        }
        if !textSlices.isEmpty {
            body["slices"] = textSlices.map { ["node": $0.node, "summary": $0.summary] }
        }
        _ = await send(path: "/worm/profile", method: "PUT", json: body)
    }

    /// Hand the backend a Spotify refresh token so it can re-sync the node headless.
    static func postSpotifySource(refreshToken: String) async {
        _ = await send(path: "/worm/sources", method: "POST", json: [
            "deviceId": deviceID, "provider": "spotify", "refreshToken": refreshToken,
        ])
    }

    /// Fill the upcoming reveal slot now (setup/manual); returns the run's cycle
    /// date + picks so the caller knows when to reveal them.
    static func triggerDig() async -> DigRunResponse? {
        guard let data = await send(path: "/worm/dig/run", method: "POST", json: ["deviceId": deviceID]) else { return nil }
        return try? JSONDecoder().decode(DigRunResponse.self, from: data)
    }

    /// The latest cycle's picks (what the reveal shows).
    static func fetchToday() async -> TodayResponse? {
        guard let data = await send(path: "/worm/today?deviceId=\(deviceID)", method: "GET", json: nil) else { return nil }
        return try? JSONDecoder().decode(TodayResponse.self, from: data)
    }

    /// The insight backlog, newest first.
    static func fetchInsights(limit: Int = 50) async -> [Insight] {
        guard let data = await send(path: "/worm/insights?deviceId=\(deviceID)&limit=\(limit)", method: "GET", json: nil) else { return [] }
        return (try? JSONDecoder().decode(InsightsResponse.self, from: data))?.insights ?? []
    }

    // MARK: Transport

    private static func send(path: String, method: String, json: [String: Any]?) async -> Data? {
        guard let url = URL(string: path, relativeTo: baseURL) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("[WormAPI] \(method) \(path) -> \(http.statusCode)")
                return nil
            }
            return data
        } catch {
            print("[WormAPI] \(method) \(path) failed: \(error.localizedDescription)")
            return nil
        }
    }
}
