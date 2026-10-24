#!/usr/bin/env bash
set -euo pipefail
if [[ "${DEEPK_RUN_GUI_TESTS:-}" != "1" ]]; then
  echo "GUI verification opens temporary windows. Run explicitly with DEEPK_RUN_GUI_TESTS=1." >&2
  exit 2
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_DIR="$(mktemp -d /private/tmp/deepk-input-test.XXXXXX)"
HOST_PID=""
cleanup() { if [[ -n "$HOST_PID" ]]; then kill "$HOST_PID" 2>/dev/null || true; fi; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/Translation/SourceEditor.swift" "$PROJECT_ROOT/DeepK/Translation/TranslationLists.swift" \
  "$PROJECT_ROOT/DeepKTests/Fixtures/SourceEditorIMESmoke.swift" -o "$TEST_DIR/ime"
"$TEST_DIR/ime"
swiftc -swift-version 6 -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepKTests/Fixtures/NativeTextHost.swift" -o "$TEST_DIR/deepk-test-host"
swiftc -swift-version 6 -warnings-as-errors -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/MacIntegration/DoubleCopyDetector.swift" \
  "$PROJECT_ROOT/DeepK/MacIntegration/DoubleCopyMonitor.swift" \
  "$PROJECT_ROOT/DeepK/Translation/CopiedMathNormalizer.swift" \
  "$PROJECT_ROOT/DeepKTests/Fixtures/DoubleCopyMonitorSmoke.swift" -o "$TEST_DIR/monitor"
"$TEST_DIR/deepk-test-host" --verification-fixture &
HOST_PID=$!
sleep 1
"$TEST_DIR/monitor"
