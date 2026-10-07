#!/bin/bash
# `clip start` and `clip quit` for real, on a built or installed Clip.app: the in-bundle `clip` asks the system to start
# this very app in the background, waits until it reports ready, and then asks it to quit.
# The instance is isolated — its own CLIPBOOK_HOME, preferences suite and named pasteboard (CLIPBOOK_BACKGROUND=1) — and an
# isolated background instance stays out of the Dock and the menu bar: nothing comes on screen and the frontmost app does
# not change. The user's library, preferences, general pasteboard and frontmost app are compared before and after.
# Exit 75 while another Clip is running: the system would hand `start` to that one, and this test never reuses or quits it.
# Opt-in, like tests/test-runtime.sh (not part of --selftest). Usage: bash tests/test-start.sh <path/to/Clip.app>
set -euo pipefail
APP="${1:?usage: bash tests/test-start.sh <path/to/Clip.app>}"
APP="$(cd "$APP" && pwd -P)"
EXE="$APP/Contents/MacOS/Clipbook"
[ -x "$EXE" ] && [ -L "$APP/Contents/Resources/bin/clip" ] || { echo "FAIL: $APP is not a Clip.app with Contents/Resources/bin/clip"; exit 1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/clip-start-test.XXXXXX")"
SUITE="cyou.tianli.clipbook.start-test.$$"
cleanup() {
  # Whatever happened above, no instance this test started stays behind (only one using this test's data dir).
  for pid in $(pgrep -f "$EXE" 2>/dev/null || true); do
    if ps eww -p "$pid" 2>/dev/null | grep -q "CLIPBOOK_HOME=$WORK/home"; then kill "$pid" 2>/dev/null || true; fi
  done
  defaults delete "$SUITE" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Preferences/$SUITE.plist" "$HOME/Library/Preferences/$SUITE.pasteboard.plist"
  rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/bin" "$WORK/home"
ln -s "$APP/Contents/Resources/bin/clip" "$WORK/bin/clip"
source "$HOME/Dev/tools/dev/lib/tools/macapp/xcode_env.sh" >/dev/null 2>&1 && xcode_env_use macosx >/dev/null 2>&1 || true
printf 'import AppKit\nprint(NSPasteboard.general.changeCount)\n' > "$WORK/cc.swift"
xcrun swiftc -O "$WORK/cc.swift" -o "$WORK/changecount" 2>/dev/null
echo "Clip $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")) · $EXE · sha256 $(shasum -a 256 "$EXE" | cut -c1-16)"
CLIP="$WORK/bin/clip" EXE="$EXE" APP="$APP" CHANGECOUNT="$WORK/changecount" HOME_DIR="$WORK/home" SUITE="$SUITE" python3 - <<'PY'
import hashlib, json, os, re, subprocess, sys, time
clip, exe, app, home, suite = (os.environ[k] for k in ("CLIP", "EXE", "APP", "HOME_DIR", "SUITE"))
env = {k: v for k, v in os.environ.items() if not k.startswith("CLIPBOOK_")}
env.update(CLIPBOOK_HOME=home, CLIPBOOK_PREFERENCES_SUITE=suite, CLIPBOOK_BACKGROUND="1")
failures, passed = [], 0

def run(*args):
    p = subprocess.run([clip, *args, "--json"], env=env, capture_output=True, text=True, timeout=60)
    try: return p.returncode, json.loads(p.stdout)
    except ValueError: return p.returncode, {}

def check(ok, what, note=""):
    global passed
    if ok: passed += 1; print("  ✅ " + what)
    else: failures.append(what); print("  🔴 " + what + (f"（{note}）" if note else ""))

def sh(*args):
    return subprocess.run(args, capture_output=True, text=True).stdout

def alive(pid):
    try: os.kill(pid, 0); return True
    except OSError: return False

# What must not change: the user's own library, preferences, general pasteboard, and which app is in front.
real = os.path.expanduser("~/Library/Application Support/Clipbook")
def stamp(name):
    try: s = os.stat(os.path.join(real, name)); return (s.st_mtime_ns, s.st_size)
    except OSError: return None
def user_state():
    prefs = subprocess.run(["defaults", "export", "cyou.tianli.clipbook", "-"], capture_output=True).stdout
    return {"runtime-state.json": stamp("runtime-state.json"), "clipbook.sqlite3": stamp("clipbook.sqlite3"),
            "cloud-requests": stamp("cloud-requests"), "preferences": hashlib.sha256(prefs).hexdigest(),
            "pasteboard": sh(os.environ["CHANGECOUNT"]).strip()}
def front(): return sh("lsappinfo", "front").strip()

code, status = run("status")
if code != 0 or status.get("gui", {}).get("running") is not False:
    print(f"SKIP: 已有 Clip 在运行（pids {status.get('gui', {}).get('pids')}），系统会把 start 交给它；这条测试不借用也不退出别的 Clip")
    sys.exit(75)
before, front_before = user_state(), front()

code, started = run("start")
pids = started.get("pids") or []
pid = pids[0] if pids else 0
check(code == 0 and started.get("started") is True and started.get("already_running") is False and started.get("ready") is True
      and len(pids) == 1 and os.path.realpath(started.get("app_path", "")) == app,
      "clip start：系统在后台启动了 clip 所在的这个 App，它报告就绪", f"退出码 {code} {started.get('message', started)}")
command = sh("ps", "-o", "command=", "-p", str(pid)).strip() if pid else ""
check(command.startswith(exe) and "--background" in command.split(), "启动的进程就是这个包的可执行文件，带 --background（不出主窗口）", command)
try: reported = json.load(open(os.path.join(home, "runtime-state.json"))).get("pid")
except (OSError, ValueError): reported = None
check(pid and reported == pid, "启动的实例用的是这次测试的隔离数据目录（它把自己的 pid 报告在那里）", f"报告 {reported} / 进程 {pid}")
asn = sh("lsappinfo", "find", f"pid={pid}").strip() if pid else ""
kind = re.search(r'type="([^"]+)"', sh("lsappinfo", "info", asn) if asn else "")
check(kind is not None and kind.group(1) != "Foreground", "隔离的后台实例不进 Dock（系统登记的应用类型不是 Foreground）", kind.group(1) if kind else f"没有读到应用类型（{asn or '无 ASN'}）")
check(front() == front_before, "最前面的 App 没有变（不抢焦点）", f"{front_before} → {front()}")
code, s2 = run("status")
check(code == 0 and s2.get("gui", {}).get("running") is True and s2.get("gui", {}).get("pids") == [pid], "clip status 读到它在运行")
code, again = run("start")
check(code == 0 and again.get("started") is False and again.get("already_running") is True and again.get("pids") == [pid]
      and len(sh("pgrep", "-f", exe).split()) == 1, "再 clip start：已在运行，不再启动第二个")
code, dry = run("quit", "--dry-run")
check(code == 0 and dry.get("would_quit") is True and dry.get("pids") == [pid] and alive(pid), "clip quit --dry-run 认出要退出的是它，不发请求")

code, quit = run("quit")
check(code == 0 and quit.get("quit") is True and quit.get("was_running") is True and quit.get("pids") == [pid] and quit.get("app_running") is False
      and not alive(pid), "clip quit：它收到退出请求并结束", f"退出码 {code} {quit.get('message', quit)}")
code, s3 = run("status"); code2, idle = run("quit")
check(code == 0 and s3.get("gui", {}).get("running") is False and code2 == 0 and idle.get("was_running") is False and idle.get("quit") is False,
      "退出后 clip status 读到没在运行；再 clip quit 没有可退出的，退出 0")
after = user_state()
check(after == before and front() == front_before, "本人的库、偏好、通用剪贴板与最前面的 App 都没有变",
      "、".join(k for k in before if before[k] != after[k]) or f"{front_before} → {front()}")
print(f"clip start / quit 真实启动与退出：{passed} 项通过" if not failures else "clip start / quit 未通过：" + "、".join(failures))
sys.exit(1 if failures else 0)
PY
