"""Installation sequencing with disposable artifacts; never builds or touches the user's Clip."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace

import pytest

SPEC = importlib.util.spec_from_file_location('clip_install_local', Path(__file__).resolve().parents[1] / 'scripts/install-local.py')
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


@pytest.fixture
def setup_install(monkeypatch, tmp_path):
    monkeypatch.setattr(installer, 'ROOT', tmp_path)
    monkeypatch.setattr(installer, 'INSTALLED', tmp_path / 'Applications/Clip.app')
    target = tmp_path / 'perf/build-receipt.json'
    target.parent.mkdir()
    target.write_bytes(b'previous installed receipt')
    events = []
    class BuildCommandError(RuntimeError):
        def __init__(self, code):
            self.returncode = code
    def build(app, artifact, patterns, command, output_path):
        events.append('build')
        assert patterns == ['Sources/**/*.swift', 'scripts/install-local.py', 'project.yaml']
        assert '--build-only' in command and '--install-local' not in command
        output_path.parent.mkdir(parents=True)
        output_path.write_bytes(b'fresh original Chapter receipt')
    def verify(app, artifact, receipt_path):
        events.append('installed_verify' if artifact == installer.INSTALLED else 'candidate_verify')
        assert target.read_bytes() == b'previous installed receipt'
        return True, 'fixture verified'
    def run(argv, **kwargs):
        events.append('install')
        assert argv == ['bash', 'build.sh', '--install-local']
        assert kwargs['cwd'] == tmp_path
        assert kwargs['env']['CLIP_DERIVED_DATA'] == str(tmp_path / 'build/local-install')
        return SimpleNamespace(returncode=0)
    sop = SimpleNamespace(load_apps=lambda name: [{'repo': tmp_path, 'sop': {'source': ['Sources/**/*.swift', 'scripts/install-local.py']}}],
                          BuildCommandError=BuildCommandError, build_receipt=build,
                          verify_build_receipt=verify, artifact_snapshot=lambda artifact: {'build': 'fixture'})
    monkeypatch.setattr(installer.subprocess, 'run', run)
    return sop, events, target


@pytest.mark.parametrize('code', [4, 75])
def test_build_refusal_preserves_installed_receipt_and_exit_code(setup_install, code):
    sop, events, target = setup_install
    def refused(*args, **kwargs):
        events.append('build_refused')
        raise sop.BuildCommandError(code)
    sop.build_receipt = refused
    assert installer.install(sop) == code
    assert events == ['build_refused']
    assert target.read_bytes() == b'previous installed receipt'


def test_candidate_refusal_never_installs(setup_install):
    sop, events, target = setup_install
    sop.verify_build_receipt = lambda *args, **kwargs: (False, 'changed source')
    with pytest.raises(RuntimeError, match='Candidate rejected'):
        installer.install(sop)
    assert events == ['build']
    assert target.read_bytes() == b'previous installed receipt'


def test_install_failure_preserves_installed_receipt(setup_install, monkeypatch):
    sop, events, target = setup_install
    monkeypatch.setattr(installer.subprocess, 'run', lambda *args, **kwargs: SimpleNamespace(returncode=4))
    assert installer.install(sop) == 4
    assert events == ['build', 'candidate_verify']
    assert target.read_bytes() == b'previous installed receipt'


def test_receipt_is_promoted_only_after_actual_installed_verification(setup_install):
    sop, events, target = setup_install
    assert installer.install(sop) == 0
    assert events == ['build', 'candidate_verify', 'install', 'installed_verify']
    assert target.read_bytes() == b'fresh original Chapter receipt'


def test_wrong_registration_never_builds(setup_install, tmp_path):
    sop, events, target = setup_install
    sop.load_apps = lambda name: [{'repo': tmp_path / 'another-component'}]
    with pytest.raises(ValueError, match='this Clip component'):
        installer.install(sop)
    assert events == []
    assert target.read_bytes() == b'previous installed receipt'
