#!/usr/bin/env bash
set -euo pipefail

# 복사 캡처(dump-pasteboard.swift나 code-copy/capture.mjs가 저장한 .txt·.html 쌍)를 앱의 가져오기로 읽어 보여 준다.
# 요청을 보내지 않는다.
#   ./scripts/inspect-copied-source.sh /private/tmp/deepk-code-copy-live
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="$(mktemp -d /private/tmp/deepk-inspect-copied-source.XXXXXX)"

swiftc -swift-version 6 -warnings-as-errors -parse-as-library -module-cache-path "${BUILD_DIR}/cache" \
  "${PROJECT_ROOT}/DeepK/Translation/TranslationMarkup.swift" "${PROJECT_ROOT}/DeepK/Translation/TranslationLists.swift" \
  "${PROJECT_ROOT}/DeepK/Translation/CopiedMathNormalizer.swift" \
  "${PROJECT_ROOT}/DeepK/Translation/RichSourceImporter.swift" \
  "${SCRIPT_DIR}/inspect-copied-source.swift" -o "${BUILD_DIR}/inspect-copied-source"
"${BUILD_DIR}/inspect-copied-source" "$@"
