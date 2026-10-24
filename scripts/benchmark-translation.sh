#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CACHE_DIR="${BENCHMARK_CACHE_DIR:-/private/tmp/deepk-translation-benchmark-cache}"
BINARY_PATH="${BENCHMARK_BINARY_PATH:-/private/tmp/deepk-translation-benchmark}"
RESULTS_PATH="${1:-${PROJECT_ROOT}/benchmarks/runs/$(date -u +%Y%m%dT%H%M%SZ).json}"
if [[ -e "$RESULTS_PATH" ]]; then
  echo "Result file already exists; choose a new path: $RESULTS_PATH" >&2
  exit 1
fi

mkdir -p "${CACHE_DIR}" "$(dirname "${RESULTS_PATH}")"

swiftc \
  -swift-version 6 \
  -module-cache-path "${CACHE_DIR}" \
  "${PROJECT_ROOT}/DeepK/Translation/CodexTranslationClient.swift" \
  "${PROJECT_ROOT}/DeepK/Translation/TranslationLiteralPlan.swift" \
  "${SCRIPT_DIR}/benchmark-translation.swift" \
  -o "${BINARY_PATH}"

"${BINARY_PATH}" \
  "${PROJECT_ROOT}/benchmarks/translation-samples.json" \
  "${RESULTS_PATH}"

echo "Pilot results written to ${RESULTS_PATH}"
