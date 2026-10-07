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

def running_now():
    return run("status", "--json")[1]["gui"]["running"]

before_pb = general()
t0 = time.monotonic(); code, _, p = run("--help"); dt = time.monotonic() - t0
check(code == 0 and "usage: clip" in p.stdout and dt < 5, f"clip --help 退出 0（{dt*1000:.0f} ms，无界面）")
code, v, _ = run("--version", "--json")
check(code == 0 and v["ok"] and v["name"] == "Clip" and v["build"] not in ("", "unknown"), f"经链接重入真实可执行：{v and v['name']} {v and v['version']} ({v and v['build']})")
code, _, p = run("frobnicate"); check(code == 2 and "未知命令" in p.stderr, "未知命令退出 2")
code, bad, _ = run("version", "--definitely-not-a-flag", "--json")
check(code == 2 and bad["ok"] is False and bad["error"] == "usage" and bad["command"] == "version", "version 多余的参数退出 2")
help_lines = [l.strip() for l in run("--help")[2].stdout.splitlines()]
unlisted = [c for c in ["unpin", "pause", "resume", "ignore add", "ignore remove", "shortcut set", "shortcut scope", "shortcut clear", "cloud show", "cloud list",
                        "cloud favorite", "cloud unfavorite", "cloud delete", "config import", "update check", "update install", "start", "quit"]
            if not any(l == c or l.startswith(c + " ") for l in help_lines)]
check(not unlisted, f"顶层帮助在行首列出每个子命令{'（缺 ' + '、'.join(unlisted) + '）' if unlisted else ''}")
for cmd in ["status", "stats", "list", "search", "show", "copy", "export", "add", "edit", "transform", "pin", "unpin", "delete",
            "merge", "clear", "collections", "collection", "settings", "ignore", "pause", "resume", "import-deck", "cloud", "shortcut", "config",
            "update", "start", "quit"]:
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
# 设置 → 快捷键 与「配置与更新」：默认没有任何绑定，命令不新增组合键；配置备份留在隔离目录。不发任何同步请求。
code, sc, _ = run("shortcut", "list", "--json")
check(code == 0 and sc["command"] == "shortcut list" and len(sc["shortcuts"]) == 12 and all(r["keys"] is None for r in sc["shortcuts"]),
      "shortcut list：十二个动作，默认没有任何绑定")
check(all(r["registration"] is None and r["status"] for r in sc["shortcuts"]), "shortcut list：没有绑定时 registration 为 null")
code, e, _ = run("shortcut", "scope", "search", "global", "--json")
check(code == 2 and e["ok"] is False and e["error"] == "invalid" and run("shortcut", "clear", "--all")[0] == 0
      and run("settings", "--json")[1]["settings"]["shortcuts"] == [], "shortcut scope 不新增组合键（退出 2）；clear --all 空操作")
# shortcut set：写出来的组合键存给动作（隔离偏好域），list 读回；被占用时说明是谁；保留组合被拒；最后清掉。
code, st, _ = run("shortcut", "set", "search", "opt+cmd+f", "--json")
rows = {r["action"]: r for r in run("shortcut", "list", "--json")[1]["shortcuts"]}
check(code == 0 and st["command"] == "shortcut set" and st["changed"] is True and st["set"] == {"action": "search", "keys": "⌥⌘F", "scope": "application", "previous": None}
      and rows["search"]["keys"] == "⌥⌘F" and rows["search"]["scope"] == "application" and rows["search"]["registration"] == "not_needed",
      "shortcut set 存下写出来的组合键，shortcut list 读回（默认仅 Clip 内）")
code, cf, _ = run("shortcut", "set", "pin", "⌥⌘F", "--json")
code2, rs, _ = run("shortcut", "set", "pin", "cmd+shift+v", "--json")
code3, dr, _ = run("shortcut", "set", "pin", "ctrl+f5", "--scope", "global", "--dry-run", "--json")
check(code == 2 and cf["error"] == "conflict" and cf["conflict"]["action"] == "search" and cf["conflict"]["keys"] == "⌥⌘F"
      and code2 == 2 and rs["error"] == "invalid" and code3 == 0 and dr["dry_run"] is True and dr["would_change"] is True
      and [s["action"] for s in run("settings", "--json")[1]["settings"]["shortcuts"]] == ["search"],
      "shortcut set：被占用退出 2 并写明是谁（conflict），⌘⇧V 被拒，--dry-run 不写")
check(run("shortcut", "clear", "--all", "--json")[1]["changed"] is True and run("settings", "--json")[1]["settings"]["shortcuts"] == [],
      "shortcut clear --all 清掉 set 存下的绑定")
cfg = os.path.join(work, "config.json")
code, ex, _ = run("config", "export", "-o", cfg, "--json")
check(code == 0 and ex["bytes"] == os.path.getsize(cfg) > 0 and run("config", "export", "-o", cfg)[0] == 2, "config export 写出文件；已存在要 --force")
run("settings", "set", "maxItems", "900")
code, e, _ = run("config", "import", cfg, "--json")
code2, im, _ = run("config", "import", cfg, "--yes", "--json")
check(code == 2 and e["error"] == "confirmation_required" and code2 == 0 and im["settings"]["maxItems"] == 800
      and os.path.isdir(os.path.join(os.environ["HOME_DIR"], "Configuration")), "config import 要 --yes；恢复导出时的值，备份留在隔离目录")
code, cs, _ = run("config", "status", "--json"); code2, dry, _ = run("config", "sync", "on", "--dry-run", "--json")
check(code == 0 and cs["sync_enabled"] is False and code2 == 0 and dry["would_change"] is True and dry["dry_run"] is True
      and run("config", "sync", "on")[0] == 2, "config status 只读；config sync 没有 --yes 不发请求")
check(cs["sync_status"]["text"] == "iCloud 配置同步已关闭" and cs["sync_status"]["from"] in ("derived", "record") and cs["sync_status"]["live"] is running_now(),
      "config status 带开关下面那句同步状态（sync_status）")
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
    check(run("cloud", "list")[0] == 3 and run("cloud", "show", "abc")[0] == 3 and run("cloud", "show")[0] == 2, "无归档缓存 cloud list / cloud show 退出 3；cloud show 缺 key 退出 2")
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
# 检查更新 through the shared command layer: an isolated run reads only a test feed, never the user's iCloud Drive.
if v["edition"] == "icloud":
    code, none, _ = run("update", "check", "--json")
    check(code == 1 and none["ok"] is False and none["error"] == "check_incomplete" and none["command"] == "update check"
          and none["current"]["build"] == v["build"], "update check：隔离运行没有发行记录时退出 1、check_incomplete，仍给出当前版本")
    feed_root = os.path.join(work, "update-feed")
    feed = os.path.join(feed_root, "TianliApps/Updates/cyou.tianli.clipbook/cloud")
    os.makedirs(feed)
    def published(version, build):
        with open(os.path.join(feed, "release.json"), "w") as f:
            json.dump({"version": version, "build": build, "bundle_id": "cyou.tianli.clipbook", "channel": "cloud",
                       "filename": f"Clip-{version}.zip", "sha256": "a" * 64, "size_bytes": 10}, f)
        p = subprocess.run([clip, "update", "check", "--json"], env=dict(env, APP_LIFECYCLE_CLOUD_DIR=feed_root), capture_output=True, text=True, timeout=60)
        return p.returncode, json.loads(p.stdout)
    code, new = published("99.0", "1")
    check(code == 0 and new["ok"] and new["update_available"] and new["state"] == "update_available" and new["latest"]["version"] == "99.0"
          and new["current"] == {"version": v["version"], "build": v["build"]} and "配置与更新" in new["upgrade"]["how"],
          "update check：读到此渠道的新版，给出升级办法")
    code, same = published(v["version"], v["build"])
    check(code == 0 and same["state"] == "up_to_date" and same["update_available"] is False and os.listdir(feed) == ["release.json"],
          "update check：已是最新；不下载、不安装")
    # 升级到新版：隔离运行只到 --dry-run，--yes 不会替换被测的这个 App。
    exe = os.path.realpath(clip)
    def install(version, build, *flags):
        with open(os.path.join(feed, "release.json"), "w") as f:
            json.dump({"version": version, "build": build, "bundle_id": "cyou.tianli.clipbook", "channel": "cloud",
                       "filename": f"Clip-{version}.zip", "sha256": "a" * 64, "size_bytes": 10}, f)
        p = subprocess.run([clip, "update", "install", *flags, "--json"], env=dict(env, APP_LIFECYCLE_CLOUD_DIR=feed_root), capture_output=True, text=True, timeout=60)
        return p.returncode, json.loads(p.stdout)
    before_exe = (os.path.getmtime(exe), os.path.getsize(exe))
    code, plan = install("99.0", "1", "--dry-run")
    check(code == 0 and plan["command"] == "update install" and plan["dry_run"] is True and plan["installed"] is False
          and plan["would_install"] == {"from": {"version": v["version"], "build": v["build"]}, "to": {"version": "99.0", "build": "1"}}
          and plan["will_quit_app"] is plan["app_running"], "update install --dry-run：报告会从哪版换到哪版，不替换")
    code, need = install("99.0", "1")
    code2, kept = install("99.0", "1", "--yes")
    check(code == 2 and need["error"] == "confirmation_required" and code2 == 4 and kept["error"] == "system_setting" and "would_install" in kept
          and (os.path.getmtime(exe), os.path.getsize(exe)) == before_exe and os.listdir(feed) == ["release.json"],
          "update install：缺 --yes 退出 2；隔离运行里 --yes 退出 4，被测的 App 没有被替换")
    code, none = install(v["version"], v["build"], "--yes")
    check(code == 0 and none["ok"] and none["installed"] is False and none["state"] == "up_to_date" and none["current"]["build"] == v["build"],
          "update install：没有新版时退出 0、installed 为 false")
code, bad, _ = run("update", "install", "--definitely-not-a-flag", "--json")
check(code == 2 and bad["ok"] is False and bad["error"] == "usage" and bad["command"] == "update install", "update install 参数错误退出 2")
# Clip 本身：隔离运行里只看 --dry-run 与「没有自己的实例可退」；真实的后台启动与退出在 tests/test-start.sh。
code, sd, _ = run("start", "--dry-run", "--json")
code2, qd, _ = run("quit", "--dry-run", "--json")
code3, q, _ = run("quit", "--json")
check(code == 0 and sd["dry_run"] is True and sd["app_path"].endswith(".app") and sd["would_start"] is (not sd["already_running"])
      and code2 == 0 and qd["would_quit"] is False and code3 == 0 and q["quit"] is False and q["was_running"] is False
      and run("start", "extra")[0] == 2 and run("quit", "--wait", "abc")[0] == 2,
      "start --dry-run 只报告；quit 在隔离运行里不退出别的 Clip；参数错误退出 2")
# 同步历史的收藏 / 删除：这个隔离目录里没有归档缓存，也没有运行中的 Clip——只看拒绝路径（真路径在 tests/test-runtime.sh）。
code, cf, _ = run("cloud", "favorite", "no-such-key", "--json")
code2, cd, _ = run("cloud", "delete", "--yes", "--json")
check(code == (3 if v["edition"] == "icloud" else 4) and cf["ok"] is False and cf["command"] == "cloud favorite"
      and code2 == 2 and cd["error"] == "usage" and cd["command"] == "cloud delete" and run("cloud", "unfavorite", "x", "--wait", "0")[0] == 2,
      "cloud favorite：没有这条记录退出 3（本地版 4）；cloud delete 缺 key、--wait 越界退出 2")
code, bad, _ = run("update", "check", "--definitely-not-a-flag", "--json")
check(code == 2 and bad["ok"] is False and bad["error"] == "usage" and bad["command"] == "update check" and run("update", "--help")[0] == 0,
      "update check 参数错误退出 2；update --help 退出 0")
check(general() == before_pb, "用户的通用剪贴板未被改动")
print(f"clip CLI 真实入口：{passed} 项通过" + (f"，失败 {len(failures)}：{'; '.join(failures)}" if failures else ""))
sys.exit(1 if failures else 0)
PY
