# Worm dig log — canonical mock-up stories (v1)

The **reusable** set of grounded "digging" stories that populate the waiting/log
screen (`Worm/App/DiggingLogView.swift`). Each follows a hero-journey pattern
(`hero-journeys.md`) using **real, verifiable** artists, records, credits, and
pages — so the screenshots we source are genuine artifacts of a real dig, not
filler. Authored with Fable; facts verified at write time. **Save and reuse.**

Schema: `offset` = seconds from burst start · descriptions uppercase, ≤~30 chars ·
`artifact` = the bold+underlined word (appears verbatim in the description) ·
`screenshotKey` maps to the asset list at the bottom.

Lanes (status-square color) = source: library · forums · reference · video ·
records · output · fault. Verb colors = activity family (indigo discovery /
orange reading / green media / maroon extract / magenta synthesis / grey fault).
In code, extract/media steps land on the `.output` / `.video` lanes respectively.

---

## The 12 stories

### S01 — The Producer's Other Door (Closed Door Artist)
Black Keys *El Camino* → Danger Mouse credit → Dan Auerbach's The Arcs → *Yours, Dreamily,* (2015).

| offset | lane | verb | description | artifact | shot |
|---|---|---|---|---|---|
| 0 | library | PROCESS | EL CAMINO: 41 PLAYS LOGGED | | |
| 5 | reference | READING | EL CAMINO CREDIT SHEET | CREDIT | |
| 19 | reference | FINDING | PRODUCER: DANGER MOUSE | | |
| 42 | reference | TRACING | AUERBACH SIDE PROJECTS | | |
| 74 | records | BROWSING | THE ARCS, DISCOGS | | discogs-arcs |
| 262 | video | LISTENING | OUTTA MY MIND (2015) | | |
| 430 | output | SAVING | YOURS, DREAMILY, FULL LP | | |
| 447 | output | SYNTHESIZING | VERDICT: SAME VOICE, NEW DOOR | VERDICT | |

### S02 — If Young Metro Don't Trust You (Producer Chain)
Future "Mask Off" → Metro Boomin credit → *Not All Heroes Wear Capes* (2018) / *Heroes & Villains* (2022).

| offset | lane | verb | description | artifact | shot |
|---|---|---|---|---|---|
| 0 | library | PROCESS | MASK OFF x30 THIS MONTH | | |
| 6 | reference | READING | GENIUS CREDITS: MASK OFF | CREDIT | genius-maskoff |
| 24 | reference | TRACING | METRO BOOMIN SOLO RUN | | |
| 51 | records | BROWSING | NOT ALL HEROES WEAR CAPES | | wiki-nahwc |
| 205 | video | LISTENING | 10 FREAKY GIRLS, 21 SAVAGE | | |
| 344 | video | LISTENING | SUPERHERO FT. FUTURE | | |
| 401 | output | EXTRACTING | PRODUCER CHAIN, 3 NODES | | |
| 415 | output | RANKING | CREDIT LINE > TRACKLIST | CREDIT | |

### S03 — 387 Versions Deep (Version Chain)
Clash "Armagideon Time" → Willie Williams 1979 → Sound Dimension "Real Rock" (Studio One, 1967).

| offset | lane | verb | description | artifact | shot |
|---|---|---|---|---|---|
| 0 | library | PROCESS | CLASH B-SIDES ON REPEAT | | |
| 7 | reference | READING | ARMAGIDEON TIME, ORIGINS | | wiki-armagideon |
| 26 | reference | TRACING | RIDDIM: REAL ROCK, 1967 | RIDDIM | |
| 63 | records | BROWSING | SOUND DIMENSION 7-INCH | | discogs-realrock |
| 231 | video | LISTENING | WILLIE WILLIAMS, 1979 CUT | | |
| 305 | records | COMPARING | 387 VERSIONS ON RECORD | VERSION | whosampled-realrock |
| 349 | output | SAVING | REAL ROCK FAMILY TREE | | |
| 361 | output | RANKING | ONE RIDDIM, PICK THREE | RIDDIM | |

### S04 — The Man With 20 Names (Alias & Side Door)
Aphex Twin *SAW 85–92* → Polygon Window (Warp 1993), The Tuss (Rephlex 2007), the 2015 user18081971 dump (mirrored on Internet Archive).

| offset | lane | verb | description | artifact | shot |
|---|---|---|---|---|---|
| 0 | library | PROCESS | SAW 85-92, EVERY NIGHT | | |
| 8 | reference | READING | RDJ ALIAS LIST, 20+ NAMES | ALIAS | discogs-aphex |
| 33 | records | BROWSING | POLYGON WINDOW, WARP 1993 | | |
| 158 | video | LISTENING | QUOTH, SINE WAVES LP | | |
| 262 | forums | READING | RDJ INTERVIEW, MOSTLY LIES | | |
| 291 | records | BROWSING | THE TUSS: RUSHUP EDGE | | |
| 337 | records | CRAWLING | USER18081971, 230 TRACKS | | archive-user18081971 |
| 420 | output | SAVING | ALIAS TREE COMPLETE | ALIAS | |
| 438 | output | SYNTHESIZING | SAME HANDS, NEW NAMES | | |

*(The joke line: S04 "RDJ INTERVIEW, MOSTLY LIES" — in-voice and factually defensible.)*

### S05 — Who Wrote That (Songwriter's Shadow)
Tim McGraw "Humble and Kind" → sole writer Lori McKenna → *The Bird & the Rifle* (2016).

| offset | lane | verb | description | artifact | shot |
|---|---|---|---|---|---|
| 0 | library | PROCESS | HUMBLE AND KIND, 14 PLAYS | | |
| 5 | reference | READING | SOLE WRITER: LORI McKENNA | | wiki-humbleandkind |
| 23 | reference | TRACING | ALSO WROTE: GIRL CRUSH | | |
| 58 | records | BROWSING | THE BIRD & THE RIFLE, 2016 | | wiki-birdrifle |
| 214 | video | LISTENING | WRECK YOU, TRACK ONE | | |
| 388 | video | LISTENING | HER OWN HUMBLE AND KIND | | |
| 421 | output | EXTRACTING | THE WRITER'S OWN VERSION | VERSION | |
| 436 | output | SYNTHESIZING | SHADOW STEPS FORWARD | | |

### S06 — Where the Riff Came From (Source DNA)
Madonna "Hung Up" → WhoSampled → ABBA "Gimme! Gimme! Gimme!" (1979).

| offset | lane | verb | description | artifact | shot |
|---|---|---|---|---|---|
| 0 | library | PROCESS | HUNG UP, TOP TRACK 2 YRS | | |
| 4 | records | TRACING | WHOSAMPLED: HUNG UP | | whosampled-hungup |
| 21 | reference | READING | GIMME! GIMME! GIMME! 1979 | | |
| 47 | video | LISTENING | ABBA SYNTH LINE AT 0:12 | | |
| 176 | records | CRAWLING | WHO ELSE PULLED THIS RIFF | | |
| 243 | output | SAVING | SOURCE DNA, ONE SAMPLE | SAMPLE | |
| 259 | output | RANKING | THE ORIGINAL STILL WINS | | |

### S07 — Slower Hits Harder (Diaspora Thread)
Cumbia → rebajada: Colombian cumbia slowed in Monterrey → Sonido Dueñez's dragged-tempo cassettes.

| offset | lane | verb | description | artifact | shot |
|---|---|---|---|---|---|
| 0 | library | PROCESS | CUMBIA CREEPING INTO MIX | | |
| 9 | reference | READING | REBAJADA: THE SLOW GENRE | GENRE | wiki-rebajada |
| 44 | reference | TRACING | COLOMBIA TO MONTERREY | | |
| 96 | forums | FINDING | SONIDO DUEÑEZ, NAMED TWICE | | |
| 138 | video | WATCHING | DUEÑEZ CASSETTE MIX | | yt-duenez |
| 402 | output | EXTRACTING | 45s DRAGGED DOWN TO 33 | | |
| 425 | output | SAVING | REBAJADA GENRE NODE | GENRE | |
| 441 | output | SYNTHESIZING | SLOWER HITS HARDER | | |

### S08 — Seven Inches of Therapy (Split & Demo)
Hardcore → Convulse Records Bandcamp → Gel / Cold Brats "Shock Therapy" split (Aug 2022) + demo underground.

| offset | lane | verb | description | artifact | shot |
|---|---|---|---|---|---|
| 0 | library | PROCESS | HARDCORE SPIKE, 2AM PLAYS | | |
| 6 | records | BROWSING | CONVULSE RECORDS BANDCAMP | | bandcamp-convulse |
| 38 | records | FINDING | GEL / COLD BRATS SPLIT | | bandcamp-shocktherapy |
| 121 | video | LISTENING | SHOCK THERAPY, GEL SIDE | | |
| 254 | records | CRAWLING | DEMO TAPES, NAME-YR-PRICE | DEMO | |
| 291 | forums | READING | R/HARDCORE DEMO ROUNDUP | | |
| 333 | output | SAVING | SPLIT + DEMO SHORTLIST | DEMO | |
| 351 | output | RANKING | DIY BEATS POLISH | | |

### S09 — The Whisky, April '66 (Live Room)
Otis Redding studio cuts → *In Person at the Whisky a Go Go* (rec. Apr 1966, rel. 1968 Atco).

| offset | lane | verb | description | artifact | shot |
|---|---|---|---|---|---|
| 0 | library | PROCESS | OTIS: STUDIO CUTS ONLY | | |
| 8 | reference | READING | WHISKY A GO GO, APR 1966 | | wiki-otiswhisky |
| 32 | records | BROWSING | 1968 ATCO PRESSING | PRESSING | discogs-otiswhisky |
| 187 | video | LISTENING | MR. PITIFUL, LIVE TAKE | | |
| 414 | video | LISTENING | CROWD LOUD ON RESPECT | | |
| 452 | output | EXTRACTING | LIVE VERSION > STUDIO | VERSION | |
| 468 | output | SYNTHESIZING | THE ROOM IS THE POINT | | |

### S10 — Password: godislove (Anonymous Drop)
SAULT's five simultaneous albums, password-locked free download, five days, Nov 2022.

| offset | lane | verb | description | artifact | shot |
|---|---|---|---|---|---|
| 0 | forums | FINDING | SAULT DROP THREAD, RYM | | rym-sault |
| 16 | reference | READING | 5 ALBUMS, 5 DAYS, LOCKED | | pitchfork-sault |
| 42 | reference | FINDING | PASSWORD WAS GODISLOVE | | |
| 71 | records | BROWSING | FOREVER LIVING ORIGINALS | | |
| 204 | video | LISTENING | UNTITLED (GOD), DISC 5 | | |
| 396 | output | SAVING | NO-NAME DISCOGRAPHY MAP | | |
| 417 | output | SYNTHESIZING | VERDICT: FACELESS, FLAWLESS | VERDICT | |

### S11 — Two Lives, One Score (Interpretation Chain)
Glenn Gould's Goldberg Variations: 1955 (aria 1:53) vs 1981 (aria 3:05).

| offset | lane | verb | description | artifact | shot |
|---|---|---|---|---|---|
| 0 | library | PROCESS | GOLDBERGS: WHICH GOULD? | | |
| 11 | reference | READING | 1955 VS 1981, THE DEBATE | | wiki-goldberg1981 |
| 46 | video | LISTENING | ARIA, 1955: RUNS 1:53 | | |
| 173 | video | LISTENING | ARIA, 1981: RUNS 3:05 | | |
| 301 | forums | COMPARING | R/CLASSICALMUSIC TAKES | | |
| 342 | records | BROWSING | 1981 EARLY DIGITAL PRESSING | PRESSING | |
| 384 | output | EXTRACTING | TWO LIVES, ONE SCORE | | |
| 405 | output | RANKING | 1981 VERSION FOR TONIGHT | VERSION | |

### S12 — The Dollar Reel (Cheap-Risk Bin)
Bargain crawl → Prix Records (Columbus OH) → Penny & the Quarters "You and Me" (Numero *Eccentric Soul: The Prix Label*).

| offset | lane | verb | description | artifact | shot |
|---|---|---|---|---|---|
| 0 | forums | FINDING | DOLLAR-BIN THREAD, R/VINYL | | |
| 27 | records | CRAWLING | DISCOGS UNDER $5, SOUL | | discogs-bargain |
| 94 | records | FINDING | PRIX RECORDS, COLUMBUS OH | | |
| 133 | reference | READING | PENNY & THE QUARTERS STORY | | |
| 297 | video | LISTENING | YOU AND ME, ONE TAKE | | |
| 341 | records | BROWSING | ECCENTRIC SOUL: PRIX | | bandcamp-numeroprix |
| 383 | output | SAVING | A $1 REEL, PRICELESS DEMO | DEMO | |
| 401 | output | RANKING | CHEAP RISK PAID OFF | | |

### Closing burst (appended to every dig, ~2 min before delivery)
| offset | lane | verb | description | artifact | shot |
|---|---|---|---|---|---|
| 0 | output | SYNTHESIZING | FOLDING TRAILS INTO TASTE | TASTE | |
| 34 | output | RANKING | 40 CANDIDATES DOWN TO 9 | | |
| 79 | output | SKIPPING | 6 TOO CLOSE TO KNOWN PLAYS | | |
| 112 | output | SAVING | PICKED 3 SONGS. VERDICT IN | VERDICT | |

---

## Screenshot asset list (real pages — capture portrait)

Name each asset in `Assets.xcassets` **exactly** the key; `DiggingLog.sites` maps
the key to the fake chrome URL. Reuse across stories where a page fits.

| key | lane | page to capture | URL |
|---|---|---|---|
| discogs-arcs | records | Discogs master: The Arcs – *Yours, Dreamily,* | discogs.com/master/878441 |
| genius-maskoff | reference | Genius: Future "Mask Off", credits block (Metro Boomin) | genius.com/Future-mask-off-lyrics |
| wiki-nahwc | reference | Wikipedia: *Not All Heroes Wear Capes* (infobox) | en.wikipedia.org/wiki/Not_All_Heroes_Wear_Capes |
| wiki-armagideon | reference | Wikipedia: "Armagideon Time" | en.wikipedia.org/wiki/Armagideon_Time |
| discogs-realrock | records | Discogs: Sound Dimension "Real Rock" (Studio One 7") | discogs.com/search?q=sound+dimension+real+rock |
| whosampled-realrock | records | WhoSampled: Williams "Armagideon Time" ← "Real Rock" | whosampled.com/sample/17272/ |
| discogs-aphex | records | Discogs artist: Aphex Twin, Aliases list | discogs.com/artist/45-Aphex-Twin |
| archive-user18081971 | records | Internet Archive: aphex user18081971 (001–230) | archive.org/details/aphex_twin_user18081971_soundcloud |
| wiki-humbleandkind | reference | Wikipedia: "Humble and Kind" (writer: Lori McKenna) | en.wikipedia.org/wiki/Humble_and_Kind |
| wiki-birdrifle | reference | Wikipedia: *The Bird & the Rifle* | en.wikipedia.org/wiki/The_Bird_%26_the_Rifle |
| whosampled-hungup | records | WhoSampled: Madonna "Hung Up" ← ABBA | whosampled.com/sample/2521/ |
| wiki-rebajada | reference | Wikipedia: "Rebajada" | en.wikipedia.org/wiki/Rebajada |
| yt-duenez | video | YouTube: Sonido Dueñez rebajada cassette mix (watch page) | youtube.com/watch |
| bandcamp-convulse | records | Convulse Records Bandcamp label front | convulserecords.bandcamp.com |
| bandcamp-shocktherapy | records | Bandcamp: Gel / Cold Brats *Shock Therapy* | convulserecords.bandcamp.com/album/shock-therapy |
| wiki-otiswhisky | reference | Wikipedia: *In Person at the Whisky a Go Go* | en.wikipedia.org/wiki/In_Person_at_the_Whisky_a_Go_Go |
| discogs-otiswhisky | records | Discogs master: Otis Redding – Whisky (1968 Atco) | discogs.com/search?q=otis+redding+whisky |
| rym-sault | forums | RateYourMusic artist: SAULT (discography grid) | rateyourmusic.com/artist/sault |
| pitchfork-sault | forums | Pitchfork news: SAULT release 5 new albums (Nov 2022) | pitchfork.com/news/sault-…/ |
| wiki-goldberg1981 | reference | Wikipedia: *Bach: The Goldberg Variations (1981)* | en.wikipedia.org/wiki/Bach:_The_Goldberg_Variations_(1981_album) |
| discogs-bargain | records | Discogs marketplace: Funk/Soul, price ascending | discogs.com/sell/list?genre=Funk+%2F+Soul&sort=price%2Casc |
| bandcamp-numeroprix | records | Numero Group Bandcamp: *Eccentric Soul: The Prix Label* | numerogroup.bandcamp.com/album/eccentric-soul-the-prix-label |

**Optional trims** (to land at ~17 captures): `wiki-nahwc`, `whosampled-realrock`,
`bandcamp-shocktherapy`, `discogs-otiswhisky` are second-shots you can skip.

Until real captures are dropped in, the iframe shows a lo-fi mock page (chrome +
title + skeleton) using the URL/title from `DiggingLog.sites`.
