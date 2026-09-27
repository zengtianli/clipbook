#!/bin/bash
# recovery acceptance: build the current source, then run `Clipbook --recovery-test` on an isolated data
# dir: reopen/WAL persistence, externally deleted blobs, corrupt database, missing Deck source,
# unreachable link-title host. Non-interactive; no window or input.
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/accept/_build.sh
isolated_env
run_selftest_entry recovery --recovery-test
