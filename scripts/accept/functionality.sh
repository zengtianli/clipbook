#!/bin/bash
# functionality acceptance: build the current source (Release, same pipeline as build.sh, --build-only;
# never installs), run the production --selftest (store/dedupe/edit/search/collections/merge/retention/
# Deck import/transform/pasteboard extraction on a private pasteboard) and the bounded link-title fetch
# test against a local HTTP server. Non-interactive; no window, focus, input or general-pasteboard use.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/accept/_build.sh
set +e; SELF="$("$EXE" --selftest 2>&1)"; SC=$?; set -e
echo "$SELF"
set +e; LINK="$(bash tests/test-link-title.sh 2>&1)"; LC=$?; set -e
echo "$LINK"
SELF="$SELF" LINK="$LINK" python3 - "$SC" "$LC" "$EXE_SHA" <<'PY'
import json, os, sys
sc, lc, sha = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
lines = os.environ["SELF"].splitlines()
passed = sum(l.strip().startswith("✅ ") for l in lines); failed = [l.strip()[2:].strip() for l in lines if l.strip().startswith("🔴 ") and "失败" not in l]
checks = {"selftest_exit_0": sc == 0, "selftest_no_failures": not failed and passed >= 60, "link_title_bounded_fetch": lc == 0}
bad = [k for k, v in checks.items() if not v]
summary = (f"当前源码 Release 构建：生产 --selftest {passed} 项断言全过，链接标题有界抓取测试通过（可执行 {sha[:12]}）"
           if not bad else "功能验收失败：" + ", ".join(bad) + ("；" + "；".join(failed[:5]) if failed else ""))
out = os.environ.get("SOP_OUT_DIR")
if out:
    open(os.path.join(out, "functionality.detail.json"), "w").write(json.dumps({"summary": summary, "executable_sha256": sha,
        "checks": checks, "selftest_assertions_passed": passed, "selftest_failures": failed,
        "link_title_output": os.environ["LINK"][-500:],
        "not_covered": ["真实前台 App 的 ⌘V 粘贴（需辅助功能授权与抢焦点，按约束不在自动验收里做）", "iCloud 真云端往返（需要账号）"]},
        ensure_ascii=False, indent=2) + "\n")
print(summary); sys.exit(1 if bad else 0)
PY
