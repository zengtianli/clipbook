#!/usr/bin/env python3
"""Fixed Chapter acceptor. Defaults to installed Clip; explicit candidate --app requires --receipt."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
LS = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def owner():
    app = Path('/Applications/Clip.app/Contents/MacOS/Clipbook')
    prefs = subprocess.run(['defaults', 'export', 'cyou.tianli.clipbook', '-'], capture_output=True)
    return {'installed_executable': sha(app) if app.is_file() else None,
            'preferences': hashlib.sha256(plistlib.dumps(plistlib.loads(prefs.stdout), sort_keys=True)).hexdigest() if prefs.returncode == 0 else None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path)
    parser.add_argument('--receipt', type=Path)
    args = parser.parse_args()
    if args.app and not args.receipt:
        parser.error('--app must bind an explicit source/build receipt')
    app = (args.app or Path('/Applications/Clip.app')).resolve()
    receipt_path = (args.receipt or ROOT / 'perf/build-receipt.json').resolve()
    spec = json.loads(os.environ['SOP_PRODUCT_BASICS_SPEC'])
    assert spec['app_id'] == os.environ['SOP_APP_ID'] == 'clipbook'
    out = Path(os.environ['SOP_OUT_DIR']).resolve()
    assert out.is_relative_to(ROOT / 'perf/acceptance')
    run = out / ('product-basics-' + uuid.uuid4().hex)
    run.mkdir()
    checks = {}
    failure = None
    cloned = run / 'fixture/Clip.app'
    identity = 'test.tianli.clipbook.basics.' + uuid.uuid4().hex
    before = owner()
    binding = {}
    try:
        receipt = json.loads(receipt_path.read_text())
        artifact = receipt['artifact']
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        executable = app / artifact['executable']
        matched = (info['CFBundleIdentifier'] == artifact['bundle_id'] == 'cyou.tianli.clipbook'
                   and info['CFBundleShortVersionString'] == artifact['version']
                   and str(info['CFBundleVersion']) == str(artifact['build'])
                   and sha(executable) == artifact['sha256'])
        # Test, acceptance and measurement edits do not change the installed app.
        # Keep production inputs bound to the original candidate/installed receipt.
        inputs = {p: h for p, h in receipt['source']['files'].items()
                  if not p.startswith(('Tests/', 'tests/', 'Test/', 'test/',
                                       'scripts/accept/', 'scripts/perf/', 'handoffs/', 'perf/'))}
        current = all((ROOT / p).is_file() and sha(ROOT / p) == h for p, h in inputs.items())
        checks['settings.artifact_matches_receipt'] = matched
        checks['settings.current_source_matches_receipt'] = current
        assert matched and current, 'Actual package/source mismatch; refusing fixture execution'
        signature = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True, text=True)
        (run / 'signature.log').write_text(signature.stdout + signature.stderr)
        checks['settings.artifact_signature_valid'] = signature.returncode == 0
        assert signature.returncode == 0
        binding = {'phase': 'candidate' if args.app else 'installed', 'app': str(app),
                   'receipt': str(receipt_path.relative_to(ROOT)), 'receipt_sha256': sha(receipt_path),
                   'source_sha256': receipt['source']['sha256'], 'source_commit': receipt['source']['commit'],
                   'artifact': artifact, 'installed_by_this_task': False}
        cloned.parent.mkdir()
        shutil.copytree(app, cloned, symlinks=True)
        checks['settings.fixture_copied_actual_executable'] = sha(cloned / artifact['executable']) == artifact['sha256']
        info['CFBundleIdentifier'] = identity
        info['LSUIElement'] = True
        (cloned / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        subprocess.run(['codesign', '--force', '--sign', '-', str(cloned)], check=True, capture_output=True)
        env = {k: v for k, v in os.environ.items() if not k.startswith(('CLIPBOOK_', 'APP_LIFECYCLE_'))}
        env.update(CLIPBOOK_HOME=str(run / 'home'), CLIPBOOK_PREFERENCES_SUITE=identity, CLIPBOOK_BACKGROUND='1',
                   APP_LIFECYCLE_SUPPORT_DIR=str(run / 'support'), APP_LIFECYCLE_CLOUD_DIR=str(run / 'cloud'),
                   APP_LIFECYCLE_NO_RELAUNCH='1')
        result = subprocess.run([str(cloned / artifact['executable']), '--product-basics-self-test', str(run)],
                                env=env, cwd=ROOT, capture_output=True, text=True, errors='replace', timeout=180)
        (run / 'process.log').write_text(result.stdout + result.stderr)
        lines = [line for line in result.stdout.splitlines() if line.startswith('{')]
        body = json.loads(lines[-1]) if lines else {}
        assert isinstance(body.get('checks'), dict), 'Real process did not return checks'
        checks.update(body['checks'])
        checks['settings.process_exit_success'] = result.returncode == 0
        for key, feature in spec['features'].items():
            for required in feature['required_checks']:
                if required not in checks:
                    checks[required] = False
    except Exception as exc:
        failure = str(exc)
        checks['settings.execution_complete'] = False
    finally:
        if cloned.exists():
            subprocess.run([LS, '-u', str(cloned)], capture_output=True)
        subprocess.run(['defaults', 'delete', identity], capture_output=True)
    after = owner()
    checks['updates.owner_and_installed_unchanged'] = before == after
    raw = {'schema_version': 1, 'app_id': 'clipbook', 'spec_digest': spec['digest'], 'checks': checks,
           'binding': binding, 'owner_before': before, 'owner_after': after, 'error': failure,
           'scope': 'Actual receipt-bound candidate/installed executable; disposable identity; native offscreen views/actions, fresh-process reads, coordinated isolated configuration and test update feed. No Apple cross-device transport or installation.'}
    raw_path = run / 'raw.json'
    raw_path.write_text(json.dumps(raw, ensure_ascii=False, indent=2) + '\n')
    features = {}
    for key in ('settings', 'shortcuts', 'icloud', 'updates'):
        names = [name for name in checks if name.startswith(key + '.')]
        required = spec['features'][key]['required_checks']
        passed = bool(names) and all(checks.get(name) is True for name in names + required)
        features[key] = {'result': 'passed' if passed else 'failed', 'method': 'ui_automation' if key == 'settings' else 'real_product',
                         'evidence': str(raw_path.relative_to(ROOT)), 'evidence_sha256': sha(raw_path), 'checks': names}
    passed = all(row['result'] == 'passed' for row in features.values())
    detail = {'schema_version': 1, 'app_id': 'clipbook', 'spec_digest': spec['digest'], 'features': features,
              'summary': f"Clip 基础功能 {'通过' if passed else '失败'}；{len(checks)} 项真实检查；{'实际已装原件' if binding.get('phase') == 'installed' else '候选包，未安装'}；iCloud 为隔离本机链路",
              'scope': raw['scope'], 'binding': binding, 'error': failure}
    (out / 'product_basics.detail.json').write_text(json.dumps(detail, ensure_ascii=False, indent=2) + '\n')
    print(detail['summary'])
    if failure:
        print(failure)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
