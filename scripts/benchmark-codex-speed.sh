#!/usr/bin/env bash
# Codex 번역 지연을 세 비교군(baseline, fast-off, fast-on)으로 교차 실측한다(계획 6절 2단계).
# 실제 Codex 구독으로 30 turn을 번역하므로 DEEPK_RUN_LIVE_BENCHMARK=1을 명시해야 실행한다.
#
#   DEEPK_RUN_LIVE_BENCHMARK=1 ./scripts/benchmark-codex-speed.sh [results.json] [--codex <경로>] [--model <모델>]
#   ./scripts/benchmark-codex-speed.sh --dry-run [--codex <경로>]   # 컴파일·실행 파일 확인·순서 출력만 한다
#
# - 기준선: DEEPK_BASELINE_REF(기본 84a24f0 = PR #42)의 CodexTranslationClient.swift를 액터 이름만 바꿔 함께 컴파일한다.
#   대기 스레드(setPrewarm)가 없는 기준선은 같은 준비 절차를 적용할 수 없어 거부한다.
# - 실행 파일: --codex 또는 CODEX_EXECUTABLE(CODEX_CLI_PATH)을 사용자 지정 경로로 엄격하게 검증해 세 비교군에 고정한다.
#   검증에 실패하면 다른 Codex로 넘어가지 않고 멈춘다. 둘 다 없으면 앱과 같은 탐색으로 한 번 고른다.
#   경로와 버전은 결과 JSON의 codex에 남는다.
# - 모델: --model → DEEPK_BENCHMARK_MODEL → 앱 설정(com.deepk.app의 Codex 모델, 읽기만 한다). 결과 JSON의 modelSource에 남는다.
# - 결과 경로를 생략하면 benchmarks/runs/<UTC 시각>-codex-speed.json에 쓴다. 출력 원문도 품질 대조용으로 저장한다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_PATH=""
DRY_RUN=0
BENCHMARK_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; BENCHMARK_ARGS+=("$1"); shift ;;
    --codex|--model)
      [[ $# -ge 2 ]] || { echo "$1에 값이 필요합니다." >&2; exit 64; }
      BENCHMARK_ARGS+=("$1" "$2"); shift 2 ;;
    -h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "알 수 없는 옵션: $1" >&2; exit 64 ;;
    *) [[ -z "$RESULTS_PATH" ]] || { echo "결과 경로는 하나만 지정합니다." >&2; exit 64; }
       RESULTS_PATH="$1"; shift ;;
  esac
done
if [[ "$DRY_RUN" -ne 1 && "${DEEPK_RUN_LIVE_BENCHMARK:-}" != "1" ]]; then
  echo "실제 Codex 구독으로 번역합니다. DEEPK_RUN_LIVE_BENCHMARK=1을 지정하세요(--dry-run은 번역하지 않습니다)." >&2
  exit 64
fi

BASELINE_REF="$(git -C "$PROJECT_ROOT" rev-parse --verify "${DEEPK_BASELINE_REF:-84a24f0}^{commit}")"
RESULTS_PATH="${RESULTS_PATH:-$PROJECT_ROOT/benchmarks/runs/$(date -u +%Y%m%dT%H%M%SZ)-codex-speed.json}"
if [[ "$DRY_RUN" -ne 1 && -e "$RESULTS_PATH" ]]; then
  echo "결과 파일이 이미 있습니다: $RESULTS_PATH" >&2
  exit 1
fi
RUN_DIR="$(mktemp -d /private/tmp/deepk-codex-speed.XXXXXX)"
git -C "$PROJECT_ROOT" show "$BASELINE_REF:DeepK/Translation/CodexTranslationClient.swift" \
  | sed 's/public actor CodexTranslationClient/public actor BaselineCodexTranslationClient/' > "$RUN_DIR/Baseline.swift"
if ! grep -q 'public func setPrewarm(model: String?' "$RUN_DIR/Baseline.swift"; then
  echo "기준선 ${BASELINE_REF}에는 setPrewarm(model:...)이 없습니다. PR #42(84a24f0) 이후 커밋을 지정하세요." >&2
  exit 64
fi
swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$RUN_DIR/cache" \
  "$RUN_DIR/Baseline.swift" \
  "$PROJECT_ROOT/DeepK/Translation/CodexTranslationClient.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationLiteralPlan.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationProvider.swift" \
  "$SCRIPT_DIR/benchmark-codex-speed.swift" -o "$RUN_DIR/benchmark"

SOURCE_REVISION="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain -- DeepK/Translation scripts/benchmark-codex-speed.swift 2>/dev/null)" ]]; then
  SOURCE_REVISION="${SOURCE_REVISION}-dirty"
fi
[[ "$DRY_RUN" -eq 1 ]] || mkdir -p "$(dirname "$RESULTS_PATH")"
"$RUN_DIR/benchmark" "$PROJECT_ROOT/benchmarks/translation-samples.json" "$RESULTS_PATH" "$BASELINE_REF" \
  --source-revision "$SOURCE_REVISION" ${BENCHMARK_ARGS[@]+"${BENCHMARK_ARGS[@]}"}
[[ "$DRY_RUN" -eq 1 ]] || echo "결과: $RESULTS_PATH"
