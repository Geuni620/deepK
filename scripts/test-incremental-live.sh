#!/usr/bin/env bash
set -euo pipefail
if [[ "${DEEPK_RUN_LIVE_TRANSLATION_TESTS:-}" != "1" ]]; then
  echo "Live verification uses six synthetic subscription requests. Set DEEPK_RUN_LIVE_TRANSLATION_TESTS=1 explicitly." >&2
  exit 64
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DIR="$(mktemp -d /private/tmp/deepk-incremental-live.XXXXXX)"
swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationStore.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationMarkup.swift" "$PROJECT_ROOT/DeepK/Translation/TranslationLists.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationDocument.swift" \
  "$PROJECT_ROOT/DeepK/Translation/IncrementalTranslationPlanner.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationOutputLint.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationOutputCheck.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaRepair.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaReading.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaReadingData.swift" \
  "$PROJECT_ROOT/DeepK/Translation/CodeBlockGuard.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationProvider.swift" \
  "$PROJECT_ROOT/DeepK/Translation/CodexTranslationClient.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationLiteralPlan.swift" \
  "$PROJECT_ROOT/DeepK/Translation/ClaudeTranslationClient.swift" \
  "$PROJECT_ROOT/DeepKTests/Fixtures/IncrementalTranslationSmoke.swift" -o "$TEST_DIR/smoke"
"$TEST_DIR/smoke" --synthetic-fixture
