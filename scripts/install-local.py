#!/usr/bin/env python3
"""Build and install this Mac's Clip once, with Chapter provenance, without notarizing.

Uses build.sh's existing Developer ID/CloudKit checks and shared BuildSlot. An
unsuccessful build never reaches installation or replaces the installed receipt.
"""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
INSTALLED = Path('/Applications/Clip.app')


def install(sop):
    app, = sop.load_apps('clipbook')
    if Path(app['repo']).resolve() != ROOT:
        raise ValueError('Chapter registration must resolve to this Clip component')
    patterns = list(dict.fromkeys([*app['sop']['source'], 'project.yaml']))
    derived = ROOT / 'build/local-install'
    candidate = derived / 'Build/Products/Release/Clipbook.app'
    receipt = ROOT / 'build/accept/local-install.json'
    command = shlex.join(['env', f'CLIP_DERIVED_DATA={derived}', 'bash', 'build.sh', '--build-only'])
    try:
        sop.build_receipt(app, candidate, patterns, command, output_path=receipt)
    except sop.BuildCommandError as exc:
        print(str(exc), file=sys.stderr)
        return exc.returncode
    matched, detail = sop.verify_build_receipt(app, candidate, receipt_path=receipt)
    if not matched:
        raise RuntimeError(f'Candidate rejected before installation: {detail}')
    result = subprocess.run(['bash', 'build.sh', '--install-local'], cwd=ROOT,
                            env=dict(os.environ, CLIP_DERIVED_DATA=str(derived)))
    if result.returncode:
        return result.returncode
    matched, detail = sop.verify_build_receipt(app, INSTALLED, receipt_path=receipt)
    if not matched:
        raise RuntimeError(f'Installed package does not match the fresh build: {detail}')
    # Promote the original Chapter receipt bytes only after verifying the actual
    # installed bundle. Never synthesize a receipt for an existing/failed build.
    target = ROOT / 'perf/build-receipt.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix('.local-install.tmp')
    temporary.write_bytes(receipt.read_bytes())
    temporary.replace(target)
    print(json.dumps({'installed': str(INSTALLED), 'artifact': sop.artifact_snapshot(INSTALLED),
                      'receipt': str(target), 'detail': detail}, ensure_ascii=False))
    return 0


def main():
    sys.path.insert(0, str(Path.home() / 'Apps/chapter/engine'))
    import app_sop
    try:
        return install(app_sop)
    except (OSError, ValueError, RuntimeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
