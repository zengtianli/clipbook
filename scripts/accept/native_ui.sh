#!/bin/bash
# native_ui acceptance: build the current source, then run the App's in-process offscreen UI self-test
# (`Clipbook --ui-self-test <dir>`): real MainView/SettingsView rendered offscreen, model actions called
# directly, screenshots asserted. Isolated data/preferences/pasteboard; no status item, Dock icon,
# activation, focus change or synthesized input. Exit 0 = pass.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/accept/_build.sh
OUT="${SOP_OUT_DIR:-build/acceptance}/native_ui"
rm -rf "$OUT" && mkdir -p "$OUT"
isolated_env
run_selftest_entry native_ui --ui-self-test "$OUT"
