#!/usr/bin/env bash
set -euo pipefail

# 자동 언어 방향이 원문을 어떻게 읽는지 보여 준다: 감지한 언어와 번역 방향, 정하지 못하면 앱이 보여 줄 언어 칩.
# 제공자에 아무것도 보내지 않는다.
#
#   ./scripts/try-languages.sh                         # 여러 언어 예문
#   ./scripts/try-languages.sh "Привет мир" "Hola"     # 직접 넣은 원문
#   ./scripts/try-languages.sh --korean-target ja      # 한국어 원문을 日本語로 보낼 때
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="$(mktemp -d /private/tmp/deepk-try-languages.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT
T="$PROJECT_ROOT/DeepK/Translation"

swiftc -swift-version 6 -parse-as-library -module-cache-path "/private/tmp/deepk-try-cache" \
  "$T/TranslationStore.swift" "$T/TranslationDocument.swift" "$T/IncrementalTranslationPlanner.swift" \
  "$T/TranslationMarkup.swift" "$T/TranslationLists.swift" "$T/TranslationOutputLint.swift" "$T/TranslationOutputCheck.swift" \
  "$T/HanjaRepair.swift" "$T/HanjaReading.swift" "$T/HanjaReadingData.swift" "$T/CodeBlockGuard.swift" \
  "$T/RichSourceImporter.swift" "$T/CopiedMathNormalizer.swift" \
  "$SCRIPT_DIR/try-languages.swift" -o "$BUILD_DIR/try-languages"
"$BUILD_DIR/try-languages" "$@"
