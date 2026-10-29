"""Exercise the Store bundle's real command, using only a disposable sandbox identity.

CLIP_STORE_TEST_APP=/absolute/test/Clip.app python -m pytest -n auto tests/test_store_cli.py
The caller builds the Store target and signs a disposable copy without restricted cloud entitlements.
This checks the local archive/CLI boundary, not Apple's cross-device transport or TestFlight delivery.
"""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import uuid

import pytest


@pytest.fixture
def command():
    location = os.environ.get('CLIP_STORE_TEST_APP')
    if not location:
        pytest.skip('requires the built disposable Store bundle')
    app = Path(location).resolve()
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'test.tianli.clipbook.store'
    assert info['ClipDistribution'] == 'store'
    clip = app / 'Contents/Resources/bin/clip'
    assert clip.is_symlink() and clip.resolve() == app / 'Contents/MacOS/Clipbook'
    token = uuid.uuid4().hex
    suite = f'test.tianli.clipbook.store.cli-test.{token}'
    container = Path.home() / 'Library/Containers/test.tianli.clipbook.store/Data'
    home = container / 'tmp' / f'cli-test-{token}'
    environment = dict(os.environ, CLIPBOOK_HOME=str(home), CLIPBOOK_PREFERENCES_SUITE=suite,
                       CLIPBOOK_BACKGROUND='1', APP_LIFECYCLE_SUPPORT_DIR=str(home / 'Configuration'),
                       APP_LIFECYCLE_CLOUD_DIR=str(home / 'CloudFixture'))

    def run(*args):
        result = subprocess.run([str(clip), *args], env=environment, capture_output=True,
                                text=True, timeout=30, stdin=subprocess.DEVNULL)
        return result.returncode, json.loads(result.stdout) if '--json' in args else result.stdout

    yield run, home, app
    shutil.rmtree(home, ignore_errors=True)
    for base in (container, Path.home()):
        (base / 'Library/Preferences' / f'{suite}.plist').unlink(missing_ok=True)


def test_help_and_signed_entry(command):
    run, _, app = command
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    code, help_text = run('--help')
    assert code == 0 and '--json' in help_text and '退出码' in help_text
    lines = [line.strip() for line in help_text.splitlines()]
    for verb in ('cloud status', 'cloud list', 'cloud show', 'cloud favorite', 'cloud unfavorite',
                 'cloud delete', 'add', 'copy', 'config status', 'shortcut list', 'start', 'quit'):
        assert any(line.startswith(verb + ' ') for line in lines), verb
    assert not any(line.startswith(('update ', 'import-deck ')) for line in lines)
    assert run('update', '--help')[0] == 2


def test_readback_keeps_empty_library_uncreated(command):
    run, home, _ = command
    code, status = run('status', '--json')
    assert code == 0 and status['ok'] and not home.exists()
    code, cloud = run('cloud', 'status', '--json')
    assert code == 0 and cloud['supported'] is True and cloud['enabled'] is False
    assert cloud['environment'] == 'Production' and not home.exists()
    code, missing = run('cloud', 'list', '--json')
    assert code == 3 and missing['error'] == 'not_found' and not home.exists()


def test_same_command_writes_and_reopens_local_library(command):
    run, _, _ = command
    code, added = run('add', '--text', 'Store CLI family fixture', '--no-fetch-title', '--json')
    assert code == 0 and added['ok']
    code, listed = run('list', '--json')
    assert code == 0
    item, = listed['items']
    assert item['preview'] == 'Store CLI family fixture'
    identity = str(item['id'])
    assert run('edit', identity, '--text', 'Store CLI edited', '--json')[0] == 0
    assert run('show', identity, '--json')[1]['item']['text'] == 'Store CLI edited'
    assert run('delete', identity, '--json')[0] == 2
    assert run('delete', identity, '--yes', '--json')[0] == 0
    assert run('list', '--json')[1]['items'] == []


@pytest.mark.parametrize('verb,args', [('update', ('install', '--yes')), ('import-deck', ())])
def test_download_only_operations_cannot_run_in_store(command, verb, args):
    run, home, _ = command
    code, result = run(verb, *args, '--json')
    assert code == 4 and result['error'] == 'unsupported_edition'
    assert not home.exists()


def test_archive_toggle_still_needs_explicit_request(command):
    run, home, _ = command
    code, dry = run('cloud', 'on', '--dry-run', '--json')
    assert code == 0 and dry['would_change'] is True and dry['dry_run'] is True
    code, refused = run('cloud', 'on', '--json')
    assert code == 2 and refused['error'] == 'confirmation_required'
    assert not home.exists()
