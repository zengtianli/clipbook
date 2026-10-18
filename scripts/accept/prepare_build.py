#!/usr/bin/env python3
"""Keep a Chapter snapshot's sources, resolving its family link from SOP_SOURCE_REPO.

The ordinary checkout needs no projection. A detached worktree has no sibling iOS
checkout; only that unchanged link may read the original family's source. Chapter
hashes its contents before/after acceptance. Never build the live Mac source tree
instead of the snapshot, or change either checkout's tracked files.
"""
import os
from pathlib import Path
import shutil
import sys

POCKET = Path('Sources/Native/PocketLibrary.swift')


def prepare(root):
    root = root.resolve()
    broken = [p for p in (root / 'Sources').rglob('*.swift') if p.is_symlink() and not p.is_file()]
    if not broken:
        return root
    original = os.environ.get('SOP_SOURCE_REPO')
    if not original or [p.relative_to(root) for p in broken] != [POCKET]:
        raise ValueError('Missing shared Swift source; check out the sibling Clip iOS repository')
    original = Path(original).resolve()
    link = original / POCKET
    if original == root or not link.is_symlink() or os.readlink(link) != os.readlink(root / POCKET) or not link.is_file():
        raise ValueError('Snapshot family link differs from SOP_SOURCE_REPO or its target is missing')

    # This directory belongs to the acceptance cache, protected by _build.sh's
    # product cache lock. The Xcode build still acquires the shared BuildSlot.
    stage = root / 'build/.accept-source'
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)

    def copy_source(src, dst):
        return shutil.copy2(link if Path(src) == root / POCKET else src, dst)

    shutil.copytree(root / 'Sources', stage / 'Sources', copy_function=copy_source,
                    ignore=shutil.ignore_patterns('.DS_Store'))
    for name in ('cloud-project.yml', 'Cloud.entitlements', 'build.sh', 'build-cloud.sh',
                 'project.yaml', 'icon/AppIcon.icns', 'scripts/developer-id-profile.py', 'scripts/install-cli.py'):
        target = stage / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / name, target)
    return stage


if __name__ == '__main__':
    try:
        print(prepare(Path.cwd()))
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
