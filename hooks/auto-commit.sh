#!/usr/bin/env bash
# Stages tracked + untracked changes and commits with an auto-generated
# message. NEVER pushes. Skips silently if there's nothing to commit.
set -uo pipefail
cd "$(dirname "$0")/.."

# Bail if there's nothing to commit.
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  echo "no changes to commit"
  exit 0
fi

# Stage everything that's tracked or already-staged or new (but respect .gitignore).
git add -A

# Build a short message: list of changed files, capped.
CHANGED=$(git diff --cached --name-only | head -10 | sed 's/^/  - /')
COUNT=$(git diff --cached --name-only | wc -l | tr -d ' ')
SUMMARY="auto: update ${COUNT} file(s) after Claude turn"

git commit -m "$(cat <<EOF
${SUMMARY}

Files:
${CHANGED}
EOF
)" || { echo "commit failed"; exit 1; }

echo "committed $(git rev-parse --short HEAD)"
