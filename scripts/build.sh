#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "$SCRIPT_DIR/version.sh"

xcodebuild \
  -project "${PROJECT_ROOT}/DeepK.xcodeproj" \
  -scheme DeepK \
  -configuration Debug \
  -sdk macosx \
  -derivedDataPath "${PROJECT_ROOT}/.build/DerivedData" \
  "MARKETING_VERSION=$DEEPK_APP_VERSION" \
  "CURRENT_PROJECT_VERSION=$DEEPK_APP_BUILD" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="${PROJECT_ROOT}/.build/DerivedData/Build/Products/Debug/DeepK.app"
SIGNING_IDENTITY="${DEEPK_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ { print $2; exit }')"
fi
if [[ -n "$SIGNING_IDENTITY" ]]; then
  # 같은 개발 인증서로 서명해 빌드마다 macOS 권한 식별자가 바뀌지 않게 한다.
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_PATH"
  codesign --verify --strict "$APP_PATH"
else
  echo "개발 인증서가 없어 임시 서명을 유지합니다. 재빌드 후 macOS 권한을 다시 허용해야 할 수 있습니다." >&2
fi
