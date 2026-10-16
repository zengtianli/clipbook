#!/usr/bin/env python3
"""Failed/deferred builds must stop sourced acceptance helpers with their real exit code."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import os
import subprocess
import tempfile

import pytest

HELPER = Path(__file__).resolve().parents[1] / 'scripts/accept/_build.sh'

def case(code):
    with tempfile.TemporaryDirectory(prefix='clip-accept-exit-') as scratch:
        root = Path(scratch)
        (root/'Sources').mkdir()
        (root/'icon').mkdir()
        (root/'Sources/Fixture.swift').write_text('// isolated build failure fixture\n')
        for name in ['cloud-project.yml', 'Cloud.entitlements', 'build.sh', 'project.yaml', 'icon/AppIcon.icns']:
            (root/name).write_text('fixture\n')
        (root/'build-cloud.sh').write_text(f'#!/bin/bash\necho fixture-build-exit-{code}\nexit {code}\n')
        env = {**os.environ, 'LC_ALL': 'C.UTF-8'}
        result = subprocess.run(['/bin/bash','-c','set -euo pipefail; source "$1"; echo ACCEPTANCE_MUST_NOT_CONTINUE',
                                 'test-accept-build', str(HELPER)], cwd=root, env=env,
                                capture_output=True, text=True, timeout=15)
        assert result.returncode == code, (code, result.returncode, result.stdout, result.stderr)
        assert 'ACCEPTANCE_MUST_NOT_CONTINUE' not in result.stdout, result.stdout
        assert not (root/'build/.accept-build.sha').exists()
        assert not (root/'build/.accept-build.lock').exists()
        return f'PASS: build exit {code} preserved; no acceptance, success stamp or leftover lock'

@pytest.mark.parametrize('code', [4, 65, 75])
def test_build_exit_is_preserved(code):
    case(code)


def test_busy_cache_does_not_build_or_release_another_owner_lock(tmp_path):
    lock = tmp_path / 'build/.accept-build.lock'
    lock.mkdir(parents=True)
    marker = lock / 'owner'
    marker.write_text('another acceptance process')
    env = {**os.environ, 'CLIP_ACCEPT_LOCK_ATTEMPTS': '1'}
    result = subprocess.run(['/bin/bash', '-c', 'set -euo pipefail; source "$1"; echo ACCEPTANCE_MUST_NOT_CONTINUE',
                             'test-accept-build', str(HELPER)], cwd=tmp_path, env=env,
                            capture_output=True, text=True, timeout=5)
    assert result.returncode == 75, result.stderr
    assert 'ACCEPTANCE_MUST_NOT_CONTINUE' not in result.stdout
    assert marker.read_text() == 'another acceptance process'
    assert not (tmp_path / 'build/.accept-build.sha').exists()


if __name__ == '__main__':
    with ThreadPoolExecutor(max_workers=3) as pool:
        for output in pool.map(case, [4, 65, 75]):
            print(output)
