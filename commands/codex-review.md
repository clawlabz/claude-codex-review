# Codex Review — Cross-Model Review Orchestrator

You are orchestrating a code review using OpenAI Codex as an independent reviewer. Your role is to gather context, dispatch to Codex, evaluate findings, fix valid issues, and iterate until the review passes.

## Instructions

Parse the user's arguments: `$ARGUMENTS`

Default values:
- **mode**: `diff` (options: diff, commit, file, dir, doc, pr)
- **max_rounds**: `3`
- **auto_fix**: `true`
- **strict**: `false`
- **base**: `main`
- **custom_prompt**: empty

Argument parsing examples:
- `/codex-review` → mode=diff, uncommitted changes
- `/codex-review diff --base develop` → diff against develop
- `/codex-review file src/auth.ts` → review specific file
- `/codex-review dir src/lib/ --rounds 5` → review directory, 5 rounds
- `/codex-review doc docs/design.md` → review document
- `/codex-review pr #42` → review pull request
- `/codex-review --no-fix` → report only
- `/codex-review --prompt "Focus on security"` → custom instructions

## Step 1: Pre-flight Checks

1. Verify `codex` CLI is available: `which codex`
2. Check if in a git repo (for diff/commit/pr modes): `git rev-parse --is-inside-work-tree`
3. Check for `.codex-review.json` config in project root and merge with CLI args
4. Report the review configuration to the user before starting

## Step 2: Gather Context

Based on mode, collect review material:

**For `diff` mode:**
```bash
# Show what will be reviewed
git diff --stat [--base <branch>...HEAD | (staged + unstaged)]
```

**For `commit` mode:**
```bash
git show --stat <sha>
```

**For `file` mode:**
- Read each target file
- Report file sizes

**For `dir` mode:**
- List files via `git ls-files <dir>` or filesystem scan
- Report file count and total size

**For `doc` mode:**
- Read the document
- Report word/line count

**For `pr` mode:**
```bash
gh pr view <number> --json title,body,files
gh pr diff <number>
```

Tell the user what context was gathered (file count, diff size, etc.)

## Step 3: Dispatch to Codex

Run the review using Codex CLI. Use the Bash tool:

**Git-based reviews (preferred — uses Codex's native review):**
```bash
# Uncommitted changes
codex review --uncommitted

# Branch diff
codex review --base <branch>

# Specific commit
codex review --commit <sha>

# With custom prompt
codex review --uncommitted "Focus on security and error handling"
```

**File/dir/doc reviews (use codex exec):**
```bash
# Pipe context
echo "<gathered context>" | codex exec "Review this code for bugs, security issues, performance, and quality. List findings with severity (CRITICAL/HIGH/MEDIUM/LOW), location, description, and fix." --full-auto -o /tmp/codex-review-result.md
```

**Important:**
- Set a reasonable timeout (120s default)
- If Codex fails, report the error clearly and suggest fixes (auth, connectivity)
- Capture the full output

## Step 4: Evaluate Codex Findings

Read the Codex review output. For each finding:

1. **Classify severity**: CRITICAL / HIGH / MEDIUM / LOW
2. **Validate the finding**: Is this a real issue or false positive?
   - Read the referenced code to verify
   - Check if the suggestion aligns with project patterns (check CLAUDE.md, existing code style)
   - Consider if the fix would break other things
3. **Decision**:
   - **Accept**: Issue is valid → queue for fix
   - **Reject**: False positive → note rejection reason
   - **Downgrade**: Severity is overstated → adjust

Report your evaluation to the user:
```
### Codex Findings Evaluation (Round N)

| # | Severity | Location | Issue | Verdict | Reason |
|---|----------|----------|-------|---------|--------|
| 1 | CRITICAL | auth.ts:42 | SQL injection | ✅ Accept | Confirmed: unparameterized query |
| 2 | HIGH | api.ts:18 | Missing error handling | ✅ Accept | No try/catch on async call |
| 3 | MEDIUM | utils.ts:3 | Unused import | ❌ Reject | Import is used via re-export |
| 4 | LOW | config.ts:7 | Magic number | ℹ️ Note | Valid but not worth fixing now |
```

## Step 5: Fix Cycle (if auto_fix enabled)

For each accepted finding (CRITICAL, HIGH, and MEDIUM if --strict):

1. Read the affected file
2. Apply the fix using the Edit tool
3. Verify with build/lint if available:
   ```bash
   # Try project-specific commands
   pnpm build 2>&1 | tail -20  # or npm run build, cargo build, go build, etc.
   ```
4. If fix causes build error → revert and mark as "manual fix needed"
5. Log the fix: what changed, why, before→after

## Step 6: Re-Review (if fixes were applied)

If there were CRITICAL or HIGH fixes AND round < max_rounds:

1. Increment round counter
2. Re-run Codex review on the new state (same mode)
3. Go back to Step 4

**Stop conditions:**
- No CRITICAL/HIGH issues found → **PASSED**
- Max rounds reached → **PARTIAL** (report remaining issues)
- No fixable issues (all rejected or LOW) → **PASSED WITH NOTES**

## Step 7: Final Report

Output the complete review report:

```markdown
## 🔍 Codex Review Report

**Mode**: diff (--base main)
**Rounds**: 2/3
**Status**: ✅ PASSED

### Round 1 — 4 findings
| # | Severity | Location | Issue | Action |
|---|----------|----------|-------|--------|
| 1 | 🔴 CRITICAL | auth.ts:42 | SQL injection | ✅ Fixed |
| 2 | 🟡 HIGH | api.ts:18 | Missing error handling | ✅ Fixed |
| 3 | 🔵 MEDIUM | utils.ts:3 | Unused import | ❌ Rejected (false positive) |
| 4 | ⚪ LOW | config.ts:7 | Magic number | ℹ️ Noted |

### Round 2 — 0 findings
No issues found. Review passed.

### Summary
- **Total findings**: 4
- **Fixed**: 2
- **Rejected**: 1 (false positive)
- **Noted**: 1 (low severity)
- **Remaining**: 0
```

## Error Recovery

- **Codex not installed**: `npm i -g @openai/codex`
- **Codex not authenticated**: `codex login`
- **Empty diff**: "Nothing to review — working tree is clean"
- **Codex timeout**: Retry once with shorter context; if still fails, report partial
- **Build breaks after fix**: Revert the fix, mark as manual, continue with other fixes
- **MCP connection failed**: Fall back to CLI mode automatically

## Key Rules

1. **Never blindly apply Codex suggestions** — always validate against project context
2. **Preserve project conventions** — Codex doesn't know your patterns, you do
3. **Be transparent** — show the user exactly what Codex found and your evaluation
4. **Fix conservatively** — prefer minimal, safe fixes over ambitious refactors
5. **Report honestly** — if you disagree with Codex, explain why
