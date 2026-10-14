#!/bin/bash
# CloudKit requires a provisioned bundle; both build entries use this pipeline.
# Every bundle it produces is a release for any Mac, not for a list of registered machines:
# Developer ID Application signature, the Developer ID (direct distribution) provisioning
# profile that carries iCloud and no device list, hardened runtime, secure timestamp
# (cloud-project.yml). Installing additionally requires an Accepted Apple notarization and a
# stapled ticket. There is no development-signed or ad hoc way into /Applications.
#   ./build-cloud.sh                 build, selftest, checks, notarize, staple, install
#   ./build-cloud.sh --build-only    stop after the checks (acceptance builds; not notarized)
#   ./build-cloud.sh --install-only  notarize, staple and install what --build-only left for this commit
#   ./build-cloud.sh --compile-only  Mini compilation for a separate signing-Mac step; never installs
#   ./build-cloud.sh --check-only    verify a transferred Developer ID product, without installing
#   ./build-cloud.sh --install-local explicitly authorized local iteration, signed checks, no notarization
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-}"
case "$MODE" in ''|--build-only|--install-only|--compile-only|--check-only|--install-local) ;; *) echo "Usage: $0 [--build-only|--install-only|--compile-only|--check-only|--install-local]" >&2; exit 2 ;; esac
GRADE="$HOME/Dev/tools/dev/lib/tools/macapp/distribution_grade.py"
source "$HOME/Dev/tools/dev/lib/tools/macapp/xcode_env.sh"
xcode_env_use macosx
source "$HOME/Dev/tools/dev/lib/tools/macapp/scrub_env.sh"
# This bundle needs the Developer ID Application identity and the Developer ID profile.
# Refuse before entering the SDK queue when the signing prerequisite is absent; unattended
# builds must never open an account/keychain authorization dialog, and never fall back to a
# development or ad hoc signature.
TEAM="$(sed -n 's/^ *DEVELOPMENT_TEAM: *//p' cloud-project.yml | head -1)"
if [[ "$MODE" != --compile-only && "$MODE" != --check-only && "$MODE" != --install-local ]] && ! security find-identity -v -p codesigning | grep -q "\"Developer ID Application: .*($TEAM)\""; then
  echo "No valid Developer ID Application identity for team $TEAM in this login keychain; build on the signing Mac." >&2
  exit 4
fi
mkdir -p build
# CLIP_DERIVED_DATA redirects the Xcode products (default .dd-cloud) for trial builds.
DD="${CLIP_DERIVED_DATA:-.dd-cloud}"
LOG="${CLIP_CLOUD_BUILD_LOG:-build/cloud-build.log}"
COUNT=$(git rev-list --count HEAD)
APP="$DD/Build/Products/Release/Clipbook.app"
if [[ "$MODE" != --install-only && "$MODE" != --check-only && "$MODE" != --install-local ]]; then
python3 "$HOME/Dev/tools/dev/lib/tools/macapp/check_codingkeys.py" .
# Manual signing needs the profile on this Mac; fetched (or created once) through the App
# Store Connect API. The shared venv has the token library; plain python3 suffices once cached.
PROFILE_PY="$HOME/Dev/.venv/bin/python"; [ -x "$PROFILE_PY" ] || PROFILE_PY=python3
if [ "$MODE" != --compile-only ]; then "$PROFILE_PY" scripts/developer-id-profile.py; fi
xcodegen generate --spec cloud-project.yml
# Release strips symbols before Xcode signs (Xcode runs strip -x -T); the dSYM beside
# the product keeps crash symbolication. Behaviour is unchanged; like an archive build,
# Xcode then omits the get-task-allow debugger entitlement.
# Use the shared sim_lane admission/queue while retaining this product's CloudKit
# signing pipeline. The generic Mac lane build strips entitlements and therefore
# cannot replace this build. Busy admission is temporary (75), never a build pass.
scrub_env_run python3 - "$DD" "$COUNT" "$MODE" <<'PY' > "$LOG" 2>&1 || { code=$?; tail -60 "$LOG"; exit "$code"; }
import os, pathlib, signal, subprocess, sys
sys.path.insert(0, str(pathlib.Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
import sim_lane

locks = sim_lane.lock_chain(f"clipbook:xcodebuild:{os.getpid()}")
child = None
def stop(signum, frame):
    raise KeyboardInterrupt
signal.signal(signal.SIGTERM, stop)
try:
    sim_lane.acquire(locks, None, lock_wait=120, load_wait=120,
                     max_load=sim_lane.max_load_default())
    command = ["xcodebuild", "-project", "Clipbook.xcodeproj", "-scheme", "Clipbook",
               "-destination", "platform=macOS,arch=arm64", "-configuration", "Release",
               "-derivedDataPath", sys.argv[1],
               f"CURRENT_PROJECT_VERSION={sys.argv[2]}", "-jobs", str(os.cpu_count() or 1),
               "DEPLOYMENT_POSTPROCESSING=YES", "STRIP_INSTALLED_PRODUCT=YES",
               "STRIP_STYLE=non-global", "build"]
    if sys.argv[3] == "--compile-only":
        command.append("CODE_SIGNING_ALLOWED=NO")
    print("sim_lane admitted: CloudKit Release build, parallel jobs", os.cpu_count() or 1, flush=True)
    # Xcode persists its inherited environment in build diagnostics. Keep only
    # the documented tool/OS inputs; shell credentials and Homebrew CC/CXX/CPATH
    # are neither required for this project nor safe to copy into build logs.
    env_keys = ("PATH", "HOME", "USER", "LOGNAME", "DEVELOPER_DIR", "TMPDIR",
                "SDKROOT", "LANG", "LC_ALL", "LC_CTYPE", "SSH_AUTH_SOCK")
    build_env = {key: os.environ[key] for key in env_keys if key in os.environ}
    try:
        child = subprocess.Popen(command, env=build_env, start_new_session=True)
        code = child.wait(timeout=900)
    except subprocess.TimeoutExpired:
        print("Clip build exceeded 900 seconds", file=sys.stderr)
        code = 124
except sim_lane.Busy as exc:
    print(str(exc), file=sys.stderr)
    code = 75
except KeyboardInterrupt:
    code = 130
finally:
    if child is not None and child.poll() is None:
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.wait()
    for lock in reversed(locks):
        lock.release()
sys.exit(code)
PY
fi
[ -x "$APP/Contents/MacOS/Clipbook" ] || { echo "No built bundle at $APP; run --build-only first" >&2; exit 1; }
"$APP/Contents/MacOS/Clipbook" --selftest
if [ "$MODE" = --compile-only ]; then echo "Compiled (not an installable product): $APP"; exit 0; fi
codesign --verify --deep --strict "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -q "^TeamIdentifier=$TEAM$" || { echo 'Developer team changed; refusing product' >&2; exit 4; }
# One shared verdict for what may enter /Applications or an update feed: Developer ID
# Application, hardened runtime, secure timestamp, no profile with a device list.
python3 "$GRADE" check --stage signed "$APP"
# The agent CLI is the same signed executable, linked inside the bundle; it must answer --help without any UI.
[ "$(readlink "$APP/Contents/Resources/bin/clip")" = "../../MacOS/Clipbook" ] || { echo 'Missing Contents/Resources/bin/clip link'; exit 1; }
"$APP/Contents/Resources/bin/clip" --help > /dev/null
python3 - "$APP" "$COUNT" <<'PY'
import pathlib, plistlib, subprocess, sys
app = pathlib.Path(sys.argv[1])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert str(info.get('CFBundleVersion')) == sys.argv[2], ('Bundle was built from another commit', info.get('CFBundleVersion'), sys.argv[2])
signed = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], check=True, capture_output=True)
entitlements = plistlib.loads(signed.stdout)
assert info.get('ClipCloudEnvironment') == 'Production', 'Release must use the App Store CloudKit environment'
assert entitlements.get('com.apple.developer.icloud-container-environment') == 'Production', 'Signed CloudKit environment must match iPhone App Store/TestFlight'
assert entitlements.get('com.apple.developer.icloud-container-identifiers') == ['iCloud.cyou.tianli.clip'], 'Signed CloudKit container changed'
assert not entitlements.get('com.apple.security.get-task-allow'), 'Release must not carry the debugger entitlement'
embedded = app / 'Contents/embedded.provisionprofile'
assert embedded.is_file(), 'Missing CloudKit provisioning profile'
profile = plistlib.loads(subprocess.run(['security', 'cms', '-D', '-i', str(embedded)], check=True, capture_output=True).stdout)
assert 'ProvisionedDevices' not in profile and profile.get('ProvisionsAllDevices') is True, 'Only the Developer ID profile (all devices, no device list) may ship'
PY
python3 - "$APP/Contents/Info.plist" <<'PY'
import pathlib, plistlib, re, sys
catalog = pathlib.Path('project.yaml').read_text()
info = plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
# The installed app name is the English brand (name_en); display_name is the bilingual registry label.
for fields, key in [(('name_en', 'display_name'), 'CFBundleDisplayName'), (('bundle_id',), 'CFBundleIdentifier')]:
    expected = next(m.group(1).strip() for f in fields if (m := re.search(r'^' + f + r':\s*([^#\n]+)', catalog, re.M)))
    assert info[key] == expected, (key, info[key], expected)
assert info['CFBundleName'] == info['CFBundleDisplayName']
assert info['CFBundleIconFile'] == 'AppIcon'
PY
if [[ "$MODE" = --build-only || "$MODE" = --check-only ]]; then echo "Built and signed: $APP"; exit 0; fi
# Submit to Apple, staple, and read back spctl "Notarized Developer ID". This runs outside the
# build queue (the wait is Apple's); a bundle that already carries its ticket is not resubmitted.
if [ "$MODE" != --install-local ]; then python3 "$GRADE" notarize "$APP"; fi
DEST=/Applications/Clip.app
if [ -e "$DEST" ]; then
  ARCHIVE="$HOME/.Trash/clip-pre-icloud-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$ARCHIVE"
  mv "$DEST" "$ARCHIVE/"
  echo "Previous bundle: $ARCHIVE/Clip.app"
fi
ditto "$APP" "$DEST"
codesign --verify --deep --strict "$DEST"
if [ "$MODE" = --install-local ]; then
  python3 "$GRADE" check --stage signed "$DEST"
else
  python3 "$GRADE" check "$DEST"
fi
echo "Installed: $DEST"
python3 scripts/install-cli.py "$DEST"
