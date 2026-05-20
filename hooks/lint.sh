#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v swiftformat >/dev/null 2>&1; then
  echo "swiftformat not installed — run 'brew install swiftformat'"
  exit 1
fi
swiftformat --lint Poro/
