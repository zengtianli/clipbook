#!/bin/bash
# privacy acceptance: static checks on the current build (signed entitlements limited to the iCloud
# container, system libraries only, no usage-description permissions, network APIs confined to link titles
# and opt-in CloudKit, ephemeral link-title session, no third-party/analytics URLs) plus the in-process
# `Clipbook --privacy-test` (concealed/transient/ignored/paused never stored, iCloud off by default, ...).
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/accept/_build.sh
ENT="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
LIBS="$(otool -L "$EXE" | tail -n +2 | awk '{print $1}' | grep -vE '^/(usr/lib|System/Library)/' || true)"
USAGE="$(plutil -p "$APP/Contents/Info.plist" | grep -i 'UsageDescription' || true)"
URLS="$(strings -a "$EXE" | grep -oiE 'https?://[A-Za-z0-9._/-]+' | sort -u || true)"
NETSRC="$(grep -rlE 'URLSession|URLRequest|CKContainer|CKDatabase|NSPersistentCloudKitContainer|Network\.framework|NWConnection' Sources | sort || true)"
EPHEMERAL="$(grep -c 'URLSession(configuration: .ephemeral)' Sources/Native/LinkTitle.swift || true)"
STATIC="$(ENT="$ENT" LIBS="$LIBS" USAGE="$USAGE" URLS="$URLS" NETSRC="$NETSRC" EPHEMERAL="$EPHEMERAL" python3 - <<'PY'
import json, os, plistlib, re
e = os.environ
try: ent = plistlib.loads(e["ENT"].encode()) if e["ENT"].strip() else {}
except Exception: ent = {"<unparsed>": True}
allowed_ent = {"com.apple.developer.icloud-container-identifiers", "com.apple.developer.icloud-services",
               "com.apple.developer.icloud-container-environment", "com.apple.developer.aps-environment",
               "com.apple.application-identifier", "com.apple.developer.team-identifier", "keychain-access-groups"}
extra_ent = sorted(set(ent) - allowed_ent)
urls = [u for u in e["URLS"].split() if u]
# Reserved example hosts and Apple DTDs; https://github.com/x is a --selftest search fixture, not a request target.
fixtures = {"https://github.com/x"}
third = [u for u in urls if u not in fixtures and not re.match(r"https?://((www\.)?apple\.com|example\.(com|org)|[a-z0-9-]+\.example(/|$)|127\.0\.0\.1|localhost)", u)]
netsrc = [f for f in e["NETSRC"].split() if f]
allowed_net = {"Sources/Native/LinkTitle.swift", "Sources/Native/MacClipSync.swift", "Sources/Native/PocketLibrary.swift"}
checks = {
  "entitlements_icloud_only": not extra_ent and ent.get("com.apple.developer.icloud-container-identifiers") == ["iCloud.cyou.tianli.clip"],
  "system_libraries_only": not e["LIBS"].strip(),
  "no_permission_usage_strings": not e["USAGE"].strip(),
  "network_apis_confined": set(netsrc) <= allowed_net,
  "link_title_ephemeral_session": e["EPHEMERAL"].strip() not in ("", "0"),
  "no_third_party_urls_in_binary": not third,
}
print(json.dumps({"checks": checks, "findings": {"extra_entitlements": extra_ent, "non_system_libs": e["LIBS"].split(),
  "usage_strings": e["USAGE"], "network_source_files": netsrc, "third_party_urls": third}}, ensure_ascii=False))
PY
)"
echo "$STATIC"
if ! python3 -c 'import json,sys; sys.exit(0 if all(json.loads(sys.argv[1])["checks"].values()) else 1)' "$STATIC"; then
  python3 - "$STATIC" <<'PY'
import json, os, sys
s = json.loads(sys.argv[1]); bad = [k for k, v in s["checks"].items() if not v]
summary = "隐私静态检查失败：" + ", ".join(bad)
if os.environ.get("SOP_OUT_DIR"):
    open(os.path.join(os.environ["SOP_OUT_DIR"], "privacy.detail.json"), "w").write(json.dumps({"summary": summary, "static": s}, ensure_ascii=False, indent=2) + "\n")
print(summary)
PY
  exit 1
fi
isolated_env
ACCEPT_EXTRA="$(python3 -c 'import json,sys; print(json.dumps({"static": json.loads(sys.argv[1])}))' "$STATIC")" \
  run_selftest_entry privacy --privacy-test
