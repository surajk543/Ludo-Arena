#!/usr/bin/env bash
# Builds an obfuscated Android release and collects its symbols for the
# release PR (owner's rules, 22 Oct 2026: release APKs/AABs are always
# obfuscated, and every release PR carries the R8 mapping and Dart symbols).
#
# Usage (from frontend/):
#   tool/build_android_release.sh apk|appbundle [flutter build options...]
#
#   tool/build_android_release.sh appbundle \
#     --dart-define=API_BASE_URL=https://… --dart-define=APP_ENV=production \
#     --dart-define-from-file=config/firebase.json
#
# Dart code is built with --obfuscate --split-debug-info, Java/Kotlin with R8
# (android/app/build.gradle.kts refuses any other release build). The
# symbols land in release-symbols/android/<version>/ (gzipped, staged in
# git), named after pubspec.yaml's version, so bump the version first:
#   mapping.txt.gz              R8 mapping (Java/Kotlin stack traces)
#   app.android-*.symbols.gz    Dart symbols per ABI (`flutter symbolize`)
#   BUILD_INFO, SHA256SUMS      what was built, from which commit
# The dart-defines are not recorded (keep config files out of git).
set -euo pipefail

cd "$(dirname "$0")/.."

target="${1:-}"
case "$target" in
  apk | appbundle) shift ;;
  *)
    sed -n '2,20p' "$0" >&2
    exit 2
    ;;
esac
for arg in "$@"; do
  case "$arg" in
    --debug | --profile | --no-obfuscate | --split-debug-info* | --obfuscate)
      echo "error: $arg is set by this script" >&2
      exit 2
      ;;
  esac
done

version="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | tr -d '[:space:]')"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
  echo "error: pubspec.yaml version '$version' is not x.y.z+build" >&2
  exit 1
fi

# A new symbols directory per run: it is an input of Flutter's Dart compile
# task, so the task always reruns and writes fresh symbols (with the same
# directory, an up-to-date Gradle build would skip it and write none).
rm -rf build/symbols/android-*
symbols="build/symbols/android-$(date +%Y%m%d%H%M%S)"
mapping=build/app/outputs/mapping/release/mapping.txt
rm -f "$mapping"

flutter build "$target" --release --obfuscate --split-debug-info="$symbols" "$@"

if [[ ! -s "$mapping" ]]; then
  echo "error: R8 mapping missing ($mapping): was R8 shrinking turned off?" >&2
  exit 1
fi
shopt -s nullglob
dart_symbols=("$symbols"/app.*.symbols)
if ((${#dart_symbols[@]} == 0)); then
  echo "error: no Dart symbols in $symbols" >&2
  exit 1
fi

if [[ "$target" == apk ]]; then
  artifact=build/app/outputs/flutter-apk/app-release.apk
else
  artifact=build/app/outputs/bundle/release/app-release.aab
fi

out="release-symbols/android/$version"
rm -rf "$out"
mkdir -p "$out"
gzip -9 -n -c "$mapping" >"$out/mapping.txt.gz"
for f in "${dart_symbols[@]}"; do
  gzip -9 -n -c "$f" >"$out/$(basename "$f").gz"
done
dirty=""
git diff --quiet HEAD -- . 2>/dev/null || dirty=" (uncommitted changes)"
{
  echo "version: $version"
  echo "target: $target"
  echo "commit: $(git rev-parse HEAD)$dirty"
  echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "flutter: $(flutter --version 2>/dev/null | head -1)"
  echo "artifact: $(basename "$artifact") sha256=$(shasum -a 256 "$artifact" | cut -d' ' -f1)"
} >"$out/BUILD_INFO"
(cd "$out" && shasum -a 256 -- *.gz >SHA256SUMS)
git add -- "$out"

echo
echo "Built $artifact (obfuscated)."
echo "Symbols staged in frontend/$out: commit them in the release PR."
