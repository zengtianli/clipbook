#!/usr/bin/env python3
"""Build the original CloudKit target on Mini and sign via the existing login-run entry.

Produces build/accept/product-basics-signed; installation remains build.sh --install-local.
No notarization, account changes, update feed, remote installation or source-tree writes.
"""
import base64
import datetime
import hashlib
import os
from pathlib import Path
import plistlib
import shlex
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/accept/product-basics-signed'
HOST = 'macbook'
IDENTITY = 'Developer ID Application: tianli Zeng (B9LJH93LA4)'
TEAM = 'B9LJH93LA4'


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main():
    os.chdir(ROOT)
    OUT.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, CLIP_DERIVED_DATA=str(OUT), CLIP_CLOUD_BUILD_LOG=str(OUT / 'compile.log'))
    run('bash', 'build.sh', '--compile-only', env=env)
    app = OUT / 'Build/Products/Release/Clipbook.app'
    # Reuse the actual installed all-device Developer ID profile. Never create an account/profile.
    reference = Path('/Applications/Clip.app')
    run('codesign', '--verify', '--deep', '--strict', str(reference))
    signature = run('codesign', '-dv', '--verbose=4', str(reference), capture_output=True, text=True)
    assert f'TeamIdentifier={TEAM}' in signature.stderr
    profile_bytes = (reference / 'Contents/embedded.provisionprofile').read_bytes()
    profile = plistlib.loads(run('security', 'cms', '-D', '-i', str(reference / 'Contents/embedded.provisionprofile'), capture_output=True).stdout)
    assert profile['Name'] == 'Clip Developer ID' and profile['ProvisionsAllDevices'] is True
    assert 'ProvisionedDevices' not in profile and profile['ExpirationDate'] > datetime.datetime.now()
    capabilities = profile['Entitlements']
    assert capabilities['com.apple.application-identifier'] == f'{TEAM}.cyou.tianli.clipbook'
    entitlements = plistlib.loads((ROOT / 'Cloud.entitlements').read_bytes().replace(b'$(CLIP_CLOUD_ENVIRONMENT)', b'Production'))
    entitlements.update({'com.apple.application-identifier': capabilities['com.apple.application-identifier'],
                         'com.apple.developer.team-identifier': TEAM})
    (app / 'Contents/embedded.provisionprofile').write_bytes(profile_bytes)
    # ditto preserves the sealed in-bundle CLI symlink across both transfers.
    payload = OUT / 'unsigned.zip'
    run('ditto', '-c', '-k', '--keepParent', str(app), str(payload))
    name = 'clip-basics-' + uuid.uuid4().hex[:16]
    remote = f'/Users/tianli/Library/Caches/mac-pair/login-run/{name}'
    script = OUT / 'sign.sh'
    payload64 = base64.b64encode(payload.read_bytes()).decode()
    entitlements64 = base64.b64encode(plistlib.dumps(entitlements)).decode()
    script.write_text(f'''#!/bin/zsh
set -euo pipefail
cd {shlex.quote(remote)}
/usr/bin/python3 - <<'PY'
import base64, hashlib, pathlib
data = base64.b64decode({payload64!r})
assert hashlib.sha256(data).hexdigest() == {hashlib.sha256(payload.read_bytes()).hexdigest()!r}
pathlib.Path('unsigned.zip').write_bytes(data)
pathlib.Path('Cloud.entitlements').write_bytes(base64.b64decode({entitlements64!r}))
PY
ditto -x -k unsigned.zip .
codesign --force --sign {shlex.quote(IDENTITY)} --options runtime --timestamp --entitlements Cloud.entitlements Clipbook.app
codesign --verify --deep --strict Clipbook.app
python3 "$HOME/Dev/tools/dev/lib/tools/macapp/distribution_grade.py" check --stage signed Clipbook.app
ditto -c -k --keepParent Clipbook.app signed.zip
shasum -a 256 signed.zip
''')
    helper = Path.home() / 'Dev/tools/cc-home/skills/macmini/scripts/login_run.py'
    run('python3', str(helper), '--host', HOST, '--name', name, '--script', str(script), '--timeout', '300', '--tail', '30')
    receipt = run('ssh', '-o', 'BatchMode=yes', HOST, f'shasum -a 256 {shlex.quote(remote + "/signed.zip")}', capture_output=True, text=True)
    signed = run('ssh', '-o', 'BatchMode=yes', HOST, f'cat {shlex.quote(remote + "/signed.zip")}', capture_output=True).stdout
    assert hashlib.sha256(signed).hexdigest() == receipt.stdout.split()[0], 'Signing transport SHA mismatch'
    (OUT / 'signed.zip').write_bytes(signed)
    # Replace only this task's unsigned candidate, retaining an exact copy for diagnosis.
    app.rename(app.with_name('Clipbook-unsigned.app'))
    run('ditto', '-x', '-k', str(OUT / 'signed.zip'), str(app.parent))
    run('bash', 'build.sh', '--check-only', env=env)
    print(f'Signed source candidate: {app}\nSigning login-run: {name}\nTransfer SHA256: {receipt.stdout.split()[0]}')


if __name__ == '__main__':
    main()
