# claude-codex-review

A [Claude Code](https://claude.ai/code) slash command that uses OpenAI Codex as an independent reviewer. Two models, one review loop — Codex reviews, Claude evaluates and fixes, Codex re-reviews.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/clawlabz/claude-codex-review/main/install.sh | bash
```

Restart Claude Code — `/codex-review` is ready.

### Prerequisites

Codex CLI must be installed and authenticated:

```bash
npm i -g @openai/codex && codex login
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

# Full project assessment (completeness, quality, architecture, etc.)
/codex-review project

# Project completeness audit only
/codex-review project --focus completeness

# Quality + security focused
/codex-review project --focus quality,security

# Free-form question about the codebase
/codex-review ask "Is the NPC system well-designed? Where are the bottlenecks?"

# Performance review of a module
/codex-review dir src/lib/ --focus performance

# Report only (no auto-fix)
/codex-review --no-fix

# Strict mode (treat warnings as errors)
/codex-review --strict

# More review rounds
/codex-review --rounds 5
```

### Focus Dimensions

Control what gets evaluated with `--focus` (comma-separated):

| Focus | Evaluates |
|-------|-----------|
| `bugs` | Logic errors, edge cases, crash risks |
| `security` | Vulnerabilities, injection, auth, secrets |
| `quality` | Style, readability, naming, complexity |
| `performance` | N+1 queries, memory, unnecessary work |
| `architecture` | Coupling, patterns, separation of concerns |
| `completeness` | TODOs, stubs, missing features, dead code |
| `testing` | Coverage gaps, missing cases, flaky tests |
| `types` | Type safety, any-casts, missing types |
| `all` | Everything (default for `project` mode) |

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

### Dispatch Strategy

Different modes use different Codex capabilities:

| Mode | Codex Command | How Context is Passed |
|------|---------------|----------------------|
| diff | `codex review --uncommitted` | Native git integration — Codex reads repo directly |
| commit | `codex review --commit <sha>` | Native git integration |
| pr | `codex review --base <branch>` | Native git integration |
| file (small) | `codex exec` | File contents piped via stdin |
| dir (small) | `codex exec` | File contents piped via stdin |
| file/dir (large) | `codex exec -C <dir> -s read-only` | Codex explores filesystem itself |
| doc | `codex exec` | Document piped via stdin |
| **project** | `codex exec -C <dir> -s read-only` | **Codex agent explores the codebase autonomously** |
| **ask** | `codex exec -C <dir> -s read-only` | **Codex agent navigates files to find answers** |

Key insight: `codex exec` is an **agent**, not a text processor. For `project` and `ask` modes, Claude sends a lightweight project brief + review instructions, then Codex autonomously navigates the codebase (`ls`, `cat`, `grep`, etc.) to build its own understanding.

## Review Modes

| Mode | Best For | Auto-Fix | Example |
|------|----------|----------|---------|
| `diff` | Pre-commit / pre-merge | Yes | `/codex-review diff --base main` |
| `commit` | Post-commit audit | Yes | `/codex-review commit HEAD` |
| `file` | Focused file review | Yes | `/codex-review file auth.ts` |
| `dir` | Module-level review | Yes | `/codex-review dir src/api/` |
| `doc` | Document review | No | `/codex-review doc DESIGN.md` |
| `pr` | Pull request review | Yes | `/codex-review pr #42` |
| `project` | Full project assessment | No | `/codex-review project` |
| `ask` | Free-form question | No | `/codex-review ask "Is X well-designed?"` |

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
