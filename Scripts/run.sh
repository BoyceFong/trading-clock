#!/bin/bash
# Dev run (bare executable, no .app): login items are disabled in this mode.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

exec swift run --package-path "$ROOT_DIR" -c debug TradingClock "$@"
