---
name: codex-review
description: >
  Cross-model code review using OpenAI Codex as an independent reviewer.
  Supports 8 modes: git diff, commit, file, dir, doc, PR, project-wide assessment,
  and free-form questions. Configurable focus dimensions (bugs, security, quality,
  performance, architecture, completeness, testing, types).
  Iterates fix-and-review cycles until passing or max rounds reached.
  Use when: code review, PR review, architecture review, project completeness audit,
  code quality assessment, or any question that benefits from a second-opinion AI model.
metadata:
  author: https://github.com/clawlabz
  version: "1.0.0"
  domain: code-quality
  triggers: codex review, cross-model review, second opinion, code audit, PR review
  role: orchestrator
  scope: workflow
  output-format: markdown
---

# Codex Review — Cross-Model Review Orchestrator

A skill that uses OpenAI Codex as an independent reviewer to provide a "second opinion" on code changes, architecture decisions, and implementation quality. Claude orchestrates the workflow: gathering context, dispatching to Codex, evaluating findings, fixing issues, and re-submitting until the review passes.

## When to Activate

- User invokes `/codex-review` with optional arguments
- User asks for a "second opinion" or "cross-model review"
- User wants Codex to review their code, PR, or architecture
- User wants an independent audit before merging or deploying

## Prerequisites

- **Codex CLI** installed: `npm i -g @openai/codex`
- **Codex MCP** registered in Claude Code: `claude mcp add codex -s user -- codex mcp-server`
- **OpenAI API key** configured for Codex (via `codex login` or env var)

## Usage

```
/codex-review [mode] [target] [--rounds N] [--fix] [--prompt "custom instructions"]
```

### Modes

| Mode | Target | What Gets Reviewed | Fix Loop |
|------|--------|--------------------|----------|
| `diff` (default) | `--base main` | Uncommitted changes or branch diff | Yes |
| `commit` | `<sha>` | A specific commit | Yes |
| `file` | `path/to/file.ts` | One or more specific files | Yes |
| `dir` | `src/lib/` | All files in a directory | Yes |
| `doc` | `docs/design.md` | A document (PRD, design doc, plan) | No |
| `pr` | `#123` or URL | Pull request (fetches diff via gh) | Yes |
| `project` | (entire repo) | Holistic project assessment | No |
| `ask` | `"question"` | Free-form question about the codebase | No |

### Focus Dimensions

Control WHAT Codex evaluates with `--focus`:

| Focus | What It Evaluates |
|-------|-------------------|
| `bugs` | Logic errors, edge cases, crash risks |
| `security` | Vulnerabilities, injection, auth, secrets |
| `quality` | Code style, readability, naming, complexity |
| `performance` | N+1 queries, memory leaks, unnecessary computation |
| `architecture` | Separation of concerns, coupling, patterns |
| `completeness` | Missing features, TODOs, stub implementations |
| `testing` | Test coverage, missing cases, flaky patterns |
| `types` | Type safety, any-casts, missing types |
| `all` | Everything above (default for `project` mode) |

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--rounds` | `3` | Maximum review-fix cycles |
| `--focus` | auto | Comma-separated focus dimensions |
| `--fix` | `true` | Auto-fix issues found by Codex |
| `--no-fix` | — | Report only, no auto-fix |
| `--prompt` | — | Custom review instructions appended to context |
| `--strict` | `false` | Treat warnings as errors |

### Examples

```bash
# Review uncommitted changes (default)
/codex-review

# Review current branch against main
/codex-review diff --base main

# Review a specific commit
/codex-review commit abc1234

# Review specific files
/codex-review file src/lib/auth.ts src/lib/session.ts

# Review a directory
/codex-review dir packages/game-engine/src/modes/

# Review a design document
/codex-review doc docs/plans/architecture.md

# Review a PR
/codex-review pr #42

# Full project assessment
/codex-review project

# Project completeness audit
/codex-review project --focus completeness

# Quality + security focused review
/codex-review project --focus quality,security

# Free-form question about the codebase
/codex-review ask "NPC系统设计是否合理？性能瓶颈在哪？"

# Performance review of a specific module
/codex-review dir src/lib/ --focus performance

# Review with custom prompt, max 5 rounds
/codex-review diff --rounds 5 --prompt "Focus on error handling"

# Report only, no fixes
/codex-review diff --no-fix
```

## Workflow

### Phase 1: Context Gathering

Based on the mode, collect the review context:

1. **diff**: Run `git diff` (staged + unstaged) or `git diff <base>...HEAD`
2. **commit**: Run `git show <sha>`
3. **file**: Read the specified file(s)
4. **dir**: List and read files in the directory (respect .gitignore)
5. **doc**: Read the document
6. **pr**: Run `gh pr diff <number>` to get the PR diff

Also gather supplementary context:
- Project README or CLAUDE.md (for project conventions)
- Recent git log (5 commits) for commit style context
- File structure overview if reviewing a directory

### Phase 2: Codex Review Dispatch

Use the **Codex CLI** `review` command for git-based reviews (fastest path):

```bash
# For uncommitted changes
codex review --uncommitted --json

# For branch diff
codex review --base main --json

# For specific commit
codex review --commit <sha> --json

# With custom prompt
codex review --uncommitted "Focus on security vulnerabilities" --json
```

For non-git reviews (files, docs), use `codex exec`:

```bash
# Pipe context to codex exec
echo "<context>" | codex exec - --json -o /tmp/codex-review-output.md
```

Alternatively, if the MCP server is available, use the MCP tool directly within Claude Code session for tighter integration.

### Phase 3: Review Evaluation

Parse the Codex review output. Classify each finding:

| Severity | Action |
|----------|--------|
| **CRITICAL** | Must fix before proceeding |
| **HIGH** | Should fix, blocks approval |
| **MEDIUM** | Fix if `--strict`, otherwise warn |
| **LOW** | Informational, log only |

**Claude evaluates each finding:**
- Is this a genuine issue or a false positive?
- Does the suggestion align with this project's patterns and conventions?
- Would the suggested fix introduce new problems?

Discard false positives with reasoning. Keep validated findings.

### Phase 4: Fix Cycle (if `--fix` enabled)

For each validated finding (CRITICAL and HIGH, plus MEDIUM if `--strict`):

1. **Claude fixes the issue** using Edit tool
2. **Run project build/lint** to verify no regressions
3. **Log the fix** with before/after context

### Phase 5: Re-Review

After fixes are applied:
1. Increment round counter
2. If `round < max_rounds` and there were CRITICAL/HIGH fixes, re-submit to Codex
3. If no CRITICAL/HIGH issues remain, review passes
4. If max rounds reached, report remaining issues to user

### Phase 6: Report

Output a structured review report:

```markdown
## Codex Review Report

**Mode**: diff (--base main)
**Rounds**: 2/3
**Status**: PASSED ✅

### Round 1
- 🔴 CRITICAL: SQL injection in `auth.ts:42` → Fixed
- 🟡 HIGH: Missing error handling in `api/route.ts:18` → Fixed
- 🔵 MEDIUM: Unused import in `utils.ts:3` → Fixed
- ⚪ LOW: Consider extracting magic number → Noted

### Round 2
- No issues found

### Summary
- Issues found: 4
- Issues fixed: 3
- Issues noted: 1
- Final status: All critical and high issues resolved
```

## Error Handling

| Error | Recovery |
|-------|----------|
| Codex CLI not installed | Print install instructions |
| Codex not authenticated | Suggest `codex login` |
| MCP server not responding | Fall back to CLI mode |
| No git repo (for diff/commit) | Error with suggestion to use `file` or `dir` mode |
| Empty diff | Report "nothing to review" |
| Codex timeout | Retry once, then report partial results |
| Fix introduces build error | Revert fix, report as manual-fix-needed |

## Configuration

The skill respects a `.codex-review.json` in project root (optional):

```json
{
  "maxRounds": 3,
  "autoFix": true,
  "strict": false,
  "defaultBase": "main",
  "ignorePatterns": ["*.test.ts", "*.spec.ts", "migrations/*"],
  "customPrompt": "This is a Next.js 15 + Supabase project. Focus on SSR safety and RLS policies.",
  "severityThreshold": "HIGH"
}
```

## Best Practices

1. **Use for pre-merge gates**: Run `/codex-review diff --base main` before creating a PR
2. **Combine with Claude's review**: Codex catches different things than Claude — use both
3. **Custom prompts matter**: Tell Codex about your stack and conventions for better results
4. **Don't blindly fix**: Claude evaluates each Codex finding — false positives are filtered
5. **Iterate on config**: Tune `.codex-review.json` as you learn what Codex catches well
