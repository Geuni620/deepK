#!/usr/bin/env bash
set -euo pipefail

# 언어 넓히기와 '묻기'(번역 뒤 대화)의 오프라인 테스트만 빠르게 돌린다. 제공자·창·클립보드를 쓰지 않는다.
# 전체 검사는 ./scripts/test.sh다.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_DIR="$(mktemp -d /private/tmp/deepk-followup-test.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
T="$PROJECT_ROOT/DeepK/Translation"

echo "1/3 대화: 프롬프트·답변 흐름·창 위치"
swiftc -swift-version 6 -warnings-as-errors -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/FollowUp/FollowUpConversation.swift" "$PROJECT_ROOT/DeepK/FollowUp/FollowUpChat.swift" \
  "$PROJECT_ROOT/DeepKTests/FollowUpTests.swift" -o "$TEST_DIR/FollowUp"
"$TEST_DIR/FollowUp"

echo "2/3 언어: 감지·방향·칩·한국어 번역 언어 (TranslationStoreTests 전체)"
swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" -DTRANSLATION_STORE_STANDALONE \
  "$T/TranslationStore.swift" "$T/TranslationDocument.swift" "$T/IncrementalTranslationPlanner.swift" \
  "$T/TranslationMarkup.swift" "$T/TranslationLists.swift" "$PROJECT_ROOT/DeepKTests/IncrementalTranslationTests.swift" \
  "$T/TranslationOutputLint.swift" "$T/TranslationOutputCheck.swift" "$T/HanjaRepair.swift" "$T/HanjaReading.swift" \
  "$T/HanjaReadingData.swift" "$T/CodeBlockGuard.swift" "$T/RichSourceImporter.swift" "$T/CopiedMathNormalizer.swift" \
  "$PROJECT_ROOT/DeepKTests/OutputCheckStoreTests.swift" "$PROJECT_ROOT/DeepKTests/CodeBlockStoreTests.swift" \
  "$PROJECT_ROOT/DeepKTests/TranslationStoreTests.swift" -o "$TEST_DIR/TranslationStore"
"$TEST_DIR/TranslationStore" | grep -v '^Incremental test'

echo "3/3 감지 표 (오프라인)"
bash "$SCRIPT_DIR/try-languages.sh"
