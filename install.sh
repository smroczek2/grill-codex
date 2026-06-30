#!/usr/bin/env bash
#
# install.sh — make the grill-codex skill available in EVERY project for your
# user, by symlinking it into ~/.claude/skills/. A symlink means a later
# `git pull` in this repo updates the skill everywhere automatically.
#
# (Prefer installing as a Claude Code plugin instead? See the README.)
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$REPO_DIR/plugins/grill-codex/skills/grill-codex"
SKILLS_DIR="${HOME}/.claude/skills"
DEST="$SKILLS_DIR/grill-codex"

[[ -f "$SKILL_SRC/SKILL.md" ]] \
  || { echo "ERROR: can't find SKILL.md at $SKILL_SRC — run this from inside the repo." >&2; exit 1; }

chmod +x "$SKILL_SRC/ask-codex.sh" 2>/dev/null || true
mkdir -p "$SKILLS_DIR"

if [[ -e "$DEST" || -L "$DEST" ]]; then
  echo "→ $DEST already exists; replacing it."
  rm -rf "$DEST"
fi

ln -s "$SKILL_SRC" "$DEST"
echo "✓ Linked grill-codex into $DEST"
echo "  (source: $SKILL_SRC)"

if command -v codex >/dev/null 2>&1; then
  echo "✓ codex CLI found: $(command -v codex)"
else
  echo "⚠ codex CLI NOT found. Install it and log in before using the skill:"
  echo "    npm i -g @openai/codex && codex login"
fi

cat <<'EOF'

Done. In any project, open Claude Code and say:

    grill codex about <your feature / change / design>

To uninstall: rm ~/.claude/skills/grill-codex
EOF
