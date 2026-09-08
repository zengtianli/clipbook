#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
variant="${1:-current}"
case "$variant" in baseline|current) ;; *) exit 2 ;; esac
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh
xcode_env_use macosx
probe_dir="$PWD/build/memory-probe-$variant"
mkdir -p "$probe_dir"
source_dir="$PWD/Sources"
if [ "$variant" = baseline ]; then source_dir="$PWD/build/memory-baseline/Sources"; fi
cp "$source_dir/ClipbookApp.swift" "$probe_dir/ProbeApp.swift"
python3 - "$probe_dir/ProbeApp.swift" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]);s=p.read_text();s=s.replace('static func main() {', 'static func main() {\n        if CommandLine.arguments.contains("--memory-probe") { exit(MainActor.assumeIsolated { MemoryProbe.run() }) }',1);p.write_text(s)
PY
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 "$source_dir"/Native/*.swift "$probe_dir/ProbeApp.swift" tests/MemoryProbe.swift -o "$probe_dir/probe"
CLIPBOOK_HOME="$PWD/build/memory-fixture" CLIPBOOK_PREFERENCES_SUITE="Clip.MemoryProbe.$variant" "$probe_dir/probe" --memory-probe
