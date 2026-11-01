#!/usr/bin/env bash
set -euo pipefail

# 원문을 앱의 자동 방향으로 번역한 뒤, '묻기' 창과 같은 프롬프트·같은 제공자 경로로 터미널에서 이어서 묻는다.
# 선택한 제공자의 구독 사용량을 쓴다. 기본 제공자·모델·실행 파일 경로는 deepK 앱 설정(com.deepk.app)을 따른다.
#
#   ./scripts/try-followup.sh "Retries use exponential backoff with jitter."
#   ./scripts/try-followup.sh --provider codex --file notes.txt
#   pbpaste | ./scripts/try-followup.sh            # 표준 입력에서 원문을 읽는다
#   ./scripts/try-followup.sh --help
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="$(mktemp -d /private/tmp/deepk-try-followup.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT
T="$PROJECT_ROOT/DeepK/Translation"

echo "빌드 중…" >&2
swiftc -swift-version 6 -parse-as-library -module-cache-path "/private/tmp/deepk-try-cache" \
  "$T/ClaudeTranslationClient.swift" "$T/CodexTranslationClient.swift" "$T/TranslationLiteralPlan.swift" \
  "$T/TranslationProvider.swift" \
  "$T/TranslationStore.swift" "$T/TranslationDocument.swift" "$T/IncrementalTranslationPlanner.swift" \
  "$T/TranslationMarkup.swift" "$T/TranslationLists.swift" "$T/TranslationOutputLint.swift" "$T/TranslationOutputCheck.swift" \
  "$T/HanjaRepair.swift" "$T/HanjaReading.swift" "$T/HanjaReadingData.swift" "$T/CodeBlockGuard.swift" \
  "$T/RichSourceImporter.swift" "$T/CopiedMathNormalizer.swift" \
  "$PROJECT_ROOT/DeepK/FollowUp/FollowUpConversation.swift" \
  "$SCRIPT_DIR/try-followup.swift" -o "$BUILD_DIR/try-followup"
"$BUILD_DIR/try-followup" "$@"
