#!/usr/bin/env bash
set -euo pipefail

# qa-result-gate.sh — Deterministic QA result evaluator
#
# Reads VERIFICATION.md and outputs an unambiguous routing directive.
# The orchestrator follows the directive literally — no judgment, no rationalization.
#
# Usage: qa-result-gate.sh <phase-dir> [verif-name]
#   phase-dir:  path to the phase directory (required)
#   verif-name: VERIFICATION.md filename (optional, defaults to VERIFICATION.md)
#
# Output (key=value, always exits 0):
#   qa_gate_writer=<value>           — writer field from frontmatter (or "missing")
#   qa_gate_result=<value>           — result field from frontmatter (or "missing"/"unreadable")
#   qa_gate_fail_count=<N>           — count of FAIL rows in body
#   qa_gate_deviation_count=<N>      — count of non-placeholder deviations across SUMMARY.md files
#   qa_gate_plan_count=<N>           — count of *-PLAN.md files in phase dir
#   qa_gate_plans_verified_count=<N> — count of plans_verified entries in VERIFICATION.md frontmatter
#   qa_gate_routing=<DIRECTIVE>      — the routing decision
#
# Optional override diagnostics (only present when an override fires):
#   qa_gate_deviation_override=true  — PASS overridden because deviations exist but no FAIL checks
#   qa_gate_plan_coverage=N/M        — plans verified vs plans expected
#
# Routing values:
#   PROCEED_TO_UAT       — QA passed cleanly, safe to enter UAT
#   REMEDIATION_REQUIRED — code has failures, needs plan→execute→verify cycle
#   QA_RERUN_REQUIRED    — no trustworthy QA result, re-spawn QA (not code remediation)

PHASE_DIR="${1:-}"
VERIF_NAME="${2:-}"

if [ -z "$PHASE_DIR" ]; then
  echo "qa_gate_writer=missing"
  echo "qa_gate_result=missing"
  echo "qa_gate_fail_count=0"
  echo "qa_gate_deviation_count=0"
  echo "qa_gate_plan_count=0"
  echo "qa_gate_plans_verified_count=0"
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

# Auto-resolve VERIFICATION.md filename using the same convention as
# phase-detect.sh and hard-gate.sh: {NN}-VERIFICATION.md is the primary
# convention, with plain VERIFICATION.md as a brownfield fallback.
if [ -z "$VERIF_NAME" ]; then
  PHASE_NUM=$(basename "$PHASE_DIR" | grep -oE '^[0-9]+' 2>/dev/null || true)
  if [ -n "$PHASE_NUM" ] && [ -e "$PHASE_DIR/${PHASE_NUM}-VERIFICATION.md" ]; then
    VERIF_NAME="${PHASE_NUM}-VERIFICATION.md"
  elif [ -e "$PHASE_DIR/VERIFICATION.md" ]; then
    VERIF_NAME="VERIFICATION.md"
  else
    # Neither convention found — use prefixed name so "file not found" is reported
    VERIF_NAME="${PHASE_NUM:-01}-VERIFICATION.md"
  fi
fi

VERIF_PATH="$PHASE_DIR/$VERIF_NAME"

# Detect active QA remediation — deviation override is suppressed during remediation
# because SUMMARY.md deviations are historical (the code has been fixed)
IN_REMEDIATION="false"
PLAN_SCOPE_DIR="$PHASE_DIR"  # Default: phase-level plans
if [ -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ]; then
  IN_REMEDIATION="true"
  # Auto-discover round VERIFICATION.md
  _gate_round=$(grep '^round=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  _gate_round="${_gate_round:-01}"
  _gate_round_dir="$PHASE_DIR/remediation/qa/round-${_gate_round}"
  _gate_round_verif="${_gate_round_dir}/R${_gate_round}-VERIFICATION.md"
  if [ -f "$_gate_round_verif" ]; then
    VERIF_PATH="$_gate_round_verif"
    VERIF_NAME="R${_gate_round}-VERIFICATION.md"
    PLAN_SCOPE_DIR="$_gate_round_dir"
  fi
fi

# 1. File doesn't exist
if [ ! -f "$VERIF_PATH" ]; then
  echo "qa_gate_writer=missing"
  echo "qa_gate_result=missing"
  echo "qa_gate_fail_count=0"
  echo "qa_gate_deviation_count=0"
  echo "qa_gate_plan_count=0"
  echo "qa_gate_plans_verified_count=0"
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

# 2. File unreadable
if [ ! -r "$VERIF_PATH" ]; then
  echo "qa_gate_writer=missing"
  echo "qa_gate_result=unreadable"
  echo "qa_gate_fail_count=0"
  echo "qa_gate_deviation_count=0"
  echo "qa_gate_plan_count=0"
  echo "qa_gate_plans_verified_count=0"
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

# Parse frontmatter fields
WRITER=$(awk '
  BEGIN { in_fm=0 }
  NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
  in_fm && /^---[[:space:]]*$/ { exit }
  in_fm && /^writer:/ { sub(/^writer:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit }
' "$VERIF_PATH" 2>/dev/null)

RESULT=$(awk '
  BEGIN { in_fm=0 }
  NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
  in_fm && /^---[[:space:]]*$/ { exit }
  in_fm && /^result:/ { sub(/^result:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit }
' "$VERIF_PATH" 2>/dev/null)

# Body FAIL count (defense-in-depth cross-check)
FAIL_COUNT=$(grep -cE '\|[[:space:]]*\*{0,2}FAIL\*{0,2}[[:space:]]*\|' "$VERIF_PATH" 2>/dev/null || echo 0)

# Deviation count — scan all SUMMARY.md files for non-placeholder deviations
# Uses the same AWK extraction logic as execute-protocol.md Step 4
DEVIATION_COUNT=0
for summary_file in "$PHASE_DIR"/*-SUMMARY.md; do
  [ -f "$summary_file" ] || continue

  # Extract deviations from YAML frontmatter
  devs=$(awk '
    BEGIN { in_fm=0; in_dev=0; count=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^deviations:/ { in_dev=1; next }
    in_fm && in_dev && /^[[:space:]]+- / {
      line=$0; sub(/^[[:space:]]+- /, "", line)
      gsub(/^"/, "", line); gsub(/"$/, "", line)
      lc = tolower(line)
      if (lc ~ /^none\.?$/ || lc ~ /^n\/a\.?$/ || lc ~ /^na\.?$/ || lc ~ /^no deviations/) next
      count++
    }
    in_fm && in_dev && /^[^[:space:]]/ { exit }
    END { print count }
  ' "$summary_file" 2>/dev/null)

  # Fallback: extract from body ## Deviations section
  if [ "${devs:-0}" -eq 0 ]; then
    devs=$(awk '
      BEGIN { count=0 }
      /^## Deviations/ { found=1; next }
      found && /^## / { exit }
      found && /^[[:space:]]*$/ { next }
      found && /^- / {
        line=$0; sub(/^- /, "", line)
        if (tolower(line) ~ /^\*\*n(one|\/a|a)\*\*/ || tolower(line) ~ /^\*\*no deviations\*\*/) next
        sub(/^\*\*[^*]+\*\*:?[[:space:]]*/, "", line)
        if (line == "") next
        lc = tolower(line)
        if (lc ~ /^none\.?$/ || lc ~ /^n\/a\.?$/ || lc ~ /^na\.?$/ || lc ~ /^no deviations/) next
        count++
      }
      END { print count }
    ' "$summary_file" 2>/dev/null)
  fi

  DEVIATION_COUNT=$((DEVIATION_COUNT + ${devs:-0}))
done

# Plan coverage — count PLAN.md files and plans_verified entries
PLAN_COUNT=0
for plan_file in "$PLAN_SCOPE_DIR"/*-PLAN.md; do
  [ -f "$plan_file" ] || continue
  PLAN_COUNT=$((PLAN_COUNT + 1))
done

# Parse plans_verified from VERIFICATION.md frontmatter (YAML array)
PLANS_VERIFIED_COUNT=$(awk '
  BEGIN { in_fm=0; in_pv=0; count=0 }
  NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
  in_fm && /^---[[:space:]]*$/ { exit }
  in_fm && /^plans_verified:/ { in_pv=1; next }
  in_fm && in_pv && /^[[:space:]]+- / {
    val=$0; sub(/^[[:space:]]+- /, "", val)
    if (!seen[val]++) count++
    next
  }
  in_fm && in_pv && /^[^[:space:]]/ { exit }
  END { print count }
' "$VERIF_PATH" 2>/dev/null)
PLANS_VERIFIED_COUNT="${PLANS_VERIFIED_COUNT:-0}"

# Output diagnostic fields
echo "qa_gate_writer=${WRITER:-missing}"
echo "qa_gate_result=${RESULT:-missing}"
echo "qa_gate_fail_count=$FAIL_COUNT"
echo "qa_gate_deviation_count=$DEVIATION_COUNT"
echo "qa_gate_plan_count=$PLAN_COUNT"
echo "qa_gate_plans_verified_count=$PLANS_VERIFIED_COUNT"

# 3. Writer provenance check
if [ -z "$WRITER" ] || [ "$WRITER" != "write-verification.sh" ]; then
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

# 4. Result field empty
if [ -z "$RESULT" ]; then
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

# 5-7. Route based on result + fail count + deviation cross-check + plan coverage
case "$RESULT" in
  PASS)
    if [ "$FAIL_COUNT" -gt 0 ] 2>/dev/null; then
      # 6. PASS with FAIL rows → defense-in-depth override
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$DEVIATION_COUNT" -gt 0 ] && [ "$IN_REMEDIATION" = "false" ]; then
      # 5a. PASS but deviations exist without FAIL checks → QA rationalized deviations
      # Suppressed during remediation: SUMMARY.md deviations are historical records,
      # the code has been fixed, and a fresh QA verdict should be trusted.
      echo "qa_gate_deviation_override=true"
      # Also check plan coverage so both diagnostics surface simultaneously
      if [ "$PLAN_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -lt "$PLAN_COUNT" ]; then
        echo "qa_gate_plan_coverage=${PLANS_VERIFIED_COUNT}/${PLAN_COUNT}"
      fi
      echo "qa_gate_routing=QA_RERUN_REQUIRED"
    elif [ "$PLAN_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -lt "$PLAN_COUNT" ]; then
      # 5b. PASS but incomplete plan coverage → QA skipped some plans
      echo "qa_gate_plan_coverage=${PLANS_VERIFIED_COUNT}/${PLAN_COUNT}"
      echo "qa_gate_routing=QA_RERUN_REQUIRED"
    else
      # 5. Clean PASS
      echo "qa_gate_routing=PROCEED_TO_UAT"
    fi
    ;;
  FAIL|PARTIAL)
    # 7. Explicit failure
    echo "qa_gate_routing=REMEDIATION_REQUIRED"
    ;;
  *)
    # Unknown result value — treat as untrustworthy
    echo "qa_gate_routing=QA_RERUN_REQUIRED"
    ;;
esac

exit 0
