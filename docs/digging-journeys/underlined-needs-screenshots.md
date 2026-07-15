# Underlined things without a screenshot

Every **underlined artifact** in the dig log (`DiggingLog.journeys` +
`closingJourney` in `Worm/App/DiggingLogView.swift`). Tapping a log line pins its
page-frame open **only if that step has a `shot` key**. The artifacts below are
underlined but have **no `shot`**, so tapping them opens nothing.

Two kinds:

- **Pages** — a real webpage the worm "viewed." These *should* get a screenshot.
  Add the asset (named the suggested key) to `Assets.xcassets`, then tell me and
  I'll set the step's `shot:` + add the `DiggingLog.sites` chrome URL (or do it
  yourself — same pattern as the others).
- **Internal** — `output`-lane synthesis/ranking/saving. These are the worm
  *thinking*, not a page, so they have no website to screenshot. Left as-is they
  simply won't open a frame (expected). Only give them a shot if you want a
  synthetic "brain" card.

---

## Pages now wired — just need the real capture (4)

These four steps now carry their `shot:` key and a `DiggingLog.sites` chrome URL,
so tapping the underlined word **opens a frame today** (showing the lo-fi mock
page). Drop a real screenshot into `Assets.xcassets` named exactly the key and it
replaces the mock automatically — no code change.

| story | log line (underlined word) | key (asset name) | page to capture |
|---|---|---|---|
| S01 Producer's Other Door | READING — EL CAMINO **CREDIT** SHEET | `credits-elcamino` | AllMusic/Discogs credits for The Black Keys — *El Camino* (credits list showing Danger Mouse) |
| S03 387 Versions Deep | TRACING — RIDDIM: REAL ROCK, 1967 (**RIDDIM**) | `wiki-realrock` | Wikipedia — "Real Rock" (Sound Dimension, Studio One) |
| S08 Seven Inches of Therapy | CRAWLING — **DEMO** TAPES, NAME-YR-PRICE | `bandcamp-demos` | A Bandcamp label/tag page of hardcore demos (name-your-price grid) |
| S11 Two Lives, One Score | BROWSING — 1981 EARLY DIGITAL **PRESSING** | `discogs-goldberg1981` | Discogs release — Gould, *The Goldberg Variations* (1981, CBS digital) |

---

## Internal synthesis artifacts (no page — won't open a frame, expected) (14)

| story | log line (underlined word) |
|---|---|
| S01 | SYNTHESIZING — **VERDICT**: SAME VOICE, NEW DOOR |
| S02 | RANKING — **CREDIT** LINE > TRACKLIST |
| S03 | RANKING — ONE **RIDDIM**, PICK THREE |
| S04 | SAVING — **ALIAS** TREE COMPLETE |
| S05 | EXTRACTING — THE WRITER'S OWN **VERSION** |
| S06 | SAVING — SOURCE DNA, ONE **SAMPLE** |
| S07 | SAVING — REBAJADA **GENRE** NODE |
| S08 | SAVING — SPLIT + **DEMO** SHORTLIST |
| S09 | EXTRACTING — LIVE **VERSION** > STUDIO |
| S10 | SYNTHESIZING — **VERDICT**: FACELESS, FLAWLESS |
| S11 | RANKING — 1981 **VERSION** FOR TONIGHT |
| S12 | SAVING — A $1 REEL, PRICELESS **DEMO** |
| Closing | SYNTHESIZING — FOLDING TRAILS INTO **TASTE** |
| Closing | SAVING — PICKED 3 SONGS. **VERDICT** IN |

---

## Already backed by a screenshot (tap opens the frame today)

These artifact lines already have a `shot`, so they're tappable now:
S02 `GENIUS CREDITS: MASK OFF` (**CREDIT** → `genius-maskoff`),
S03 `387 VERSIONS ON RECORD` (**VERSION** → `whosampled-realrock`),
S04 `RDJ ALIAS LIST` (**ALIAS** → `discogs-aphex`),
S07 `REBAJADA: THE SLOW GENRE` (**GENRE** → `wiki-rebajada`),
S09 `1968 ATCO PRESSING` (**PRESSING** → `discogs-otiswhisky`).

Plus the non-artifact page lines (already have shots): `discogs-arcs`,
`wiki-nahwc`, `wiki-armagideon`, `archive-user18081971`, `wiki-humbleandkind`,
`wiki-birdrifle`, `whosampled-hungup`, `bandcamp-convulse`,
`bandcamp-shocktherapy`, `wiki-otiswhisky`, `rym-sault`, `pitchfork-sault`,
`wiki-goldberg1981`, `discogs-bargain`, `bandcamp-numeroprix`, `yt-duenez`.
