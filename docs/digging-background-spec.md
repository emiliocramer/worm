# Digging background — living animation spec (ALTERNATIVE / UNIMPLEMENTED)

**Status:** alternative concept, **not** the current direction, **not** built.
Kept on purpose so we can try it later. The live direction is the lo-fi terminal
log in [`digging-log-spec.md`](digging-log-spec.md); this square-cluster concept is
the earlier idea (authored by Fable) parked as a possible alternative aesthetic.

## Where it goes

The **waiting screen** — the home "base state" while the worm is off digging,
shown after the user sets a delivery time. Top overlay reads `i'll be back in
Hh:Mm`. This animation is the **living background** behind the worm mascot and
that countdown copy.

Flow context (already wired in `WormHomeView`, `deliveryFlow` state machine):
`picker → notify → done → waiting`. The time-of-day sky (`DeliveryTimeBackdrop`)
shows only through `.picker/.notify/.done` and **crossfades out into plain paper**
as we enter `.waiting` (`showDeliveryBackdrop == isDeliveryInterstitial`). The
waiting screen is currently just paper + worm + countdown; this spec fills the
paper with the living digging animation.

Intended wiring when implemented: render inside the home `ZStack` gated on
`isWaiting`, at `zIndex(2)` (behind the worm at `zIndex 4` and the top-overlay
copy). Suggested call: `DiggingBackground(wormCenterUnit: CGPoint(x: 0.5, y: 0.78))`
with `.transition(.opacity)`.

Also pending: a hardcoded pool of the 50 thread labels below (see §7).

---

# Worm "Digging the Internet" — Living Background Motion Spec

Reference canvas: 393 × 852 pt (iPhone portrait). All numbers scale proportionally on other sizes; grid pitch stays fixed at 30 pt.

---

## 0. Core primitives

- **Grid**: invisible 30 pt square grid covering the whole screen, origin at top-left, offset by (16, 8) so cells never kiss the screen edge. All squares snap to this grid.
- **Square**: 30 × 30 pt, corner radius 4 pt, stroke black `#141414` at 1.5 pt (stroke drawn *inside* so adjacent squares share a crisp 1.5 pt double-line seam — this is the look; do not overlap or merge strokes).
- **Label**: monospaced (`.system(size: 12, weight: .regular, design: .monospaced)`), color `#141414`, max 2 lines, line spacing 2 pt.

---

## 1. Cluster growth algorithm

**Target size**: random int in **5…9 squares** (uniform).

**Accretion (Eden-growth with tail):**
1. Place seed square at the thread's anchor cell.
2. **Body phase** (squares 2 … N−T): each new square picks a random *occupied* cell weighted by `1 / (1 + distanceFromSeed)` (keeps it blobby, not stringy), then occupies one of its free 4-neighbors, chosen with weights: toward-seed-side neighbors ×2, others ×1. If the chosen cell would give the new square 3+ occupied neighbors, accept immediately (rewards compactness). Reject-and-retry up to 6 times, then take any free neighbor.
3. **Tail phase** (last **T** squares, where T = 0, 2, or 3 with probability 0.4 / 0.4 / 0.2): pick a random cardinal direction once; each tail square extends strictly in that direction from the previous square, allowing one single 90° kink at probability 0.3. This produces the "trailing tail of singles" from the mockups.
4. Never grow into another cluster's footprint + 1-cell margin (see §4).

**Spawn cadence**: one square every **0.28 s** (add ±0.05 s jitter per square so it feels hand-placed, not metronomic).

**Per-square pop-in**:
- Scale: **0.4 → 1.0**, spring: `response 0.32, dampingFraction 0.68` (one small overshoot to ~1.06, settles).
- Opacity: **0 → 1** over **0.12 s**, linear, simultaneous with scale start.
- Anchor: square's own center.
- Fill and stroke fade in together (don't stroke-then-fill).

---

## 2. Thread lifecycle timeline

Total lifetime: **9.5–12.5 s** depending on square count/word count.

| Phase | Start | Duration | Notes |
|---|---|---|---|
| Spawn (seed pop) | 0.0 s | 0.32 s | seed square pops in |
| Grow | 0.28 s | (N−1) × 0.28 s ≈ 1.1–2.3 s | squares accrete |
| Type label | begins at **0.9 s** (overlaps growth) | words × 0.35 s ≈ 0.7–1.75 s | see §3 |
| Hold (alive) | growth+typing done | **5.5 s** | breathing + shimmer (§6) run here |
| Finish pulse | last 0.5 s of hold | 0.5 s | magical touch (§6) |
| Fade out | after hold | **0.8 s** | whole thread (squares + label) opacity → 0, easeIn; squares also scale 1.0 → 0.92; despawn order: tail-first, one square per 0.06 s, label fades last |
| Despawn | — | — | remove from scene, free grid cells |

**Concurrency & stagger**: max **3** live threads, target average 2.5. Spawn a new thread every **4.0 s ± 0.8 s jitter**, but only if live count < 3; if a thread just despawned and live count is 1, spawn the next one after only **1.2 s** (never let the screen drop to a lone dying thread for long). Never zero threads: the very first frame spawns 2 threads staggered 1.5 s apart.

**Label pool**: draw from the 50-item pool (§7) via a shuffled bag — reshuffle when empty, and never repeat any of the last 8 used.

---

## 3. Label typing

- **Cadence**: one word appears every **0.35 s**, starting 0.9 s after thread spawn (so the cluster already has 3–4 squares — the label feels like a *report on* the digging, not a caption).
- **Per-word animation**: opacity 0 → 1 over 0.1 s + rise of 3 pt (offset y: 3 → 0), easeOut. No scale. Words appear typewriter-hard, not floaty.
- **Cursor**: a `▌` block cursor sits after the last typed word, blinking at 0.5 s on / 0.5 s off; cursor disappears 0.7 s after the final word.
- **Line handling**: labels are pre-split in the pool as 1 or 2 explicit lines (action line / subject line). Line 2 starts typing only after line 1 completes. Never soft-wrap.
- **Position**: left-aligned, anchored to the cluster bounding box:
  - Default: **8 pt below** the cluster's bottom edge, x aligned to the seed square's leading edge.
  - If the cluster bottom is within 60 pt of the screen bottom or of a safe region (§4), flip to **8 pt above** the cluster top instead.
- **Vertical anchor**: top of the label block is fixed; growing to line 2 extends downward (or upward when flipped) — the cluster never shifts to accommodate text.

---

## 4. Placement & safe regions

**Safe regions (no square, no label may intersect):**
- **Top band**: y 0 → 150 pt full-width (status bar + "i'll be back in Hh:Mm" copy).
- **Worm zone**: centered horizontal band x 96 → 297 pt (center ±100 pt), y 470 → 852 pt (lower-center mascot).
- **Edge margin**: 12 pt on left/right, 24 pt on bottom.

**Usable field** is therefore: mid-band full width (y 150–470), plus two lower side columns (x 12–96 and x 297–381, y 470–828).

**Slot system** (simple, collision-free): divide the usable field into **6 loose slots**:
1. upper-left (x 12–190, y 150–310)
2. upper-right (x 200–381, y 150–310)
3. mid-left (x 12–190, y 315–470)
4. mid-right (x 200–381, y 315–470)
5. lower-left column (x 12–96, y 470–828) — *tail-heavy vertical clusters only, max 6 squares*
6. lower-right column (x 297–381, y 470–828) — same constraint

**Rules**: a new thread picks a random slot that is (a) unoccupied and (b) not the slot just vacated by the most recent despawn (forces the eye to travel). Anchor cell = random grid cell inside the slot with ≥ 3 cells of growth room toward slot center; growth is clipped to slot + safe-region boundaries (a blocked direction just re-rolls per §1). Maintain a **1 grid-cell (30 pt) minimum gap** between clusters — automatic with slots, but enforce it as a hard check anyway. Reserve label space (2 lines ≈ 34 pt) inside the slot when choosing the anchor.

---

## 5. Palette

13 fills on cream background `#F7F5ED` (RGB 0.97, 0.96, 0.93):

| Name | Hex |
|---|---|
| lilac | `#C9ABE2` |
| mint | `#BEE3C6` |
| rust | `#B0583A` |
| dark maroon | `#5C2B30` |
| tan | `#D9B98C` |
| purple | `#7C4FA8` |
| red | `#D9442F` |
| salmon | `#F2A38E` |
| mint-green | `#8FD0A6` |
| gold | `#E2B33C` |
| warm grey | `#B8AEA1` |
| cream | `#F0E7D3` |
| magenta | `#C44E8C` |

**Selection per square**: shuffled bag per cluster (draw without replacement, refill when empty) **plus** an adjacency check — a new square rejects a color matching any of its 4-neighbors (re-draw, max 3 tries, then accept). Bias: each cluster picks one "accent" (gold, red, or magenta) allowed at most twice per cluster, so the loud colors stay special. Cream squares always read via their stroke — keep them; they're the breathing room.

---

## 6. Aliveness layer

- **Layer opacity**: whole background layer at **0.92**; additionally apply a soft radial fade (opacity → 0.55) in a 140 pt radius around the worm mascot's center so the mascot always pops. No blur — keep strokes crisp.
- **Breathing**: each *cluster* (as a group, anchored at its centroid) scales 1.000 → 1.012 → 1.000 on a 3.4 s sine loop, phase-offset randomly per cluster. Barely perceptible; that's the point.
- **Drift**: none. Grid-snapped stillness between pops is part of the typewriter character. Motion comes from accretion, typing, and breathing only.
- **Easing philosophy**: arrivals are springy (things *land*), departures are eased (things *dissolve*). Nothing linear except opacity ramps under 0.15 s.

**Three magical touches (use all three, nothing more):**
1. **Shimmer scan**: during hold, once per thread, a brightness pulse (+12% lightness, 0.25 s each) sweeps square-by-square through the cluster in accretion order — the worm "re-reading" its find. Trigger at hold-start + 1.5 s.
2. **Finish pulse**: 0.5 s before fade-out, the seed square pulses scale 1.0 → 1.12 → 1.0 (spring, response 0.25) and emits one expanding 1.5 pt-stroke rounded-square outline that grows from 30 pt to 54 pt while fading 0.6 → 0 over 0.5 s. Reads as "got it."
3. **Listening threads glow**: any label starting "Listening to:" gets a 0.5 s on / 0.5 s off gentle opacity pulse (1.0 ↔ 0.85) on its *cluster* during hold — the cluster quietly keeps the beat.

---

## 7. Thread label pool (50)

Format: `line1 / line2` (single-line entries have no `/`).

1. Digging / Reddit
2. Browsing / r/vinylheads
3. Browsing / r/indieheads
4. Finding / Producer Credits
5. Reading / Liner Notes
6. Crawling / Discogs Pressings
7. Combing / Bandcamp Tags
8. Tracing / A Sample Source
9. Reading / Setlist.fm
10. Scanning / Label Rosters
11. Following / A YouTube Rabbit Hole
12. Reading / Pitchfork Archives
13. Digging / Crate By Crate
14. Checking / Who Mixed This
15. Tracing / Session Musicians
16. Reading / Genius Annotations
17. Browsing / Boomkat Reviews
18. Combing / SoundCloud Reposts
19. Finding / The Original Press
20. Reading / Tour Riders
21. Scanning / Radio Playlists
22. Tracing / A Cover's Origin
23. Browsing / r/popheads
24. Digging / B-Sides
25. Finding / The Demo Version
26. Reading / Fan Forums
27. Crawling / Last.fm Neighbors
28. Checking / Festival Undercards
29. Tracing / Who Played Bass
30. Reading / RateYourMusic Lists
31. Combing / Mixtape Tracklists
32. Finding / Unreleased Sessions
33. Browsing / NTS Radio Archives
34. Digging / 2004 Music Blogs
35. Reading / Album Thank-Yous
36. Tracing / The Drum Break
37. Scanning / DJ Set IDs
38. Finding / The Japanese Bonus Track
39. Browsing / KEXP Live Sessions
40. Checking / Remix Credits
41. Listening to: / Xtal - Aphex Twin
42. Listening to: / Pink + White - Frank Ocean
43. Listening to: / Marquee Moon - Television
44. Listening to: / Kokomo, IN - Japanese Breakfast
45. Listening to: / Déjà Vu - Roosevelt
46. Listening to: / Sirens - Nicolas Jaar
47. Listening to: / Only Shallow - My Bloody Valentine
48. Listening to: / Tezeta - Mulatu Astatke
49. Listening to: / Two Weeks - Grizzly Bear
50. Listening to: / Chop Suey Remaster? No.

(Item 50 is the one joke; keep exactly one joke in the pool.)

---

## 8. Implementation notes (non-code)

- One master clock (TimelineView) drives everything; each thread stores its spawn timestamp and derives its phase from elapsed time — makes the whole system deterministic per thread and cheap in Canvas.
- Springs on square pop-in are the only per-view animations worth doing with real SwiftUI springs; if fully in Canvas, approximate the spring as: scale = `1 + 0.06·e^(−6t)·cos(14t)` for t in 0–0.4 s.
- Everything (colors, growth path, slot, jitter) should derive from a per-thread seeded RNG so a thread's whole life is computed once at spawn — the timeline just plays it back.
