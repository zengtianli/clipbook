#!/bin/bash
# Public local edition. The optional CloudKit development build stays separate.
# CLIP_LOCAL_RELEASE_DIR redirects all outputs (default build/local-release) so a
# trial build never overwrites the published download package.
set -euo pipefail
cd "$(dirname "$0")"
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh
xcode_env_use macosx
export CLIP_LOCAL_RELEASE_DIR="${CLIP_LOCAL_RELEASE_DIR:-build/local-release}"
OUT="$CLIP_LOCAL_RELEASE_DIR"
mkdir -p "$OUT"
python3 /Users/tianli/Dev/tools/dev/lib/tools/macapp/check_codingkeys.py .
xcrun swiftc -O -parse-as-library -DCLIP_LOCAL_DISTRIBUTION \
  -target arm64-apple-macosx14.0 Sources/Native/*.swift Sources/ClipbookApp.swift \
  -o "$OUT/Clipbook"
# Drop the local symbol table (about half the executable) before selftest and signing;
# behaviour is unchanged and the selftest below runs on the stripped binary.
strip -x "$OUT/Clipbook"
"$OUT/Clipbook" --selftest
python3 scripts/package-local.py
codesign --force --sign - "$OUT/Clip.app"
codesign --verify --deep --strict "$OUT/Clip.app"
python3 scripts/package-local.py --archive
