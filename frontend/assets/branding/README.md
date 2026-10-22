# Ludo Arena — brand assets

Master artwork for the app icon and launch screens. These files are **not**
bundled into the app (they aren't listed in `pubspec.yaml`); they are the
sources for the generated platform icons and for uploads elsewhere.

| File | Size | Use it for |
|---|---|---|
| `app_icon_1024.png` | 1024×1024, opaque | **App Store** icon (Apple rejects transparency), press kits, anywhere a square icon is wanted |
| `play_store_icon_512.png` | 512×512, 32-bit PNG (with alpha) | **Google Play** listing → *App icon* |
| `app_icon_rounded_1024.png` | 1024×1024, rounded corners, transparent outside | Website, social media, documents, presentations |
| `app_icon_rounded_512.png` | 512×512, rounded corners, transparent outside | Same, smaller |
| `launch_logo_1024.png` | 1024×1291, transparent | The crest alone (no background tile) — headers, banners, overlays on your own background |
| `adaptive_foreground_1024.png`, `adaptive_background_1024.png`, `adaptive_monochrome_1024.png` | 1024×1024 | Android adaptive / themed icon layers (inputs to the generator) |

Regenerate the in-app/platform icons and launch images with
`flutter test tool/generate_brand_assets.dart` (from `frontend/`). The rounded
and Play exports were made from `app_icon_1024.png` with ffmpeg (rounded-corner
radius 230/1024, Lanczos downscale).
