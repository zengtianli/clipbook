"""A named all-device profile is usable only with this Mac's valid signing key."""
import base64
import copy
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import sys
from types import SimpleNamespace

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/developer-id-profile.py'
TEAM = 'B9LJH93LA4'
BUNDLE = 'cyou.tianli.clipbook'
NAME = 'Clip Developer ID'
CERT = b'fixture current certificate'
IDENTITY = hashlib.sha1(CERT).hexdigest().upper()


@pytest.fixture
def module():
    spec = importlib.util.spec_from_file_location('clip_profile_fixture', SCRIPT)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


@pytest.fixture
def profile():
    return {'Name': NAME, 'UUID': 'fixture-profile', 'TeamIdentifier': [TEAM],
            'ProvisionsAllDevices': True, 'DeveloperCertificates': [CERT],
            'ExpirationDate': datetime.datetime.now() + datetime.timedelta(days=30),
            'Entitlements': {'com.apple.application-identifier': f'{TEAM}.{BUNDLE}',
                             'com.apple.developer.team-identifier': TEAM,
                             'com.apple.developer.icloud-container-environment': 'Production',
                             'com.apple.developer.icloud-container-identifiers': ['iCloud.cyou.tianli.clip'],
                             'com.apple.developer.icloud-services': ['CloudKit']}}


@pytest.mark.parametrize('mutation', ['certificate', 'devices', 'expiry', 'bundle', 'team', 'cloud', 'development'])
def test_stale_or_wrong_profile_is_rejected(module, profile, mutation):
    assert module.usable(profile, NAME, BUNDLE, TEAM, [IDENTITY])
    if mutation == 'certificate':
        profile['DeveloperCertificates'] = [b'old signing Mac certificate']
    elif mutation == 'devices':
        profile['ProvisionedDevices'] = ['fixture-device']
    elif mutation == 'expiry':
        profile['ExpirationDate'] = datetime.datetime.now() + datetime.timedelta(days=2)
    elif mutation == 'bundle':
        profile['Entitlements']['com.apple.application-identifier'] = f'{TEAM}.other.app'
    elif mutation == 'team':
        profile['TeamIdentifier'] = ['OTHERTEAM']
    elif mutation == 'cloud':
        profile['Entitlements']['com.apple.developer.icloud-container-identifiers'] = ['iCloud.other']
    else:
        profile['Entitlements']['com.apple.developer.icloud-container-environment'] = 'Development'
    assert not module.usable(profile, NAME, BUNDLE, TEAM, [IDENTITY])


def test_identity_lookup_uses_valid_developer_id_of_the_product_team(module, monkeypatch):
    output = (f'  1) {IDENTITY} "Developer ID Application: Fixture ({TEAM})"\n'
              f'  2) {"A" * 40} "Apple Development: Fixture ({TEAM})"\n'
              f'  3) {"B" * 40} "Developer ID Application: Fixture (OTHERTEAM)"\n')
    def run(argv, **kwargs):
        assert argv == ['security', 'find-identity', '-v', '-p', 'codesigning']
        assert kwargs['check']
        return subprocess.CompletedProcess(argv, 0, output, '')
    monkeypatch.setattr(module.subprocess, 'run', run)
    assert module.signing_identities(TEAM) == [IDENTITY]


def test_same_name_stale_cache_does_not_hide_compatible_profile(module, profile, tmp_path, monkeypatch):
    stale = copy.deepcopy(profile)
    stale['DeveloperCertificates'] = [b'old certificate']
    for name in ('a-stale', 'z-compatible'):
        (tmp_path / f'{name}.provisionprofile').write_bytes(b'fixture')
    monkeypatch.setattr(module, 'STORES', [tmp_path])
    monkeypatch.setattr(module, 'decode', lambda path: stale if path.stem == 'a-stale' else profile)
    path, found = module.installed(NAME, BUNDLE, TEAM, [IDENTITY])
    assert path.stem == 'z-compatible' and found is profile


@pytest.mark.parametrize('has_match', [True, False])
def test_fetch_validates_content_and_never_changes_account(module, profile, monkeypatch, has_match):
    stale = copy.deepcopy(profile)
    stale['DeveloperCertificates'] = [b'old certificate']
    def attributes(value):
        return {'name': NAME, 'profileState': 'ACTIVE',
                'profileContent': base64.b64encode(plistlib.dumps(value)).decode()}
    rows = [{'attributes': attributes(stale)}]
    if has_match:
        rows.append({'attributes': attributes(profile)})
    calls = []
    def get(path, params):
        calls.append(path)
        return {'data': rows}
    monkeypatch.setitem(sys.modules, 'asc', SimpleNamespace(get=get))  # no POST API exists
    monkeypatch.setattr(module.subprocess, 'run', lambda argv, **kwargs:
                        subprocess.CompletedProcess(argv, 0, kwargs['input'], b''))
    result = module.fetch(NAME, BUNDLE, TEAM, [IDENTITY])
    assert (result is not None) is has_match
    assert calls == ['/profiles']
    if result:
        assert result == rows[1]['attributes']


def test_check_reports_real_mismatch_without_network_or_writes(module, monkeypatch, capsys):
    monkeypatch.setattr(module, 'signing_identities', lambda team: [IDENTITY])
    monkeypatch.setattr(module, 'installed', lambda *args: (None, None))
    monkeypatch.setattr(module, 'fetch', lambda *args: pytest.fail('--check attempted a network fetch'))
    monkeypatch.setattr(sys, 'argv', [str(SCRIPT), '--check'])
    assert module.main() == 4
    result = json.loads(capsys.readouterr().err)
    assert result['error'] == 'signing_profile_unavailable'
    assert result['signing_identities'] == [IDENTITY]


def test_cached_success_reports_exact_certificate_for_xcode(module, profile, monkeypatch, capsys):
    monkeypatch.setattr(module, 'signing_identities', lambda team: [IDENTITY])
    monkeypatch.setattr(module, 'installed', lambda *args: (Path('fixture'), profile))
    monkeypatch.setattr(module, 'fetch', lambda *args: pytest.fail('usable cache fetched again'))
    assert module.main() == 0
    result = json.loads(capsys.readouterr().out)
    assert (result['uuid'], result['signing_identity']) == ('fixture-profile', IDENTITY)
