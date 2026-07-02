# Worm

An iOS app that hosts **personality nodes**. The shipping home is the worm's
digging surface; the original node graph still exists as a developer surface for
inspecting each node.

There are currently six nodes:

- **Spotify node** — OAuth (Authorization Code + PKCE)
- **Apple Music node** — MusicKit
- **YouTube culture node** — Google OAuth (Authorization Code + PKCE)
- **Contacts node** — Contacts framework (`CNContactStore`)
- **Photos node** — Photos framework (`PHPhotoLibrary`)
- **Calendar node** — EventKit events + reminders

Each connects the user's account and pulls the most complete possible picture of
their identity for that source. Full node snapshots stay on the device and are
persisted locally (JSON in Application Support, plus the keychain for OAuth
tokens) so a returning user sees their data instantly and never has to
reconnect; calling **Disconnect** clears it. The brain layer may send compact
node slices to Claude for synthesis and debug chat; it never sends full raw
snapshots.

## Brain layer

Nodes reduce into compact **brain slices** (`NodeBrainSlice`): summaries,
high-signal facts, evidence strings, retrieval chunks, node health, and local
novelty memory. `TasteProfile` combines those slices into a `BrainContext`.
`BrainRetriever` selects a small working set from that context for each direct
question, then `BrainSynthesizer` asks Claude for reads, insights, and debug chat
answers. `ClaudeClient` is transport-only and has no node-specific knowledge.

The north star is **taste -> music**, not music -> music. Spotify and Apple Music
are important evidence, but YouTube, Contacts, Photos, Calendar, and future
culture/media nodes must be able to change the pick. A recommendation has to be
new, real, catalog verified, and explainable from the whole taste profile.

The first debug query lives at **Profile → Chat**. Asking
`recommend me a new song` retrieves music memories from the combined brain
context and then rejects any known track, artist, or album found in
Spotify/Apple Music novelty memory. It also rejects tracks that fail Spotify or
Apple Music catalog verification.

## What the Spotify node captures

Across the full read surface of the Spotify Web API:

- **Profile** — display name, id, email, product tier, country, follower count
- **Playback** — currently playing, full playback state, available devices, queue
- **Recently played**
- **Taste** — top tracks *and* top artists across all three time ranges
  (last 4 weeks / 6 months / all time)
- **Library** — every saved track, album, show, episode, and audiobook, plus
  saved-album track lists, saved-show episode lists, and saved-audiobook
  chapter lists where Spotify returns them
- **Social** — every followed artist
- **Playlists** — every playlist, each hydrated to its full track list

### Scopes requested

`user-read-private`, `user-read-email`, `user-read-currently-playing`,
`user-read-playback-state`, `user-read-playback-position`,
`user-read-recently-played`, `user-top-read`, `user-library-read`,
`user-follow-read`, `playlist-read-private`, `playlist-read-collaborative`.

> Note: Spotify deprecated the audio-features / audio-analysis endpoints for
> new apps (Nov 2024), so per-track audio descriptors are intentionally not
> included. Some scopes (e.g. `user-read-email`) require justification in the
> Spotify dashboard to leave development mode.

## What the Apple Music node captures

Via MusicKit, on-device after `MusicAuthorization`:

- **Subscription** — can-play-catalog and can-subscribe state
- **Library** — every song, album, artist, and playlist with MusicKit metadata
  such as genres, dates, play counts, artwork, ratings, identifiers, durations,
  editorial notes, labels, playlist descriptions, and URLs where exposed
- **Album tracks** — each library album's hydrated track list, including songs
  and music videos where MusicKit exposes them
- **Playlist entries** — each playlist's ordered entries, item type, artist,
  album, position, play counts, dates, genres, preview assets, ISRC, URLs,
  artwork, and music-video flags where exposed
- **Recently played**
- **Personal recommendations**
- **Now playing** — current system-player item

> Requires the **MusicKit capability** on the App ID (Xcode → Signing &
> Capabilities → **+ MusicKit**) and a real device on iOS 16+. The simulator and
> unprovisioned builds return limited or empty results. `NSAppleMusicUsageDescription`
> is already set in `Info.plist`.

## What the YouTube culture node captures

Google is treated as an auth spine. The first real Google-backed taste node is
YouTube, because it carries non-music culture signal: creators, video formats,
references, topics, hobbies, aesthetics, and media habits.

Via Google OAuth and the YouTube Data API:

- **Google identity** — name, email, profile picture, locale where exposed
- **Owned YouTube channels** — channel snippets, descriptions, custom URLs,
  country, thumbnails, related playlists, status, statistics, topic categories,
  branding settings, and localizations
- **Subscriptions** — every readable subscribed channel with snippet and
  content details
- **Channel sections** — the user's visible channel shelves and their linked
  playlists/channels where exposed
- **Activities** — readable account activity with activity type and linked
  resource identifiers
- **Playlists** — every owned playlist with snippet, descriptions, status,
  player/localization data, and item counts
- **Playlist items** — every readable item from every owned playlist, bounded by
  a high safety cap
- **Uploads** — uploaded-video playlist items for any owned channel
- **Liked videos** — every video returned by the account's liked-video feed
- **Video enrichment** — batched metadata for videos discovered from likes,
  playlists, uploads, and activities: titles, descriptions, tags, channel,
  category, duration, definition, caption flag, region restrictions, status,
  statistics, topics, recording/live details, player/localizations, and paid
  placement flag where exposed
- **Channel enrichment** — rich metadata for subscribed/recurring creators
- **Video categories** — region category names so the brain sees "Comedy" or
  "Education" instead of opaque category IDs

> Standard YouTube Data API access does **not** expose full watch history or
> Watch Later. The node records that limitation in its health/debug output
> instead of pretending the graph has data it cannot legally read.

## What the Contacts node captures

Via the Contacts framework, after the user grants address-book access:

- **Every contact** — identifier, contact type, all name fields, previous family
  name, nickname, phonetic names, organization, phonetic organization,
  department, and job title
- **Dates** — birthday, non-Gregorian birthday, and every labeled custom date
  with raw date components
- **Communication surfaces** — every labeled phone number, email address, URL,
  instant-message handle, social profile, and postal address
- **Relationship graph** — every labeled contact relation and relation name
- **Accounts and groups** — every readable Contacts account/container, every
  group, and contact membership maps for both
- **Images** — image availability plus full and thumbnail image bytes where the
  framework exposes them
- **Brain slice signal** — compact retrieval chunks for groups, accounts,
  representative contacts, organizations, departments, jobs, relationship
  labels, social services, email domains, URL hosts, places, birthday months,
  and name/affiliation terms

> `CNContactNoteKey` is intentionally not requested because modern iOS requires
> a special Apple entitlement for contact notes. The Contacts node records that
> limitation in its health/debug output.

## What the Photos node captures

Via the Photos framework, after the user grants library access, for **every
asset in the library** (photos and videos, including hidden and burst assets):

- **Asset** — media type, every media subtype (Live Photo, HDR, panorama,
  screenshot, depth/portrait, slo-mo, time-lapse, cinematic, spatial…), pixel
  dimensions, duration, creation/modification dates, favorite/hidden flags,
  playback style, source type, burst identity, and whether it has edits
- **Location** — latitude, longitude, altitude, horizontal/vertical accuracy,
  speed, course, and fix timestamp from the asset's `CLLocation`
- **Files** — every backing `PHAssetResource` (original, edited render,
  adjustment data, paired Live-Photo movie…) with original filename, UTI, and
  byte size
- **Embedded metadata** — the complete EXIF / TIFF / GPS / IPTC dictionaries
  read from each photo's image data via ImageIO, flattened to dotted keys
  (`Exif.FNumber`, `Exif.ISOSpeedRatings`, `TIFF.Model`, `GPS.Altitude`, …)
- **Video metadata** — for local videos, AVFoundation container metadata,
  request info, metadata formats, media characteristics, and every track's
  codec/format descriptions, timing, bitrate, dimensions, language, frame rate,
  and track metadata
- **On-device Vision analysis** — the same kind of content understanding that
  powers the Photos app's search ("lamp", "beach", "dog"): scene/object
  **classifications** with confidence, **recognized text** (OCR) read out of the
  image, and a **face count**, all computed locally with the Vision framework
- **Albums** — every album and smart album with title, type, count, date range,
  and location names

> Requires the `NSPhotoLibraryUsageDescription` (already set in `Info.plist`).
> Embedded-metadata extraction reads each photo's original data **locally only**
> (iCloud network access is disabled), so iCloud-only originals still get their
> full `PHAsset`-level fields but may have empty embedded metadata until
> downloaded. The simulator returns whatever is in its seeded library.

## What the Calendar node captures

Via EventKit, after the user grants full access to events and/or reminders:

- **Sources/accounts** — every EventKit source with type, title, delegate flag,
  and event/reminder calendar counts
- **Calendars/lists** — every event calendar and reminder list with source,
  color, mutability, subscription state, supported availabilities, and allowed
  entity types
- **Events** — event occurrences across a broad 20-years-back / 10-years-forward
  window, chunked around EventKit's four-year event-query limit
- **Event detail** — identifiers, title, notes, URL, calendar, creation/modified
  dates, timezone, start/end/all-day state, availability, status, detached
  recurrence state, birthday contact identifier, structured location, organizer,
  attendees, alarms, and recurrence rules
- **Reminders** — every accessible reminder with identifiers, list, title, notes,
  URL, dates, timezone, start/due components, completion state/date, priority,
  attendees, alarms, and recurrence rules

> Requires `NSCalendarsFullAccessUsageDescription` and
> `NSRemindersFullAccessUsageDescription` (already set in `Info.plist`).

## Setup

1. Create local config files from the tracked examples:
   ```sh
   cp .env.example .env
   cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
   cp Config/Production.xcconfig.example Config/Production.xcconfig
   ```
2. For local direct-Claude development, set `WORM_ANTHROPIC_API_KEY` in
   `Config/Secrets.xcconfig`. For a production iOS build, leave that key empty
   in `Config/Production.xcconfig` and set `WORM_ANTHROPIC_BASE_URL` to a
   server-side proxy that holds the key.
3. Create an app in the [Spotify developer dashboard](https://developer.spotify.com/dashboard).
4. Add this redirect URI to the app settings:
   `com.shibuya.worm.spotify-auth://oauth-callback`
5. Set `WORM_SPOTIFY_CLIENT_ID`, `WORM_SPOTIFY_REDIRECT_URI`, and
   `WORM_SPOTIFY_CALLBACK_SCHEME` in `.env`, `Config/Secrets.xcconfig`, and
   `Config/Production.xcconfig`.
6. Create a Google OAuth client for the iOS app and enable the YouTube Data API.
7. Set `WORM_GOOGLE_CLIENT_ID`, `WORM_GOOGLE_REDIRECT_URI`, and
   `WORM_GOOGLE_CALLBACK_SCHEME` in `.env`, `Config/Secrets.xcconfig`, and
   `Config/Production.xcconfig`.
8. Generate the Xcode project and open it:
   ```sh
   xcodegen generate
   open Worm.xcodeproj
   ```
9. Build & run. Tap **Connect** on any node, authorize, and the node syncs
   everything it can read.

## Project layout

```
Worm/
  App/
    WormApp.swift          # @main; owns node instances for the app lifetime
    RootView.swift          # NavigationStack + node-route destinations
  Graph/
    PersonalityGraphView.swift # the node graph home screen
  Nodes/
    Music/
      MusicNodeView.swift   # Spotify: connect/disconnect + readout
      Spotify/
        SpotifyConfig.swift        # client config + the full set of read scopes
        SpotifyModels.swift        # Codable models for every entity
        SpotifyWebAPI.swift        # HTTP client + keychain token store
        SpotifyMusicNode.swift     # @Observable node: PKCE auth, refresh, full sync
    AppleMusic/
      AppleMusicNodeView.swift     # Apple Music: connect/disconnect + readout
      AppleMusicNode.swift         # @Observable node: MusicKit auth + full sync
    YouTube/
      GoogleConfig.swift           # Google client config + YouTube read scope
      YouTubeModels.swift          # Codable models for YouTube account data
      YouTubeWebAPI.swift          # HTTP client + keychain token store
      YouTubeCultureNode.swift     # @Observable node: PKCE auth, refresh, full sync
      YouTubeCultureNodeView.swift # YouTube: connect/disconnect + readout
    Contacts/
      ContactsNodeView.swift       # Contacts: connect/disconnect + full readout
      ContactsNode.swift           # @Observable node: Contacts auth + full scan
    Calendar/
      CalendarNodeView.swift       # Calendar/Reminders: connect/disconnect + readout
      CalendarNode.swift           # @Observable node: EventKit auth + full scan
    Photos/
      PhotosNodeView.swift         # Photos: connect/disconnect + per-photo readout
      PhotosNode.swift             # @Observable node: PHPhotoLibrary auth + full scan
  Persistence/
    SnapshotStore.swift            # generic JSON snapshot cache (Application Support)
```

Adding a node: create its `@Observable` manager + detail view, add a `NodeRoute`
case (wired in `RootView`), and add it to `PersonalityGraphView.nodeList`.

The project file is generated by [XcodeGen](https://github.com/yonkeltron/XcodeGen)
from `project.yml`; `Worm.xcodeproj` is regenerable and not the source of truth.
# worm
