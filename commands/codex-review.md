# Codex Review — Cross-Model Review Orchestrator

You are orchestrating a review using OpenAI Codex as an independent reviewer. Your role is to gather context, dispatch to Codex, evaluate findings, fix valid issues (if applicable), and iterate until the review passes.

## Instructions

Parse the user's arguments: `$ARGUMENTS`

Default values:
- **mode**: `diff` (options: diff, commit, file, dir, doc, pr, project, ask)
- **max_rounds**: `3`
- **auto_fix**: `true`
- **strict**: `false`
- **base**: `main`
- **focus**: auto-detected based on mode
- **custom_prompt**: empty

### Modes

| Mode | Purpose | Fix Loop |
|------|---------|----------|
| `diff` | Review uncommitted or branch changes | Yes |
| `commit` | Review a specific commit | Yes |
| `file` | Review specific files | Yes |
| `dir` | Review a directory/module | Yes |
| `doc` | Review a document (PRD, design, plan) | No (report only) |
| `pr` | Review a pull request | Yes |
| `project` | Holistic project assessment | No (report only) |
| `ask` | Free-form question to Codex about the codebase | No (report only) |

### Focus Dimensions

The `--focus` flag controls WHAT Codex evaluates. Multiple can be combined with commas.

| Focus | What It Evaluates |
|-------|-------------------|
| `bugs` | Logic errors, edge cases, crash risks |
| `security` | Vulnerabilities, injection, auth, secrets |
| `quality` | Code style, readability, naming, complexity |
| `performance` | N+1 queries, memory leaks, unnecessary computation |
| `architecture` | Separation of concerns, coupling, patterns |
| `completeness` | Missing features, TODOs, stub implementations, dead code |
| `testing` | Test coverage, missing test cases, flaky patterns |
| `types` | Type safety, any-casts, missing types |
| `all` | Everything above (default for `project` mode) |

Default focus by mode:
- `diff/commit/pr/file` → `bugs,security,quality`
- `dir` → `bugs,security,quality,architecture`
- `doc` → `completeness,quality`
- `project` → `all`
- `ask` → determined by the user's question

### Argument Parsing Examples

```
/codex-review                                    → diff, uncommitted
/codex-review diff --base develop                → diff against develop
/codex-review file src/auth.ts                   → review specific file
/codex-review dir src/lib/ --rounds 5            → review directory, 5 rounds
/codex-review doc docs/design.md                 → review document
/codex-review pr #42                             → review pull request
/codex-review project                            → full project assessment
/codex-review project --focus completeness       → just completeness audit
/codex-review project --focus quality,security   → quality + security
/codex-review ask "NPC系统设计是否合理？瓶颈在哪？"  → free-form question
/codex-review dir src/ --focus performance       → performance review of src/
/codex-review --no-fix                           → report only, any mode
/codex-review --prompt "Focus on error handling" → custom instructions
```

## Step 1: Pre-flight Checks

1. Verify `codex` CLI is available: `which codex`
2. Check if in a git repo (for git-based modes): `git rev-parse --is-inside-work-tree`
3. Check for `.codex-review.json` config in project root and merge with CLI args
4. Read CLAUDE.md or README.md for project context (passed to Codex as background)
5. Report the review configuration to the user before starting

## Step 2: Gather Context

Based on mode, collect review material:

**For `diff` mode:**
```bash
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
- Exclude node_modules, .git, build artifacts

**For `doc` mode:**
- Read the document
- Report word/line count

**For `pr` mode:**
```bash
gh pr view <number> --json title,body,files
gh pr diff <number>
```

**For `project` mode:**
Gather a holistic view of the project:
1. Read CLAUDE.md, README.md, package.json (or Cargo.toml, go.mod, etc.) for project overview
2. Get project structure: `find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/dist/*' | head -200`
3. Count lines of code: `git ls-files | xargs wc -l 2>/dev/null | tail -1` or `find`-based
4. Get recent git activity: `git log --oneline -20`
5. Check for TODOs/FIXMEs: `grep -r "TODO\|FIXME\|HACK\|XXX" --include="*.ts" --include="*.tsx" --include="*.py" --include="*.rs" --include="*.go" -c`
6. Check test coverage if available
7. List key directories and their purpose
8. Sample representative files from each major module (read 2-3 key files)

**For `ask` mode:**
- The user's question IS the review prompt
- Gather relevant context based on what the question is about:
  - If about a specific module → read those files
  - If about architecture → get project structure + key files
  - If about performance → find hot paths, DB queries, API routes
  - If general → use project-level context (same as `project` mode but lighter)

Tell the user what context was gathered (file count, diff size, etc.)

## Step 3: Build Review Prompt

Construct the Codex prompt based on mode + focus:

**Base template:**
```
You are reviewing a project. Here is the project context:
{CLAUDE.md or README content}

Focus areas: {focus dimensions}

{mode-specific instructions}

{gathered context}

{custom_prompt if provided}

Provide your findings in this format:
## Findings
For each issue:
- **Severity**: CRITICAL / HIGH / MEDIUM / LOW / INFO
- **Category**: {focus dimension it falls under}
- **Location**: file:line (if applicable)
- **Issue**: what's wrong
- **Suggestion**: how to fix or improve
- **Rationale**: why this matters

## Summary
- Overall assessment (1-2 paragraphs)
- Score: X/10 for each focus dimension
- Top 3 priorities to address
```

**Mode-specific prompt additions:**

For `project --focus completeness`:
```
Assess project completeness:
- What features appear planned but unfinished? (TODOs, stubs, placeholder UI)
- What critical functionality is missing for a production-ready product?
- Are there dead code paths or abandoned experiments?
- Is documentation complete?
- Are there integration points that aren't connected?
Score completeness as a percentage with justification.
```

For `project --focus quality`:
```
Assess code quality:
- Naming conventions: are they consistent and descriptive?
- Function/file size: any god functions or god files?
- DRY: is there significant duplication?
- Error handling: is it comprehensive or spotty?
- Type safety: are types well-defined or loose?
- Dependencies: are they well-managed and up to date?
```

For `project --focus architecture`:
```
Assess architecture:
- Is the separation of concerns clear?
- Are dependencies between modules well-managed?
- Is the data flow easy to follow?
- Are there circular dependencies?
- Is the project structure intuitive for a new developer?
- Are abstractions at the right level (not over/under-engineered)?
```

For `ask` mode:
```
The user asks: "{user's question}"
Answer this question thoroughly based on the codebase context provided.
Be specific — reference actual files, functions, and line numbers.
```

## Step 4: Dispatch to Codex

**For git-based reviews (diff/commit/pr):**
```bash
codex review --uncommitted "{focus-aware prompt}"
codex review --base <branch> "{focus-aware prompt}"
codex review --commit <sha> "{focus-aware prompt}"
```

**For all other modes (file/dir/doc/project/ask):**
```bash
# Write context to temp file, pipe to codex exec
cat /tmp/codex-review-context.txt | codex exec "{review prompt}" --full-auto -o /tmp/codex-review-result.md
```

If context is too large (>100KB), split into chunks:
1. Send project overview + structure first
2. Then send detailed file contents in batches
3. Ask Codex to synthesize across batches

**Important:**
- Timeout: 180s for project mode, 120s for others
- If Codex fails, report error and suggest fixes
- Capture full output

## Step 5: Evaluate Codex Findings

Read the Codex review output. For each finding:

1. **Classify severity**: CRITICAL / HIGH / MEDIUM / LOW / INFO
2. **Validate the finding**:
   - Read the referenced code to verify
   - Check if the suggestion aligns with project patterns
   - Consider if the fix would break other things
   - For `project`/`ask` mode: validate factual claims (does the file/function actually exist?)
3. **Decision**:
   - **Accept**: Issue is valid → queue for fix (if fixable mode)
   - **Reject**: False positive → note rejection reason
   - **Downgrade**: Severity is overstated → adjust
   - **Amplify**: Codex underestimated severity → upgrade

Report your evaluation:
```
### Codex Findings Evaluation (Round N)

| # | Severity | Category | Location | Issue | Verdict | Reason |
|---|----------|----------|----------|-------|---------|--------|
| 1 | CRITICAL | security | auth.ts:42 | SQL injection | Accept | Confirmed |
| 2 | HIGH | quality | api.ts:18 | Missing error handling | Accept | No try/catch |
| 3 | MEDIUM | bugs | utils.ts:3 | Unused import | Reject | Used via re-export |
| 4 | INFO | architecture | — | Consider splitting module | Note | Valid suggestion |
```

For `project` and `ask` modes, also present:
- **Scores** per focus dimension (if project mode)
- **Direct answer** to the user's question (if ask mode)
- **Claude's own assessment** — where you agree/disagree with Codex

## Step 6: Fix Cycle (if applicable)

**Only for fixable modes** (diff, commit, file, dir, pr) **with auto_fix enabled**:

For each accepted finding (CRITICAL, HIGH, and MEDIUM if --strict):

1. Read the affected file
2. Apply the fix using the Edit tool
3. Verify with build/lint if available
4. If fix causes build error → revert and mark as "manual fix needed"
5. Log the fix

**For non-fixable modes** (doc, project, ask): skip to Step 8 (Final Report).

## Step 7: Re-Review (if fixes were applied)

If there were CRITICAL or HIGH fixes AND round < max_rounds:

1. Increment round counter
2. Re-run Codex review on the new state
3. Go back to Step 5

**Stop conditions:**
- No CRITICAL/HIGH issues found → **PASSED**
- Max rounds reached → **PARTIAL**
- No fixable issues → **PASSED WITH NOTES**

## Step 8: Final Report

### For fixable modes (diff/commit/file/dir/pr):

```markdown
## Codex Review Report

**Mode**: diff (--base main) | **Focus**: bugs, security, quality
**Rounds**: 2/3 | **Status**: PASSED

### Round 1 — 4 findings
| # | Sev | Category | Location | Issue | Action |
|---|-----|----------|----------|-------|--------|
| 1 | CRITICAL | security | auth.ts:42 | SQL injection | Fixed |
| 2 | HIGH | quality | api.ts:18 | Missing error handler | Fixed |
| 3 | MEDIUM | bugs | utils.ts:3 | Unused import | Rejected |
| 4 | LOW | quality | config.ts:7 | Magic number | Noted |

### Round 2 — 0 findings
Review passed.

### Summary
- Total: 4 | Fixed: 2 | Rejected: 1 | Noted: 1 | Remaining: 0
```

### For project mode:

```markdown
## Codex Project Assessment

**Project**: {name} | **Focus**: {dimensions}
**Files**: {count} | **LOC**: {lines}

### Scores
| Dimension | Score | Notes |
|-----------|-------|-------|
| Completeness | 7/10 | 3 features have TODO stubs |
| Quality | 8/10 | Good naming, some large files |
| Architecture | 9/10 | Clean separation, no circular deps |
| Security | 6/10 | Missing rate limiting on 4 endpoints |
| Performance | 7/10 | 2 N+1 query patterns found |
| Testing | 5/10 | ~40% coverage, no E2E tests |

### Top Priorities
1. {most important finding}
2. {second}
3. {third}

### Detailed Findings
{categorized findings list}

### Claude's Assessment
{your own evaluation — where you agree/disagree with Codex, additional context}
```

### For ask mode:

```markdown
## Codex Analysis

**Question**: {user's question}

### Codex's Answer
{Codex response}

### Claude's Evaluation
{your assessment of Codex's answer — corrections, additional context, agreement}

### Conclusion
{synthesized answer combining both perspectives}
```

## Error Recovery

- **Codex not installed**: `npm i -g @openai/codex`
- **Codex not authenticated**: `codex login`
- **Empty diff**: "Nothing to review — working tree is clean"
- **Codex timeout**: Retry once with shorter context; if still fails, report partial
- **Build breaks after fix**: Revert the fix, mark as manual, continue with other fixes
- **Context too large**: Chunk and summarize; never silently truncate
- **Codex returns garbage**: Report raw output, skip evaluation, suggest retry

## Key Rules

1. **Never blindly apply Codex suggestions** — always validate against project context
2. **Preserve project conventions** — Codex doesn't know your patterns, you do
3. **Be transparent** — show the user exactly what Codex found and your evaluation
4. **Fix conservatively** — prefer minimal, safe fixes over ambitious refactors
5. **Report honestly** — if you disagree with Codex, explain why
6. **Adapt the prompt** — tailor the review prompt to the focus dimensions, don't use a generic prompt for every mode
7. **Verify facts** — when Codex claims a file/function exists or doesn't exist, check before reporting
