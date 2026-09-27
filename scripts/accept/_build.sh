# Sourced by the acceptance scripts. Builds the current source once (acceptors run in parallel, so under a
# lock; skipped when the inputs are unchanged since the last successful acceptance build) with the same
# pipeline as build.sh but --build-only, which also runs the production --selftest gate. Never installs.
# Sets APP and EXE, and helpers isolated_env / cleanup_isolated for the in-process self-tests.
ACC_DD=build/.dd-accept
LOCK=build/.accept-build.lock
mkdir -p build
inputs_sha() {
  { find -L Sources -name '*.swift' -type f | LC_ALL=C sort | xargs cat
    cat cloud-project.yml Cloud.entitlements build.sh build-cloud.sh project.yaml icon/AppIcon.icns; } | shasum -a 256 | cut -d' ' -f1
}
for _ in $(seq 1 1200); do mkdir "$LOCK" 2>/dev/null && break; sleep 0.5; done
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
SHA="$(inputs_sha)"
APP="$ACC_DD/Build/Products/Release/Clipbook.app"
if [ "$(cat build/.accept-build.sha 2>/dev/null)" != "$SHA" ] || [ ! -x "$APP/Contents/MacOS/Clipbook" ]; then
  rm -f build/.accept-build.sha
  CLIP_DERIVED_DATA="$ACC_DD" CLIP_CLOUD_BUILD_LOG=build/accept-build.log bash build-cloud.sh --build-only \
    > build/accept-selftest.log 2>&1 || { tail -40 build/accept-selftest.log; echo "构建或 --selftest 门失败"; exit 1; }
  echo "$SHA" > build/.accept-build.sha
fi
rmdir "$LOCK"; trap - EXIT
EXE="$APP/Contents/MacOS/Clipbook"
EXE_SHA="$(shasum -a 256 "$EXE" | cut -d' ' -f1)"

# Isolated data dir, preferences suite and pasteboard (ProductIdentity.backgroundPreview): never the user's.
ISO_SUITE=""; ISO_HOME=""
isolated_env() {
  ISO_HOME="$(mktemp -d "${TMPDIR:-/tmp}/clip-accept.XXXXXX")"
  ISO_SUITE="cyou.tianli.clipbook.accept.${SOP_CHECK:-manual}.$$"
  export CLIPBOOK_HOME="$ISO_HOME" CLIPBOOK_PREFERENCES_SUITE="$ISO_SUITE" CLIPBOOK_BACKGROUND=1
  trap cleanup_isolated EXIT
}
cleanup_isolated() {
  [ -n "$ISO_SUITE" ] && { defaults delete "$ISO_SUITE" >/dev/null 2>&1 || true; rm -f "$HOME/Library/Preferences/$ISO_SUITE.plist"; }
  [ -n "$ISO_HOME" ] && rm -rf "$ISO_HOME"
  unset CLIPBOOK_HOME CLIPBOOK_PREFERENCES_SUITE CLIPBOOK_BACKGROUND
}

# Run an in-process self-test entry; writes <check>.detail.json from its final JSON line.
run_selftest_entry() {  # $1 = check name, rest = args
  local name="$1"; shift
  set +e; RESULT="$("$EXE" "$@" 2>&1)"; CODE=$?; set -e
  echo "$RESULT"
  ACCEPT_RESULT="$RESULT" python3 - "$name" "$CODE" "$EXE_SHA" "$*" <<'PY'
import json, os, sys
name, code, sha, args = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
lines = [l.strip() for l in os.environ["ACCEPT_RESULT"].splitlines() if l.strip().startswith("{")]
try: data = json.loads(lines[-1])
except Exception: data = {"ok": False, "checks": {}}
checks = data.get("checks") or {}
failed = [k for k, v in checks.items() if not v]
ok = code == 0 and data.get("ok") is True and checks and not failed
extra = json.loads(os.environ.get("ACCEPT_EXTRA") or "{}")
static = (extra.get("static") or {}).get("checks") or {}
label = {"native_ui": "进程内离屏界面自检", "recovery": "故障与恢复自检", "privacy": "隐私边界自检"}.get(name, name)
summary = (f"{label} {len(checks)}/{len(checks)} 项通过（当前源码 Release 构建，Clipbook {args}，可执行 {sha[:12]}；隔离数据/偏好/剪贴板）"
           + (f"；构建静态检查 {len(static)}/{len(static)} 项通过" if static else "")
           if ok else f"{label}未通过：{', '.join(failed) or '退出码 %d / 无 JSON' % code}")
detail = {"summary": summary, "executable_sha256": sha, "entry": args, "exit_code": code, "checks": checks,
          "screenshots": [f"perf/acceptance/{name}/{s}" for s in data.get("screenshots", [])],
          "not_covered": data.get("not_covered", []), **extra}
out = os.environ.get("SOP_OUT_DIR")
if out:
    open(os.path.join(out, f"{name}.detail.json"), "w").write(json.dumps(detail, ensure_ascii=False, indent=2) + "\n")
print(summary); sys.exit(0 if ok else 1)
PY
}
