#!/usr/bin/env bash
# compile-debug-session-context.sh — Extract QA/UAT scope from a debug session markdown.
#
# Reads the debug session file and extracts structured context for QA and UAT agents.
# Output is a compact markdown summary suitable for injecting into agent prompts.
#
# Usage:
#   compile-debug-session-context.sh <session-file> [qa|uat]
#
# Output sections (qa mode):
#   - Issue summary
#   - Root cause
#   - Fix plan
#   - Changed files
#   - Commit reference
#   - Prior QA round results (if any)
#
# Output sections (uat mode):
#   - Issue summary
#   - Implementation summary
#   - Changed files
#   - Latest QA result
#   - Prior UAT round results (if any)

set -euo pipefail

SESSION_FILE="${1:-}"
CONTEXT_MODE="${2:-qa}"

if [ -z "$SESSION_FILE" ]; then
  echo "Usage: compile-debug-session-context.sh <session-file> [qa|uat]" >&2
  exit 1
fi

if [ ! -f "$SESSION_FILE" ]; then
  echo "Error: session file not found: $SESSION_FILE" >&2
  exit 1
fi

# Read frontmatter field
read_field() {
  local field="$1"
  sed -n '/^---$/,/^---$/p' "$SESSION_FILE" | grep "^${field}:" | head -1 | sed "s/^${field}:[[:space:]]*//"
}

# Extract section content between ## Heading and next ## or EOF
extract_section() {
  local heading="$1"
  awk -v heading="$heading" '
    /^## / {
      if (in_section) exit
      if ($0 == "## " heading) { in_section = 1; next }
    }
    in_section { print }
  ' "$SESSION_FILE"
}

SESSION_ID=$(read_field "session_id")
TITLE=$(read_field "title")
STATUS=$(read_field "status")
QA_ROUND=$(read_field "qa_round")
QA_LAST=$(read_field "qa_last_result")
UAT_ROUND=$(read_field "uat_round")
UAT_LAST=$(read_field "uat_last_result")

# Extract sections
ISSUE_CONTENT=$(extract_section "Issue")
INVESTIGATION_CONTENT=$(extract_section "Investigation")
PLAN_CONTENT=$(extract_section "Plan")
IMPL_CONTENT=$(extract_section "Implementation")
QA_CONTENT=$(extract_section "QA")
UAT_CONTENT=$(extract_section "UAT")

case "$CONTEXT_MODE" in
  qa)
    cat <<ENDCONTEXT
# Debug Session QA Context

**Session:** ${SESSION_ID}
**Title:** ${TITLE}
**Status:** ${STATUS}
**QA Round:** ${QA_ROUND} (last result: ${QA_LAST})

## Issue Summary

${ISSUE_CONTENT:-No issue description recorded.}

## Root Cause & Investigation

${INVESTIGATION_CONTENT:-No investigation recorded.}

## Fix Plan

${PLAN_CONTENT:-No plan recorded.}

## Implementation

${IMPL_CONTENT:-No implementation recorded.}
ENDCONTEXT

    # Include prior QA rounds if any exist
    if [ -n "$QA_CONTENT" ] && [ "$QA_CONTENT" != "{QA rounds are appended here by the QA workflow.}" ]; then
      echo ""
      echo "## Prior QA Rounds"
      echo ""
      echo "$QA_CONTENT"
    fi
    ;;

  uat)
    cat <<ENDCONTEXT
# Debug Session UAT Context

**Session:** ${SESSION_ID}
**Title:** ${TITLE}
**Status:** ${STATUS}
**UAT Round:** ${UAT_ROUND} (last result: ${UAT_LAST})

## Issue Summary

${ISSUE_CONTENT:-No issue description recorded.}

## Implementation

${IMPL_CONTENT:-No implementation recorded.}

## Latest QA Result

QA round ${QA_ROUND}: ${QA_LAST}
ENDCONTEXT

    # Include QA details for UAT reference
    if [ -n "$QA_CONTENT" ] && [ "$QA_CONTENT" != "{QA rounds are appended here by the QA workflow.}" ]; then
      echo ""
      echo "## QA Details"
      echo ""
      echo "$QA_CONTENT"
    fi

    # Include prior UAT rounds if any
    if [ -n "$UAT_CONTENT" ] && [ "$UAT_CONTENT" != "{UAT rounds are appended here by the UAT workflow.}" ]; then
      echo ""
      echo "## Prior UAT Rounds"
      echo ""
      echo "$UAT_CONTENT"
    fi
    ;;

  *)
    echo "Error: unknown context mode '$CONTEXT_MODE'. Valid: qa, uat" >&2
    exit 1
    ;;
esac
