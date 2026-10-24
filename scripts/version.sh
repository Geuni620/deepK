#!/usr/bin/env bash

DEEPK_VERSION_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEEPK_APP_VERSION="${DEEPK_VERSION:-$(cat "$DEEPK_VERSION_ROOT/VERSION")}"
DEEPK_APP_BUILD="${DEEPK_BUILD_NUMBER:-$(git -C "$DEEPK_VERSION_ROOT" rev-list --count HEAD)}"
if [[ ! "$DEEPK_APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "DEEPK_VERSION은 0.1.0 형태의 숫자 버전이어야 합니다." >&2
  return 1
fi
if [[ ! "$DEEPK_APP_BUILD" =~ ^[1-9][0-9]*$ ]]; then
  echo "DEEPK_BUILD_NUMBER는 양의 정수여야 합니다." >&2
  return 1
fi
