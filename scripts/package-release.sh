#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROJECT_FILE="${PROJECT_ROOT}/DeepK.xcodeproj"

source "$SCRIPT_DIR/version.sh"
DEFAULT_VERSION="$DEEPK_APP_VERSION"
DEFAULT_ARCH="arm64"
# DeepK.xcodeproj currently targets macOS 15. Keep this fixed until the project
# target and the compatibility test matrix change together.
MINIMUM_MACOS="15.0"
BUILD_NUMBER="$DEEPK_APP_BUILD"
MODE="distribution"
VERSION="${DEEPK_VERSION:-$DEFAULT_VERSION}"
ARCH="${DEEPK_ARCH:-$DEFAULT_ARCH}"
NOTARY_TIMEOUT="${DEEPK_NOTARY_TIMEOUT:-10m}"

STAGING_DIR=""
FINAL_STAGING_DIR=""

usage() {
  cat <<'USAGE'
사용법: ./scripts/package-release.sh [--local] [--version VERSION] [--arch ARCH]

기본 모드:
  배포용 Release를 만들고 Developer ID Application 서명과 Apple 공증을 수행합니다.
  DEEPK_DEVELOPER_ID와 DEEPK_NOTARY_PROFILE이 없으면 빌드 전에 실패합니다.

로컬 모드:
  --local       Release를 ad-hoc 서명으로 패키징합니다. 로컬 전용이며 배포·공증용이 아닙니다.

옵션:
  --version     버전 (기본값: VERSION 파일, 또는 DEEPK_VERSION)
  --arch        arm64 (기본값), x86_64, universal (또는 DEEPK_ARCH)
  --help        도움말
USAGE
}

fail() {
  printf 'package-release: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "필요한 명령을 찾을 수 없습니다: $1"
}

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null || true
}

validate_app_metadata() {
  local app_path="$1"
  local executable_path="${app_path}/Contents/MacOS/DeepK"
  local plist_path="${app_path}/Contents/Info.plist"
  local actual_arches plist_version plist_bundle_id plist_minimum_os plist_build_number

  actual_arches="$(lipo -archs "$executable_path" 2>/dev/null)" \
    || fail "앱 실행 파일의 아키텍처를 읽지 못했습니다."
  case "$ARCH" in
    arm64|x86_64)
      [[ "$actual_arches" == "$ARCH" ]] \
        || fail "앱 아키텍처가 요청한 값과 다릅니다: requested=$ARCH actual=$actual_arches"
      ;;
    universal)
      [[ " $actual_arches " == *" arm64 "* && " $actual_arches " == *" x86_64 "* ]] \
        || fail "Universal 앱에 arm64와 x86_64가 모두 없습니다: actual=$actual_arches"
      ;;
  esac

  [[ -f "$plist_path" ]] || fail "앱 Info.plist를 찾을 수 없습니다: $plist_path"
  plist_version="$(plist_value CFBundleShortVersionString "$plist_path")"
  [[ "$plist_version" == "$VERSION" ]] \
    || fail "앱 버전이 요청한 값과 다릅니다: requested=$VERSION actual=$plist_version"
  plist_build_number="$(plist_value CFBundleVersion "$plist_path")"
  [[ "$plist_build_number" == "$BUILD_NUMBER" ]] \
    || fail "앱 빌드 번호가 요청한 값과 다릅니다."
  plist_bundle_id="$(plist_value CFBundleIdentifier "$plist_path")"
  [[ "$plist_bundle_id" == com.deepk.app ]] \
    || fail "앱 bundle identifier가 deepK 계약과 다릅니다: $plist_bundle_id"
  plist_minimum_os="$(plist_value LSMinimumSystemVersion "$plist_path")"
  if [[ -z "$plist_minimum_os" ]]; then
    plist_minimum_os="$(plist_value MinimumOSVersion "$plist_path")"
  fi
  [[ "$plist_minimum_os" == "$MINIMUM_MACOS" ]] \
    || fail "앱 최소 macOS가 프로젝트 계약과 다릅니다: requested=$MINIMUM_MACOS actual=$plist_minimum_os"
}

cleanup() {
  if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
    rm -rf -- "$STAGING_DIR"
  fi
  if [[ -n "$FINAL_STAGING_DIR" && -d "$FINAL_STAGING_DIR" ]]; then
    rm -rf -- "$FINAL_STAGING_DIR"
  fi
}

while (($# > 0)); do
  case "$1" in
    --local)
      [[ "$MODE" == distribution ]] || fail "--local을 여러 번 지정할 수 없습니다."
      MODE="local"
      shift
      ;;
    --version)
      (($# >= 2)) || fail "--version에는 값이 필요합니다."
      VERSION="$2"
      shift 2
      ;;
    --version=*)
      VERSION="${1#*=}"
      shift
      ;;
    --arch)
      (($# >= 2)) || fail "--arch에는 값이 필요합니다."
      ARCH="$2"
      shift 2
      ;;
    --arch=*)
      ARCH="${1#*=}"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf '지원하지 않는 인자입니다: %s\n\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "버전 형식이 올바르지 않습니다: $VERSION"
[[ "$ARCH" == arm64 || "$ARCH" == x86_64 || "$ARCH" == universal ]] \
  || fail "지원하지 않는 아키텍처입니다: $ARCH (arm64, x86_64, universal 중 하나)"
[[ "$MINIMUM_MACOS" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] \
  || fail "최소 macOS 버전 형식이 올바르지 않습니다: $MINIMUM_MACOS"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] \
  || fail "빌드 번호는 숫자여야 합니다: $BUILD_NUMBER"
[[ "$NOTARY_TIMEOUT" =~ ^[0-9]+[smh]$ ]] \
  || fail "공증 대기 시간 형식이 올바르지 않습니다: $NOTARY_TIMEOUT"

[[ "$(uname -s)" == Darwin ]] || fail "deepK Release 패키징은 macOS에서만 실행할 수 있습니다."
[[ -d "$PROJECT_FILE" ]] || fail "Xcode 프로젝트를 찾을 수 없습니다: $PROJECT_FILE"

require_command git
require_command xcodebuild
require_command ditto
require_command shasum
require_command date
require_command codesign
require_command lipo
[[ -x /usr/libexec/PlistBuddy ]] || fail "PlistBuddy를 찾을 수 없습니다."

DEVELOPER_ID="${DEEPK_DEVELOPER_ID:-}"
NOTARY_PROFILE="${DEEPK_NOTARY_PROFILE:-}"

if [[ "$MODE" == distribution ]]; then
  [[ -n "$DEVELOPER_ID" ]] \
    || fail "배포 모드에는 DEEPK_DEVELOPER_ID가 필요합니다. 개발 인증서나 임시 서명으로 대체하지 않습니다."
  [[ "$DEVELOPER_ID" == "Developer ID Application:"* ]] \
    || fail "DEEPK_DEVELOPER_ID는 Developer ID Application 인증서여야 합니다."
  [[ -n "$NOTARY_PROFILE" ]] \
    || fail "배포 모드에는 Keychain notarytool 프로필 이름인 DEEPK_NOTARY_PROFILE이 필요합니다."

  require_command security
  require_command xcrun
  require_command plutil
  require_command spctl

  IDENTITY_LIST="$(security find-identity -v -p codesigning 2>/dev/null)" \
    || fail "Keychain의 코드 서명 identity를 조회하지 못했습니다."
  [[ "$IDENTITY_LIST" == *"\"${DEVELOPER_ID}\""* ]] \
    || fail "지정한 Developer ID Application identity를 Keychain에서 찾지 못했습니다."
  xcrun --find notarytool >/dev/null 2>&1 \
    || fail "Xcode의 notarytool을 찾지 못했습니다."
  xcrun --find stapler >/dev/null 2>&1 \
    || fail "Xcode의 stapler를 찾지 못했습니다."
fi

SOURCE_COMMIT="$(git -C "$PROJECT_ROOT" rev-parse --verify HEAD 2>/dev/null)" \
  || fail "현재 Git 커밋을 확인하지 못했습니다."
[[ "$SOURCE_COMMIT" =~ ^[0-9A-Fa-f]{7,64}$ ]] \
  || fail "Git 커밋 SHA 형식이 올바르지 않습니다."
WORKTREE_STATUS="$(git -C "$PROJECT_ROOT" status --porcelain --untracked-files=normal)" \
  || fail "Git 작업 트리 상태를 확인하지 못했습니다."
if [[ -n "$WORKTREE_STATUS" ]]; then
  DIRTY="true"
  ARTIFACT_SHA="${SOURCE_COMMIT:0:12}-dirty"
else
  DIRTY="false"
  ARTIFACT_SHA="${SOURCE_COMMIT:0:12}"
fi
if [[ "$MODE" == distribution && "$DIRTY" == true ]]; then
  fail "배포 모드는 깨끗한 Git 작업 트리에서만 실행할 수 있습니다. 로컬 변경을 먼저 정리하세요."
fi

RELEASE_BUILD_ROOT="${PROJECT_ROOT}/.build/release"
DERIVED_DATA_PATH="${RELEASE_BUILD_ROOT}/DerivedData"
OUTPUT_PARENT="${PROJECT_ROOT}/dist/release/${VERSION}/${ARCH}/${MODE}"
OUTPUT_DIR="${OUTPUT_PARENT}/${ARTIFACT_SHA}"
ARTIFACT_BASE="deepK-${MODE}-${VERSION}-${ARCH}-${ARTIFACT_SHA}"

if path_exists "$OUTPUT_DIR"; then
  fail "동일한 Release 출력이 이미 있습니다. 덮어쓰지 않습니다: $OUTPUT_DIR"
fi

mkdir -p "$RELEASE_BUILD_ROOT"
STAGING_DIR="$(mktemp -d "${RELEASE_BUILD_ROOT}/package-staging.XXXXXX")"
trap cleanup EXIT

XCODEBUILD_ARGS=(
  -project "$PROJECT_FILE"
  -scheme DeepK
  -configuration Release
  -sdk macosx
  -derivedDataPath "$DERIVED_DATA_PATH"
  "MACOSX_DEPLOYMENT_TARGET=${MINIMUM_MACOS}"
  "MARKETING_VERSION=${VERSION}"
  "CURRENT_PROJECT_VERSION=${BUILD_NUMBER}"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=
  ONLY_ACTIVE_ARCH=NO
)
case "$ARCH" in
  arm64)
    XCODEBUILD_ARGS+=(ARCHS=arm64)
    ;;
  x86_64)
    XCODEBUILD_ARGS+=(ARCHS=x86_64)
    ;;
  universal)
    XCODEBUILD_ARGS+=("ARCHS=arm64 x86_64")
    ;;
esac

printf 'Release 빌드 중: version=%s arch=%s mode=%s\n' "$VERSION" "$ARCH" "$MODE"
xcodebuild "${XCODEBUILD_ARGS[@]}" build

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/DeepK.app"
[[ -d "$APP_PATH" ]] || fail "Release 앱을 찾을 수 없습니다: $APP_PATH"
[[ -x "$APP_PATH/Contents/MacOS/DeepK" ]] \
  || fail "Release 실행 파일을 찾을 수 없습니다: $APP_PATH/Contents/MacOS/DeepK"
validate_app_metadata "$APP_PATH"

STAGED_APP="${STAGING_DIR}/DeepK.app"
ditto "$APP_PATH" "$STAGED_APP"

NOTARY_RESULT=""
NOTARY_STATUS="not-run"
SIGNING_STATUS="ad-hoc"
if [[ "$MODE" == distribution ]]; then
  SIGNING_STATUS="Developer ID Application"
  printf 'Developer ID 서명 중 (identity 값은 출력하지 않음)\n'
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$DEVELOPER_ID" \
    "$STAGED_APP"
  codesign --verify --deep --strict "$STAGED_APP"

  SUBMISSION_ZIP="${STAGING_DIR}/${ARTIFACT_BASE}.notarization.zip"
  ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$SUBMISSION_ZIP"

  NOTARY_RESULTS_ROOT="${RELEASE_BUILD_ROOT}/notary-results"
  mkdir -p "$NOTARY_RESULTS_ROOT"
  NOTARY_RESULT_DIR="$(mktemp -d "${NOTARY_RESULTS_ROOT}/${ARTIFACT_BASE}.XXXXXX")"
  NOTARY_RESULT="${NOTARY_RESULT_DIR}/result.json"

  printf 'Apple 공증 제출 중 (Keychain 프로필 이름과 자격 증명은 출력하지 않음)\n'
  if ! xcrun notarytool submit "$SUBMISSION_ZIP" \
    --wait \
    --timeout "$NOTARY_TIMEOUT" \
    --output-format json \
    --keychain-profile "$NOTARY_PROFILE" \
    >"$NOTARY_RESULT"; then
    fail "Apple 공증 제출 또는 대기가 실패했습니다. JSON 결과를 보존했습니다: $NOTARY_RESULT"
  fi
  NOTARY_STATUS="$(plutil -extract status raw -o - "$NOTARY_RESULT" 2>/dev/null || true)"
  [[ "$NOTARY_STATUS" == Accepted ]] \
    || fail "Apple 공증 상태가 Accepted가 아닙니다: ${NOTARY_STATUS:-unknown}. JSON 결과를 보존했습니다: $NOTARY_RESULT"

  xcrun stapler staple "$STAGED_APP"
  xcrun stapler validate "$STAGED_APP"
  spctl --assess --type execute --verbose=4 "$STAGED_APP"
else
  printf '로컬 ad-hoc 서명 중 (Developer ID 서명·공증용이 아님)\n'
  codesign --force --sign - --timestamp=none "$STAGED_APP"
  codesign --verify --deep --strict "$STAGED_APP"
fi

FINAL_ZIP="${STAGING_DIR}/${ARTIFACT_BASE}.zip"
ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$FINAL_ZIP"

ZIP_SHA256="$(shasum -a 256 "$FINAL_ZIP" | awk '{print $1}')"
[[ "$ZIP_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || fail "ZIP SHA-256을 계산하지 못했습니다."
CHECKSUM_FILE="${STAGING_DIR}/${ARTIFACT_BASE}.sha256"
printf '%s  %s\n' "$ZIP_SHA256" "$(basename "$FINAL_ZIP")" > "$CHECKSUM_FILE"

MANIFEST_FILE="${STAGING_DIR}/${ARTIFACT_BASE}.manifest.json"
CREATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
cat > "$MANIFEST_FILE" <<MANIFEST
{
  "app": "deepK",
  "bundle_identifier": "com.deepk.app",
  "version": "${VERSION}",
  "build_number": "${BUILD_NUMBER}",
  "commit": "${SOURCE_COMMIT}",
  "dirty": ${DIRTY},
  "architecture": "${ARCH}",
  "minimum_macos": "${MINIMUM_MACOS}",
  "mode": "${MODE}",
  "signing": "${SIGNING_STATUS}",
  "notary_status": "${NOTARY_STATUS}",
  "zip": "$(basename "$FINAL_ZIP")",
  "zip_sha256": "${ZIP_SHA256}",
  "created_at_utc": "${CREATED_AT}"
}
MANIFEST

mkdir -p "$OUTPUT_PARENT"
FINAL_STAGING_DIR="$(mktemp -d "${OUTPUT_PARENT}/.staging.XXXXXX")"
cp "$FINAL_ZIP" "$FINAL_STAGING_DIR/$(basename "$FINAL_ZIP")"
cp "$CHECKSUM_FILE" "$FINAL_STAGING_DIR/$(basename "$CHECKSUM_FILE")"
cp "$MANIFEST_FILE" "$FINAL_STAGING_DIR/$(basename "$MANIFEST_FILE")"
if [[ -n "$NOTARY_RESULT" ]]; then
  cp "$NOTARY_RESULT" "$FINAL_STAGING_DIR/$(basename "$NOTARY_RESULT")"
fi

if path_exists "$OUTPUT_DIR"; then
  fail "동일한 Release 출력이 생성되는 동안 발견되었습니다. 덮어쓰지 않습니다: $OUTPUT_DIR"
fi
mv "$FINAL_STAGING_DIR" "$OUTPUT_DIR"
FINAL_STAGING_DIR=""

printf '패키징 완료: %s\n' "$OUTPUT_DIR"
if [[ "$MODE" == local ]]; then
  printf '로컬 모드: ad-hoc 서명만 했고 공증하지 않았습니다. 배포 가능한 파일로 표시하지 마세요.\n'
else
  printf '배포 모드: Developer ID 서명, 공증 Accepted, stapler 및 Gatekeeper 검증을 완료했습니다.\n'
fi
