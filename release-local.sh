#!/bin/bash
# Public local edition. The optional CloudKit development build stays separate.
set -euo pipefail
cd "$(dirname "$0")"
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh
xcode_env_use macosx
mkdir -p build/local-release
python3 /Users/tianli/Dev/tools/dev/lib/tools/macapp/check_codingkeys.py .
xcrun swiftc -O -parse-as-library -DCLIP_LOCAL_DISTRIBUTION \
  -target arm64-apple-macosx14.0 Sources/Native/*.swift Sources/ClipbookApp.swift \
  -o build/local-release/Clipbook
build/local-release/Clipbook --selftest
python3 scripts/package-local.py
codesign --force --sign - build/local-release/Clip.app
codesign --verify --deep --strict build/local-release/Clip.app
python3 scripts/package-local.py --archive
