#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ "${1:-}" != --live || $# -ne 2 ]]; then
  echo 'Usage: bash scripts/test-fidelity-holdouts.sh --live <result.json>' >&2
  echo 'Existing Claude subscription only: 9 translations, at most one duration revision each.' >&2
  exit 2
fi
BUILD_DIR="$PROJECT_ROOT/.build/language-checks"
mkdir -p "$BUILD_DIR"
swiftc -parse-as-library -swift-version 6 -warnings-as-errors -module-cache-path "$BUILD_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/ClaudeTranslationClient.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationProvider.swift" \
  "$PROJECT_ROOT/DeepKTests/Fixtures/MultilingualFidelityHoldouts.swift" -o "$BUILD_DIR/FidelityHoldouts"
"$BUILD_DIR/FidelityHoldouts" --live "$PROJECT_ROOT/benchmarks/ja-zh-fidelity-holdouts.json" "$2"
