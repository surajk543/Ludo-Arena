#!/usr/bin/env bash
# Imports the app's sound effects from Kenney's CC0 audio packs into
# assets/audio/sfx/ as 16-bit PCM mono WAV (iOS cannot decode Ogg Vorbis).
#
# Usage (from frontend/):
#   tool/import_kenney_audio.sh <kenney-dir> [--music <upbeat-loop.mp3>]
#
# <kenney-dir> holds the unzipped packs, one folder per pack, named after the
# download zip (the pack content may sit directly in it or in `extracted/`):
#   kenney_interface-sounds/ https://kenney.nl/assets/interface-sounds
#   kenney_casino-audio/     https://kenney.nl/assets/casino-audio
#   kenney_impact-sounds/    https://kenney.nl/assets/impact-sounds
#   kenney_music-jingles/    https://kenney.nl/assets/music-jingles
# All four packs are CC0 1.0 (see assets/audio/ASSET_LICENSES.md).
#
# Processing per file (ffmpeg, deterministic):
#   1. optional segment cut (`seg=start-end`, seconds) and low-pass (`lp=Hz`,
#      tames bright metallic clinks);
#   2. downmix to mono, resample (44.1 kHz; 22.05 kHz for jingles);
#   3. leading silence below -50 dBFS removed (latency), 2 ms fade-in;
#   4. optional max length (`max=seconds`) with a 30 ms fade-out; trailing
#      silence below -60 dBFS removed and a 12 ms fade-out on the cut;
#   5. loudness: gain so the loudest 50 ms window reaches the category
#      target (ui -22 dBFS RMS, game -19, jingle -18) without the sample peak
#      exceeding the ceiling (ui -3 dBFS, game/jingle -1.5 dBFS);
#   6. 16-bit PCM WAV with a canonical 44-byte header (no metadata).
# Per-sound playback gains are tuned in code (`Sfx` in
# lib/core/audio_haptics/sfx.dart), not here.
#
# --music: (re)creates assets/audio/music/lobby_loop.m4a from the original
# Freesound download (sound 512340 "Upbeat loop" by mistermender, CC0; the
# mp3 is not in the repo). This is the exact command used for the shipped file.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  sed -n '2,32p' "$0"
  exit 64
fi

KENNEY="$1"
shift
MUSIC_SRC=""
if [[ "${1:-}" == "--music" ]]; then
  MUSIC_SRC="${2:?--music needs the mp3 path}"
fi

OUT="assets/audio/sfx"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

pack_dir() {
  local p="$KENNEY/$1"
  [[ -d "$p/extracted" ]] && p="$p/extracted"
  echo "$p"
}

# target | pack | file inside the pack's Audio/ folder | category | options
read -r -d '' TABLE <<'EOF' || true
ui_tap           | kenney_interface-sounds | select_002.ogg                       | ui     |
ui_tab           | kenney_interface-sounds | select_001.ogg                       | ui     |
ui_toggle        | kenney_interface-sounds | toggle_002.ogg                       | ui     |
ui_open          | kenney_interface-sounds | maximize_009.ogg                     | ui     |
ui_close         | kenney_interface-sounds | minimize_009.ogg                     | ui     |
ui_confirm       | kenney_interface-sounds | confirmation_003.ogg                 | ui     |
ui_error         | kenney_interface-sounds | error_004.ogg                        | ui     |
ui_tick          | kenney_interface-sounds | tick_004.ogg                         | ui     |
lobby_play       | kenney_interface-sounds | maximize_006.ogg                     | ui     |
notification     | kenney_interface-sounds | glass_001.ogg                        | ui     |
chat_pop         | kenney_interface-sounds | drop_003.ogg                         | ui     |
dice_roll        | kenney_casino-audio     | die-throw-1.ogg                      | game   |
dice_land        | kenney_casino-audio     | die-throw-4.ogg                      | game   | seg=0.10-0.30
token_select     | kenney_interface-sounds | pluck_002.ogg                        | game   | lp=9000
token_step       | kenney_impact-sounds    | impactWood_light_002.ogg             | game   | max=0.16
token_leave_base | kenney_interface-sounds | maximize_007.ogg                     | game   |
token_safe       | kenney_interface-sounds | glass_003.ogg                        | game   |
token_home_path  | kenney_interface-sounds | select_004.ogg                       | game   |
token_capture    | kenney_impact-sounds    | impactPunch_medium_002.ogg           | game   | max=0.35
token_captured   | kenney_interface-sounds | minimize_006.ogg                     | game   |
turn_mine        | kenney_interface-sounds | confirmation_001.ogg                 | game   |
coin             | kenney_casino-audio     | chips-stack-3.ogg                    | game   | lp=9000
purchase         | kenney_casino-audio     | chips-handle-6.ogg                   | game   | lp=9000
match_start      | kenney_music-jingles    | Pizzicato jingles/jingles_PIZZI16.ogg | jingle |
token_home       | kenney_music-jingles    | Pizzicato jingles/jingles_PIZZI08.ogg | jingle |
win              | kenney_music-jingles    | Steel jingles/jingles_STEEL10.ogg     | jingle |
lose             | kenney_music-jingles    | Pizzicato jingles/jingles_PIZZI11.ogg | jingle |
level_up         | kenney_music-jingles    | Steel jingles/jingles_STEEL02.ogg     | jingle |
reward_claim     | kenney_music-jingles    | Steel jingles/jingles_STEEL08.ogg     | jingle |
ladder_climb     | kenney_music-jingles    | Pizzicato jingles/jingles_PIZZI02.ogg | jingle |
snake_slide      | kenney_music-jingles    | Pizzicato jingles/jingles_PIZZI01.ogg | jingle |
EOF

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; echo "${s%"${s##*[![:space:]]}"}"; }

# Loudest 50 ms window RMS (dBFS) of a WAV.
max_window_rms() {
  local f="$1" rate n meta="$WORK/meta.txt"
  rate=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 "$f")
  n=$((rate / 20))
  rm -f "$meta"
  ffmpeg -hide_banner -nostats -loglevel error -i "$f" \
    -af "asetnsamples=n=$n:p=0,astats=metadata=1:reset=1,ametadata=mode=print:key=lavfi.astats.Overall.RMS_level:file=$meta" \
    -f null -
  awk -F= '/RMS_level=/{ if ($2 != "-inf" && (m == "" || $2 + 0 > m)) m = $2 + 0 } END { print m }' "$meta"
}

peak_db() {
  ffmpeg -hide_banner -nostats -i "$1" -af volumedetect -f null - 2>&1 |
    sed -n 's/.*max_volume: \(-\{0,1\}[0-9.]*\) dB/\1/p'
}

while IFS='|' read -r target pack file category options; do
  target=$(trim "$target")
  [[ -z "$target" ]] && continue
  pack=$(trim "$pack")
  file=$(trim "$file")
  category=$(trim "$category")
  options=$(trim "$options")
  src="$(pack_dir "$pack")/Audio/$file"
  [[ -f "$src" ]] || { echo "missing: $src" >&2; exit 1; }

  rate=44100
  target_rms=-19
  ceiling=-1.5
  case "$category" in
    ui) target_rms=-22; ceiling=-3 ;;
    jingle) rate=22050; target_rms=-18 ;;
  esac

  pre="" post="" maxlen=""
  for opt in $options; do
    case "$opt" in
      seg=*)
        range="${opt#seg=}"
        pre="atrim=start=${range%-*}:end=${range#*-},asetpts=PTS-STARTPTS," ;;
      lp=*) pre="${pre}lowpass=f=${opt#lp=}," ;;
      max=*) maxlen="${opt#max=}" ;;
    esac
  done
  if [[ -n "$maxlen" ]]; then
    fade_start=$(awk -v m="$maxlen" 'BEGIN { printf "%.3f", m - 0.03 }')
    post="atrim=end=${maxlen},afade=t=out:st=${fade_start}:d=0.03,"
  fi

  stage="$WORK/$target.f32.wav"
  ffmpeg -hide_banner -nostats -loglevel error -y -i "$src" \
    -af "${pre}aformat=channel_layouts=mono,aresample=${rate},silenceremove=start_periods=1:start_threshold=-50dB,afade=t=in:d=0.002,${post}areverse,silenceremove=start_periods=1:start_threshold=-60dB,afade=t=in:d=0.012,areverse" \
    -ac 1 -ar "$rate" -c:a pcm_f32le "$stage"

  rms=$(max_window_rms "$stage")
  peak=$(peak_db "$stage")
  gain=$(awk -v t="$target_rms" -v r="$rms" -v c="$ceiling" -v p="$peak" \
    'BEGIN { g = t - r; h = c - p; if (h < g) g = h; printf "%.2f", g }')

  ffmpeg -hide_banner -nostats -loglevel error -y -i "$stage" \
    -af "volume=${gain}dB" -ac 1 -ar "$rate" -c:a pcm_s16le \
    -map_metadata -1 -fflags +bitexact -flags:a +bitexact "$OUT/$target.wav"

  printf '%-17s <- %-40s gain %6s dB  %s\n' "$target" "$pack/$file" "$gain" \
    "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/$target.wav")s"
done <<<"$TABLE"

if [[ -n "$MUSIC_SRC" ]]; then
  mkdir -p assets/audio/music
  ffmpeg -hide_banner -nostats -loglevel error -y -i "$MUSIC_SRC" \
    -af "loudnorm=I=-20:TP=-2:LRA=11" -ar 44100 -ac 2 -c:a aac -b:a 96k \
    -movflags +faststart assets/audio/music/lobby_loop.m4a
  echo "music: assets/audio/music/lobby_loop.m4a"
fi

du -ch "$OUT"/*.wav | tail -1
