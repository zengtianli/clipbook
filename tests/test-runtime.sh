#!/bin/bash
# The running-app side of `clip`, on a built or installed Clip.app (this script never builds):
#   bash tests/test-runtime.sh <path/to/Clip.app>
# `Clipbook --runtime-self-test` is the running Clip (production AppDelegate wiring, activation policy .prohibited:
# no Dock icon, status item, window or focus change) while the real in-bundle `clip` runs beside it as separate
# processes; then, once that process has exited, `clip` is read again for the "Clip is not running" answers.
# Isolated data dir, preferences suite and 配置与更新 directories; the pasteboard watcher is not started and iCloud is
# never switched on. Opt-in: it registers ⌃⌥⇧⌘F20 / F19 as global hot keys for a few seconds.
set -euo pipefail
APP="${1:?usage: bash tests/test-runtime.sh <path/to/Clip.app>}"
APP="$(cd "$APP" && pwd)"
EXE="$APP/Contents/MacOS/Clipbook"; CLIP="$APP/Contents/Resources/bin/clip"
[ -x "$EXE" ] && [ -L "$CLIP" ] || { echo "FAIL: $APP is not a Clip.app with Contents/Resources/bin/clip"; exit 1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/clip-runtime-test.XXXXXX")"
SUITE="cyou.tianli.clipbook.runtime-test.$$"
cleanup() {
  defaults delete "$SUITE" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Preferences/$SUITE.plist"
  rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/home"
export CLIPBOOK_HOME="$WORK/home" CLIPBOOK_PREFERENCES_SUITE="$SUITE" CLIPBOOK_BACKGROUND=1
# The same directories the self-test sets for itself, so the reads after it has exited use them too.
export APP_LIFECYCLE_SUPPORT_DIR="$WORK/home/Lifecycle/support" APP_LIFECYCLE_CLOUD_DIR="$WORK/home/Lifecycle/cloud"
echo "Clip $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")) · $EXE · sha256 $(shasum -a 256 "$EXE" | cut -c1-16)"
set +e; "$EXE" --runtime-self-test > "$WORK/run.log" 2>&1; CODE=$?; set -e
cat "$WORK/run.log"
CLIP="$CLIP" CODE="$CODE" LOG="$WORK/run.log" python3 - <<'PY'
import json, os, subprocess, sys
clip, code = os.environ["CLIP"], int(os.environ["CODE"])
lines = [l for l in open(os.environ["LOG"], encoding="utf-8").read().splitlines() if l.startswith("{")]
try: summary = json.loads(lines[-1])
except Exception: summary = {"ok": False, "checks": {}}
checks = summary.get("checks") or {}
failed = [k for k, v in checks.items() if not v]

def read(*args):
    p = subprocess.run([clip, *args, "--json"], capture_output=True, text=True, timeout=30)
    try: return p.returncode, json.loads(p.stdout)
    except ValueError: return p.returncode, {}

# The app process has exited: what it last reported about the grant stays (marked not live); the rest is "not running".
after = []
def check(ok, what):
    after.append((what, bool(ok))); print(("PASS " if ok else "FAIL ") + what)
_, status = read("status")
grant = ((status.get("permissions") or {}).get("accessibility") or {})
check(status.get("gui", {}).get("running") is False and isinstance(grant.get("trusted"), bool) and grant.get("live") is False
      and isinstance(grant.get("as_of"), str), "App 退出后：status 给出它上次报告的授权结果，并标明不是实时")
_, keys = read("shortcut", "list")
rows = {r["action"]: r for r in keys.get("shortcuts", [])}
check(rows.get("toggleWindow", {}).get("registration") == "app_not_running" and rows.get("pause", {}).get("registration") == "app_not_running"
      and rows.get("toggleWindow", {}).get("status", "").startswith("已保存"), "App 退出后：全局键 registration 为 app_not_running，不再声称已启用")
_, cloud = read("cloud", "status")
check(cloud.get("live") is None and "未运行" in (cloud.get("live_status") or ""), "App 退出后：cloud status 的 live 为 null，写明 Clip 未运行")
ok = code == 0 and summary.get("ok") is True and checks and not failed and all(v for _, v in after)
total = len(checks) + len(after)
print(f"clip 运行态自检：{total} 项通过" if ok else "clip 运行态自检未通过：" + "、".join(failed + [w for w, v in after if not v] or [f"退出码 {code} / 无结果"]))
sys.exit(0 if ok else 1)
PY
