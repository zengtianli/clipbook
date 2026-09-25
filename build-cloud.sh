#!/bin/bash
# CloudKit requires a provisioned bundle; both build entries use this pipeline.
set -euo pipefail
cd "$(dirname "$0")"
source "$HOME/Dev/tools/dev/lib/tools/macapp/xcode_env.sh"
xcode_env_use macosx
source "$HOME/Dev/tools/dev/lib/tools/macapp/scrub_env.sh"
mkdir -p build
# CLIP_DERIVED_DATA redirects the Xcode products (default .dd-cloud) for trial builds.
DD="${CLIP_DERIVED_DATA:-.dd-cloud}"
LOG="${CLIP_CLOUD_BUILD_LOG:-build/cloud-build.log}"
python3 "$HOME/Dev/tools/dev/lib/tools/macapp/check_codingkeys.py" .
xcodegen generate --spec cloud-project.yml
COUNT=$(git rev-list --count HEAD)
# Release strips symbols before Xcode signs (Xcode runs strip -x -T); the dSYM beside
# the product keeps crash symbolication. Behaviour is unchanged; like an archive build,
# Xcode then omits the get-task-allow debugger entitlement.
scrub_env_run xcodebuild -project Clipbook.xcodeproj -scheme Clipbook \
  -destination 'platform=macOS,arch=arm64' -configuration Release \
  -derivedDataPath "$DD" -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$COUNT" \
  DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES STRIP_STYLE=non-global \
  build > "$LOG" 2>&1 || { tail -60 "$LOG"; exit 1; }
APP="$DD/Build/Products/Release/Clipbook.app"
"$APP/Contents/MacOS/Clipbook" --selftest
codesign --verify --deep --strict "$APP"
python3 - "$APP" <<'PY'
import pathlib, plistlib, subprocess, sys
app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
signed = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], check=True, capture_output=True)
entitlements = plistlib.loads(signed.stdout)
assert info.get('ClipCloudEnvironment') == 'Production', 'Release must use the App Store CloudKit environment'
assert entitlements.get('com.apple.developer.icloud-container-environment') == 'Production', 'Signed CloudKit environment must match iPhone App Store/TestFlight'
PY
[ -f "$APP/Contents/embedded.provisionprofile" ] || { echo 'Missing CloudKit provisioning profile'; exit 1; }
python3 - "$APP/Contents/Info.plist" <<'PY'
import pathlib, plistlib, re, sys
catalog = pathlib.Path('project.yaml').read_text()
info = plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
for field, key in [('display_name', 'CFBundleDisplayName'), ('bundle_id', 'CFBundleIdentifier')]:
    expected = re.search(r'^' + field + r':\s*([^#\n]+)', catalog, re.M).group(1).strip()
    assert info[key] == expected, (key, info[key], expected)
assert info['CFBundleName'] == info['CFBundleDisplayName']
assert info['CFBundleIconFile'] == 'AppIcon'
PY
if [ "${1:-}" = --build-only ]; then echo "Built: $APP"; exit 0; fi
DEST=/Applications/Clip.app
if [ -e "$DEST" ]; then
  ARCHIVE="$HOME/.Trash/clip-pre-icloud-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$ARCHIVE"
  mv "$DEST" "$ARCHIVE/"
fi
ditto "$APP" "$DEST"
codesign --verify --deep --strict "$DEST"
echo "Installed: $DEST"
