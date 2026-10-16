"""Acceptance boundary regressions; no real app, preferences or evidence is changed."""
import importlib.util
import json
from pathlib import Path
import plistlib
import sys
from types import SimpleNamespace

import pytest


SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/accept/product_basics.py'
spec = importlib.util.spec_from_file_location('clip_product_basics', SCRIPT)
accept = importlib.util.module_from_spec(spec)
spec.loader.exec_module(accept)
DIGEST = 'a' * 64


@pytest.fixture
def rig(tmp_path, monkeypatch):
    app = tmp_path / 'Clip.app'
    executable = app / 'Contents/MacOS/Clipbook'
    executable.parent.mkdir(parents=True)
    executable.write_bytes(b'receipt-bound executable')
    info = dict(CFBundleIdentifier='cyou.tianli.clipbook', CFBundleShortVersionString='1.2.1', CFBundleVersion='124')
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    receipt = tmp_path / 'receipt.json'
    receipt.write_text(json.dumps(dict(artifact=dict(bundle_id=info['CFBundleIdentifier'], version='1.2.1', build='124',
        executable='Contents/MacOS/Clipbook', sha256=accept.sha(executable)), source=dict(sha256='old full receipt digest',
        commit='original-build', files={'scripts/accept/old.py': 'stale', 'Tests/old.swift': 'stale',
                                       'project.yaml': 'old SOP registration'}))))
    out = tmp_path / 'perf/acceptance'
    out.mkdir(parents=True)
    features = {name: dict(required_checks=[name + '.behavior']) for name in ('settings', 'shortcuts', 'icloud', 'updates')}
    monkeypatch.setattr(accept, 'ROOT', tmp_path)
    monkeypatch.setattr(accept, 'owner', lambda: dict(unchanged=True))
    monkeypatch.setenv('SOP_APP_ID', 'clipbook')
    monkeypatch.setenv('SOP_PRODUCT_BASICS_SPEC', json.dumps(dict(app_id='clipbook', digest='fixture-spec', features=features)))
    monkeypatch.setenv('SOP_OUT_DIR', str(out))
    monkeypatch.setenv('SOP_CODE_BINDING_SHA256', DIGEST)
    monkeypatch.setenv('SOP_BUILD_CURRENT', '1')
    monkeypatch.setattr(sys, 'argv', [str(SCRIPT), '--app', str(app), '--receipt', str(receipt)])
    # Route this disposable fixture through the installed branch without touching /Applications.
    original_binding = accept.source_binding
    monkeypatch.setattr(accept, 'source_binding', lambda app, receipt_path, candidate: original_binding(app, receipt_path, False))
    calls = []

    def run(argv, **kwargs):
        calls.append(argv)
        if '--product-basics-self-test' in argv:
            body = dict(checks={name + '.behavior': True for name in features})
            return SimpleNamespace(returncode=0, stdout=json.dumps(body), stderr='')
        return SimpleNamespace(returncode=0, stdout='', stderr='')

    monkeypatch.setattr(accept.subprocess, 'run', run)

    def result():
        status = accept.main()
        detail = json.loads((out / 'product_basics.detail.json').read_text())
        raw = json.loads(next(out.glob('product-basics-*/raw.json')).read_text())
        return status, detail, raw

    return SimpleNamespace(app=app, executable=executable, receipt=receipt, calls=calls, result=result)


def test_chapter_binding_accepts_non_production_receipt_churn(rig):
    status, detail, raw = rig.result()
    assert status == 0 and all(row['result'] == 'passed' for row in detail['features'].values())
    assert raw['binding']['code_binding_sha256'] == DIGEST
    assert raw['checks']['settings.artifact_matches_receipt'] is True
    assert raw['checks']['settings.artifact_signature_valid'] is True
    assert any('--product-basics-self-test' in argv for argv in rig.calls)


@pytest.mark.parametrize('digest,current', [(DIGEST, '0'), ('', '1'), ('invalid', '1'), (DIGEST, None), (DIGEST, 'true')])
def test_unproved_production_never_executes_fixture(rig, monkeypatch, digest, current):
    monkeypatch.setenv('SOP_CODE_BINDING_SHA256', digest)
    if current is None:
        monkeypatch.delenv('SOP_BUILD_CURRENT')
    else:
        monkeypatch.setenv('SOP_BUILD_CURRENT', current)
    status, detail, raw = rig.result()
    assert status == 1 and detail['error']
    assert raw['checks']['settings.execution_complete'] is False
    assert not any('--product-basics-self-test' in argv for argv in rig.calls)


def test_changed_actual_executable_is_rejected_despite_current_binding(rig):
    rig.executable.write_bytes(b'different executable')
    status, detail, raw = rig.result()
    assert status == 1 and 'package does not match' in detail['error']
    assert raw['checks']['settings.artifact_matches_receipt'] is False
    assert not any('--product-basics-self-test' in argv for argv in rig.calls)


def test_early_installed_failure_is_never_labelled_candidate(rig, monkeypatch):
    monkeypatch.setattr(sys, 'argv', [str(SCRIPT), '--receipt', str(rig.receipt)])
    monkeypatch.setattr(accept, 'Path', lambda value: rig.app if value == '/Applications/Clip.app' else Path(value))
    monkeypatch.setenv('SOP_BUILD_CURRENT', '0')
    status, detail, raw = rig.result()
    assert status == 1 and raw['binding']['phase'] == 'installed'
    assert raw['binding']['build_current'] is False
    assert '实际已装原件' in detail['summary'] and '候选包' not in detail['summary']


def test_invalid_actual_signature_is_rejected(rig, monkeypatch):
    original = accept.subprocess.run

    def run(argv, **kwargs):
        if argv[:2] == ['codesign', '--verify']:
            return SimpleNamespace(returncode=1, stdout='', stderr='signature invalid')
        return original(argv, **kwargs)

    monkeypatch.setattr(accept.subprocess, 'run', run)
    status, detail, raw = rig.result()
    assert status == 1 and raw['checks']['settings.artifact_signature_valid'] is False
    assert 'signature is invalid' in detail['error']
    assert not any('--product-basics-self-test' in argv for argv in rig.calls)


@pytest.mark.parametrize('verified', [True, False])
def test_candidate_uses_original_verifier_instead_of_installed_verdict(tmp_path, monkeypatch, verified):
    monkeypatch.setenv('SOP_CODE_BINDING_SHA256', DIGEST)
    monkeypatch.setenv('SOP_BUILD_CURRENT', '0' if verified else '1')
    app, receipt = tmp_path / 'candidate.app', tmp_path / 'receipt.json'
    product = dict(id='clipbook')
    calls = []

    def verify(*args, **kwargs):
        calls.append((args, kwargs))
        return verified, 'original Chapter verification'

    monkeypatch.setitem(sys.modules, 'app_sop', SimpleNamespace(load_apps=lambda name: [product], verify_build_receipt=verify))
    assert accept.source_binding(app, receipt, True) == (DIGEST, verified, 'original Chapter verification')
    assert calls == [((product, app), dict(receipt_path=receipt, code_only=True))]
