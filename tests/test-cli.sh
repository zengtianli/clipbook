#!/bin/bash
# `clip` through its real entry: ~/.local/bin-style link → Clip.app/Contents/Resources/bin/clip → ../../MacOS/Clipbook
# (re-exec to the real executable, Bundle.main = the app). Every run is isolated: its own CLIPBOOK_HOME,
# preferences suite and named pasteboard (CLIPBOOK_BACKGROUND=1); the user's library, preferences and general
# pasteboard are never touched (the general pasteboard change count is compared before/after).
# Usage: bash tests/test-cli.sh [path/to/Clipbook.app]   (default: build the current source via scripts/accept/_build.sh)
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -n "${1:-}" ]; then APP="$1"; else source scripts/accept/_build.sh; fi
[ -L "$APP/Contents/Resources/bin/clip" ] || { echo "FAIL: $APP has no Contents/Resources/bin/clip link"; exit 1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/clip-cli-test.XXXXXX")"
SUITE="cyou.tianli.clipbook.cli-test.$$"
cleanup() {
  defaults delete "$SUITE" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Preferences/$SUITE.plist"
  rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/bin"
ln -s "$(cd "$APP" && pwd)/Contents/Resources/bin/clip" "$WORK/bin/clip"
source "$HOME/Dev/tools/dev/lib/tools/macapp/xcode_env.sh" >/dev/null 2>&1 && xcode_env_use macosx >/dev/null 2>&1 || true
printf 'import AppKit\nprint(NSPasteboard.general.changeCount)\n' > "$WORK/cc.swift"
xcrun swiftc -O "$WORK/cc.swift" -o "$WORK/changecount" 2>/dev/null
CLIP="$WORK/bin/clip" CHANGECOUNT="$WORK/changecount" HOME_DIR="$WORK/home" SUITE="$SUITE" WORK="$WORK" python3 - <<'PY'
import json, os, subprocess, sys, time
clip, work = os.environ["CLIP"], os.environ["WORK"]
env = {k: v for k, v in os.environ.items() if not k.startswith("CLIPBOOK_")}
env.update(CLIPBOOK_HOME=os.environ["HOME_DIR"], CLIPBOOK_PREFERENCES_SUITE=os.environ["SUITE"], CLIPBOOK_BACKGROUND="1")
failures, passed = [], 0

def run(*args, stdin=None):
    p = subprocess.run([clip, *args], env=env, input=stdin, capture_output=True, text=True, timeout=30)
    try: data = json.loads(p.stdout) if "--json" in args else None
    except ValueError: data = None
    return p.returncode, data, p

def check(ok, what):
    global passed
    if ok: passed += 1; print("  ✅ " + what)
    else: failures.append(what); print("  🔴 " + what)

def general():
    return subprocess.run([os.environ["CHANGECOUNT"]], capture_output=True, text=True).stdout.strip()

before_pb = general()
t0 = time.monotonic(); code, _, p = run("--help"); dt = time.monotonic() - t0
check(code == 0 and "usage: clip" in p.stdout and dt < 5, f"clip --help 退出 0（{dt*1000:.0f} ms，无界面）")
code, v, _ = run("--version", "--json")
check(code == 0 and v["ok"] and v["name"] == "Clip" and v["build"] not in ("", "unknown"), f"经链接重入真实可执行：{v and v['name']} {v and v['version']} ({v and v['build']})")
code, _, p = run("frobnicate"); check(code == 2 and "未知命令" in p.stderr, "未知命令退出 2")
for cmd in ["status", "stats", "list", "search", "show", "copy", "export", "add", "edit", "transform", "pin", "unpin", "delete",
            "merge", "clear", "collections", "collection", "settings", "ignore", "pause", "resume", "import-deck", "cloud"]:
    if run(cmd, "--help")[0] != 0: failures.append(f"{cmd} --help")
check(not [f for f in failures if f.endswith("--help")], "每个命令 --help 退出 0")

code, s, _ = run("status", "--json")
check(code == 0 and s["data"]["database_exists"] is False and not os.path.exists(os.environ["HOME_DIR"]), "status 只读：空目录不建库")
code, e, _ = run("list", "--json"); check(code == 3 and e["ok"] is False and e["error"] == "not_found", "无库 list → ok:false 退出 3")
code, a, _ = run("add", "--text", "hello from agent", "--json")
code2, a2, _ = run("add", "--text", "hello from agent", "--json")
check(code == 0 and code2 == 0 and a2["id"] == a["id"] and a2["deduplicated"] is True, "add 新增并去重")
code, s2, _ = run("add", "--stdin", "--json", stdin="line one\nline two")
check(code == 0 and s2["kind"] == "text", "add --stdin")
code, l, _ = run("list", "--json"); check(code == 0 and l["total"] == 2 and l["items"][0]["id"] == s2["id"], "list 顺序与总数")
code, sh, _ = run("show", str(a["id"]), "--json"); check(code == 0 and sh["item"]["text"] == "hello from agent" and sh["item"]["app_name"] == "Clip CLI", "show 全文与来源")
code, _, _ = run("transform", str(a["id"]), "upper", "--json"); code_s, sh2, _ = run("show", str(a["id"]), "--json")
check(code == 0 and sh2["item"]["text"] == "HELLO FROM AGENT", "transform 保存")
code, cp, _ = run("copy", str(a["id"]), "--json"); check(code == 0 and cp["copied"] == 1, "copy 写入隔离剪贴板")
code, m, _ = run("merge", str(a["id"]), str(s2["id"]), "--json"); check(code == 0 and m["parts"] == 2, "merge")
check(run("delete", str(m["id"]))[0] == 2 and run("delete", str(m["id"]), "--yes")[0] == 0 and run("show", str(m["id"]))[0] == 3, "delete 需 --yes，删后 show 退出 3")
code, c, _ = run("collection", "create", "agent", "--json"); check(code == 0 and run("collection", "add", "agent", str(a["id"]))[0] == 0, "收藏夹新建与加入")
check(run("settings", "set", "maxItems", "50")[0] == 2 and run("settings", "set", "maxItems", "800")[0] == 0, "设置范围校验与写入")
code, st, _ = run("settings", "--json"); check(st["settings"]["maxItems"] == 800 and st["settings"]["domain"] == os.environ["SUITE"], "设置写入隔离偏好域")
check(run("pause")[0] == 0 and run("status", "--json")[1]["recording"]["paused"] is True and run("resume")[0] == 0, "pause / resume")
check(run("clear")[0] == 2 and run("clear", "--yes", "--json")[1]["kept"] == 1, "clear 需 --yes，保留收藏夹里的")
code, bad, _ = run("collection", "create", "x", "--icon", "nosuch", "--json")
check(code == 2 and bad["ok"] is False and bad["command"] == "collection create", "失败时 JSON command 与成功相同（collection create）")
code, ed, _ = run("edit", str(a["id"]), "--title", "不应写入", "--text", "   ", "--json")
check(code == 2 and run("show", str(a["id"]), "--json")[1]["item"]["title"] == "", "edit 先校验再写：被拒绝时标题不变")
code, same, _ = run("edit", str(a["id"]), "--text", "HELLO FROM AGENT", "--json")
check(code == 0 and same["changed"] is False, "edit 正文未变不重写（changed:false）")
code, dup, _ = run("add", "--text", "HELLO FROM AGENT", "--json")
check(code == 0 and dup["deduplicated"] is True and dup["previous_source"]["app_bundle"] == "cyou.tianli.clipbook.cli", "去重时给出原来源 previous_source")
check(run("cloud", "frobnicate")[0] == 2, "cloud 未知子命令退出 2")
if v["edition"] == "icloud":
    check(run("cloud", "list")[0] == 3, "无归档缓存 cloud list 退出 3")
    check(run("cloud", "push", "--yes")[0] == 2, "iCloud 归档未开时 cloud push 退出 2")
    code, dry, _ = run("cloud", "on", "--dry-run", "--json")
    check(code == 0 and dry["dry_run"] is True and dry["would_change"] is True and run("cloud", "on")[0] == 2, "cloud on 需 --yes；--dry-run 只报告")
    running = run("status", "--json")[1]["gui"]["running"]
    code, on, _ = run("cloud", "on", "--yes", "--json")
    # Not running → exit 4. Running → the request is posted with this sandbox's scope, which the user's Clip ignores.
    check((code == 4 and on["error"] == "app_not_running") if not running else (code == 0 and on["requested"] is True),
          f"cloud on --yes：Clip {'运行中→只发隔离范围的请求' if running else '未运行→退出 4'}")
else:
    code, lst, _ = run("cloud", "list", "--json")
    check(code == 4 and lst["error"] == "unsupported_edition" and run("cloud", "push", "--yes")[0] == 4, "本地版不含 iCloud：cloud list / push 退出 4")
code, login, _ = run("settings", "set", "launchAtLogin", "true", "--json")
check(code == 4 and login["error"] == "system_setting" and run("settings", "set", "launchAtLogin", "true", "--dry-run")[0] == 0,
      "开机自启：隔离运行退出 4，--dry-run 只报告")
check(general() == before_pb, "用户的通用剪贴板未被改动")
print(f"clip CLI 真实入口：{passed} 项通过" + (f"，失败 {len(failures)}：{'; '.join(failures)}" if failures else ""))
sys.exit(1 if failures else 0)
PY
