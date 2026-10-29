#!/bin/bash
# Read-only contract, also run by Xcode before each build.
set -euo pipefail
cd "$(dirname "$0")"
PY="${PYTHON:-$HOME/Dev/.venv/bin/python}"
[ -x "$PY" ] || PY=python3
"$PY" -B - <<'PY'
from pathlib import Path
import json, struct, yaml
spec = yaml.safe_load(Path('project.yml').read_text())
cloud = yaml.safe_load(Path('../cloud-project.yml').read_text())['targets']['Clipbook']
target = spec['targets']['Clip']
settings = {**spec['settings']['base'], **target['settings']['base']}
version = str(cloud['settings']['base']['MARKETING_VERSION'])
assert str(settings['MARKETING_VERSION']) == version, 'Store version differs from cloud-project.yml'
release = Path('../build/local-release/release.json')
if release.exists():
    assert str(json.loads(release.read_text())['version']) == version, 'Store version differs from public release'
properties = target['info']['properties']
assert set(cloud['info']['properties']) <= set(properties), 'Existing Cloud Info keys must be retained'
assert settings['PRODUCT_BUNDLE_IDENTIFIER'] == 'cyou.tianli.clipbook'
assert properties['LSApplicationCategoryType'] == 'public.app-category.productivity'
entitlements = target['entitlements']['properties']
assert entitlements['com.apple.security.app-sandbox'] is True
assert not any('temporary-exception' in key for key in entitlements)
assert 'APP_STORE' in settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'].split()
excludes = target['sources'][0]['excludes']
assert 'Native/ClipCLI.swift' not in excludes, 'Store must ship the registered family CLI'
assert 'Native/RuntimeSelfTest.swift' not in excludes, 'Store CLI must retain the production runtime acceptance entry'
for source in ['Shared/AppLifecycleCLI.swift', 'Shared/AppLifecycle.swift', 'Shared/AppLifecycleUI.swift']:
    assert source in excludes, 'Store must not link the downloadable app updater'
assert any('../../MacOS/Clipbook' in script['script'] and '/bin/clip' in script['script']
           for script in target.get('postBuildScripts', [])), 'Seal the clip link before signing'
assert entitlements['com.apple.developer.icloud-container-identifiers'] == ['iCloud.cyou.tianli.clip']
assert entitlements['com.apple.developer.icloud-services'] == ['CloudKit']
assert entitlements['com.apple.developer.icloud-container-environment'] == 'Production'
assert entitlements['com.apple.developer.aps-environment'] == 'production'
assert not list(Path('../Sources').rglob('*sync-conflict-*')), 'Reconcile source conflict copies first'
iconset = Path('Assets.xcassets/AppIcon.appiconset')
contents = json.loads((iconset/'Contents.json').read_text())
assert len(contents['images']) == 10
for image in contents['images']:
    size = int(image['size'].split('x')[0]) * int(image['scale'][0])
    data = (iconset/image['filename']).read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack('>II', data[16:24]) == (size,size)
print(f'store/check.sh: ok (version {version}, {len(entitlements)} entitlements, 10 icon PNGs)')
PY
