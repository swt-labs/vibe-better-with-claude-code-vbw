#!/usr/bin/env bash
# compile-verify-context.sh — Pre-compute PLAN/SUMMARY data for verify.md.
# Usage: compile-verify-context.sh [--remediation-only] <phase-dir>
#
# Outputs compact structured blocks per plan so the LLM doesn't need to
# read individual PLAN.md and SUMMARY.md files during verification.
#
# Options:
#   --remediation-only  Only emit plans from the latest completed remediation
#                       round (R*-PLAN.md with matching R*-SUMMARY.md).
#                       Falls back to full scope if no completed round found.
#
# For each plan, emits:
#   verify_scope=full|remediation [round=RR]
#   === PLAN <plan-id>: <title> ===
#   must_haves: <item1>; <item2>; ...
#   what_was_built: <first 5 lines of "What Was Built" section>
#   files_modified: <file1>, <file2>, ...
#   status: <complete|partial|failed|no_summary>
#
# If no PLAN files exist, outputs: verify_context=empty

set -euo pipefail

REMEDIATION_ONLY=false
if [ "${1:-}" = "--remediation-only" ]; then
  REMEDIATION_ONLY=true
  shift
fi

PHASE_DIR="${1:?Usage: compile-verify-context.sh [--remediation-only] <phase-dir>}"

if [ ! -d "$PHASE_DIR" ]; then
  echo "verify_context_error=no_phase_dir"
  exit 0
fi

# Find plan files based on scope mode
if [ "$REMEDIATION_ONLY" = true ]; then
  # Find the latest completed round (has both R{RR}-PLAN.md and R{RR}-SUMMARY.md)
  LATEST_ROUND=""
  REMED_DIR="$PHASE_DIR/remediation"
  if [ -d "$REMED_DIR" ]; then
    for round_dir in $(find "$REMED_DIR" -maxdepth 1 -type d -name 'round-*' 2>/dev/null | sort -t- -k2 -n -r); do
      round_num=$(basename "$round_dir" | sed 's/^round-//')
      rr=$(printf '%02d' "$round_num")
      if ls "$round_dir"/R"${rr}"-PLAN.md >/dev/null 2>&1 && ls "$round_dir"/R"${rr}"-SUMMARY.md >/dev/null 2>&1; then
        LATEST_ROUND="$round_num"
        break
      fi
    done
  fi

  if [ -n "$LATEST_ROUND" ]; then
    rr=$(printf '%02d' "$LATEST_ROUND")
    ALL_PLAN_FILES=$(find "$REMED_DIR/round-$rr" -maxdepth 1 -name "R${rr}-PLAN.md" 2>/dev/null | sort)
    SCOPE_HEADER="verify_scope=remediation round=$rr"
    UAT_PATH="remediation/round-$rr/R${rr}-UAT.md"
  else
    # Fallback: no completed round found — use full scope
    REMEDIATION_ONLY=false
  fi
fi

if [ "$REMEDIATION_ONLY" = false ]; then
  # Full scope: all phase-root plans + all round-dir plans
  PLAN_FILES=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' -name '[0-9]*-PLAN.md' 2>/dev/null | sort)
  ROUND_PLAN_FILES=$(find "$PHASE_DIR" -path '*/remediation/round-*/R*-PLAN.md' 2>/dev/null | sort)

  ALL_PLAN_FILES="$PLAN_FILES"
  if [ -n "$ROUND_PLAN_FILES" ]; then
    if [ -n "$ALL_PLAN_FILES" ]; then
      ALL_PLAN_FILES=$(printf '%s\n%s' "$ALL_PLAN_FILES" "$ROUND_PLAN_FILES")
    else
      ALL_PLAN_FILES="$ROUND_PLAN_FILES"
    fi
  fi
  SCOPE_HEADER="verify_scope=full"
  # Extract phase number from directory basename (e.g., "03" from "03-slug-name")
  _phase_num=$(basename "$PHASE_DIR" | sed 's/^\([0-9]*\).*/\1/')
  UAT_PATH="${_phase_num}-UAT.md"
fi

if [ -z "$ALL_PLAN_FILES" ]; then
  echo "verify_context=empty"
  exit 0
fi

# Emit scope header and UAT path after confirming plans exist
echo "$SCOPE_HEADER"
echo "uat_path=$UAT_PATH"

PLAN_COUNT=0

while IFS= read -r plan_file; do
  [ -f "$plan_file" ] || continue
  PLAN_COUNT=$((PLAN_COUNT + 1))

  # Extract plan number and title from frontmatter
  PLAN_ID=$(awk '/^---$/{n++; next} n==1 && /^plan:/{v=$2; gsub(/^["'"'"']|["'"'"']$/, "", v); print v; exit}' "$plan_file" 2>/dev/null) || PLAN_ID=""
  TITLE=$(awk '/^---$/{n++; next} n==1 && /^title:/{sub(/^title: */, ""); gsub(/^["'"'"']|["'"'"']$/, ""); print; exit}' "$plan_file" 2>/dev/null) || TITLE=""

  # Extract must_haves from frontmatter (reuse pattern from generate-contract.sh)
  MUST_HAVES=$(awk '
    BEGIN { in_front=0; in_mh=0; in_sub=0 }
    /^---$/ { if (in_front==0) { in_front=1; next } else { exit } }
    in_front && /^must_haves:/ { in_mh=1; next }
    in_front && in_mh && /^[[:space:]]+truths:/ { in_sub=1; next }
    in_front && in_mh && /^[[:space:]]+artifacts:/ { in_sub=1; next }
    in_front && in_mh && /^[[:space:]]+key_links:/ { in_sub=1; next }
    in_front && in_mh && in_sub && /^[[:space:]]+- / {
      line = $0
      sub(/^[[:space:]]+- /, "", line)
      gsub(/^"/, "", line); gsub(/"$/, "", line)
      # For complex items (path:, provides:, from:), extract a one-liner
      if (line ~ /^\{/) {
        # YAML flow mapping — emit as-is
      }
      items = items (items ? "; " : "") line
      next
    }
    in_front && in_mh && !in_sub && /^[[:space:]]+- / {
      line = $0
      sub(/^[[:space:]]+- /, "", line)
      gsub(/^"/, "", line); gsub(/"$/, "", line)
      items = items (items ? "; " : "") line
      next
    }
    in_front && in_mh && /^[^[:space:]]/ && !/^[[:space:]]+/ { exit }
    END { print items }
  ' "$plan_file" 2>/dev/null) || MUST_HAVES=""

  # Find corresponding SUMMARY file
  # Phase-root plans: {NN}-{MM}-PLAN.md → {NN}-{MM}-SUMMARY.md (same dir)
  # Round-dir plans: R{RR}-PLAN.md → R{RR}-SUMMARY.md (same dir)
  PLAN_BASE=$(basename "$plan_file" | sed 's/-PLAN\.md$//')
  PLAN_DIR=$(dirname "$plan_file")
  SUMMARY_FILE=$(find "$PLAN_DIR" -maxdepth 1 ! -name '.*' -name "${PLAN_BASE}-SUMMARY.md" 2>/dev/null | head -1)

  STATUS="no_summary"
  WHAT_BUILT=""
  FILES_MODIFIED=""

  if [ -n "$SUMMARY_FILE" ] && [ -f "$SUMMARY_FILE" ]; then
    # Extract status from frontmatter
    STATUS=$(awk '
      BEGIN { in_fm=0 }
      NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
      in_fm && /^---[[:space:]]*$/ { exit }
      in_fm && /^status:/ { sub(/^status:[[:space:]]*/, ""); print; exit }
    ' "$SUMMARY_FILE" 2>/dev/null) || STATUS="unknown"

    # Extract "What Was Built" (first 5 lines after the heading)
    WHAT_BUILT=$(awk '
      /^## What Was Built/ { found=1; count=0; next }
      found && /^## / { exit }
      found && /^[[:space:]]*$/ { next }
      found { count++; if (count <= 5) print; if (count >= 5) exit }
    ' "$SUMMARY_FILE" 2>/dev/null) || WHAT_BUILT=""

    # Extract "Files Modified" section
    FILES_MODIFIED=$(awk '
      /^## Files Modified/ { found=1; next }
      found && /^## / { exit }
      found && /^[[:space:]]*$/ { next }
      found && /^- / {
        line = $0
        sub(/^- /, "", line)
        # Extract just the file path (before " -- ")
        if (index(line, " -- ") > 0) {
          line = substr(line, 1, index(line, " -- ") - 1)
        }
        # Strip backticks
        gsub(/`/, "", line)
        files = files (files ? ", " : "") line
      }
      END { print files }
    ' "$SUMMARY_FILE" 2>/dev/null) || FILES_MODIFIED=""
  fi

  # Emit structured block
  echo "=== PLAN ${PLAN_ID}: ${TITLE} ==="
  echo "must_haves: ${MUST_HAVES:-none}"
  if [ -n "$WHAT_BUILT" ]; then
    echo "what_was_built:"
    echo "$WHAT_BUILT" | sed 's/^/  /'
  else
    echo "what_was_built: none"
  fi
  echo "files_modified: ${FILES_MODIFIED:-none}"
  echo "status: ${STATUS}"
  echo ""
done <<< "$ALL_PLAN_FILES"

echo "verify_plan_count=${PLAN_COUNT}"
