#!/usr/bin/env bash
set -euo pipefail
if [[ "${DEEPK_RUN_GUI_TESTS:-}" != "1" ]]; then
  echo "GUI verification opens temporary windows. Run explicitly with DEEPK_RUN_GUI_TESTS=1." >&2
  exit 2
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_DIR="$(mktemp -d /private/tmp/deepk-session-test.XXXXXX)"
HOST_PID=""
cleanup() {
  if [[ -n "$HOST_PID" ]]; then kill "$HOST_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
swiftc -swift-version 6 -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepKTests/Fixtures/NativeTextHost.swift" -o "$TEST_DIR/deepk-test-host"
swiftc -swift-version 6 -parse-as-library -module-cache-path "$TEST_DIR/cache" \
  "$PROJECT_ROOT/DeepK/MacIntegration/InvocationSession.swift" \
  "$PROJECT_ROOT/DeepKTests/Fixtures/InvocationSessionSmoke.swift" -o "$TEST_DIR/session-smoke"
"$TEST_DIR/deepk-test-host" --verification-fixture &
HOST_PID=$!
sleep 1
"$TEST_DIR/session-smoke"
