import Foundation
import Observation

/// A resolved recommendation for the daily reveal. Artwork is optional so the UI
/// can show a neutral placeholder rather than a mismatched cover.
struct FoundSong: Codable, Hashable {
    let title: String
    let artist: String
    let artwork: String?
}

/// The immutable inputs needed to sync one daily dig. Keeping these separate
/// from the Home view makes the network boundary explicit and testable.
struct DigCycleSyncInput {
    let deliveryHour: Int
    let deliveryMinute: Int
    let wormName: String?
    let nodes: WormAPI.WormNodesPayload
    let textSlices: [WormAPI.TextSlice]
    let spotifyRefreshToken: String?
}

/// Owns the daily recommendation cycle: persisted batch state, deadline
/// resolution, backend synchronization, and reset. `WormHomeView` owns only the
/// presentation state (setup, waiting, and arrived).
@MainActor
@Observable
final class DigCycleCoordinator {
    private struct CachedRecommendations: Codable {
        let revealDate: String
        let recommendations: [FoundSong]
    }

    private enum Key {
        static let recommendations = "worm.digRecs"
        static let revealDate = "worm.digRevealDate"
        static let lastRevealedDate = "worm.lastRevealedDate"
    }

    private let defaults: UserDefaults
    private(set) var recommendations: [FoundSong] = []
    private(set) var deadline: Date?
    private(set) var isSyncing = false
    private(set) var revealDate: String
    private(set) var lastRevealedDate: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.revealDate = defaults.string(forKey: Key.revealDate) ?? ""
        self.lastRevealedDate = defaults.string(forKey: Key.lastRevealedDate) ?? ""
    }

    func beginWaiting(input: DigCycleSyncInput, testDeadline: TimeInterval, now: Date = .now) {
        loadCachedRecommendations()
        deadline = resolvedDeadline(input: input, testDeadline: testDeadline, now: now)
    }

    func remaining(at now: Date = .now) -> TimeInterval {
        max(0, (deadline ?? .distantPast).timeIntervalSince(now))
    }

    func formattedRemaining(at now: Date = .now) -> String {
        let total = Int(remaining(at: now).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    /// Returns true when a newly received batch is already due and Home should
    /// transition directly to its arrived/reveal state.
    func sync(input: DigCycleSyncInput, testDeadline: TimeInterval, now: Date = .now) async -> Bool {
        guard !isSyncing else { return false }
        isSyncing = true
        defer { isSyncing = false }

        await WormAPI.putProfile(deliveryHour: input.deliveryHour, deliveryMinute: input.deliveryMinute, wormName: input.wormName, nodes: input.nodes, textSlices: input.textSlices)
        if let token = input.spotifyRefreshToken { await WormAPI.postSpotifySource(refreshToken: token) }

        var response = await WormAPI.fetchToday()
        if response == nil || response?.ready != true,
           let run = await WormAPI.triggerDig(), let recommendations = run.recommendations, !recommendations.isEmpty {
            response = WormAPI.TodayResponse(ready: true, cycleDate: run.cycleDate, deliveryHour: input.deliveryHour, deliveryMinute: input.deliveryMinute, recommendations: recommendations)
        }
        return apply(response, input: input, testDeadline: testDeadline, now: now)
    }

    func forceReveal(input: DigCycleSyncInput) async {
        recommendations = []
        revealDate = ""
        defaults.removeObject(forKey: Key.recommendations)

        var response = await WormAPI.fetchToday()
        if response == nil || response?.ready != true,
           let run = await WormAPI.triggerDig(), let recommendations = run.recommendations, !recommendations.isEmpty {
            response = WormAPI.TodayResponse(ready: true, cycleDate: run.cycleDate, deliveryHour: input.deliveryHour, deliveryMinute: input.deliveryMinute, recommendations: recommendations)
        }
        guard let response, let cycleDate = response.cycleDate, !response.recommendations.isEmpty else { return }
        recommendations = mapped(response.recommendations)
        revealDate = String(cycleDate.prefix(10))
        lastRevealedDate = revealDate
        persist()
    }

    func markRevealed() {
        guard !revealDate.isEmpty else { return }
        lastRevealedDate = revealDate
        defaults.set(lastRevealedDate, forKey: Key.lastRevealedDate)
    }

    func reset(input: DigCycleSyncInput, testDeadline: TimeInterval, now: Date = .now) {
        recommendations = []
        revealDate = ""
        defaults.removeObject(forKey: Key.recommendations)
        defaults.removeObject(forKey: Key.revealDate)
        deadline = resolvedDeadline(input: input, testDeadline: testDeadline, now: now)
    }

    private func apply(_ response: WormAPI.TodayResponse?, input: DigCycleSyncInput, testDeadline: TimeInterval, now: Date) -> Bool {
        guard let response, response.ready, let cycleDate = response.cycleDate, !response.recommendations.isEmpty else { return false }
        let incomingDate = String(cycleDate.prefix(10))
        if incomingDate == lastRevealedDate {
            if testDeadline == 0 { deadline = nextDelivery(input: input, after: now) }
            return false
        }
        recommendations = mapped(response.recommendations)
        revealDate = incomingDate
        persist()
        deadline = resolvedDeadline(input: input, testDeadline: testDeadline, now: now)
        return testDeadline == 0 && (deadline ?? .distantFuture) <= now
    }

    private func loadCachedRecommendations() {
        guard let data = defaults.data(forKey: Key.recommendations),
              let cached = try? JSONDecoder().decode(CachedRecommendations.self, from: data),
              cached.revealDate == revealDate else { return }
        recommendations = cached.recommendations
    }

    private func persist() {
        defaults.set(revealDate, forKey: Key.revealDate)
        defaults.set(lastRevealedDate, forKey: Key.lastRevealedDate)
        if let data = try? JSONEncoder().encode(CachedRecommendations(revealDate: revealDate, recommendations: recommendations)) {
            defaults.set(data, forKey: Key.recommendations)
        }
    }

    private func mapped(_ recommendations: [WormAPI.TodayRec]) -> [FoundSong] {
        recommendations.sorted { $0.rank < $1.rank }.prefix(3).map { FoundSong(title: $0.title, artist: $0.artist, artwork: $0.artworkUrl) }
    }

    private func resolvedDeadline(input: DigCycleSyncInput, testDeadline: TimeInterval, now: Date) -> Date {
        if testDeadline > 0 { return Date(timeIntervalSinceReferenceDate: testDeadline) }
        if !revealDate.isEmpty, revealDate != lastRevealedDate, let date = revealMoment(revealDate, input: input) { return date }
        return nextDelivery(input: input, after: now)
    }

    private func revealMoment(_ date: String, input: DigCycleSyncInput) -> Date? {
        let parts = date.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
        components.hour = input.deliveryHour; components.minute = input.deliveryMinute
        return Calendar.current.date(from: components)
    }

    private func nextDelivery(input: DigCycleSyncInput, after date: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        components.hour = input.deliveryHour; components.minute = input.deliveryMinute
        let today = Calendar.current.date(from: components) ?? date
        return today > date ? today : (Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today)
    }
}
