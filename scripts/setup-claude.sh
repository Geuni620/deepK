#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
case "${1:-}" in
  "") APP_DOMAIN=com.deepk.app.dev ;;
  --installed) APP_DOMAIN=com.deepk.app ;;
  *) echo "사용법: ./scripts/setup-claude.sh [--installed] (기본: deepK Dev)" >&2; exit 2 ;;
esac
RUNTIME_DIR="${PROJECT_ROOT}/.build/claude-runtime"
case "$(uname -m)" in
  arm64) platform=darwin-arm64 ;;
  x86_64) platform=darwin-x64 ;;
  *) echo "지원하지 않는 Mac 아키텍처입니다." >&2; exit 1 ;;
esac
npm install --prefix "$RUNTIME_DIR" --no-audit --no-fund --ignore-scripts @anthropic-ai/claude-code@2.1.278
CLI_PATH="${RUNTIME_DIR}/node_modules/@anthropic-ai/claude-code-${platform}/claude"
"$CLI_PATH" --version
defaults write "$APP_DOMAIN" claudeExecutablePath -string "$CLI_PATH"
echo "앱 전용 Claude CLI를 준비했습니다 ($APP_DOMAIN). 해당 앱을 다시 실행하고 설정에서 Claude Code를 선택하세요."
