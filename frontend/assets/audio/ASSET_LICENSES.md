# Audio asset licenses

Every sound shipped under `frontend/assets/audio/`. All of them are public-domain
dedications (CC0 1.0): no attribution is required; credit is given here anyway.
This file is documentation only (it is not bundled in the app).

## Sound effects — Kenney (www.kenney.nl), CC0 1.0

- **Creator:** Kenney (www.kenney.nl) — Kenney Vleugels.
- **License:** Creative Commons Zero, CC0 1.0 Universal
  (http://creativecommons.org/publicdomain/zero/1.0/), as stated in each pack's
  `License.txt` (quoted below).
- **Attribution:** not required ("Credit (Kenney or www.kenney.nl) would be nice
  but is not mandatory").
- **Downloaded:** from the pack pages below with the user's permission (October 2026).

### Processing (all effects)

Reproducible with `frontend/tool/import_kenney_audio.sh <kenney-dir>` (ffmpeg):
Ogg Vorbis → 16-bit PCM WAV (iOS cannot decode Ogg), downmixed to mono,
44.1 kHz (jingles 22.05 kHz to save space), leading silence below −50 dBFS
removed (latency) with a 2 ms fade-in, trailing silence below −60 dBFS removed
with a 12 ms fade-out, then a gain so the loudest 50 ms window reaches the
category target (UI −22 dBFS RMS / peak ≤ −3 dBFS; game −19 dBFS / jingles
−18 dBFS RMS, peak ≤ −1.5 dBFS). Per-file extras are listed in the table.

### Files

| Local file | Original file | Pack (source page) | Length | Size | Extra processing |
|---|---|---|---|---|---|
| `sfx/ui_tap.wav` | `select_002.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.04 s, 44.1 kHz | 3.5 KB | — |
| `sfx/ui_tab.wav` | `select_001.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.04 s, 44.1 kHz | 3.5 KB | — |
| `sfx/ui_toggle.wav` | `toggle_002.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.10 s, 44.1 kHz | 8.4 KB | — |
| `sfx/ui_open.wav` | `maximize_009.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.21 s, 44.1 kHz | 17.8 KB | — |
| `sfx/ui_close.wav` | `minimize_009.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.20 s, 44.1 kHz | 17.2 KB | — |
| `sfx/ui_confirm.wav` | `confirmation_003.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.32 s, 44.1 kHz | 27.3 KB | — |
| `sfx/ui_error.wav` | `error_004.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.10 s, 44.1 kHz | 9.0 KB | — |
| `sfx/ui_tick.wav` | `tick_004.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.06 s, 44.1 kHz | 4.8 KB | — |
| `sfx/lobby_play.wav` | `maximize_006.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.37 s, 44.1 kHz | 31.8 KB | — |
| `sfx/notification.wav` | `glass_001.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.28 s, 44.1 kHz | 23.8 KB | — |
| `sfx/chat_pop.wav` | `drop_003.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.19 s, 44.1 kHz | 16.3 KB | stereo → mono |
| `sfx/dice_roll.wav` | `die-throw-1.ogg` | Casino Audio 1.1 ([kenney.nl/assets/casino-audio](https://kenney.nl/assets/casino-audio)) | 0.37 s, 44.1 kHz | 31.9 KB | stereo → mono |
| `sfx/dice_land.wav` | `die-throw-4.ogg` | Casino Audio 1.1 ([kenney.nl/assets/casino-audio](https://kenney.nl/assets/casino-audio)) | 0.17 s, 44.1 kHz | 15.0 KB | segment 0.10–0.30 s (one impact), stereo → mono |
| `sfx/token_select.wav` | `pluck_002.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.13 s, 44.1 kHz | 11.6 KB | low-pass 9 kHz, stereo → mono |
| `sfx/token_step.wav` | `impactWood_light_002.ogg` | Impact Sounds 1.0 ([kenney.nl/assets/impact-sounds](https://kenney.nl/assets/impact-sounds)) | 0.13 s, 44.1 kHz | 11.7 KB | cut to 0.16 s with 30 ms fade-out, stereo → mono |
| `sfx/token_leave_base.wav` | `maximize_007.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.18 s, 44.1 kHz | 15.2 KB | — |
| `sfx/token_safe.wav` | `glass_003.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.12 s, 44.1 kHz | 10.4 KB | — |
| `sfx/token_home_path.wav` | `select_004.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.21 s, 44.1 kHz | 18.0 KB | — |
| `sfx/token_capture.wav` | `impactPunch_medium_002.ogg` | Impact Sounds 1.0 ([kenney.nl/assets/impact-sounds](https://kenney.nl/assets/impact-sounds)) | 0.32 s, 44.1 kHz | 28.0 KB | cut to 0.35 s with 30 ms fade-out, stereo → mono |
| `sfx/token_captured.wav` | `minimize_006.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.36 s, 44.1 kHz | 31.4 KB | — |
| `sfx/turn_mine.wav` | `confirmation_001.ogg` | Interface Sounds 1.0 ([kenney.nl/assets/interface-sounds](https://kenney.nl/assets/interface-sounds)) | 0.29 s, 44.1 kHz | 25.0 KB | — |
| `sfx/coin.wav` | `chips-stack-3.ogg` | Casino Audio 1.1 ([kenney.nl/assets/casino-audio](https://kenney.nl/assets/casino-audio)) | 0.35 s, 44.1 kHz | 30.1 KB | low-pass 9 kHz, stereo → mono |
| `sfx/purchase.wav` | `chips-handle-6.ogg` | Casino Audio 1.1 ([kenney.nl/assets/casino-audio](https://kenney.nl/assets/casino-audio)) | 0.40 s, 44.1 kHz | 34.7 KB | low-pass 9 kHz, stereo → mono |
| `sfx/match_start.wav` | `Pizzicato jingles/jingles_PIZZI16.ogg` | Music Jingles ([kenney.nl/assets/music-jingles](https://kenney.nl/assets/music-jingles)) | 0.45 s, 22.05 kHz | 19.6 KB | 22.05 kHz, stereo → mono |
| `sfx/token_home.wav` | `Pizzicato jingles/jingles_PIZZI08.ogg` | Music Jingles ([kenney.nl/assets/music-jingles](https://kenney.nl/assets/music-jingles)) | 0.56 s, 22.05 kHz | 24.1 KB | 22.05 kHz, stereo → mono |
| `sfx/win.wav` | `Steel jingles/jingles_STEEL10.ogg` | Music Jingles ([kenney.nl/assets/music-jingles](https://kenney.nl/assets/music-jingles)) | 0.91 s, 22.05 kHz | 39.2 KB | 22.05 kHz, stereo → mono |
| `sfx/lose.wav` | `Pizzicato jingles/jingles_PIZZI11.ogg` | Music Jingles ([kenney.nl/assets/music-jingles](https://kenney.nl/assets/music-jingles)) | 0.79 s, 22.05 kHz | 34.0 KB | 22.05 kHz, stereo → mono |
| `sfx/level_up.wav` | `Steel jingles/jingles_STEEL02.ogg` | Music Jingles ([kenney.nl/assets/music-jingles](https://kenney.nl/assets/music-jingles)) | 1.39 s, 22.05 kHz | 59.8 KB | 22.05 kHz, stereo → mono |
| `sfx/reward_claim.wav` | `Steel jingles/jingles_STEEL08.ogg` | Music Jingles ([kenney.nl/assets/music-jingles](https://kenney.nl/assets/music-jingles)) | 0.78 s, 22.05 kHz | 33.5 KB | 22.05 kHz, stereo → mono |
| `sfx/ladder_climb.wav` | `Pizzicato jingles/jingles_PIZZI02.ogg` | Music Jingles ([kenney.nl/assets/music-jingles](https://kenney.nl/assets/music-jingles)) | 0.95 s, 22.05 kHz | 40.7 KB | 22.05 kHz, stereo → mono |
| `sfx/snake_slide.wav` | `Pizzicato jingles/jingles_PIZZI01.ogg` | Music Jingles ([kenney.nl/assets/music-jingles](https://kenney.nl/assets/music-jingles)) | 0.99 s, 22.05 kHz | 42.5 KB | 22.05 kHz, stereo → mono |

Total: 31 files, 720 KB.

### Pack license texts (verbatim)

**Interface Sounds 1.0** — https://kenney.nl/assets/interface-sounds (`kenney_interface-sounds/License.txt`):

```text
Interface Sounds (1.0)

Created/distributed by Kenney (www.kenney.nl)
Creation date: 11-02-2020

------------------------------

License: (Creative Commons Zero, CC0)
http://creativecommons.org/publicdomain/zero/1.0/

This content is free to use in personal, educational and commercial projects.

Support us by crediting Kenney or www.kenney.nl (this is not mandatory)

------------------------------

Donate:   http://support.kenney.nl
Patreon:  http://patreon.com/kenney/

Follow on Twitter for updates:
http://twitter.com/KenneyNL
```

**Casino Audio 1.1** — https://kenney.nl/assets/casino-audio (`kenney_casino-audio/License.txt`):

```text
Casino Audio (1.1)

by  Kenney Vleugels (Kenney.nl)

------------------------------

License (Creative Commons Zero, CC0)
http://creativecommons.org/publicdomain/zero/1.0/

You may use these assets in personal and commercial projects.
Credit (Kenney or www.kenney.nl) would be nice but is not mandatory.

------------------------------

Donate:   http://support.kenney.nl
Request:  http://request.kenney.nl

Follow on Twitter for updates:
@KenneyNL
```

**Impact Sounds 1.0** — https://kenney.nl/assets/impact-sounds (`kenney_impact-sounds/License.txt`):

```text
Impact Sounds (1.0)

Created/distributed by Kenney (www.kenney.nl)
Creation date: 19-12-2019

------------------------------

License: (Creative Commons Zero, CC0)
http://creativecommons.org/publicdomain/zero/1.0/

This content is free to use in personal, educational and commercial projects.

Support us by crediting Kenney or www.kenney.nl (this is not mandatory)

------------------------------

Donate:   http://support.kenney.nl
Request:  http://request.kenney.nl
Patreon:  http://patreon.com/kenney/

Follow on Twitter for updates:
http://twitter.com/KenneyNL
```

**Music Jingles** — https://kenney.nl/assets/music-jingles (`kenney_music-jingles/License.txt`):

```text
Music Jingles

by  Kenney Vleugels (Kenney.nl)

------------------------------

License (Creative Commons Zero, CC0)
http://creativecommons.org/publicdomain/zero/1.0/

You may use these assets in personal and commercial projects.
Credit (Kenney or www.kenney.nl) would be nice but is not mandatory.

------------------------------

Donate:   http://support.kenney.nl
Request:  http://request.kenney.nl

Follow on Twitter for updates:
@KenneyNL
```

Also downloaded but not shipped (no file used): UI Audio (UI SFX Set) (CC0 1.0).

## Music — lobby loop, CC0 1.0

| Field | Value |
|---|---|
| Local file | `music/lobby_loop.m4a` (AAC-LC 96 kbps, 44.1 kHz stereo, 57.7 s, 711 KB) |
| Title / creator | "Upbeat loop" by mistermender |
| Source | https://freesound.org/people/mistermender/sounds/512340/ (Freesound sound 512340, uploaded April 8th 2020) |
| Original file | `512340__mistermender__upbeat-loop.mp3` (MP3 192 kbps, 44.1 kHz stereo, 57.652 s) |
| License | Creative Commons 0 (CC0 1.0), as shown on the Freesound page: "You can copy, modify, distribute and perform the sound, even for commercial purposes, all without the need of asking permission to the author". Uploader's description: "Spice up your project with a free to use upbeat loop! Free to use with no credit required." |
| Attribution | Not required (CC0). Optional credit: "Upbeat loop by mistermender (freesound.org)". |
| Downloaded | By the project lead via the user's logged-in Freesound account, with the user's approval. |
| Processing | Loudness-normalized (original −6.9 LUFS, far too loud for background music) and re-encoded: `ffmpeg -i 512340__mistermender__upbeat-loop.mp3 -af "loudnorm=I=-20:TP=-2:LRA=11" -ar 44100 -ac 2 -c:a aac -b:a 96k -movflags +faststart lobby_loop.m4a` → −20.7 LUFS integrated, true peak −2 dBTP. Documented as the `--music` step of `tool/import_kenney_audio.sh` (the mp3 is not in the repo). Played with `ReleaseMode.loop`; a tiny gap at the loop point (AAC padding) is acceptable. |

## Launch intro jingle — Sun Game Studio (the owner's own asset)

| Field | Value |
|---|---|
| Local file | `jingles/studio_intro.m4a` (AAC-LC 96 kbps, 44.1 kHz stereo, 6.59 s, 79 KB) |
| Source | The audio track of the owner's studio logo video "Sun Game Studio Logo.mp4" (H.264 768×768 24 fps + AAC 32 kHz stereo, 6.59 s), provided by the owner on 22 Oct 2026. |
| License | Owned by Sun Game Studio (the app's publisher); not third-party. |
| Processing | `ffmpeg -i "Sun Game Studio Logo.mp4" -vn -ac 2 -ar 44100 -af "volume=-3dB" -c:a aac -b:a 96k -map_metadata -1 -movflags +faststart studio_intro.m4a` (−3 dB: −18 dB mean, −7 dB peak, the jingle level). Streamed by the jingle player (`Jingle.studioIntro`), not an effects pool. The video's frames ship separately as `assets/animations/studio_intro.webp` (animated WebP, 158 frames at 24 fps, 768 px, `img2webp -loop 1 -lossy -q 80 -d 42`, 3.3 MB), played by `StudioIntro`. |

Total shipped audio: 1510 KB.
