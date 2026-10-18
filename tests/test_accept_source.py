"""A detached acceptance snapshot must build its own sources plus the family link."""
import importlib.util
import os
from pathlib import Path
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('clip_accept_source', ROOT / 'scripts/accept/prepare_build.py')
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


@pytest.fixture
def snapshot(tmp_path, monkeypatch):
    original = tmp_path / 'family/mac'
    frozen = tmp_path / 'isolated/mac'
    for root in (original, frozen):
        (root / 'Sources/Native').mkdir(parents=True)
        (root / prepare.POCKET).symlink_to('../../../ios/Shared/ClipLibrary.swift')
        (root / 'Sources/Native/App.swift').write_text('// frozen source\n')
    family = tmp_path / 'ios/Shared/ClipLibrary.swift'
    family.parent.mkdir(parents=True)
    family.write_text('// one family source\n')
    # The relative path lands in family/ios for the original checkout only.
    (tmp_path / 'family/ios').symlink_to(tmp_path / 'ios', target_is_directory=True)
    for name in ('cloud-project.yml', 'Cloud.entitlements', 'build.sh', 'project.yaml',
                 'icon/AppIcon.icns', 'scripts/developer-id-profile.py', 'scripts/install-cli.py'):
        path = frozen / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('snapshot input\n')
    (frozen / 'build-cloud.sh').write_text('#!/bin/bash\nexit 75\n')
    (original / 'Sources/Native/App.swift').write_text('// changed live source: must not compile\n')
    monkeypatch.setenv('SOP_SOURCE_REPO', str(original))
    return original, frozen, family


def test_intact_checkout_needs_no_projection(snapshot):
    original, _, _ = snapshot
    assert prepare.prepare(original) == original
    assert not (original / 'build').exists()


def test_snapshot_uses_frozen_mac_sources_and_same_family_source(snapshot):
    original, frozen, family = snapshot
    link = frozen / prepare.POCKET
    target = os.readlink(link)
    stage = prepare.prepare(frozen)
    assert (stage / prepare.POCKET).read_bytes() == family.read_bytes()
    assert not (stage / prepare.POCKET).is_symlink()
    assert (stage / 'Sources/Native/App.swift').read_text() == '// frozen source\n'
    assert (stage / 'cloud-project.yml').read_bytes() == (frozen / 'cloud-project.yml').read_bytes()
    assert link.is_symlink() and os.readlink(link) == target and not link.exists()
    assert (original / prepare.POCKET).is_file()
    # A changed shared dependency must invalidate the build cache's content hash.
    family.write_text('// next family version\n')
    assert (prepare.prepare(frozen) / prepare.POCKET).read_bytes() == family.read_bytes()


@pytest.mark.parametrize('mode', ['no_original', 'different_link', 'missing_family', 'other_broken_link'])
def test_missing_or_changed_dependencies_are_not_silently_omitted(snapshot, monkeypatch, mode):
    original, frozen, family = snapshot
    if mode == 'no_original':
        monkeypatch.delenv('SOP_SOURCE_REPO')
    elif mode == 'different_link':
        (original / prepare.POCKET).unlink()
        (original / prepare.POCKET).symlink_to(family)
    elif mode == 'missing_family':
        family.unlink()
    else:
        (frozen / 'Sources/Native/Other.swift').symlink_to('missing.swift')
    with pytest.raises(ValueError):
        prepare.prepare(frozen)


def test_projected_build_preserves_deferred_exit_and_releases_cache_lock(snapshot):
    _, frozen, _ = snapshot
    result = subprocess.run(['/bin/bash', '-c', 'set -euo pipefail; source "$1"; echo MUST_NOT_CONTINUE',
                             'test-source-projection', str(ROOT / 'scripts/accept/_build.sh')],
                            cwd=frozen, env=os.environ.copy(), text=True, capture_output=True, timeout=10)
    assert result.returncode == 75, result.stdout + result.stderr
    assert 'MUST_NOT_CONTINUE' not in result.stdout
    assert not (frozen / 'build/.accept-build.lock').exists()
    assert not (frozen / 'build/.accept-build.sha').exists()
