#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$ROOT/Worm/Assets.xcassets"
VIEWPORT="1440,1100"
WAIT=2500

captures=(
  "discogs-arcs|https://www.discogs.com/master/878441"
  "genius-maskoff|https://genius.com/Future-mask-off-lyrics"
  "wiki-nahwc|https://en.wikipedia.org/wiki/Not_All_Heroes_Wear_Capes"
  "wiki-armagideon|https://en.wikipedia.org/wiki/Armagideon_Time"
  "discogs-realrock|https://www.discogs.com/search/?q=sound+dimension+real+rock&type=all"
  "whosampled-realrock|https://www.whosampled.com/sample/17272/"
  "discogs-aphex|https://www.discogs.com/artist/45-Aphex-Twin"
  "archive-user18081971|https://archive.org/details/aphex_twin_user18081971_soundcloud"
  "wiki-humbleandkind|https://en.wikipedia.org/wiki/Humble_and_Kind"
  "wiki-birdrifle|https://en.wikipedia.org/wiki/The_Bird_%26_the_Rifle"
  "whosampled-hungup|https://www.whosampled.com/sample/2521/"
  "wiki-rebajada|https://en.wikipedia.org/wiki/Rebajada"
  "yt-duenez|https://www.youtube.com/watch?v=NWj8HQAgo6g"
  "bandcamp-convulse|https://convulserecords.bandcamp.com/"
  "bandcamp-shocktherapy|https://convulserecords.bandcamp.com/album/shock-therapy"
  "wiki-otiswhisky|https://en.wikipedia.org/wiki/In_Person_at_the_Whisky_a_Go_Go"
  "discogs-otiswhisky|https://www.discogs.com/search/?q=otis+redding+whisky&type=all"
  "rym-sault|https://rateyourmusic.com/artist/sault"
  "pitchfork-sault|https://pitchfork.com/news/sault-release-surprise-album-acts-of-faith-as-free-download/"
  "wiki-goldberg1981|https://en.wikipedia.org/wiki/Bach:_The_Goldberg_Variations_(1981_album)"
  "discogs-bargain|https://www.discogs.com/sell/list?genre=Funk+%2F+Soul&sort=price%2Casc"
  "bandcamp-numeroprix|https://numerogroup.com/products/eccentric-soul-the-prix-label"
  "credits-elcamino|https://www.allmusic.com/album/el-camino-mw0002243314/credits"
  "wiki-realrock|https://en.wikipedia.org/wiki/Real_Rock"
  "bandcamp-demos|https://bandcamp.com/tag/hardcore?tab=all_releases"
  "discogs-goldberg1981|https://www.discogs.com/search/?q=glenn+gould+goldberg+variations+1981&type=all"
)

capture() {
  local entry="$1" key url target
  key="${entry%%|*}"
  url="${entry#*|}"
  target="$ASSETS/$key.imageset/$key.png"
  mkdir -p "${target%/*}"
  echo "Capturing $key"
  playwright screenshot --browser chromium --viewport-size="$VIEWPORT" --wait-for-timeout="$WAIT" --timeout=45000 --ignore-https-errors "$url" "$target"
}

export -f capture
export ASSETS VIEWPORT WAIT

printf '%s\n' "${captures[@]}" | xargs -P 4 -I {} bash -c 'capture "$@"' _ {}
