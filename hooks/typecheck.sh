#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Collect all Swift files under Poro/ except the ones that the project-wide
# typecheck can't resolve standalone (entry points and SPM-backed files).
FILES=$(find Poro -name '*.swift' \
  ! -path 'Poro/App/AppDelegate.swift' \
  ! -path 'Poro/KeyboardShortcuts.swift' \
  ! -path 'Poro/PoroApp.swift')

if [ -z "$FILES" ]; then
  echo "no Swift files found under Poro/"
  exit 1
fi

# shellcheck disable=SC2086
swiftc -typecheck $FILES
