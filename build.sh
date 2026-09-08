#!/bin/bash
# CloudKit builds need Xcode-managed provisioning; build-cloud.sh owns the pipeline.
exec "$(cd "$(dirname "$0")" && pwd)/build-cloud.sh" "$@"
