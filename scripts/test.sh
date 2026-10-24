#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
bash "$SCRIPT_DIR/test-format-regressions.sh"
TEST_DIR="$(mktemp -d /private/tmp/deepk-unit-test.XXXXXX)"
# 결과 창을 컴파일하는 대상은 모두 이 파일들을 함께 쓴다.
RESULT_VIEW_SOURCES=(
  "$PROJECT_ROOT/DeepK/Translation/TranslationResultTextView.swift"
  "$PROJECT_ROOT/DeepK/Translation/TranslationMarkup.swift" "$PROJECT_ROOT/DeepK/Translation/TranslationLists.swift"
  "$PROJECT_ROOT/DeepK/Translation/ResultClipboard.swift"
  "$PROJECT_ROOT/DeepK/Translation/ResultStyle.swift"
  "$PROJECT_ROOT/DeepK/Translation/ResultDisplaySettings.swift"
  "$PROJECT_ROOT/DeepK/Translation/CodeBlockChrome.swift"
  "$PROJECT_ROOT/DeepK/Translation/CodeFoldLayout.swift"
  "$PROJECT_ROOT/DeepK/Translation/SyntaxHighlighter.swift"
  "$PROJECT_ROOT/DeepK/Translation/SyntaxLanguages.swift"
  "$PROJECT_ROOT/DeepK/Translation/SourceEditor.swift"
)
for suite in DoubleCopyDetector TranslationStore; do
  extra_sources=()
  case "$suite" in
    DoubleCopyDetector) source_dir=MacIntegration; flag=DOUBLE_COPY_DETECTOR_STANDALONE ;;
    TranslationStore)
      source_dir=Translation; flag=TRANSLATION_STORE_STANDALONE
      extra_sources+=("$PROJECT_ROOT/DeepK/Translation/TranslationDocument.swift" "$PROJECT_ROOT/DeepK/Translation/IncrementalTranslationPlanner.swift" "$PROJECT_ROOT/DeepK/Translation/TranslationMarkup.swift" "$PROJECT_ROOT/DeepK/Translation/TranslationLists.swift" "$PROJECT_ROOT/DeepKTests/IncrementalTranslationTests.swift")
      extra_sources+=(
        "$PROJECT_ROOT/DeepK/Translation/TranslationOutputLint.swift"
        "$PROJECT_ROOT/DeepK/Translation/TranslationOutputCheck.swift"
        "$PROJECT_ROOT/DeepK/Translation/HanjaRepair.swift"
        "$PROJECT_ROOT/DeepK/Translation/HanjaReading.swift"
        "$PROJECT_ROOT/DeepK/Translation/HanjaReadingData.swift"
        "$PROJECT_ROOT/DeepK/Translation/CodeBlockGuard.swift"
        "$PROJECT_ROOT/DeepK/Translation/RichSourceImporter.swift"
        "$PROJECT_ROOT/DeepK/Translation/CopiedMathNormalizer.swift"
        "$PROJECT_ROOT/DeepKTests/OutputCheckStoreTests.swift"
        "$PROJECT_ROOT/DeepKTests/CodeBlockStoreTests.swift"
      )
      ;;
  esac
  swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" -D"$flag" \
    "$PROJECT_ROOT/DeepK/$source_dir/$suite.swift" \
    ${extra_sources[@]+"${extra_sources[@]}"} \
    "$PROJECT_ROOT/DeepKTests/${suite}Tests.swift" -o "$TEST_DIR/$suite"
  "$TEST_DIR/$suite"
done

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationStore.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationDocument.swift" \
  "$PROJECT_ROOT/DeepK/Translation/IncrementalTranslationPlanner.swift" \
  "${RESULT_VIEW_SOURCES[@]}" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationOutputLint.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationOutputCheck.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaRepair.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaReading.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaReadingData.swift" \
  "$PROJECT_ROOT/DeepK/Translation/CodeBlockGuard.swift" \
  "$PROJECT_ROOT/DeepKTests/StableAppendIntegrationTests.swift" -o "$TEST_DIR/StableAppendIntegration"
"$TEST_DIR/StableAppendIntegration"

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" -DCODEX_TRANSLATION_STANDALONE \
  "$PROJECT_ROOT/DeepK/Translation/CodexTranslationClient.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationLiteralPlan.swift" \
  "$PROJECT_ROOT/DeepKTests/CodexTransportTests.swift" \
  "$PROJECT_ROOT/DeepKTests/CodexExecutableResolverTests.swift" -o "$TEST_DIR/CodexTransport"
(cd "$PROJECT_ROOT" && "$TEST_DIR/CodexTransport")

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationProvider.swift" \
  "$PROJECT_ROOT/DeepKTests/TranslationProviderTests.swift" -o "$TEST_DIR/TranslationProvider"
"$TEST_DIR/TranslationProvider"

swiftc -swift-version 6 -warnings-as-errors -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationOutputLint.swift" \
  "$PROJECT_ROOT/DeepKTests/TranslationOutputLintTests.swift" -o "$TEST_DIR/TranslationOutputLint"
"$TEST_DIR/TranslationOutputLint"

swiftc -swift-version 6 -warnings-as-errors -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationOutputLint.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaReadingData.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaReading.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaRepair.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationMarkup.swift" "$PROJECT_ROOT/DeepK/Translation/TranslationLists.swift" \
  "$PROJECT_ROOT/DeepKTests/HanjaRepairTests.swift" -o "$TEST_DIR/HanjaRepair"
"$TEST_DIR/HanjaRepair"

swiftc -swift-version 6 -warnings-as-errors -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationOutputLint.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaReadingData.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaReading.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaRepair.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationOutputCheck.swift" \
  "$PROJECT_ROOT/DeepKTests/TranslationOutputCheckTests.swift" -o "$TEST_DIR/TranslationOutputCheck"
"$TEST_DIR/TranslationOutputCheck"

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationMarkup.swift" "$PROJECT_ROOT/DeepK/Translation/TranslationLists.swift" \
  "$PROJECT_ROOT/DeepKTests/TranslationMarkupTests.swift" -o "$TEST_DIR/TranslationMarkup"
"$TEST_DIR/TranslationMarkup"

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/CopiedMathNormalizer.swift" \
  "$PROJECT_ROOT/DeepKTests/CopiedMathNormalizerTests.swift" -o "$TEST_DIR/CopiedMathNormalizer"
(cd "$PROJECT_ROOT" && "$TEST_DIR/CopiedMathNormalizer")

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationMarkup.swift" "$PROJECT_ROOT/DeepK/Translation/TranslationLists.swift" \
  "$PROJECT_ROOT/DeepK/Translation/CopiedMathNormalizer.swift" \
  "$PROJECT_ROOT/DeepK/Translation/RichSourceImporter.swift" \
  "$PROJECT_ROOT/DeepKTests/RichSourceImporterTests.swift" -o "$TEST_DIR/RichSourceImporter"
(cd "$PROJECT_ROOT" && "$TEST_DIR/RichSourceImporter")

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationMarkup.swift" "$PROJECT_ROOT/DeepK/Translation/TranslationLists.swift" \
  "$PROJECT_ROOT/DeepK/Translation/CodeBlockGuard.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationOutputLint.swift" \
  "$PROJECT_ROOT/DeepKTests/CodeBlockGuardTests.swift" -o "$TEST_DIR/CodeBlockGuard"
"$TEST_DIR/CodeBlockGuard"

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "${RESULT_VIEW_SOURCES[@]}" \
  "$PROJECT_ROOT/DeepKTests/Fixtures/ResultStyleFixtures.swift" \
  "$PROJECT_ROOT/DeepKTests/TranslationResultTextViewTests.swift" -o "$TEST_DIR/TranslationResultTextView"
"$TEST_DIR/TranslationResultTextView"

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/SourceEditor.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationStore.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationDocument.swift" \
  "$PROJECT_ROOT/DeepK/Translation/IncrementalTranslationPlanner.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationMarkup.swift" "$PROJECT_ROOT/DeepK/Translation/TranslationLists.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationOutputLint.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationOutputCheck.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaRepair.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaReading.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaReadingData.swift" \
  "$PROJECT_ROOT/DeepK/Translation/CodeBlockGuard.swift" \
  "$PROJECT_ROOT/DeepKTests/SourceEditorTests.swift" -o "$TEST_DIR/SourceEditor"
"$TEST_DIR/SourceEditor"

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationFooterState.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationStore.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationDocument.swift" \
  "$PROJECT_ROOT/DeepK/Translation/IncrementalTranslationPlanner.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationMarkup.swift" "$PROJECT_ROOT/DeepK/Translation/TranslationLists.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationOutputLint.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationOutputCheck.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaRepair.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaReading.swift" \
  "$PROJECT_ROOT/DeepK/Translation/HanjaReadingData.swift" \
  "$PROJECT_ROOT/DeepK/Translation/CodeBlockGuard.swift" \
  "$PROJECT_ROOT/DeepKTests/TranslationFooterStateTests.swift" -o "$TEST_DIR/TranslationFooterState"
"$TEST_DIR/TranslationFooterState"

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "${RESULT_VIEW_SOURCES[@]}" \
  "$PROJECT_ROOT/DeepKTests/Fixtures/ResultStyleFixtures.swift" \
  "$PROJECT_ROOT/DeepKTests/ResultStyleTests.swift" -o "$TEST_DIR/ResultStyle"
"$TEST_DIR/ResultStyle"

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Settings/CodeStylePickerModel.swift" \
  "$PROJECT_ROOT/DeepK/Translation/ResultStyle.swift" \
  "$PROJECT_ROOT/DeepK/Translation/ResultDisplaySettings.swift" \
  "$PROJECT_ROOT/DeepKTests/CodeStylePickerModelTests.swift" -o "$TEST_DIR/CodeStylePickerModel"
"$TEST_DIR/CodeStylePickerModel"

# 표시 탭과 코드 스타일 고르기 화면을 화면 밖에서 그린다. DEEPK_SETTINGS_SNAPSHOTS=<폴더>를 주면 PNG도 남긴다.
swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "${RESULT_VIEW_SOURCES[@]}" \
  "$PROJECT_ROOT/DeepK/Settings/CodeStylePickerModel.swift" \
  "$PROJECT_ROOT/DeepK/Settings/CodeStylePicker.swift" \
  "$PROJECT_ROOT/DeepKTests/Fixtures/ResultStyleFixtures.swift" \
  "$PROJECT_ROOT/DeepKTests/CodeStylePickerViewTests.swift" -o "$TEST_DIR/CodeStylePickerView"
"$TEST_DIR/CodeStylePickerView"

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/SyntaxHighlighter.swift" \
  "$PROJECT_ROOT/DeepK/Translation/SyntaxLanguages.swift" \
  "$PROJECT_ROOT/DeepKTests/SyntaxHighlighterTests.swift" -o "$TEST_DIR/SyntaxHighlighter"
"$TEST_DIR/SyntaxHighlighter"

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" -DCLAUDE_TRANSLATION_STANDALONE \
  "$PROJECT_ROOT/DeepK/Translation/ClaudeTranslationClient.swift" \
  "$PROJECT_ROOT/DeepK/Translation/TranslationProvider.swift" \
  "$PROJECT_ROOT/DeepKTests/ClaudeTransportTests.swift" -o "$TEST_DIR/ClaudeTransport"
(cd "$PROJECT_ROOT" && "$TEST_DIR/ClaudeTransport")

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/MacIntegration/DoubleCopyDetector.swift" \
  "$PROJECT_ROOT/DeepK/MacIntegration/DoubleCopyMonitor.swift" \
  "$PROJECT_ROOT/DeepK/Translation/CopiedMathNormalizer.swift" \
  "$PROJECT_ROOT/DeepKTests/DoubleCopyMonitorPermissionTests.swift" -o "$TEST_DIR/MonitorPermission"
"$TEST_DIR/MonitorPermission"

APP_SOURCES=()
while IFS= read -r source_path; do
  APP_SOURCES+=("$PROJECT_ROOT/$source_path")
done < <(cd "$PROJECT_ROOT" && rg --files DeepK -g '*.swift' -g '!DeepKApp.swift')
swiftc -swift-version 6 -warnings-as-errors -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "${APP_SOURCES[@]}" "$PROJECT_ROOT/DeepKTests/PermissionPresentationTests.swift" -o "$TEST_DIR/PermissionPresentation"
"$TEST_DIR/PermissionPresentation"

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/MacIntegration/WindowPresentation.swift" \
  "$PROJECT_ROOT/DeepKTests/WindowPresentationTests.swift" -o "$TEST_DIR/WindowPresentation"
"$TEST_DIR/WindowPresentation"

swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Settings/LoginItemController.swift" \
  "$PROJECT_ROOT/DeepKTests/LoginItemControllerTests.swift" -o "$TEST_DIR/LoginItemController"
"$TEST_DIR/LoginItemController"
