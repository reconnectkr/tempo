#!/usr/bin/env bash
# Tempo 재빌드 + 재실행. 코드 수정 후 이 스크립트 한 번 실행하면
# 메뉴바에 떠 있던 기존 인스턴스를 끄고 최신 빌드로 다시 띄움.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="${TEMPO_CONFIG:-Debug}"

cd "$PROJECT_DIR"

echo "▶︎ Building Tempo ($CONFIG)…"
BUILD_OUTPUT=$(xcodebuild \
    -project Tempo.xcodeproj \
    -scheme Tempo \
    -configuration "$CONFIG" \
    -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')

xcodebuild \
    -project Tempo.xcodeproj \
    -scheme Tempo \
    -configuration "$CONFIG" \
    build >/dev/null

APP_PATH="$BUILD_OUTPUT/Tempo.app"
if [ ! -d "$APP_PATH" ]; then
    echo "✗ Build artifact not found at $APP_PATH" >&2
    exit 1
fi

echo "▶︎ Killing running Tempo…"
killall Tempo 2>/dev/null || true

echo "▶︎ Launching $APP_PATH"
open "$APP_PATH"

echo "✓ Done."
