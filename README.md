# codex-review

Cross-model code review skill for [Claude Code](https://claude.ai/code). Uses OpenAI Codex as an independent reviewer, with Claude orchestrating the fix-and-review loop.

## Why?

Two models catch more bugs than one. Codex and Claude have different training data, different blindspots, and different strengths. This skill lets them collaborate: Codex reviews, Claude evaluates and fixes, then Codex re-reviews — until the code passes or max rounds are reached.

## Install

### One-line install (recommended)

```bash
# Add the slash command to Claude Code
claude install-skill clawlabz/codex-review
```

### Manual install

```bash
# 1. Clone
git clone https://github.com/clawlabz/codex-review.git ~/.claude/skills/codex-review

# 2. Copy the command file
cp ~/.claude/skills/codex-review/commands/codex-review.md ~/.claude/commands/codex-review.md
```

### Prerequisites

```bash
# Install Codex CLI
npm i -g @openai/codex

# Authenticate
codex login

# Register MCP server (optional, for tighter integration)
claude mcp add codex -s user -- codex mcp-server
```

## Usage

```bash
# Review uncommitted changes (default)
/codex-review

# Review branch diff against main
/codex-review diff --base main

# Review a specific commit
/codex-review commit abc1234

# Review specific files
/codex-review file src/lib/auth.ts src/lib/session.ts

# Review a directory
/codex-review dir packages/engine/src/

# Review a design document
/codex-review doc docs/architecture.md

# Review a pull request
/codex-review pr #42

# Custom review focus
/codex-review diff --prompt "Focus on security and SQL injection"

# Report only (no auto-fix)
/codex-review --no-fix

# Strict mode (treat warnings as errors)
/codex-review --strict

# More review rounds
/codex-review --rounds 5
```

## How It Works

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│ 1. Gather   │────▶│ 2. Codex     │────▶│ 3. Claude   │
│    Context   │     │    Reviews    │     │    Evaluates │
└─────────────┘     └──────────────┘     └──────┬──────┘
                                                 │
                         ┌───────────────────────┘
                         ▼
                    ┌─────────┐    ┌──────────────┐
                    │ 4. Fix  │───▶│ 5. Re-Review │──▶ Loop until
                    │  Issues │    │    (Codex)   │    PASS or
                    └─────────┘    └──────────────┘    max rounds
```

1. **Gather Context** — Collects git diff, files, or documents based on mode
2. **Codex Reviews** — Dispatches to Codex CLI (`codex review` or `codex exec`)
3. **Claude Evaluates** — Validates each finding against project context, rejects false positives
4. **Fix Issues** — Claude applies minimal, safe fixes for confirmed issues
5. **Re-Review** — Codex reviews the fixed code; loop continues until passing

## Review Modes

| Mode | Best For | Example |
|------|----------|---------|
| `diff` | Pre-commit / pre-merge review | `/codex-review diff --base main` |
| `commit` | Post-commit audit | `/codex-review commit HEAD` |
| `file` | Focused file review | `/codex-review file auth.ts` |
| `dir` | Module-level review | `/codex-review dir src/api/` |
| `doc` | Architecture/design review | `/codex-review doc DESIGN.md` |
| `pr` | Pull request review | `/codex-review pr #42` |

## Configuration

Create `.codex-review.json` in your project root (optional):

```json
{
  "maxRounds": 3,
  "autoFix": true,
  "strict": false,
  "defaultBase": "main",
  "ignorePatterns": ["*.test.ts", "migrations/*"],
  "customPrompt": "This is a Next.js project. Focus on SSR safety.",
  "severityThreshold": "HIGH"
}
```

## Output

Each review produces a structured report:

```
## Codex Review Report

Mode: diff (--base main) | Rounds: 2/3 | Status: PASSED

### Round 1 — 3 findings
| Severity | Location      | Issue                | Action         |
|----------|---------------|----------------------|----------------|
| CRITICAL | auth.ts:42    | SQL injection        | Fixed          |
| HIGH     | api.ts:18     | Missing error handler| Fixed          |
| LOW      | config.ts:7   | Magic number         | Noted          |

### Round 2 — 0 findings
Review passed.
```

## Requirements

- [Claude Code](https://claude.ai/code) (CLI, desktop, or IDE extension)
- [Codex CLI](https://github.com/openai/codex) >= 0.100.0
- Node.js >= 18
- Git (for diff/commit/pr modes)
- [GitHub CLI](https://cli.github.com/) (for pr mode only)

## License

MIT
