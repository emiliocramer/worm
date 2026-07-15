# Digging log — lo-fi terminal spec (current direction, not yet implemented)

**Status:** spec only. Nothing built. This is the **current** design for the
living "it's digging" background on the waiting screen. The earlier square-cluster
idea is parked as an alternative in
[`digging-background-spec.md`](digging-background-spec.md).

## The idea in one line

While the worm is off digging, the home screen fills — **from the bottom up** —
with a lo-fi terminal **log** of what it's browsing right now, timestamped and
real, and every so often a **screenshot of the actual page** it cracked open pops
in like an iframe, tied by hand-drawn connector lines to the log line that opened
it. It should read as *genuinely been digging for hours*, not a looping animation.

## Where it goes

The **waiting screen** — home base state after a delivery time is set, while the
top overlay counts down `i'll be back in Hh:Mm` (see `WormHomeView`, `deliveryFlow
== .waiting`). This log is the waiting-screen background.

**Layering (decision needed):** the reference mockups show *only* the log — no
worm. Recommendation: **hide the worm during `.waiting`** (he's literally away
digging — it fits "i'll be back"), keep the `i'll be back in Hh:Mm` copy pinned
top, and let the log own the screen. If we keep the worm, the log sits behind it
at `zIndex 2` with a clear-ish lower-center band, same as the other spec. Flagged
so whoever builds it picks one; the mockups imply worm-hidden.

---

## 1. Anatomy of a log line

```
▉  12:16:26 - FINDING - SYNTHESIZING PROFILE
```

Left → right, one line, monospaced, uppercase (except the timestamp):

1. **Status square** — solid, ~18×18 pt, ~2 pt corner radius, no stroke. Color =
   the **source lane** currently being dug (see §3). Consecutive lines on the same
   source share a color, so bursts read as clusters.
2. **Timestamp** — `HH:MM:SS`, 24-hour, ink black, monospace. Real (see §4).
3. `" - "` separator, ink black.
4. **Action verb** — colored by family (see §2), uppercase, e.g. `PROCESS`,
   `FINDING`, `WATCHING`.
5. `" - "` separator, ink black.
6. **Description** — uppercase, ink black, truncated with `…` to fit one line. May
   contain one **artifact** word rendered **bold + underlined** (the thing being
   produced: `PROFILE`, `REVIEW`, `GENRE`, `TASTE`, `VERDICT`). See §2.

Background is paper `#F7F5ED`. Font: `.system(size: 15, weight: .regular, design:
.monospaced)`. Row height ~30 pt. Left inset 20 pt. Square-to-text gap 10 pt.

---

## 2. Action verbs & colors

Verbs are grouped into families; each family shares a color so the log reads at a
glance. All are uppercase.

| Family | Color | Hex | Verbs |
|---|---|---|---|
| Discovery | indigo | `#3A2BE6` | PROCESS, SCANNING, CONNECTING, CRAWLING, QUEUEING |
| Reading | orange | `#E8611E` | FINDING, READING, BROWSING, TRACING, COMPARING |
| Media | green | `#1E9E3C` | WATCHING, LISTENING |
| Extract | maroon | `#9E1B1B` | EXTRACTING, SAVING |
| Synthesis | magenta | `#C41ECD` | SYNTHESIZING, RANKING, SKIPPING |
| Fault | warm grey | `#8A8A8A` | TIMEOUT, RETRYING, RATE-LIMITED, RESTING |

**Timestamp / separators / description:** ink `#141414`.

**Artifact word** (bold + underlined, ink): the payload of the dig —
`PROFILE`, `TASTE`, `GENRE`, `REVIEW`, `VERDICT`, `PRESSING`, `CREDIT`, `SAMPLE`.
At most one per line. This is what earns the underline — the moment the dig
*produced* something.

---

## 3. Status-square source lanes

The square encodes **which source the worm is on**, so a run of lines on one site
shares a color (the reference's red→green→magenta drift). Lane palette:

| Source | Color | Hex |
|---|---|---|
| Your library (Spotify / Apple Music) | green | `#35C41E` |
| Forums (Reddit, RYM, fan boards) | red | `#F01E1E` |
| Reference (Wikipedia, Genius, AllMusic) | blue | `#2E5BFF` |
| Video (YouTube, Boiler Room, NTS) | magenta | `#E01ECD` |
| Records (Discogs, Bandcamp, liner notes) | gold | `#E2B33C` |

A dig moves between lanes as it follows a thread; the square color moves with it.

---

## 4. The timeline — why it feels real

This is the heart of it: **not a loop.** The log is a deterministic function of
**real wall-clock time** since the dig began, so reopening the app after minutes
*or hours* shows exactly the state a real crawler would be in.

- **Anchor:** `digStartedAt` — persisted the moment `.waiting` begins (i.e., when
  the delivery time is confirmed, or the first launch into waiting). The dig
  "ends" at the next delivery time (the countdown's target).
- **Schedule = bursts + idle.** The span from `digStartedAt` → delivery is filled
  with **activity bursts** separated by long **idle gaps**:
  - A **burst** = one *dig journey* (§6): 5–12 log lines over 1–8 minutes, with
    small irregular intra-burst gaps (2 s … 90 s; a "reading"/"watching" step can
    be a few minutes).
  - **Idle gaps** between bursts: 20–120 min, occasionally punctuated by a single
    `RESTING` / `RATE-LIMITED` / `TIMEOUT` fault line so the silence reads as the
    worm pacing itself, not the app being asleep.
  - Bursts get **denser toward delivery**; the **final burst** (last ~2 min before
    delivery) is the synthesis climax → ends on the result (§6, closing lines).
- **Determinism:** everything (which journeys, their order, all gaps, the seed for
  each journey's variant) derives from a seed = `hash(digStartedAt)`. So the whole
  day's log is fixed at anchor time; the view just renders the prefix whose
  timestamps are `≤ now`. Reopen after 3 h → the correct ~N lines are already
  "there," newest at the bottom, the rest scrolled up/off. No catch-up animation
  on cold open — it's just already deep in the dig.
- **Live appends:** while the app is open and an entry's timestamp passes, it
  appends at the bottom in real time (§7).
- **Timestamps** render as the real clock time the entry "occurred"
  (`digStartedAt + offset`), so a user who set 8:00 pm and opens at 6:30 pm sees a
  believable afternoon of `14:xx … 18:2x` entries.

Edge cases to spec in code: if `now` is already past delivery (worm's back), show
the completed log ending on the result and a final `DONE` line; if the wait is
short (dev fast-forward), compress bursts proportionally.

---

## 5. Screenshot iframes

Every so often the worm "opens a page," and we show a **real screenshot** of it,
framed like a cracked-open iframe, tied to its log line.

- **Trigger:** specific journey steps carry a `screenshot:` cue (e.g. the
  `READ METRO BOOMIN…` line). When that line appears, its screenshot pops in.
- **Frame:** the capture in a thin black `1.5 pt` border, ~4 pt corner radius, a
  faint drop shadow, optional 1-line fake browser chrome (a grey bar + url) to
  sell "iframe." Sized ~300×380 pt, placed in the upper-middle empty area above
  the current log stack.
- **Connector lines:** two straight hand-drawn ink lines from the screenshot's
  bottom-left and bottom-right corners converging toward the log line that opened
  it — a callout tying page ↔ log (exactly as in the reference).
- **Lifecycle:** pop in (scale 0.96→1, opacity 0→1, ~0.3 s) → connector lines
  draw on (~0.25 s) → hold while that burst continues → fade out (~0.4 s) as the
  dig moves on and the stack scrolls up past it. **One at a time** (rarely two
  overlapping during a hand-off).
- **Aliveness:** a barely-there idle drift is fine; keep it lo-fi and still,
  matching the terminal character.

**Screenshot asset set** (real pages, captured as bundled images — see §8). Each
maps to journey steps in §6:

- Wikipedia — artist page (e.g. *Metro Boomin*)
- Discogs — a release / pressing page
- Genius — annotated lyrics
- Reddit — a thread (r/hiphopheads, r/indieheads, r/vinylheads)
- YouTube — an album-review video
- Bandcamp — an album page
- RateYourMusic — a chart / list
- Setlist.fm — a setlist
- Pitchfork / AllMusic — a review / credits page
- NTS / Boiler Room — a show page

---

## 6. Dig journeys (hero-story quality)

Each burst is a scripted journey with its own arc: *scan → catch a lead → open a
source → follow it → extract → produce something.* Offsets are relative to the
burst start (`+m:ss`); `lane` = square color; `SS:` marks a screenshot cue.
Artifacts shown in **bold-underline**. These are the bar for quality — write ~15
of them; four are specced here.

### Journey A — "The producer thread" (Metro Boomin) — matches the reference
```
+0:00  ●spotify  CONNECTING  - SCANNING SPOTIFY LIBRARY
+0:03  ●spotify  PROCESS     - FINDING ARTIST CREDITS
+0:06  ●spotify  PROCESS     - FINDING ARTIST CREDITS
+0:06  ●ref      FINDING     - READ METRO BOOMIN INTERVIEW…   SS: Wikipedia/Metro Boomin
+1:19  ●ref      FINDING     - SYNTHESIZING **PROFILE**
+1:35  ●ref      PROCESS     - FINDING ARTIST CREDITS
+2:57  ●records  EXTRACTING  - SAVING FAVOURITE **GENRE**…
+7:27  ●video    WATCHING    - WATCHING **REVIEW**            SS: YouTube/album review
+7:46  ●video    WATCHING    - SKIPPING TO SYNTHESIS
```

### Journey B — "Down the crate" (a sample source)
```
+0:00  ●forums   BROWSING    - r/VINYLHEADS TOP OF WEEK       SS: Reddit/r/vinylheads
+0:14  ●forums   TRACING     - TRACING A **SAMPLE**
+0:41  ●records  READING     - DISCOGS 1974 **PRESSING**      SS: Discogs/release
+2:03  ●records  EXTRACTING  - SAVING THE ORIGINAL PRESS
+2:20  ●ref      READING     - WHO PLAYED BASS ON THIS
+4:55  ●ref      SYNTHESIZING- UPDATING **TASTE**
```

### Journey C — "Annotations rabbit hole"
```
+0:00  ●ref      BROWSING    - GENIUS ANNOTATIONS             SS: Genius/lyrics
+0:22  ●ref      FINDING     - FINDING A **CREDIT**
+0:58  ●forums   READING     - FAN FORUM DISAGREES
+1:47  ●fault    RATE-LIMITED- BACKING OFF 40s
+2:31  ●video    WATCHING    - LIVE SESSION ON NTS            SS: NTS/show
+4:10  ●video    RANKING     - RANKING AGAINST YOUR **TASTE**
```

### Journey D — "Late-night listen" (the quiet one)
```
+0:00  ●library  LISTENING   - Xtal — Aphex Twin
+0:39  ●library  LISTENING   - SKIPPING AT 1:12
+1:20  ●ref      READING     - ALBUM THANK-YOUS
+3:30  ●records  BROWSING    - BANDCAMP TAGS                  SS: Bandcamp/album
+5:02  ●output   EXTRACTING  - SAVING A **VERDICT**
```

**Closing burst (final ~2 min before delivery), every dig:**
```
+0:00  ●output   SYNTHESIZING - COMPILING THE **PROFILE**
+0:18  ●output   RANKING      - RANKING 340 CANDIDATES
+0:52  ●output   EXTRACTING   - PICKING 3 THAT ARE SO YOU
+1:10  ●output   PROCESS      - DONE — HEADING BACK
```
(Output lane = magenta `#C41ECD`. This is what dovetails into "he found you 3
songs" — keep the count in sync with the notification.)

Also keep **one** deliberate joke line somewhere in the pool, à la the other
spec — e.g. `WATCHING - CHOP SUEY REMASTER? NO.`

---

## 7. Layout & motion (lo-fi)

- **Bottom-anchored stack.** Newest line at the very bottom (above the safe bottom
  inset ~24 pt). When a new line appears, the whole stack **eases up** by one row
  (~0.22 s, easeOut); the new row fades/rises in at the bottom (opacity 0→1 + 4 pt
  rise). Older rows that pass the top just clip off.
- **Max rows** = fits screen height (~26–30). Keep a handful of extra rows above
  the top edge so the scroll-up reveals history rather than empty space.
- **Cursor.** A blinking block `▉` sits after the last (active) line while the
  worm is "mid-step" (0.5 s on / 0.5 s off). It's the only always-moving element.
- **Cold open** (reopened after time passed): render the correct prefix instantly,
  fully settled, no replay — it should feel like it's been running, not booting.
- **Texture.** Keep it raw: monospace, hard edges, no gradients, no bounce.
  "Lo-fi" is the restraint. Optional: a *very* faint paper grain, nothing more.
- **Screenshots** animate per §5, above the stack, without pushing the log.

---

## 8. Asset production notes

- Capture the §5 pages as **real screenshots**, bundled as image assets, each
  cropped to a consistent iframe frame (target ~300×380 pt @3x). Prefer stable,
  benign public pages; store a manifest mapping `assetName → journey step` so the
  screenshot cue in §6 resolves to the right image.
- Keep a small set (10–15) — they recur across dig days, which is fine; the log
  copy varies around them.
- If we ever want them "live," they could later be real thumbnails, but v1 is
  hardcoded captures — same spirit as the faked timeline.

---

## 9. Open questions

1. Worm shown or hidden during `.waiting`? (Rec: hidden — see layering note.)
2. Is `digStartedAt` the delivery-confirm moment, or the first `.waiting` entry
   each cycle? (Rec: reset each daily cycle so the log restarts fresh each day.)
3. Do we persist the seed so the same day's log is identical across reopens?
   (Rec: yes — `seed = hash(digStartedAt)`, recomputed per cycle.)
4. Tapping a screenshot / log — inert for now, or a peek? (Rec: inert v1.)
