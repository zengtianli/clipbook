#!/usr/bin/env python3
"""Link ~/.local/bin/clip to the installed Clip.app's in-bundle command; never overwrite an unrelated file.

The command is Clip.app/Contents/Resources/bin/clip, a relative link to the app's own signed executable
(../../MacOS/Clipbook). build-cloud.sh runs this after installing; it can also be run by hand:
    python3 scripts/install-cli.py /Applications/Clip.app
"""
import argparse
import os
import plistlib
import subprocess
from pathlib import Path

BUNDLE_ID = "cyou.tianli.clipbook"


def install(app: Path, bin_dir: Path) -> str:
    app = app.resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise RuntimeError(f"{app} is not Clip ({info.get('CFBundleIdentifier')})")
    target = app / "Contents/Resources/bin/clip"
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    if os.path.realpath(target) != str(executable):
        raise RuntimeError(f"{target} does not resolve to the app executable")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    subprocess.run([str(target), "--help"], check=True, capture_output=True, stdin=subprocess.DEVNULL, timeout=10)
    link = bin_dir / "clip"
    bin_dir.mkdir(parents=True, exist_ok=True)
    if link.is_symlink():
        if os.path.realpath(link) == str(executable):
            return f"{link} -> {os.readlink(link)} (unchanged)"
        current = os.path.realpath(link)
        if "/Clip.app/" not in current and not current.endswith("/Clipbook"):
            raise RuntimeError(f"{link} already points to {current}; left unchanged")
        link.unlink()  # an older Clip.app location: replace
    elif link.exists():
        raise RuntimeError(f"{link} is an existing file; left unchanged")
    link.symlink_to(target)
    assert os.path.realpath(link) == str(executable)
    return f"{link} -> {target}"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("app", type=Path, nargs="?", default=Path("/Applications/Clip.app"))
    parser.add_argument("--bin-dir", type=Path, default=Path.home() / ".local/bin")
    args = parser.parse_args()
    print(install(args.app, args.bin_dir))
