#!/usr/bin/env bash
set -euo pipefail
SAMPLE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SAMPLE_DIR/../../.." && pwd)"
RENDER_ENGINE="${REMOTION_ENGINE:-/Users/tianli/Dev/stations/apps/blog/pipelines/video}"
RENDER_CLI="$RENDER_ENGINE/node_modules/.bin/remotion"
RENDER_BROWSER="$RENDER_ENGINE/node_modules/.remotion/chrome-headless-shell/mac-arm64/chrome-headless-shell-mac-arm64/chrome-headless-shell"
cd "$SAMPLE_DIR"
python3 prepare.py
"$RENDER_CLI" render index.tsx ClipSample "$SAMPLE_DIR/sample.mp4" \
  --public-dir="$APP_DIR/build/ai-video-sample/public" \
  --browser-executable="$RENDER_BROWSER" --bundle-cache=false \
  --codec=h264 --crf=18 --pixel-format=yuv420p --concurrency=2 --muted --overwrite
ffmpeg -y -v error -ss 10.5 -i "$SAMPLE_DIR/sample.mp4" -frames:v 1 "$SAMPLE_DIR/poster.jpg"
