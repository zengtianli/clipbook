#!/bin/bash
# CloudKit requires a provisioned bundle; both build entries use this pipeline.
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/Dev/tools/dev/lib/tools/macapp/xcode_env.sh"
xcode_env_use macosx
source "$HOME/Dev/tools/dev/lib/tools/macapp/scrub_env.sh"
mkdir -p build
python3 "$HOME/Dev/tools/dev/lib/tools/macapp/check_codingkeys.py" .
xcodegen generate --spec cloud-project.yml
COUNT=$(git rev-list --count HEAD)
scrub_env_run xcodebuild -project Clipbook.xcodeproj -scheme Clipbook \
  -destination 'platform=macOS,arch=arm64' -configuration Release \
  -derivedDataPath .dd-cloud -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$COUNT" \
  build > build/cloud-build.log 2>&1 || { tail -60 build/cloud-build.log; exit 1; }
APP=.dd-cloud/Build/Products/Release/Clipbook.app
"$APP/Contents/MacOS/Clipbook" --selftest
codesign --verify --deep --strict "$APP"
[ -f "$APP/Contents/embedded.provisionprofile" ] || { echo 'Missing CloudKit provisioning profile'; exit 1; }
if [ "${1:-}" = --build-only ]; then echo "Built: $APP"; exit 0; fi
DEST=/Applications/Clip.app
if [ -e "$DEST" ]; then
  ARCHIVE="$HOME/.Trash/clip-pre-icloud-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$ARCHIVE"
  mv "$DEST" "$ARCHIVE/"
fi
ditto "$APP" "$DEST"
codesign --verify --deep --strict "$DEST"
python3 - "$DEST/Contents/Info.plist" <<'PY'
import pathlib, plistlib, re, sys
catalog = pathlib.Path('catalog.yaml').read_text()
info = plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
for field, key in [('display_name', 'CFBundleDisplayName'), ('bundle_id', 'CFBundleIdentifier')]:
    expected = re.search(r'^' + field + r':\s*([^#\n]+)', catalog, re.M).group(1).strip()
    assert info[key] == expected, (key, info[key], expected)
assert info['CFBundleName'] == info['CFBundleDisplayName']
assert info['CFBundleIconFile'] == 'AppIcon'
PY
echo "Installed: $DEST"
