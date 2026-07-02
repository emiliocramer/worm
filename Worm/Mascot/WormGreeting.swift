import CoreLocation
import Foundation
import Observation
import UIKit
import WeatherKit

/// Composes the worm's home-screen greeting — e.g. "Enjoying New York, Emilio?"
/// — entirely from **local, permission-free** signals. It depends on **no
/// nodes** and triggers **no system prompts**. It is always just **time + place
/// (+ name)** — never device-state chatter.
///
/// - **Place**: the device time-zone city (`America/New_York` → "New York"),
///   falling back to the locale's country.
/// - **Time**: time of day.
/// - **Name**: an optional value the user sets once in-app (not a system
///   permission), with a best-effort parse of the device name if the
///   user-assigned-device-name entitlement happens to be granted.
@MainActor
@Observable
final class WormGreeting {
    private static let nameKey = "worm.userName"

    private(set) var message: String = ""

    // Stable per-session pick so the phrasing stays put within a launch.
    @ObservationIgnored private let variant = Int.random(in: 0..<10_000)
    @ObservationIgnored private var weatherWord: String?
    @ObservationIgnored private var hasLoadedWeather = false

    init() {
        refresh()
    }

    /// The name the user has explicitly set, if any (without the device-name
    /// fallback) — used to prefill the edit field.
    var editableName: String {
        UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
    }

    func setName(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.nameKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: Self.nameKey)
        }
        refresh()
    }

    /// Re-reads the local context and recomposes the greeting. Synchronous and
    /// cheap — safe to call whenever the home screen appears.
    func refresh() {
        message = Self.compose(context: Self.currentContext(name: resolvedName), weather: weatherWord, variant: variant)
    }

    /// Fetches current conditions for the time-zone city and folds the weather
    /// into the greeting ("Another rainy afternoon in New York?"). No location
    /// permission: we forward-geocode the city name to a coordinate and ask
    /// WeatherKit about that coordinate. Silently no-ops if WeatherKit isn't
    /// entitled or the device is offline, leaving the plain time+place greeting.
    func loadWeather() async {
        guard !hasLoadedWeather, let city = Self.timeZoneCity() else { return }
        hasLoadedWeather = true
        let geocoder = CLGeocoder()
        guard let location = try? await geocoder.geocodeAddressString(city).first?.location else { return }
        guard let weather = try? await WeatherService.shared.weather(for: location) else { return }
        weatherWord = Self.describe(weather.currentWeather.condition)
        refresh()
    }

    private var resolvedName: String? {
        let stored = UserDefaults.standard.string(forKey: Self.nameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }
        return Self.parsedDeviceOwnerName()
    }

    // MARK: - Composition

    private static func currentContext(name: String?) -> (name: String?, place: String?, timeOfDay: String) {
        let hour = Calendar.current.component(.hour, from: Date())
        let place = timeZoneCity() ?? Locale.current.region.flatMap {
            Locale.current.localizedString(forRegionCode: $0.identifier)
        }
        return (name, place, timeOfDay(hour: hour))
    }

    /// Time + place (+ name), optionally colored by the weather. Always a
    /// question — it's the worm checking in on you.
    private static func compose(context ctx: (name: String?, place: String?, timeOfDay: String), weather: String?, variant: Int) -> String {
        let suffix = ctx.name.map { ", \($0)" } ?? ""

        let pool: [String]
        if let place = ctx.place {
            let timeWord = ctx.timeOfDay == "Late night" ? "night" : ctx.timeOfDay.lowercased()
            if var weather {
                // "clear" reads as "sunny" in daylight.
                if weather == "clear", timeWord != "night" { weather = "sunny" }
                pool = [
                    "Another \(weather) \(timeWord) in \(place)\(suffix)?",
                    "\(weather.capitalized) \(timeWord) in \(place)\(suffix)?",
                    "How's the \(weather) \(timeWord) in \(place)\(suffix)?",
                ]
            } else {
                pool = [
                    "Enjoying \(place)\(suffix)?",
                    "\(timeWord.capitalized) in \(place)\(suffix)?",
                    "How's \(place)\(suffix)?",
                ]
            }
        } else {
            pool = [
                "How's your \(ctx.timeOfDay.lowercased())\(suffix)?",
                "How are you\(suffix)?",
            ]
        }
        return pool[variant % pool.count]
    }

    /// Maps a WeatherKit condition to a one-word vibe, or nil for conditions not
    /// worth a line.
    private static func describe(_ condition: WeatherCondition) -> String? {
        switch condition {
        case .clear, .mostlyClear: return "clear"
        case .partlyCloudy, .mostlyCloudy: return "cloudy"
        case .cloudy: return "grey"
        case .drizzle, .rain, .heavyRain, .sunShowers, .freezingRain, .freezingDrizzle: return "rainy"
        case .thunderstorms, .strongStorms, .isolatedThunderstorms, .scatteredThunderstorms: return "stormy"
        case .snow, .heavySnow, .flurries, .sleet, .blizzard, .blowingSnow, .wintryMix: return "snowy"
        case .foggy, .haze, .smoky: return "foggy"
        case .windy, .breezy, .blowingDust: return "windy"
        case .hot: return "scorching"
        case .frigid: return "freezing"
        default: return nil
        }
    }

    // MARK: - Place

    /// "America/New_York" → "New York"; "Europe/London" → "London".
    private static func timeZoneCity() -> String? {
        guard let last = TimeZone.current.identifier.split(separator: "/").last else { return nil }
        let city = last.replacingOccurrences(of: "_", with: " ")
        return city.isEmpty ? nil : city
    }

    // MARK: - Name / time

    private static func parsedDeviceOwnerName() -> String? {
        let deviceName = UIDevice.current.name
        // "Emilio's iPhone" → "Emilio". On iOS 16+ this is usually just a
        // generic model name (no possessive) unless the app holds the
        // user-assigned-device-name entitlement, in which case this works.
        for separator in ["’s ", "'s "] {
            if let range = deviceName.range(of: separator) {
                let first = String(deviceName[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !first.isEmpty { return first }
            }
        }
        return nil
    }

    private static func timeOfDay(hour: Int) -> String {
        switch hour {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<22: return "Evening"
        default: return "Late night"
        }
    }
}
