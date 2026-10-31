#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_ROOT="${1:-$PROJECT_ROOT}"
OUTPUT="${2:-$PROJECT_ROOT/.build/permission-evidence/after.png}"
RENDER_DIR="$(mktemp -d /private/tmp/deepk-permission-render.XXXXXX)"
trap 'rm -rf -- "$RENDER_DIR"' EXIT
mkdir -p "$(dirname "$OUTPUT")"
# 기존 ref의 private 멤버도 같은 렌더러로 확인한다. 접근 범위만 열고 화면 동작은 바꾸지 않는다.
sed 's/private var permissionPopover: some View/var permissionPopover: some View/' \
  "$SOURCE_ROOT/DeepK/Settings/FinalSettingsView.swift" > "$RENDER_DIR/FinalSettingsView.swift"
SOURCES=()
while IFS= read -r source_path; do
  SOURCES+=("$SOURCE_ROOT/$source_path")
done < <(cd "$SOURCE_ROOT" && rg --files DeepK -g '*.swift' -g '!DeepKApp.swift' -g '!FinalSettingsView.swift')
swiftc -swift-version 6 -warnings-as-errors -parse-as-library -module-cache-path "$RENDER_DIR/cache" \
  "${SOURCES[@]}" "$RENDER_DIR/FinalSettingsView.swift" \
  "$PROJECT_ROOT/DeepKTests/Fixtures/PermissionRecoverySnapshot.swift" -o "$RENDER_DIR/render"
"$RENDER_DIR/render" "$OUTPUT"
