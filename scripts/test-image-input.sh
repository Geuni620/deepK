#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
test_root="$(mktemp -d /private/tmp/deepk-image-release-test.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT
sources=()
while IFS= read -r source_file;do sources+=("$project_root/$source_file");done < <(cd "$project_root" && rg --files DeepK -g '*.swift' -g '!DeepKApp.swift' | sort)
fixtures=(ImageTranslationFixtures ImageTranslationTests NativeImageTests InputResilienceTests ChatLayoutTests ImageFeedbackBenchmark ScreenScannerTests)
for fixture in "${fixtures[@]}";do sources+=("$project_root/experiments/image-translation/$fixture.swift");done
xcrun swiftc -swift-version 6 -warnings-as-errors -parse-as-library -D DEEPK_IMAGE_TRANSLATION -D IMAGE_INPUT_RELEASE_TESTS \
  -module-cache-path "$test_root/cache" "${sources[@]}" "$project_root/DeepKTests/ImageInputReleaseTests.swift" \
  -o "$test_root/ImageInputReleaseTests" -framework AppKit -framework SwiftUI -framework Vision -framework ScreenCaptureKit -framework CoreML -lxml2
"$test_root/ImageInputReleaseTests" --assert-feedback
