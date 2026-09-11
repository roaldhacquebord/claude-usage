#!/bin/bash
# Runs the tests with Xcode's toolchain; the Command Line Tools can't run Swift Testing.
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
exec swift test "$@"
