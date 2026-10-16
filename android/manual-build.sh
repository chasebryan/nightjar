#!/usr/bin/env bash
# Compatibility entry point for the former machine-specific manual pipeline.
set -euo pipefail
exec "$(dirname "$0")/build-release.sh" "$@"
