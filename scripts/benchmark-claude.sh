#!/usr/bin/env bash
set -euo pipefail

# Claude Code 번역 경로(one-shot json, stream, 대기 프로세스)의 지연을 arm별로 교차 실측한다.
# 구독 쿼터를 쓰므로 DEEPK_RUN_LIVE_BENCHMARK=1을 명시해야 실행한다.
#
#   DEEPK_RUN_LIVE_BENCHMARK=1 ./scripts/benchmark-claude.sh [results.json] [--] [options...]
#   DEEPK_RUN_LIVE_BENCHMARK=1 ./scripts/benchmark-claude.sh --dry-run --arms baseline-json,stream-warm
#
# 표본 파일은 BENCHMARK_SAMPLES_PATH로 바꿀 수 있다(기본값 benchmarks/translation-samples.json).
# 결과 경로를 생략하면 benchmarks/runs/<UTC 시각>-claude.json에 쓴다. 옵션은 --help를 참고한다.
# 코드 블록 표본은 BENCHMARK_SAMPLES_PATH=benchmarks/codeblock-samples.json처럼 지정한다.
if [[ "${DEEPK_RUN_LIVE_BENCHMARK:-}" != "1" ]]; then
  echo "The Claude benchmark sends subscription requests. Set DEEPK_RUN_LIVE_BENCHMARK=1 explicitly (add --dry-run to print the schedule only)." >&2
  exit 64
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CACHE_DIR="${BENCHMARK_CACHE_DIR:-/private/tmp/deepk-claude-benchmark-cache}"

RESULTS_PATH=""
if [[ $# -gt 0 && "$1" != -* ]]; then
  RESULTS_PATH="$1"
  shift
fi
if [[ $# -gt 0 && "$1" == "--" ]]; then
  shift
fi
RESULTS_PATH="${RESULTS_PATH:-${PROJECT_ROOT}/benchmarks/runs/$(date -u +%Y%m%dT%H%M%SZ)-claude.json}"
if [[ -e "$RESULTS_PATH" ]]; then
  echo "Result file already exists; choose a new path: $RESULTS_PATH" >&2
  exit 1
fi

mkdir -p "${CACHE_DIR}" "$(dirname "${RESULTS_PATH}")"
BINARY_PATH="${BENCHMARK_BINARY_PATH:-$(mktemp -d /private/tmp/deepk-claude-benchmark.XXXXXX)/benchmark-claude}"

swiftc \
  -swift-version 6 \
  -warnings-as-errors \
  -module-cache-path "${CACHE_DIR}" \
  "${PROJECT_ROOT}/DeepK/Translation/ClaudeTranslationClient.swift" \
  "${PROJECT_ROOT}/DeepK/Translation/TranslationProvider.swift" \
  "${PROJECT_ROOT}/DeepK/Translation/TranslationOutputLint.swift" \
  "${SCRIPT_DIR}/benchmark-claude.swift" \
  -o "${BINARY_PATH}"

SOURCE_REVISION="$(git -C "${PROJECT_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git -C "${PROJECT_ROOT}" status --porcelain -- DeepK/Translation/ClaudeTranslationClient.swift DeepK/Translation/TranslationProvider.swift DeepK/Translation/TranslationOutputLint.swift scripts/benchmark-claude.swift 2>/dev/null)" ]]; then
  SOURCE_REVISION="${SOURCE_REVISION}-dirty"
fi
SAMPLES_PATH="${BENCHMARK_SAMPLES_PATH:-${PROJECT_ROOT}/benchmarks/translation-samples.json}"
CLIENT_SHA256="$(shasum -a 256 "${PROJECT_ROOT}/DeepK/Translation/ClaudeTranslationClient.swift" | awk '{print $1}')"
LINT_SHA256="$(shasum -a 256 "${PROJECT_ROOT}/DeepK/Translation/TranslationOutputLint.swift" | awk '{print $1}')"
SAMPLES_SHA256="$(shasum -a 256 "${SAMPLES_PATH}" | awk '{print $1}')"

"${BINARY_PATH}" \
  "${SAMPLES_PATH}" \
  "${RESULTS_PATH}" \
  --source-revision "${SOURCE_REVISION}" \
  --client-sha256 "${CLIENT_SHA256}" \
  --lint-sha256 "${LINT_SHA256}" \
  --samples-sha256 "${SAMPLES_SHA256}" \
  "$@"
