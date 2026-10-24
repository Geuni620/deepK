#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_ROOT="${DEEPK_FORMAT_SOURCE_ROOT:-$PROJECT_ROOT}"
BUILD_DIR="$(mktemp -d /private/tmp/deepk-format-preview.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT
SOURCES=(TranslationMarkup ResultClipboard ResultStyle ResultDisplaySettings CodeBlockChrome CodeFoldLayout
  SyntaxHighlighter SyntaxLanguages SourceEditor TranslationResultTextView CopiedMathNormalizer RichSourceImporter)
if [[ -f "$SOURCE_ROOT/DeepK/Translation/TranslationLists.swift" ]]; then SOURCES+=(TranslationLists); fi
SOURCE_PATHS=()
for source_name in "${SOURCES[@]}"; do SOURCE_PATHS+=("$SOURCE_ROOT/DeepK/Translation/$source_name.swift"); done
swiftc -swift-version 6 -warnings-as-errors -parse-as-library -module-cache-path "$BUILD_DIR/cache" \
  "${SOURCE_PATHS[@]}" "$PROJECT_ROOT/DeepKTests/Fixtures/FormatLayoutPreview.swift" -o "$BUILD_DIR/preview"
"$BUILD_DIR/preview" "$@"
