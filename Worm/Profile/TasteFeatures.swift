import Foundation

/// A distilled Spotify music brief used by the Spotify node-slice builder. It
/// keeps the texture a human would notice — actual artist names, playlist
/// titles, eras — not just counts, because that texture is where real taste
/// lives.
///
/// This type is not a model boundary. The brain decides what compact context is
/// sent to Claude.
struct TasteFeatures: Codable {
    var name: String?
    var recentTopArtists: [String] = []      // short-term tops, in order
    var allTimeTopArtists: [String] = []     // long-term tops, in order
    var rideOrDie: [String] = []             // present across every range
    var newcomers: [String] = []             // recent-only, not in the longer record
    var topGenres: [String] = []             // "folk rock (13%)"
    var coolingGenres: [String] = []         // bigger all-time than now
    var heatingGenres: [String] = []         // bigger now than all-time
    var meanPopularity: Double?              // 0–100, of recent top tracks
    var pctObscure: Double?                  // share of recent top tracks under 30 popularity
    var eras: [String] = []                  // "1970s (41%)"
    var onRepeat: String?                    // most-repeated recent track
    var nightOwlRatio: Double?               // share of recent plays after midnight
    var playlistTitles: [String] = []        // self-owned playlist names
    var ownedPlaylistCount: Int = 0
    var savedTrackCount: Int = 0
    var product: String?                     // spotify tier

    /// Enough signal to be worth synthesizing.
    var hasSignal: Bool {
        !recentTopArtists.isEmpty || !allTimeTopArtists.isEmpty || !topGenres.isEmpty
    }

    /// The brief as the labeled prose the model reads. Empty fields are dropped
    /// so the model never reasons over blanks.
    var briefText: String {
        var lines: [String] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { lines.append("\(label): \(value)") }
        }
        func add(_ label: String, _ list: [String]) {
            if !list.isEmpty { lines.append("\(label): \(list.joined(separator: ", "))") }
        }

        add("Name", name)
        add("Recent favorite artists (this month)", recentTopArtists)
        add("All-time favorite artists", allTimeTopArtists)
        add("Stayed with them across years", rideOrDie)
        add("New in their rotation lately", newcomers)
        add("Dominant genres", topGenres)
        add("Fading genres", coolingGenres)
        add("Rising genres", heatingGenres)
        if let meanPopularity {
            let mainstream = meanPopularity >= 65 ? "mainstream" : meanPopularity <= 35 ? "deep underground" : "mixed"
            add("Average track popularity", "\(Int(meanPopularity))/100 (\(mainstream))")
        }
        if let pctObscure, pctObscure > 0 {
            add("Share of favorites the public has never heard", "\(Int(pctObscure))%")
        }
        add("Eras they live in", eras)
        add("On repeat lately", onRepeat)
        if let nightOwlRatio, nightOwlRatio > 0 {
            add("Share of listening after midnight", "\(Int(nightOwlRatio * 100))%")
        }
        add("Playlists they made (titles)", playlistTitles)
        if ownedPlaylistCount > 0 { add("Playlists they've built", "\(ownedPlaylistCount)") }
        if savedTrackCount > 0 { add("Saved tracks", "\(savedTrackCount)") }
        add("Spotify tier", product)

        return lines.joined(separator: "\n")
    }
}
