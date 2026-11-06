#!/usr/bin/env bash
# Explicit synthetic replay only. No global shortcuts, user clipboard or provider requests.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
variant="${1:-after}"
case "$variant" in before|after) ;; *) echo "Usage: $0 [before|after]" >&2;exit 64;; esac
build_root="$project_root/.build/image-resilience-replay"
mkdir -p "$build_root/cache"
run_root="$(mktemp -d "$build_root/$variant.XXXXXX")"
source_root="$run_root/source"
mkdir -p "$source_root"
flags=()
if [[ "$variant" == before ]]; then
  git -C "$project_root" archive 596fea1507ee11c26332e91dc086a39c4eeb83c8 DeepK experiments/image-translation | tar -x -C "$source_root"
else
  cp -R "$project_root/DeepK" "$source_root/DeepK"
  mkdir -p "$source_root/experiments"
  cp -R "$project_root/experiments/image-translation" "$source_root/experiments/image-translation"
  flags+=(-D ISSUE_AFTER)
fi
sources=()
while IFS= read -r source_file;do sources+=("$source_file");done < <(rg --files "$source_root/DeepK" "$source_root/experiments/image-translation" -g '*.swift' | rg -v '/DeepKApp.swift$|/replay/' | sort)
app="$run_root/Image Replay.app"
mkdir -p "$app/Contents/MacOS"
xcrun swiftc -swift-version 6 -warnings-as-errors -Onone -parse-as-library -D DEEPK_IMAGE_TRANSLATION_POC ${flags[@]+"${flags[@]}"} \
  -module-cache-path "$build_root/cache" "${sources[@]}" "$project_root/experiments/image-translation/replay/ReplayMain.swift" \
  -o "$app/Contents/MacOS/ImageReplay" -framework AppKit -framework SwiftUI -framework Vision -framework ScreenCaptureKit -framework CoreML -framework AVFoundation -lxml2
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.deepk.poc.issue-replay.$variant</string><key>CFBundleExecutable</key><string>ImageReplay</string><key>CFBundleName</key><string>Image Replay $variant</string><key>CFBundlePackageType</key><string>APPL</string><key>NSPrincipalClass</key><string>NSApplication</string></dict></plist>
PLIST
codesign --force --sign - "$app" >/dev/null 2>&1
"$app/Contents/MacOS/ImageReplay" "$run_root/evidence"
echo "Synthetic replay output: $run_root/evidence"
