#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POC_ROOT="$PROJECT_ROOT/experiments/image-translation"
BUILD_ROOT="$PROJECT_ROOT/.build/image-translation-poc"
APP_PATH="$BUILD_ROOT/deepK Rich POC.app"

case "${1:-}" in
  --help|-h)
    echo "사용법: ./scripts/image-translation-poc.sh [--open|--resign|--build-only|--test|--record-synthetic-demo|--scan-live-smoke]"
    echo "인자 없이 실행하면 POC를 빌드하고 다시 엽니다. 설치된 deepK는 실행·종료하지 않습니다."
    echo "--open은 빌드 없이 POC만 다시 엽니다. POC 화면의 메모리 내용은 비워집니다."
    echo "--resign은 기존 POC에 개발 서명만 다시 적용합니다. DEEPK_POC_SIGNING_IDENTITY 또는 기존 DEEPK_SIGNING_IDENTITY를 사용할 수 있습니다."
    echo "--test는 합성 이미지만 검사합니다. --scan-live-smoke는 DEEPK_IMAGE_POC_LIVE=1이 필요합니다."
    exit 0 ;;
  ""|--open|--resign|--build-only|--test|--scan-live-smoke|--record-synthetic-demo) ;;
  *) echo "지원하지 않는 인자입니다. --help를 확인하세요." >&2; exit 64 ;;
esac
if [[ "$(uname -s)" != Darwin ]] || (( $(sw_vers -productVersion | cut -d. -f1) < 15 )); then
  echo "macOS 15 이상과 Swift 6가 필요합니다." >&2; exit 1
fi
sign_poc() {
  [[ -x "$APP_PATH/Contents/MacOS/ImageTranslationPOC" ]] || { echo "먼저 POC를 빌드해 주세요." >&2; return 1; }
  local poc_bundle_id
  poc_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
  [[ "$poc_bundle_id" == com.deepk.poc.rich-selection ]] || { echo "POC 앱 식별자가 달라 서명을 중단합니다." >&2; return 1; }
  local poc_signing_identity="${DEEPK_POC_SIGNING_IDENTITY:-${DEEPK_SIGNING_IDENTITY:-}}"
  if [[ -z "$poc_signing_identity" ]]; then
    poc_signing_identity="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ { print $2; exit }')"
  fi
  if [[ -n "$poc_signing_identity" && "$poc_signing_identity" != - ]]; then
    codesign --force --sign "$poc_signing_identity" --timestamp=none "$APP_PATH"
    echo "POC에 고정 개발 서명을 적용했습니다. 기존 임시 서명에서 바뀌었다면 macOS 권한을 한 번 갱신해 주세요."
  else
    codesign --force --sign - --timestamp=none "$APP_PATH"
    echo "개발 인증서가 없어 임시 서명을 사용합니다. 재빌드 후 macOS 권한을 다시 허용해야 할 수 있습니다." >&2
  fi
  codesign --verify --strict "$APP_PATH"
}
launch_poc() {
  [[ -x "$APP_PATH/Contents/MacOS/ImageTranslationPOC" ]] || { echo "먼저 POC를 빌드해 주세요." >&2; return 1; }
  echo "테스트 POC만 다시 엽니다. POC 화면의 메모리 내용은 비워집니다."
  xcrun swift -module-cache-path "$BUILD_ROOT/cache" - "$APP_PATH" <<'SWIFT'
import AppKit
let expected = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.deepk.poc.rich-selection")
    .filter { $0.bundleURL?.standardizedFileURL == expected }
for application in applications { _ = application.terminate() }
let deadline = Date().addingTimeInterval(8)
while applications.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
if applications.contains(where: { !$0.isTerminated }) {
    fputs("POC가 종료되지 않았습니다. 테스트 앱을 직접 종료한 뒤 --open을 다시 실행해 주세요.\n", stderr)
    exit(1)
}
SWIFT
  open "$APP_PATH" "$@"
  echo "deepK Rich POC를 열었습니다. 기존 번역창에서 글과 이미지를 함께 받습니다."
}
if [[ "${1:-}" == --open ]]; then launch_poc; exit 0; fi
if [[ "${1:-}" == --resign ]]; then sign_poc; exit 0; fi
if [[ "${1:-}" == --record-synthetic-demo ]]; then
  # Keep explicit synthetic evidence outside protected Desktop/Documents folders. The GUI never needs
  # additional folder access just to execute the audit helper or write the requested demonstration.
  POC_DEMO_ROOT="$(mktemp -d /private/tmp/deepk-synthetic-demo.XXXXXX)"
  cp "$POC_ROOT/audit-codex.py" "$POC_DEMO_ROOT/audit-codex.py"
  chmod +x "$POC_DEMO_ROOT/audit-codex.py"
  POC_DEMO_OPTIONS=()
  if [[ "${DEEPK_POC_DEMO_FIXTURE:-station}" == chat ]]; then POC_DEMO_OPTIONS+=(--chat-layout-demo); fi
  launch_poc --stdout "$POC_DEMO_ROOT/recording-status.log" --stderr "$POC_DEMO_ROOT/recording-errors.log" --args \
    --record-synthetic-demo --synthetic-copy-replay --seed-synthetic-input --synthetic-output "$POC_DEMO_ROOT" \
    --audit-proxy "$POC_DEMO_ROOT/audit-codex.py" --real-codex "${DEEPK_POC_DEMO_CODEX:-$(command -v codex)}" \
    --audit-output "$POC_DEMO_ROOT/native-request-audit.json" ${POC_DEMO_OPTIONS[@]+"${POC_DEMO_OPTIONS[@]}"}
  echo "합성 시연 폴더: $POC_DEMO_ROOT (사용자 콘텐츠 없음; 확인 후 이 폴더를 삭제할 수 있습니다.)"
  exit 0
fi
mkdir -p "$APP_PATH/Contents/MacOS" "$BUILD_ROOT/cache"
APP_SOURCES=()
while IFS= read -r path; do APP_SOURCES+=("$PROJECT_ROOT/$path"); done < <(cd "$PROJECT_ROOT" && rg --files DeepK -g '*.swift' | sort)
xcrun swiftc -swift-version 6 -warnings-as-errors -O -whole-module-optimization -num-threads 2 -parse-as-library \
  -target "$(uname -m)-apple-macosx15.0" -module-cache-path "$BUILD_ROOT/cache" \
  -D DEEPK_IMAGE_TRANSLATION_POC "${APP_SOURCES[@]}" \
  "$POC_ROOT/ImageTranslationCore.swift" "$POC_ROOT/ImageTranslationTests.swift" \
  "$POC_ROOT/ImagePOCIntegration.swift" \
  "$POC_ROOT/ScreenScanner.swift" "$POC_ROOT/ScreenScannerTests.swift" \
  "$POC_ROOT/NativeImageInput.swift" "$POC_ROOT/NaturalImageRenderer.swift" \
  "$POC_ROOT/ImageRegionBatch.swift" "$POC_ROOT/ClipboardImageImport.swift" \
  "$POC_ROOT/NativeImageTests.swift" \
  "$POC_ROOT/SyntheticDemo.swift" \
  "$POC_ROOT/ImageFeedbackBenchmark.swift" \
  "$POC_ROOT/ImageProgress.swift" \
  "$POC_ROOT/ChatLayoutTests.swift" \
  -o "$APP_PATH/Contents/MacOS/ImageTranslationPOC" -framework AppKit -framework SwiftUI -framework Vision -framework ScreenCaptureKit -framework CoreML -lxml2
cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.deepk.poc.rich-selection</string>
<key>CFBundleName</key><string>deepK Rich POC</string>
<key>CFBundleDisplayName</key><string>deepK Rich POC</string>
<key>CFBundleExecutable</key><string>ImageTranslationPOC</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>사용자가 지정한 화면 영역에서 글자를 읽어 번역합니다. 이미지는 이 Mac에서 처리하고 인식한 글자만 선택한 번역 제공자에게 보냅니다.</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
if [[ -d "$BUILD_ROOT/models/compiled/MIGAN_512.mlmodelc" ]]; then
  mkdir -p "$APP_PATH/Contents/Resources"
  ditto "$BUILD_ROOT/models/compiled/MIGAN_512.mlmodelc" "$APP_PATH/Contents/Resources/MIGAN_512.mlmodelc"
  cp "$POC_ROOT/THIRD-PARTY-NOTICES.md" "$APP_PATH/Contents/Resources/THIRD-PARTY-NOTICES.md"
  cp "$BUILD_ROOT/models/LICENSE-MWOYEO" "$APP_PATH/Contents/Resources/LICENSE-MWOYEO"
  cp "$BUILD_ROOT/models/LICENSE-MI-GAN-WEIGHTS" "$APP_PATH/Contents/Resources/LICENSE-MI-GAN-WEIGHTS"
fi
sign_poc
case "${1:-}" in
  --build-only) echo "$APP_PATH" ;;
  --test)
    "$APP_PATH/Contents/MacOS/ImageTranslationPOC" --self-test --synthetic-output "$BUILD_ROOT/synthetic"
    "$APP_PATH/Contents/MacOS/ImageTranslationPOC" --native-self-test --synthetic-output "$BUILD_ROOT/synthetic"
    "$APP_PATH/Contents/MacOS/ImageTranslationPOC" --feedback-benchmark --assert-feedback --synthetic-output "$BUILD_ROOT/synthetic"
    "$APP_PATH/Contents/MacOS/ImageTranslationPOC" --scanner-self-test
    python3 "$POC_ROOT/test-audit-helper.py" ;;
  --scan-live-smoke) "$APP_PATH/Contents/MacOS/ImageTranslationPOC" --scan-live-smoke ;;
  *) launch_poc ;;
esac
