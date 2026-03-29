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
#   qa_gate_metadata_only_override=true — PASS overridden because remediation round changed only metadata
#   qa_gate_phase_deviation_count=<N> — deviations in phase-root SUMMARYs (metadata-only override)
#   qa_gate_plan_coverage=N/M        — plans verified vs plans expected
#
# Routing values:
#   PROCEED_TO_UAT       — QA passed cleanly, safe to enter UAT
#   REMEDIATION_REQUIRED — code has failures, needs plan→execute→verify cycle
#   QA_RERUN_REQUIRED    — no trustworthy QA result, re-spawn QA (not code remediation)

PHASE_DIR="${1:-}"
VERIF_NAME="${2:-}"
EXPLICIT_VERIF_NAME=false
if [ -n "$VERIF_NAME" ]; then
  EXPLICIT_VERIF_NAME=true
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOLVE_VERIF_SCRIPT="$SCRIPT_DIR/resolve-verification-path.sh"

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
  VERIF_PATH=$(bash "$RESOLVE_VERIF_SCRIPT" phase "$PHASE_DIR" 2>/dev/null || true)
  if [ -n "$VERIF_PATH" ]; then
    VERIF_NAME=$(basename "$VERIF_PATH")
  else
    PHASE_NUM=$(basename "$PHASE_DIR" | grep -oE '^[0-9]+' 2>/dev/null || true)
    VERIF_NAME="${PHASE_NUM:-01}-VERIFICATION.md"
    VERIF_PATH="$PHASE_DIR/$VERIF_NAME"
  fi
else
  VERIF_PATH="$PHASE_DIR/$VERIF_NAME"
fi

# Detect active QA remediation — deviation override is suppressed during remediation
# because SUMMARY.md deviations are historical (the code has been fixed)
IN_REMEDIATION="false"
PLAN_SCOPE_DIR="$PHASE_DIR"  # Default: phase-level plans
SUMMARY_SCOPE_DIR="$PHASE_DIR"  # Default: phase-level summaries
if [ -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ]; then
  _gate_stage=$(grep '^stage=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  _gate_stage="${_gate_stage:-none}"
  case "$_gate_stage" in
    plan|execute|verify|done) IN_REMEDIATION="true" ;;
    *) _gate_stage="none" ;;
  esac
  _gate_round=$(grep '^round=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  _gate_round="${_gate_round:-01}"
  # Defensive: ensure round is numeric before arithmetic
  if ! [[ "$_gate_round" =~ ^[0-9]+$ ]]; then
    _gate_round="01"
  fi
  # Defensive zero-padding (consistent with phase-detect.sh)
  _gate_round=$(printf '%02d' "$((10#${_gate_round}))")
  _gate_round_dir="$PHASE_DIR/remediation/qa/round-${_gate_round}"
  _gate_round_verif="${_gate_round_dir}/R${_gate_round}-VERIFICATION.md"
  if [ "$EXPLICIT_VERIF_NAME" = false ]; then
    case "$_gate_stage" in
      verify)
        VERIF_PATH="$_gate_round_verif"
        VERIF_NAME=$(basename "$VERIF_PATH")
        ;;
      done)
        _gate_authoritative_verif=$(bash "$RESOLVE_VERIF_SCRIPT" authoritative "$PHASE_DIR" 2>/dev/null || true)
        if [ -n "${_gate_authoritative_verif:-}" ]; then
          VERIF_PATH="$_gate_authoritative_verif"
          VERIF_NAME=$(basename "$VERIF_PATH")
        fi
        ;;
    esac
  fi
  if [ "$VERIF_PATH" = "$_gate_round_verif" ]; then
    PLAN_SCOPE_DIR="$_gate_round_dir"
    SUMMARY_SCOPE_DIR="$_gate_round_dir"
  fi
fi

# Count non-placeholder deviations across SUMMARY.md files in a given directory.
# Uses the same AWK extraction logic as execute-protocol.md Step 4.
# Arguments: $1 = directory to scan for SUMMARY.md files
count_deviations_in_dir() {
  local scan_dir="${1:-}"
  local total=0
  [ -d "$scan_dir" ] || { echo 0; return; }
  while IFS= read -r _cdf_file; do
    [ -f "$_cdf_file" ] || continue
    local _cdf_devs
    _cdf_devs=$(awk '
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
    ' "$_cdf_file" 2>/dev/null)
    if [ "${_cdf_devs:-0}" -eq 0 ]; then
      _cdf_devs=$(awk '
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
      ' "$_cdf_file" 2>/dev/null)
    fi
    total=$((total + ${_cdf_devs:-0}))
  done < <(find "$scan_dir" -maxdepth 1 ! -name '.*' \( -name '*-SUMMARY.md' -o -name 'SUMMARY.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
  echo "$total"
}

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

# Deviation count — scan SUMMARY.md files for non-placeholder deviations
DEVIATION_COUNT=$(count_deviations_in_dir "$SUMMARY_SCOPE_DIR")

# Metadata-only round detection — if remediation round modified only
# .vbw-planning/ files (no production code), phase-level deviations
# are still unresolved and the override must fire.
METADATA_ONLY_ROUND="false"
if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; then
  # Scan round SUMMARY.md files_modified for non-metadata paths
  _mo_has_code_changes="false"
  _mo_found_summary="false"
  while IFS= read -r _mo_summary; do
    [ -f "$_mo_summary" ] || continue
    _mo_found_summary="true"
    # Extract files_modified from YAML frontmatter
    _mo_files=$(awk '
      BEGIN { in_fm=0; in_fm_arr=0 }
      NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
      in_fm && /^---[[:space:]]*$/ { exit }
      in_fm && /^files_modified:/ {
        # Inline array: files_modified: [a, b]
        rest=$0; sub(/^files_modified:[[:space:]]*/, "", rest)
        if (rest ~ /^\[/) {
          gsub(/[\[\]"]/, "", rest)
          # Split comma-separated values onto separate lines
          n = split(rest, arr, ",")
          for (i = 1; i <= n; i++) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", arr[i])
            if (arr[i] != "") print arr[i]
          }
          exit
        }
        in_fm_arr=1; next
      }
      in_fm && in_fm_arr && /^[[:space:]]+- / {
        line=$0; sub(/^[[:space:]]+- /, "", line)
        gsub(/^"/, "", line); gsub(/"$/, "", line)
        print line
      }
      in_fm && in_fm_arr && /^[^[:space:]]/ { exit }
    ' "$_mo_summary" 2>/dev/null)
    # Also check commit_hashes — empty means no real commits
    _mo_commits=$(awk '
      BEGIN { in_fm=0; in_arr=0; count=0 }
      NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
      in_fm && /^---[[:space:]]*$/ { exit }
      in_fm && /^commit_hashes:/ {
        rest=$0; sub(/^commit_hashes:[[:space:]]*/, "", rest)
        if (rest ~ /^\[\]/) { exit }
        if (rest ~ /^\[/) { count++; exit }
        in_arr=1; next
      }
      in_fm && in_arr && /^[[:space:]]+- / { count++ }
      in_fm && in_arr && /^[^[:space:]]/ { exit }
      END { print count }
    ' "$_mo_summary" 2>/dev/null)
    _mo_commits="${_mo_commits:-0}"
    if [ -n "$_mo_files" ]; then
      while IFS= read -r _mo_path; do
        _mo_path=$(echo "$_mo_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/,$//')
        [ -n "$_mo_path" ] || continue
        case "$_mo_path" in
          .vbw-planning/*) ;; # metadata path — continue checking
          *) _mo_has_code_changes="true"; break ;;
        esac
      done <<< "$_mo_files"
    elif [ "$_mo_commits" -gt 0 ] 2>/dev/null; then
      # No files listed but commits exist → assume code changes were made
      _mo_has_code_changes="true"
    fi
    [ "$_mo_has_code_changes" = "true" ] && break
  done < <(find "$SUMMARY_SCOPE_DIR" -maxdepth 1 ! -name '.*' \( -name '*-SUMMARY.md' -o -name 'SUMMARY.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
  # Only flag metadata-only when a round SUMMARY.md exists — if no summary was
  # found, we can't determine what changed, so fall through to default behavior.
  if [ "$_mo_found_summary" = "true" ] && [ "$_mo_has_code_changes" = "false" ]; then
    METADATA_ONLY_ROUND="true"
  fi
fi

# Plan coverage — count PLAN.md files and plans_verified entries
PLAN_COUNT=0
while IFS= read -r plan_file; do
  [ -f "$plan_file" ] || continue
  PLAN_COUNT=$((PLAN_COUNT + 1))
done < <(find "$PLAN_SCOPE_DIR" -maxdepth 1 ! -name '.*' \( -name '*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))

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

# 5-7. Route based on result + fail count + deviation cross-check + plan coverage + metadata-only
case "$RESULT" in
  PASS)
    if [ "$FAIL_COUNT" -gt 0 ] 2>/dev/null; then
      # 6. PASS with FAIL rows → defense-in-depth override
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$DEVIATION_COUNT" -gt 0 ] && { [ "$IN_REMEDIATION" = "false" ] || [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; }; then
      # 5a. PASS but deviations exist without FAIL checks → QA rationalized deviations.
      # During remediation, phase-root SUMMARY.md deviations are historical and must
      # not override a fresh PASS. Current-round SUMMARY.md deviations are still real
      # and must be reflected as FAIL checks, so scoped round summaries keep the override.
      echo "qa_gate_deviation_override=true"
      # Also check plan coverage so both diagnostics surface simultaneously
      if [ "$PLAN_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -lt "$PLAN_COUNT" ]; then
        echo "qa_gate_plan_coverage=${PLANS_VERIFIED_COUNT}/${PLAN_COUNT}"
      fi
      echo "qa_gate_routing=QA_RERUN_REQUIRED"
    elif [ "$METADATA_ONLY_ROUND" = "true" ]; then
      # 5c. Remediation round made no code changes — only metadata/.vbw-planning/ updates.
      # Re-check phase-level deviations since they are still unresolved.
      PHASE_DEVIATION_COUNT=$(count_deviations_in_dir "$PHASE_DIR")
      if [ "$PHASE_DEVIATION_COUNT" -gt 0 ] 2>/dev/null; then
        echo "qa_gate_metadata_only_override=true"
        echo "qa_gate_phase_deviation_count=$PHASE_DEVIATION_COUNT"
        echo "qa_gate_routing=REMEDIATION_REQUIRED"
      elif [ "$PLAN_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -lt "$PLAN_COUNT" ]; then
        echo "qa_gate_plan_coverage=${PLANS_VERIFIED_COUNT}/${PLAN_COUNT}"
        echo "qa_gate_routing=QA_RERUN_REQUIRED"
      else
        echo "qa_gate_routing=PROCEED_TO_UAT"
      fi
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
