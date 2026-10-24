#!/usr/bin/env bash
set -euo pipefail

# 저장된 벤치마크 출력에 번역 출력 검사기를 돌린다. 요청을 보내지 않는다.
# 원래 출력의 규칙별 결과에 더해 앱의 실행 중 판정(원문 반복 비율, 한자 치환 뒤 foreignScript)을 함께 보여 준다.
#   ./scripts/lint-benchmark-outputs.sh benchmarks/translation-samples-v2.json benchmarks/runs/<run>.json...
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="$(mktemp -d /private/tmp/deepk-lint-benchmark.XXXXXX)"

swiftc -swift-version 6 -warnings-as-errors -parse-as-library -module-cache-path "${BUILD_DIR}/cache" \
  "${PROJECT_ROOT}/DeepK/Translation/TranslationOutputLint.swift" \
  "${PROJECT_ROOT}/DeepK/Translation/HanjaReadingData.swift" \
  "${PROJECT_ROOT}/DeepK/Translation/HanjaReading.swift" \
  "${PROJECT_ROOT}/DeepK/Translation/HanjaRepair.swift" \
  "${PROJECT_ROOT}/DeepK/Translation/TranslationOutputCheck.swift" \
  "${SCRIPT_DIR}/lint-benchmark-outputs.swift" -o "${BUILD_DIR}/lint-benchmark-outputs"
"${BUILD_DIR}/lint-benchmark-outputs" "$@"
