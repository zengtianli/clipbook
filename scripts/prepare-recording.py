"""Prepare a separate real Clip instance without touching the user's library."""
from pathlib import Path
import json
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "build/homepage-recording"
DATA = WORK / "data"
APP = WORK / "Clip Preview.app"
SUITE = "cyou.tianli.clipbook.productdemo.20260910"
WORK.mkdir(parents=True, exist_ok=True)
if not (DATA / "clipbook.sqlite3").exists():
    subprocess.run(["python3", str(ROOT / "promotion/prepare_demo.py"), "--out", str(DATA)], check=True)
if APP.exists():
    raise SystemExit("Recording app already exists; keep it until its session is finished")
shutil.copytree(ROOT / "build/local-release/Clip.app", APP)
info_path = APP / "Contents/Info.plist"
info = plistlib.loads(info_path.read_bytes())
info["CFBundleIdentifier"] = SUITE
info.pop("CFBundleURLTypes", None)
info["LSEnvironment"] = {"CLIPBOOK_HOME": str(DATA), "CLIPBOOK_PREFERENCES_SUITE": SUITE,
                         "CLIPBOOK_BACKGROUND": "1"}
info_path.write_bytes(plistlib.dumps(info))
prefs = Path.home() / "Library/Preferences" / (SUITE + ".plist")
if prefs.exists():
    raise SystemExit("Demo preference suite already exists; refusing to overwrite")
prefs.write_bytes(plistlib.dumps({"paused": True, "copySound": False,
                                  "fetchLinkTitles": False, "cloudEnabled": False}))
subprocess.run(["codesign", "--force", "--sign", "-", str(APP)], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(APP)], check=True)
(WORK / "environment.json").write_text(json.dumps({"app": str(APP), "suite": SUITE, "data": str(DATA), "private_pasteboard": SUITE + ".pasteboard"}, indent=2))
print(APP)
