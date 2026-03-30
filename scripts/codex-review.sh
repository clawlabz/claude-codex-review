#!/usr/bin/env bash
# codex-review.sh — Dispatch review to Codex CLI and capture structured output
# Called by the Claude Code skill; not intended for direct user invocation.
#
# Usage:
#   codex-review.sh diff [--base <branch>] [--uncommitted] [--prompt "..."]
#   codex-review.sh commit <sha> [--prompt "..."]
#   codex-review.sh file <path...> [--prompt "..."]
#   codex-review.sh dir <path> [--prompt "..."]
#   codex-review.sh doc <path> [--prompt "..."]
#   codex-review.sh pr <number> [--prompt "..."]
#
# Outputs JSON-lines to stdout. Exits 0 on success, 1 on error.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
MODE="${1:-diff}"
shift || true

BASE_BRANCH="main"
COMMIT_SHA=""
TARGETS=()
CUSTOM_PROMPT=""
OUTPUT_FILE=$(mktemp /tmp/codex-review-XXXXXX.md)
TIMEOUT=120

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)       BASE_BRANCH="$2"; shift 2 ;;
    --uncommitted) BASE_BRANCH="__uncommitted__"; shift ;;
    --prompt)     CUSTOM_PROMPT="$2"; shift 2 ;;
    --timeout)    TIMEOUT="$2"; shift 2 ;;
    -*)           echo "Unknown flag: $1" >&2; exit 1 ;;
    *)            TARGETS+=("$1"); shift ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
check_codex() {
  if ! command -v codex &>/dev/null; then
    echo '{"error": "codex CLI not found. Install with: npm i -g @openai/codex"}' >&2
    exit 1
  fi
}

json_escape() {
  python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"
}

# ── Mode handlers ─────────────────────────────────────────────────────────────
review_diff() {
  local args=()
  if [[ "$BASE_BRANCH" == "__uncommitted__" ]]; then
    args+=(--uncommitted)
  else
    args+=(--base "$BASE_BRANCH")
  fi

  if [[ -n "$CUSTOM_PROMPT" ]]; then
    codex review "${args[@]}" "$CUSTOM_PROMPT" -o "$OUTPUT_FILE" 2>/dev/null
  else
    codex review "${args[@]}" -o "$OUTPUT_FILE" 2>/dev/null
  fi
}

review_commit() {
  local sha="${TARGETS[0]:-HEAD}"
  if [[ -n "$CUSTOM_PROMPT" ]]; then
    codex review --commit "$sha" "$CUSTOM_PROMPT" -o "$OUTPUT_FILE" 2>/dev/null
  else
    codex review --commit "$sha" -o "$OUTPUT_FILE" 2>/dev/null
  fi
}

review_file() {
  # Read files and pipe as context to codex exec
  local context=""
  for f in "${TARGETS[@]}"; do
    if [[ -f "$f" ]]; then
      context+="--- FILE: $f ---"$'\n'
      context+="$(cat "$f")"$'\n\n'
    else
      echo "{\"warning\": \"File not found: $f\"}"
    fi
  done

  local prompt="Review the following code for bugs, security issues, performance problems, and code quality. Provide findings with severity (CRITICAL/HIGH/MEDIUM/LOW), file path, line number, description, and suggested fix."
  [[ -n "$CUSTOM_PROMPT" ]] && prompt="$prompt Additional instructions: $CUSTOM_PROMPT"

  echo "${prompt}"$'\n\n'"${context}" | codex exec - -o "$OUTPUT_FILE" 2>/dev/null
}

review_dir() {
  local dir="${TARGETS[0]:-.}"
  # Collect files respecting .gitignore
  local context=""
  while IFS= read -r f; do
    context+="--- FILE: $f ---"$'\n'
    context+="$(cat "$f")"$'\n\n'
  done < <(git ls-files "$dir" 2>/dev/null || find "$dir" -type f -not -path '*/node_modules/*' -not -path '*/.git/*' | head -50)

  local prompt="Review the following codebase directory for bugs, security issues, architecture problems, and code quality. Provide findings with severity (CRITICAL/HIGH/MEDIUM/LOW), file path, line number, description, and suggested fix."
  [[ -n "$CUSTOM_PROMPT" ]] && prompt="$prompt Additional instructions: $CUSTOM_PROMPT"

  echo "${prompt}"$'\n\n'"${context}" | codex exec - -o "$OUTPUT_FILE" 2>/dev/null
}

review_doc() {
  local doc="${TARGETS[0]}"
  if [[ ! -f "$doc" ]]; then
    echo "{\"error\": \"Document not found: $doc\"}" >&2
    exit 1
  fi

  local prompt="Review this document for completeness, accuracy, consistency, and potential issues. Identify gaps, contradictions, unclear sections, and suggest improvements. Provide findings with severity (CRITICAL/HIGH/MEDIUM/LOW)."
  [[ -n "$CUSTOM_PROMPT" ]] && prompt="$prompt Additional instructions: $CUSTOM_PROMPT"

  echo "${prompt}"$'\n\n'"$(cat "$doc")" | codex exec - -o "$OUTPUT_FILE" 2>/dev/null
}

review_pr() {
  local pr_ref="${TARGETS[0]}"
  # Strip # prefix if present
  pr_ref="${pr_ref#\#}"

  # Get PR diff
  local diff
  diff=$(gh pr diff "$pr_ref" 2>/dev/null) || {
    echo "{\"error\": \"Failed to fetch PR #$pr_ref. Ensure gh is authenticated.\"}" >&2
    exit 1
  }

  local title
  title=$(gh pr view "$pr_ref" --json title -q .title 2>/dev/null || echo "")

  codex review --uncommitted --title "$title" -o "$OUTPUT_FILE" 2>/dev/null <<< "$diff"
}

# ── Main ──────────────────────────────────────────────────────────────────────
check_codex

case "$MODE" in
  diff)   review_diff ;;
  commit) review_commit ;;
  file)   review_file ;;
  dir)    review_dir ;;
  doc)    review_doc ;;
  pr)     review_pr ;;
  *)      echo "{\"error\": \"Unknown mode: $MODE\"}" >&2; exit 1 ;;
esac

# Output the review result
if [[ -f "$OUTPUT_FILE" && -s "$OUTPUT_FILE" ]]; then
  cat "$OUTPUT_FILE"
  rm -f "$OUTPUT_FILE"
  exit 0
else
  echo "Codex review completed but produced no output file. Check codex authentication and connectivity."
  rm -f "$OUTPUT_FILE"
  exit 1
fi
