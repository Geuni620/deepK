#!/usr/bin/env bash
# 실제 ~/.codex 설정으로 deepK 번역 요청 본문을 캡처하고 계획 4·5절 기준으로 검사한다.
# 모델 요청은 로컬 가짜 Responses 서버로만 가므로 구독 사용량을 쓰지 않는다.
# 계정 확인(account/read)·모델 목록(model/list)과 Codex가 스스로 하는 조회(사용 한도 등)는 실제 계정으로 나간다.
# 이 접속 호스트는 보고서의 outboundHosts에 남는다.
#
#   ./scripts/capture-codex-request.sh [--codex <경로>] [--model <모델>] [--output <report.json>]
#
# --codex를 생략하면 앱과 같은 순서(codexExecutablePath → CODEX_EXECUTABLE → 설치 위치 → PATH → 앱 번들)로 찾는다.
# --model을 생략하면 앱 설정(com.deepk.app)의 Codex 모델로 캡처하고, 기본 모델과 다르면 기본 모델도 함께 캡처한다.
# 짧은 JSON은 표준 출력, 전체 보고서는 --output(기본: 캡처 디렉터리의 report.json)에 쓴다.
# 기준을 하나라도 넘으면 exit 1이다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER_ARGS=()
REPORT_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --codex|--model)
      [[ $# -ge 2 ]] || { echo "$1에 값이 필요합니다." >&2; exit 64; }
      HELPER_ARGS+=("$1" "$2"); shift 2 ;;
    --output)
      [[ $# -ge 2 ]] || { echo "--output에 경로가 필요합니다." >&2; exit 64; }
      REPORT_PATH="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 64 ;;
  esac
done

RUN_DIR="$(mktemp -d /private/tmp/deepk-codex-capture.XXXXXX)"
REPORT_PATH="${REPORT_PATH:-$RUN_DIR/report.json}"
echo "캡처: $RUN_DIR" >&2
swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$RUN_DIR/cache" -parse-as-library \
  "$PROJECT_ROOT/DeepK/Translation/CodexTranslationClient.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationLiteralPlan.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationProvider.swift" \
  "$SCRIPT_DIR/capture-codex-request.swift" -o "$RUN_DIR/capture"

# ~/.codex에는 쓰지 않는다. Codex가 일회성 스레드에서 스스로 쓰는 파일만 전후 목록 비교로 기록한다.
python3 "$SCRIPT_DIR/capture-codex-request.py" snapshot "$RUN_DIR/codex-home-before.json"
helper_status=0
"$RUN_DIR/capture" "$SCRIPT_DIR/capture-codex-request.py" "$RUN_DIR" ${HELPER_ARGS[@]+"${HELPER_ARGS[@]}"} || helper_status=$?
python3 "$SCRIPT_DIR/capture-codex-request.py" snapshot "$RUN_DIR/codex-home-after.json"
if [[ "$helper_status" -ne 0 ]]; then
  echo "캡처 실행이 실패했습니다(exit $helper_status)." >&2
  exit "$helper_status"
fi
python3 "$SCRIPT_DIR/capture-codex-request.py" report "$RUN_DIR" "$REPORT_PATH"
