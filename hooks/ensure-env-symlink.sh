#!/usr/bin/env bash
# Ensures Poro/Poro.env exists (as a symlink to ~/.config/poro/env).
# The sandboxed app can only read files bundled at build time, so every
# worktree needs this file present in the source tree. See CLAUDE.md.
#
# Behavior:
#   - Real file or working symlink → no-op (silent).
#   - Missing entirely → create symlink.
#   - Broken symlink (target doesn't exist) → remove and recreate.
#   - Source ~/.config/poro/env missing → warn but exit 0 (don't break hooks).
set -uo pipefail

cd "$(dirname "$0")/.."

TARGET="Poro/Poro.env"
SOURCE="$HOME/.config/poro/env"

# Real file or working symlink — leave it alone.
if [ -e "$TARGET" ]; then
  exit 0
fi

# Source must exist before we can link to it.
if [ ! -e "$SOURCE" ]; then
  echo "⚠ Poro/Poro.env missing and ~/.config/poro/env not found — fill ~/.config/poro/env with your keys, then re-run."
  exit 0
fi

# Broken symlink (-L true, -e false): remove the dangling reference so ln -s succeeds.
if [ -L "$TARGET" ]; then
  broken_target="$(readlink "$TARGET")"
  rm "$TARGET"
  echo "▶ removed broken Poro/Poro.env symlink → $broken_target"
fi

ln -s "$SOURCE" "$TARGET"
echo "▶ created Poro/Poro.env → $SOURCE"
