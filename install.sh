#!/usr/bin/env bash
# install.sh — One-line installer for claude-codex-review
# Usage: curl -fsSL https://raw.githubusercontent.com/clawlabz/claude-codex-review/main/install.sh | bash
set -euo pipefail

REPO="clawlabz/claude-codex-review"
BRANCH="main"
BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"
CMD_DIR="$HOME/.claude/commands"
CMD_FILE="$CMD_DIR/codex-review.md"

echo "Installing claude-codex-review..."

# 1. Create commands directory
mkdir -p "$CMD_DIR"

# 2. Download the slash command
curl -fsSL "$BASE/commands/codex-review.md" -o "$CMD_FILE"
echo "  ✓ /codex-review command installed"

# 3. Check codex CLI
if command -v codex &>/dev/null; then
  echo "  ✓ codex CLI found ($(codex --version 2>/dev/null || echo 'unknown version'))"
else
  echo "  ✗ codex CLI not found — install with: npm i -g @openai/codex"
  echo "    Then run: codex login"
fi

echo ""
echo "Done! Restart Claude Code, then use /codex-review"
echo ""
echo "Quick start:"
echo "  /codex-review                          # review uncommitted changes"
echo "  /codex-review project                  # full project assessment"
echo "  /codex-review project --focus quality   # code quality audit"
echo "  /codex-review ask \"Is the auth secure?\" # free-form question"
