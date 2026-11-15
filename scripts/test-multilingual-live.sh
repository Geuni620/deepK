#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ "${1:-}" != --live || ( $# -ne 2 && $# -ne 3 ) ]]; then
  echo 'Usage: bash scripts/test-multilingual-live.sh --live <result.json>' >&2
  echo 'Opt-in only: up to 66 existing-subscription translation requests; Claude may add one bounded duration revision; no API or retry loop.' >&2
  exit 2
fi
if [[ $# -eq 3 && "$3" != claude && "$3" != codex ]]; then
  echo 'Optional third argument must be claude or codex.' >&2; exit 2
fi
BUILD_DIR="$PROJECT_ROOT/.build/language-checks"
mkdir -p "$BUILD_DIR"
swiftc -parse-as-library -swift-version 6 -warnings-as-errors -module-cache-path "$BUILD_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/CodexTranslationClient.swift" \
  "$PROJECT_ROOT/DeepK/Translation/ClaudeTranslationClient.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationLiteralPlan.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationProvider.swift" \
  "$PROJECT_ROOT/DeepKTests/Fixtures/MultilingualLiveProbe.swift" -o "$BUILD_DIR/MultilingualLiveProbe"
if [[ $# -eq 3 ]]; then
  "$BUILD_DIR/MultilingualLiveProbe" --live "$PROJECT_ROOT/benchmarks/ja-zh-samples.json" "$2" "$3"
else
  "$BUILD_DIR/MultilingualLiveProbe" --live "$PROJECT_ROOT/benchmarks/ja-zh-samples.json" "$2"
fi
