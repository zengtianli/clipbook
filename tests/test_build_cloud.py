"""Exercise the real custom xcodebuild block with isolated SDK/slot substitutes."""
from pathlib import Path
import re
import signal
import subprocess
import sys
from types import SimpleNamespace

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / 'build-cloud.sh'
BUILD = re.search(r"<<'PY'[^\n]*\n(.*?)\nPY", SCRIPT.read_text(), re.S).group(1)


@pytest.mark.parametrize('mode,build_exit,busy', [('--build-only', 0, False), ('--compile-only', 0, False),
                                               ('--build-only', 65, False), ('--build-only', 0, True)])
def test_custom_build_slot_and_exact_signing_selection(monkeypatch, mode, build_exit, busy):
    calls = []
    class Busy(Exception):
        pass
    class Slot:
        def __init__(self, label, wait):
            assert label.startswith('clipbook:xcodebuild:') and wait == 120
        def __enter__(self):
            calls.append('admit')
            if busy:
                raise Busy('fixture slot busy')
        def __exit__(self, *args):
            calls.append('release')
    def popen(argv, **kwargs):
        calls.append('build')
        assert argv[0] == 'xcodebuild'
        assert 'CLIP_TEST_SECRET' not in kwargs['env']
        if mode == '--compile-only':
            assert 'CODE_SIGNING_ALLOWED=NO' in argv
            assert not any(arg.startswith('PROVISIONING_PROFILE=') for arg in argv)
        else:
            assert 'PROVISIONING_PROFILE_SPECIFIER=' in argv
            assert 'PROVISIONING_PROFILE=fixture-uuid' in argv
            assert 'CODE_SIGN_IDENTITY=fixture-cert' in argv
        return SimpleNamespace(wait=lambda **kwargs: build_exit, poll=lambda: build_exit)
    monkeypatch.setitem(sys.modules, 'sim_lane', SimpleNamespace(BuildSlot=Slot, Busy=Busy))
    monkeypatch.setattr(subprocess, 'Popen', popen)
    monkeypatch.setattr(signal, 'signal', lambda *args: None)
    monkeypatch.setenv('CLIP_TEST_SECRET', 'fixture-only')
    monkeypatch.setattr(sys, 'argv', ['-', 'fixture-dd', '128', mode, 'fixture-uuid', 'fixture-cert'])
    with pytest.raises(SystemExit) as ended:
        exec(compile(BUILD, str(SCRIPT), 'exec'), {})
    assert ended.value.code == (75 if busy else build_exit)
    assert calls == (['admit'] if busy else ['admit', 'build', 'release'])
