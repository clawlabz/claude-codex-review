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
Gather a **lightweight project brief** only (Codex will explore the rest itself):
1. Read CLAUDE.md or README.md for project overview
2. Read package.json / Cargo.toml / go.mod for dependencies and scripts
3. Get top-level directory structure: `ls -la` + `ls` of key subdirectories
4. Count files and LOC: `git ls-files | wc -l` and `git ls-files | xargs wc -l 2>/dev/null | tail -1`
5. Get recent git activity: `git log --oneline -10`

**Do NOT** try to read all project files — Codex runs as an agent in the project directory and will explore the codebase itself.

**For `ask` mode:**
Gather minimal context to orient Codex:
1. Read CLAUDE.md or README.md
2. Get directory structure overview
3. If the question mentions specific files/modules, note their paths

**Do NOT** try to pre-read everything the question might need — Codex will navigate the codebase to find answers.

Tell the user what context was gathered (file count, diff size, etc.)

## Step 3: Build Review Prompt

Write the review prompt to a temp file. The prompt has 3 parts:

### Part 1: Project Brief (for project/ask modes)

Include the lightweight context gathered in Step 2:
```
## Project Brief
{CLAUDE.md or README content, truncated to key sections}

## Project Stats
- Files: {count}, LOC: {lines}
- Stack: {detected from package.json/Cargo.toml/go.mod}
- Structure: {top-level directory listing}
- Recent activity: {last 10 commits}
```

### Part 2: Review Instructions (mode + focus specific)

For `project` mode — build instructions per focus dimension:

```
You are an independent code reviewer. Explore this codebase thoroughly and assess it.

Focus areas: {focus dimensions}

For each focus area, you MUST:
1. Navigate the actual source files — read key modules, entry points, configs
2. Look for real evidence, not surface-level impressions
3. Score each dimension X/10 with specific justification

{include relevant focus-specific instructions below}

Output format:
## Findings
For each issue found:
- **Severity**: CRITICAL / HIGH / MEDIUM / LOW / INFO
- **Category**: {which focus dimension}
- **Location**: file:line
- **Issue**: what's wrong
- **Suggestion**: how to fix
- **Rationale**: why it matters

## Scores
| Dimension | Score | Justification |
|-----------|-------|---------------|

## Top 3 Priorities
1. ...
2. ...
3. ...
```

Focus-specific instruction blocks (include only the requested dimensions):

**completeness:**
```
COMPLETENESS: Browse the codebase for TODOs, FIXMEs, stub implementations, placeholder UI,
commented-out code, and features mentioned in docs but not implemented. Check if tests exist.
Score as percentage complete with evidence.
```

**quality:**
```
QUALITY: Check naming conventions, function/file sizes, DRY violations, error handling patterns,
type safety, and dependency hygiene. Read 5-10 representative source files across modules.
```

**architecture:**
```
ARCHITECTURE: Map the module dependency graph. Check separation of concerns, data flow clarity,
circular dependencies, abstraction levels. Is the structure intuitive for a new developer?
```

**security:**
```
SECURITY: Scan for hardcoded secrets, SQL injection, XSS, missing auth checks, insecure
dependencies, exposed internal errors. Check env handling and input validation at boundaries.
```

**performance:**
```
PERFORMANCE: Look for N+1 queries, missing indexes (check migration files), unnecessary
computation in hot paths, memory leaks, missing pagination, large payloads without streaming.
```

**testing:**
```
TESTING: Check test file existence, coverage config, test patterns (unit/integration/e2e).
Are critical paths tested? Are tests meaningful or just smoke tests?
```

**types:**
```
TYPES: Check for `any` casts, missing return types, loose interfaces, unvalidated external data.
Is there runtime validation (Zod, joi) at system boundaries?
```

**bugs:**
```
BUGS: Look for logic errors, off-by-one, race conditions, null/undefined access, unhandled
promise rejections, incorrect error propagation, edge cases in state machines.
```

For `ask` mode:
```
The user asks: "{user's question}"

Explore the codebase to answer this question thoroughly.
Navigate actual source files — read the relevant modules, trace the code paths.
Be specific: reference actual files, functions, and line numbers.
Do not guess — if you can't find evidence, say so.

{custom_prompt if provided}
```

### Part 3: Custom Prompt (optional)

Append user's `--prompt` value if provided.

Write the assembled prompt to `/tmp/codex-review-prompt.txt`.

## Step 4: Dispatch to Codex

### Strategy by mode:

**Git-based reviews (diff/commit/pr) — use `codex review` (native, fast):**
```bash
codex review --uncommitted "{focus-aware prompt}"
codex review --base <branch> "{focus-aware prompt}"
codex review --commit <sha> "{focus-aware prompt}"
```

**File/dir reviews — use `codex exec` with context piped in:**
For small targets (<50KB total), pipe the file contents:
```bash
echo "{file contents}" | codex exec "Review this code. {focus instructions}" -s read-only -o /tmp/codex-review-result.md
```

For large targets, let Codex read them itself:
```bash
codex exec "Review the files in {dir}. {focus instructions}" -C {project-root} -s read-only -o /tmp/codex-review-result.md
```

**Doc reviews — pipe the document:**
```bash
cat {doc-path} | codex exec "Review this document. {focus instructions}" -s read-only -o /tmp/codex-review-result.md
```

**Project/ask reviews — let Codex explore (critical difference):**

Codex exec is an **agent with file system access**. Don't pipe the whole project — give it the brief + instructions and let it navigate:

```bash
codex exec "$(cat /tmp/codex-review-prompt.txt)" \
  -C {project-root} \
  -s read-only \
  -o /tmp/codex-review-result.md
```

Key flags:
- `-C {project-root}` — sets Codex's working directory to the project
- `-s read-only` — sandbox: can read all files but not modify anything
- `-o /tmp/codex-review-result.md` — captures the final output
- `--full-auto` — optional, auto-approves Codex's own tool calls (file reads, commands)

This way Codex can:
- `ls`, `find`, `cat` any file in the project
- Run `grep` to search for patterns
- Read package.json, configs, source files as needed
- Build a comprehensive understanding autonomously

**Important:**
- Timeout: 300s for project mode (Codex needs time to explore), 180s for ask, 120s for others
- If Codex produces no output file, check if it printed to stdout instead
- If Codex fails, report error and suggest: check `codex login`, check API key, retry

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
