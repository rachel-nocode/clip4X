#!/usr/bin/env bash
set -euo pipefail

# Build the debug binary, code-sign it with a stable Developer ID identity, and
# run it. Signing gives the binary a stable designated requirement so the macOS
# Keychain "Always Allow" choice persists across rebuilds — otherwise every
# `swift run` produces a new unsigned identity and re-prompts for the password.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_ID="${DEV_ID:-Developer ID Application: Rachel Larralde (5U92RP4C5J)}"
ENTITLEMENTS="$ROOT/Clip4X.entitlements"
BINARY="$ROOT/.build/debug/Clip4X"

cd "$ROOT"
swift build
codesign --force --options runtime --timestamp=none \
  --entitlements "$ENTITLEMENTS" \
  --sign "$DEV_ID" "$BINARY"

exec "$BINARY"
