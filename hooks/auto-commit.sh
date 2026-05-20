#!/usr/bin/env bash
# Stages tracked + untracked changes and commits with a Claude-generated
# message describing what changed. NEVER pushes. Skips if nothing to commit.
set -uo pipefail
cd "$(dirname "$0")/.."

# Bail if there's nothing to commit.
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  echo "no changes to commit"
  exit 0
fi

# Stage everything that's tracked or already-staged or new (respects .gitignore).
git add -A

# Collect the staged diff + name-status for Claude to summarize.
DIFF_NAMES=$(git diff --cached --name-status)
DIFF_FULL=$(git diff --cached --stat)
# Bound the actual patch body — huge diffs aren't worth paying tokens for.
DIFF_BODY=$(git diff --cached | head -c 12000)

PROMPT=$(cat <<PROMPT_EOF
Write a single-line git commit message subject for the diff below. Rules:
- Use the conventional commits style when it fits: \`fix:\`, \`feat:\`, \`refactor:\`, \`docs:\`, \`style:\`, \`chore:\`, \`test:\`. If none fit, omit the prefix entirely.
- Max 72 chars.
- Describe what changed and why, not just the file list.
- Imperative mood ("add", "fix", "remove"), not past tense.
- No trailing period.
- Output ONLY the subject line. No explanation, no quotes, no markdown.

Changed files:
$DIFF_NAMES

Diff stat:
$DIFF_FULL

Diff body (truncated to 12k chars):
$DIFF_BODY
PROMPT_EOF
)

# Try Claude. If it fails or returns empty, surface the failure and bail.
if ! command -v claude >/dev/null 2>&1; then
  echo "auto-commit failed: 'claude' CLI not found in PATH" >&2
  echo "  staged changes remain staged — commit manually or install Claude Code" >&2
  exit 1
fi

SUBJECT=$(printf '%s' "$PROMPT" | claude -p --output-format text 2>/dev/null | head -1 | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [ -z "$SUBJECT" ]; then
  echo "auto-commit failed: claude -p returned empty subject" >&2
  echo "  staged changes remain staged — commit manually with 'git commit'" >&2
  exit 1
fi

# Strip wrapping quotes if Claude added them despite the instructions.
SUBJECT="${SUBJECT#\"}"
SUBJECT="${SUBJECT%\"}"
SUBJECT="${SUBJECT#\'}"
SUBJECT="${SUBJECT%\'}"

# Commit. Body lists the changed files (capped) for an audit trail.
CHANGED=$(git diff --cached --name-only | head -10 | sed 's/^/  - /')
git commit -m "$(cat <<COMMIT_EOF
$SUBJECT

Files:
$CHANGED
COMMIT_EOF
)" || { echo "commit failed"; exit 1; }

echo "committed $(git rev-parse --short HEAD): $SUBJECT"
