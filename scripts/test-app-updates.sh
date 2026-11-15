#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
test_root="$(mktemp -d /private/tmp/deepk-update-test.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT
swiftc -swift-version 6 -warnings-as-errors -parse-as-library \
  -module-cache-path "$test_root/cache" \
  "$project_root/DeepK/Localization.swift" \
  "$project_root/DeepK/Settings/AppRelease.swift" \
  "$project_root/DeepK/Settings/AppUpdateController.swift" \
  "$project_root/DeepKTests/AppUpdateTests.swift" -o "$test_root/AppUpdateTests"
"$test_root/AppUpdateTests" "$@"
