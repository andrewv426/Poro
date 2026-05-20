#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
xcodebuild \
  -project Poro.xcodeproj \
  -scheme Poro \
  -configuration Debug \
  -destination 'platform=macOS' \
  build \
  -quiet
