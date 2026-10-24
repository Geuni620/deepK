#!/usr/bin/env bash
set -euo pipefail

# Offline: no subscription client, login, windows or clipboard access.
# --strict fails on known unresolved cases; --report <path> writes a new JSON report.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FORMAT_TEST_DIR="$(mktemp -d /private/tmp/deepk-format-regression.XXXXXX)"
trap 'rm -rf "$FORMAT_TEST_DIR"' EXIT
FIXTURES_PATH="${DEEPK_FORMAT_FIXTURES_PATH:-$PROJECT_ROOT/DeepKTests/Fixtures/Formatting}"
BINARY_PATH="${DEEPK_FORMAT_REGRESSION_BINARY:-$FORMAT_TEST_DIR/FormatRegressions}"

SOURCES=(
  TranslationStore TranslationDocument IncrementalTranslationPlanner TranslationMarkup TranslationLists
  TranslationOutputLint TranslationOutputCheck HanjaRepair HanjaReading HanjaReadingData
  CodeBlockGuard CopiedMathNormalizer RichSourceImporter
)
SOURCE_PATHS=()
for source_name in "${SOURCES[@]}"; do
  SOURCE_PATHS+=("$PROJECT_ROOT/DeepK/Translation/$source_name.swift")
done
swiftc -swift-version 6 -warnings-as-errors -parse-as-library \
  -module-cache-path "$FORMAT_TEST_DIR/cache" \
  "${SOURCE_PATHS[@]}" "$PROJECT_ROOT/DeepKTests/FormatRegressionTests.swift" \
  -o "$BINARY_PATH"

"$BINARY_PATH" "$FIXTURES_PATH" "$@"
