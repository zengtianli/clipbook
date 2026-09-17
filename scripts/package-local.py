"""Build a local-edition bundle and derive the public release manifest from it."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "build/local-release"
APP = WORK / "Clip.app"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", action="store_true")
    args = parser.parse_args()
    catalog = (ROOT / "project.yaml").read_text()
    def field(key):
        return re.search(r"^" + key + r":\s*([^#\n]+)", catalog, re.M).group(1).strip()
    if not args.archive:
        if APP.exists():
            shutil.rmtree(APP)
        (APP / "Contents/MacOS").mkdir(parents=True)
        (APP / "Contents/Resources").mkdir()
        shutil.copy2(WORK / "Clipbook", APP / "Contents/MacOS/Clipbook")
        shutil.copy2(ROOT / "icon/AppIcon.icns", APP / "Contents/Resources/AppIcon.icns")
        version = re.search(r"MARKETING_VERSION:\s*['\"]?([\d.]+)", (ROOT / "cloud-project.yml").read_text()).group(1)
        build = subprocess.check_output(["git", "rev-list", "--count", "HEAD"], cwd=ROOT, text=True).strip()
        info = {"CFBundleIdentifier": field("bundle_id"), "CFBundleName": field("display_name"),
                "CFBundleDisplayName": field("display_name"), "CFBundleExecutable": "Clipbook",
                "CFBundleShortVersionString": version, "CFBundleVersion": build,
                "CFBundlePackageType": "APPL", "CFBundleIconFile": "AppIcon",
                "LSMinimumSystemVersion": "14.0", "LSUIElement": False,
                "NSHighResolutionCapable": True, "NSPrincipalClass": "NSApplication",
                "CFBundleURLTypes": [{"CFBundleURLName": field("bundle_id"), "CFBundleURLSchemes": ["clipbook"]}],
                "ClipDistribution": "local"}
        (APP / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        return
    info = plistlib.loads((APP / "Contents/Info.plist").read_bytes())
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    archive = WORK / f"Clip-{version}-local-arm64.zip"
    subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(APP), str(archive)], check=True)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    manifest = {"product": "Clip", "version": version, "build": build, "edition": "local",
                "arch": "arm64", "minimum_macos": "14.0", "filename": archive.name,
                "bytes": archive.stat().st_size, "sha256": digest, "signature": "ad-hoc", "notarized": False,
                "icloud": False, "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()}
    (WORK / "release.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    (WORK / "SHA256SUMS.txt").write_text(f"{digest}  {archive.name}\n")
    print(json.dumps(manifest, ensure_ascii=False))

if __name__ == "__main__":
    main()
