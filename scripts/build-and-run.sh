#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$PROJECT_ROOT/.build/DerivedData/Build/Products/Debug/DeepK.app"

case "${1:-}" in
  --help|-h)
    echo "사용법: ./scripts/build-and-run.sh"
    echo "macOS 15 이상과 Xcode의 Swift 6 환경에서 deepK를 빌드하고 실행합니다."
    echo "실행 중인 deepK는 정상 종료하며, 빌드·서명 실패 시 실행하지 않습니다."
    exit 0
    ;;
  "") ;;
  *) echo "지원하지 않는 인자입니다. --help를 확인하세요." >&2; exit 2 ;;
esac

if [[ "$(uname -s)" != Darwin ]]; then
  echo "deepK는 macOS에서만 실행할 수 있습니다." >&2
  exit 1
fi
if (( $(sw_vers -productVersion | cut -d. -f1) < 15 )); then
  echo "macOS 15 이상이 필요합니다." >&2
  exit 1
fi
if ! xcodebuild -version >/dev/null 2>&1 || ! xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1; then
  echo "전체 Xcode를 설치하고 한 번 실행하여 초기 설정을 완료하세요." >&2
  echo "Command Line Tools만 선택되어 있다면 Xcode → Settings → Locations → Command Line Tools에서 Xcode를 선택하세요." >&2
  exit 1
fi
if ! xcrun swift --version | grep -Eq 'Swift version ([6-9]|[1-9][0-9]+)\.'; then
  echo "Swift 6 이상을 제공하는 Xcode가 필요합니다." >&2
  exit 1
fi

echo "실행 중인 deepK를 종료합니다. 현재 번역창 내용은 사라질 수 있습니다."
# 워크스페이스 별칭(심볼릭 링크) 이름이 바뀌어도 미리 컴파일된 헤더의 경로가 어긋나지 않도록 실제 경로를 쓴다.
LAUNCHER_CACHE="$(cd "$PROJECT_ROOT" && pwd -P)/.build/launcher-module-cache"
xcrun swift -module-cache-path "$LAUNCHER_CACHE" - <<'SWIFT'
import AppKit
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.deepk.app")
for app in apps { _ = app.terminate() }
let deadline = Date().addingTimeInterval(8)
while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
if apps.contains(where: { !$0.isTerminated }) {
    fputs("deepK가 종료되지 않았습니다. 메뉴 막대에서 종료한 뒤 다시 실행하세요.\n", stderr)
    exit(1)
}
SWIFT

bash "$SCRIPT_DIR/build.sh"
if [[ ! -x "$APP_PATH/Contents/MacOS/DeepK" ]]; then
  echo "빌드 결과를 찾을 수 없습니다: $APP_PATH" >&2
  exit 1
fi
open "$APP_PATH"
echo "deepK를 실행했습니다. 메뉴 막대의 ‘ㅋ’에서 열기·설정을 선택하세요."
echo "처음 사용하는 Mac에서는 Codex 또는 Claude Code 설치·구독 로그인과 macOS 권한 허용이 필요합니다."
echo "권한 설정에 추가할 앱: $APP_PATH"
