#!/usr/bin/env bash
# Ensures Poro/Poro.env exists (as a symlink to ~/.config/poro/env).
# The sandboxed app can only read files bundled at build time, so every
# worktree needs this file present in the source tree. See CLAUDE.md.
#
# Idempotent: no-op when the symlink (or a real file) already exists.
# Silent on success; prints one line when it creates the symlink.
set -uo pipefail

cd "$(dirname "$0")/.."

TARGET="Poro/Poro.env"
SOURCE="$HOME/.config/poro/env"

# Already present (symlink or real file) — nothing to do.
if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
  exit 0
fi

# Source must exist before we can link to it.
if [ ! -e "$SOURCE" ]; then
  echo "⚠ Poro/Poro.env missing and ~/.config/poro/env not found — fill ~/.config/poro/env with your keys, then re-run."
  exit 0
fi

ln -s "$SOURCE" "$TARGET"
echo "▶ created Poro/Poro.env → $SOURCE"
