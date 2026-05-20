#!/usr/bin/env bash
# Orchestrator. Runs in order: typecheck (hard) → lint (hard) → build (soft) → auto-commit.
# Exits non-zero if any HARD check fails. Soft failures print a warning but
# do not block the Claude Code Stop hook. Auto-commit only runs on green.
set -uo pipefail

cd "$(dirname "$0")/.."

FAIL=0

echo "▶ typecheck"
if ! ./hooks/typecheck.sh; then
  echo "✗ typecheck failed"
  FAIL=1
fi

echo "▶ lint"
if ! ./hooks/lint.sh; then
  echo "✗ lint failed — run 'swiftformat Poro/' to auto-fix"
  FAIL=1
fi

echo "▶ build (soft)"
if ! ./hooks/build.sh; then
  echo "⚠ build failed (soft — known KeyboardShortcuts SPM CLI issue, see RepoContext.md)"
fi

if [ $FAIL -eq 0 ]; then
  echo "▶ auto-commit"
  ./hooks/auto-commit.sh || echo "⚠ auto-commit skipped or failed (non-blocking)"
fi

exit $FAIL
