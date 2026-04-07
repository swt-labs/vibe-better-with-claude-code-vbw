#!/usr/bin/env bash
# compile-verify-context.sh — Pre-compute PLAN/SUMMARY data for verify.md.
# Usage: compile-verify-context.sh [--remediation-only] [--remediation-kind {qa|uat}] <phase-dir>
#
# Outputs compact structured blocks per plan so the LLM doesn't need to
# read individual PLAN.md and SUMMARY.md files during verification.
#
# Options:
#   --remediation-only  Only emit plans from the latest completed remediation
#                       round (R*-PLAN.md with matching R*-SUMMARY.md).
#                       Falls back to full scope if no completed round found.
#   --remediation-kind  Filter remediation scan to only the specified kind
#                       (qa or uat). Prevents wrong-kind matches when both
#                       remediation dirs exist. Only meaningful with
#                       --remediation-only.
#
# For each plan, emits:
#   verify_scope=full|remediation [round=RR]
#   === PLAN <plan-id>: <title> ===
#   must_haves: <item1>; <item2>; ...
#   what_was_built: <first 5 lines of "What Was Built" section>
#   files_modified: <file1>, <file2>, ...
#   status: <complete|partial|failed|no_summary>
#
# Remediation awareness: when .uat-remediation-stage indicates a round-dir
# layout and stage=done/verify, scopes to the current round's R{RR}-PLAN.md
# and R{RR}-SUMMARY.md instead of phase-root plans. Also emits prior UAT
# issues so the verifier knows what was supposed to be fixed.
#
# If no PLAN files exist, outputs: verify_context=empty

set -euo pipefail

extract_frontmatter_array_items() {
  local file_path="${1:-}"
  local key_name="${2:-}"
  [ -f "$file_path" ] || return 0
  [ -n "$key_name" ] || return 0
  awk -v key="$key_name" '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    function strip_quotes(v, first, last) {
      first = substr(v, 1, 1)
      last = substr(v, length(v), 1)
      if ((first == "\"" && last == "\"") || (first == squote && last == squote)) {
        return substr(v, 2, length(v) - 2)
      }
      return v
    }
    function emit_value(v) {
      v = trim(v)
      if (v == "") return
      v = strip_quotes(v)
      if (v != "") print v
    }
    function parse_flow_array(rest, i, ch, current, quote) {
      rest = trim(rest)
      if (rest !~ /^\[/) return 0
      sub(/^\[/, "", rest)
      sub(/\][[:space:]]*$/, "", rest)
      current = ""
      quote = ""
      for (i = 1; i <= length(rest); i++) {
        ch = substr(rest, i, 1)
        if (quote == "") {
          if (ch == "\"" || ch == squote) {
            quote = ch
            current = current ch
            continue
          }
          if (ch == ",") {
            emit_value(current)
            current = ""
            continue
          }
        } else if (ch == quote) {
          quote = ""
          current = current ch
          continue
        }
        current = current ch
      }
      emit_value(current)
      return 1
    }
    BEGIN {
      in_fm = 0
      in_arr = 0
      squote = sprintf("%c", 39)
    }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && $0 ~ ("^" key ":[[:space:]]*") {
      rest = $0
      sub("^" key ":[[:space:]]*", "", rest)
      if (parse_flow_array(rest)) exit
      in_arr = 1
      next
    }
    in_fm && in_arr && /^[[:space:]]+- / {
      line = $0
      sub(/^[[:space:]]+- /, "", line)
      emit_value(line)
      next
    }
    in_fm && in_arr && /^[^[:space:]]/ { exit }
  ' "$file_path" 2>/dev/null
}

frontmatter_key_present() {
  local file_path="${1:-}"
  local key_name="${2:-}"
  [ -f "$file_path" ] || return 1
  [ -n "$key_name" ] || return 1
  awk -v key="$key_name" '
    BEGIN { in_fm = 0; found = 0 }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit(found ? 0 : 1) }
    in_fm && $0 ~ ("^" key ":[[:space:]]*") { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$file_path" >/dev/null 2>&1
}

_CVC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_CVC_SCRIPT_DIR/summary-utils.sh" ]; then
  # shellcheck source=summary-utils.sh
  . "$_CVC_SCRIPT_DIR/summary-utils.sh"
else
  # Fallback: treat all summaries as terminal when helpers unavailable
  is_summary_terminal() { [ -f "$1" ]; }
fi

REMEDIATION_ONLY=false
REMEDIATION_KIND=""
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --remediation-only) REMEDIATION_ONLY=true; shift ;;
    --remediation-kind)
      if [ $# -lt 2 ] || [ -z "${2:-}" ] || [[ "${2:-}" == --* ]]; then
        echo "error: --remediation-kind requires a value (qa or uat)" >&2
        exit 1
      fi
      REMEDIATION_KIND="$2"
      shift 2
      ;;
    --remediation-kind=*)
      REMEDIATION_KIND="${1#--remediation-kind=}"
      if [ -z "$REMEDIATION_KIND" ]; then
        echo "error: --remediation-kind requires a value (qa or uat)" >&2; exit 1
      fi
      shift
      ;;
    *) break ;;
  esac
done

if [ -n "$REMEDIATION_KIND" ]; then
  case "$REMEDIATION_KIND" in
    qa|uat) ;;
    *) echo "error: --remediation-kind must be 'qa' or 'uat', got: $REMEDIATION_KIND" >&2; exit 1 ;;
  esac
fi

PHASE_DIR="${1:?Usage: compile-verify-context.sh [--remediation-only] [--remediation-kind qa|uat] phase-dir}"

if [ ! -d "$PHASE_DIR" ]; then
  echo "verify_context_error=no_phase_dir"
  exit 0
fi

# Find plan files based on scope mode
if [ "$REMEDIATION_ONLY" = true ]; then
  # Find the latest completed round (has both R{RR}-PLAN.md and R{RR}-SUMMARY.md)
  LATEST_ROUND=""
  REMED_DIR=""
  REMED_KIND=""
  _cvc_preferred_round=""
  _cvc_preferred_kind=""

  _cvc_candidates=()
  _active_remediation=false
  if [ -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ] && [ "$REMEDIATION_KIND" != "uat" ]; then
    _qa_stage=$(grep '^stage=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    case "${_qa_stage:-none}" in
      verify|done)
        _cvc_candidates+=("$PHASE_DIR/remediation/qa")
        _cvc_preferred_round=$(grep '^round=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
        if ! [[ "${_cvc_preferred_round:-}" =~ ^[0-9]+$ ]]; then
          _cvc_preferred_round=""
        elif [ -n "$_cvc_preferred_round" ]; then
          _cvc_preferred_round=$(printf '%02d' "$((10#$_cvc_preferred_round))")
        fi
        _cvc_preferred_kind="qa"
        _active_remediation=true
        ;;
    esac
  fi
  if [ -f "$PHASE_DIR/remediation/uat/.uat-remediation-stage" ] && [ "$REMEDIATION_KIND" != "qa" ]; then
    _uat_stage=$(grep '^stage=' "$PHASE_DIR/remediation/uat/.uat-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    case "${_uat_stage:-none}" in
      research|plan|execute|fix|verify|done)
        if [ "$_active_remediation" = false ]; then
          _cvc_candidates+=("$PHASE_DIR/remediation/uat")
          _cvc_preferred_round=$(grep '^round=' "$PHASE_DIR/remediation/uat/.uat-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
          if ! [[ "${_cvc_preferred_round:-}" =~ ^[0-9]+$ ]]; then
            _cvc_preferred_round=""
          elif [ -n "$_cvc_preferred_round" ]; then
            _cvc_preferred_round=$(printf '%02d' "$((10#$_cvc_preferred_round))")
          fi
          _cvc_preferred_kind="uat"
          _active_remediation=true
        fi
        ;;
    esac
  fi
  # Historical fallback order for explicit --remediation-only callers when no
  # active state picked a scope: UAT rounds first, then QA rounds.
  # Respect --remediation-kind filter when set.
  if [ "$_active_remediation" = false ]; then
    if [ "$REMEDIATION_KIND" = "uat" ]; then
      _cvc_candidates+=("$PHASE_DIR/remediation/uat")
    elif [ "$REMEDIATION_KIND" = "qa" ]; then
      _cvc_candidates+=("$PHASE_DIR/remediation/qa")
    else
      _cvc_candidates+=("$PHASE_DIR/remediation/uat" "$PHASE_DIR/remediation/qa")
    fi
  fi

  for _candidate in "${_cvc_candidates[@]}"; do
    [ -d "$_candidate" ] || continue
    if [ "$_candidate" = "$PHASE_DIR/remediation/qa" ] && [ "$_cvc_preferred_kind" = "qa" ] && [ -n "$_cvc_preferred_round" ]; then
      _preferred_round_dir="$_candidate/round-$_cvc_preferred_round"
      if [ -d "$_preferred_round_dir" ] && \
         ls "$_preferred_round_dir"/R"$_cvc_preferred_round"-PLAN.md >/dev/null 2>&1 && \
         ls "$_preferred_round_dir"/R"$_cvc_preferred_round"-SUMMARY.md >/dev/null 2>&1 && \
         is_summary_terminal "$_preferred_round_dir/R${_cvc_preferred_round}-SUMMARY.md"; then
        LATEST_ROUND="$_cvc_preferred_round"
        REMED_DIR="$_candidate"
        REMED_KIND="qa"
        break
      fi
      # Active QA remediation should not be hijacked by a stale higher round.
      REMEDIATION_ONLY=false
      break
    fi
    if [ "$_candidate" = "$PHASE_DIR/remediation/uat" ] && [ "$_cvc_preferred_kind" = "uat" ] && [ -n "$_cvc_preferred_round" ]; then
      # Active UAT re-verification must stay on the current remediation round,
      # even if an earlier round is the latest one with a terminal summary.
      # Falling back to a stale completed round risks overwriting prior-round
      # UAT evidence and mis-scoping the re-verification session.
      LATEST_ROUND="$_cvc_preferred_round"
      REMED_DIR="$_candidate"
      REMED_KIND="uat"
      break
    fi
    _best_round_num=0
    _candidate_round=""
    for round_dir in "$_candidate"/round-*/; do
      [ -d "$round_dir" ] || continue
      round_num=$(basename "$round_dir" | sed 's/^round-0*//')
      round_num=${round_num:-0}
      rr=$(printf '%02d' "$round_num")
      if [ "$round_num" -gt "$_best_round_num" ] 2>/dev/null && \
         ls "$round_dir"/R"${rr}"-PLAN.md >/dev/null 2>&1 && \
         ls "$round_dir"/R"${rr}"-SUMMARY.md >/dev/null 2>&1 && \
         is_summary_terminal "$round_dir/R${rr}-SUMMARY.md"; then
        _best_round_num="$round_num"
        _candidate_round="$rr"
      fi
    done
    if [ -n "$_candidate_round" ]; then
      LATEST_ROUND="$_candidate_round"
      REMED_DIR="$_candidate"
      case "$_candidate" in
        */remediation/uat) REMED_KIND="uat" ;;
        */remediation/qa) REMED_KIND="qa" ;;
      esac
      break
    fi
  done

  # Legacy fallback: check old remediation/round-* layout if no new-style round dir found.
  # Legacy round dirs represent historical UAT remediation only; an explicit
  # QA filter must not cross over into that legacy UAT chain.
  if [ -z "$LATEST_ROUND" ] && [ -d "$PHASE_DIR/remediation" ] && [ "$REMEDIATION_KIND" != "qa" ]; then
    REMED_DIR="$PHASE_DIR/remediation"
    REMED_KIND="legacy"
    _best_round_num=0
    for round_dir in "$REMED_DIR"/round-*/; do
      [ -d "$round_dir" ] || continue
      round_num=$(basename "$round_dir" | sed 's/^round-0*//')
      round_num=${round_num:-0}
      rr=$(printf '%02d' "$round_num")
      if [ "$round_num" -gt "$_best_round_num" ] 2>/dev/null && \
         ls "$round_dir"/R"${rr}"-PLAN.md >/dev/null 2>&1 && \
         ls "$round_dir"/R"${rr}"-SUMMARY.md >/dev/null 2>&1 && \
         is_summary_terminal "$round_dir/R${rr}-SUMMARY.md"; then
        _best_round_num="$round_num"
        LATEST_ROUND="$rr"
      fi
    done
  fi

  if [ -n "$LATEST_ROUND" ]; then
    rr=$(printf '%02d' "$LATEST_ROUND")
    ALL_PLAN_FILES=$(find "$REMED_DIR/round-$rr" -maxdepth 1 \( -name "R${rr}-PLAN.md" -o -name "R${rr}-*-PLAN.md" \) 2>/dev/null | sort)
    SCOPE_HEADER="verify_scope=remediation round=$rr"
    # UAT remediation rounds write round-scoped UAT artifacts; QA remediation
    # rounds still hand off to the canonical phase-level UAT path.
    case "$REMED_KIND" in
      qa)
        UAT_PATH=$(bash "${_CVC_SCRIPT_DIR}/resolve-artifact-path.sh" uat "$PHASE_DIR")
        ;;
      *)
        UAT_PATH="${REMED_DIR#"$PHASE_DIR/"}/round-$rr/R${rr}-UAT.md"
        ;;
    esac
  else
    # Fallback: no completed round found — use full scope
    REMEDIATION_ONLY=false
  fi
fi

if [ "$REMEDIATION_ONLY" = false ]; then
  # Full scope: all phase-root plans + all round-dir plans
  PLAN_FILES=$(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' \( -name '[0-9]*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | sort)
  ROUND_PLAN_FILES=$(find "$PHASE_DIR" -path '*/remediation/uat/round-*/R*-PLAN.md' 2>/dev/null | sort)
  # Legacy fallback: check old remediation/round-* layout for brownfield compat
  if [ -z "$ROUND_PLAN_FILES" ]; then
    ROUND_PLAN_FILES=$(find "$PHASE_DIR" -path '*/remediation/round-*/R*-PLAN.md' 2>/dev/null | sort)
  fi

  # QA remediation plans live in remediation/qa/round-*/R*-PLAN.md
  QA_ROUND_PLAN_FILES=$(find "$PHASE_DIR" -path '*/remediation/qa/round-*/R*-PLAN.md' 2>/dev/null | sort)

  ALL_PLAN_FILES="$PLAN_FILES"
  for _extra_plans in "$ROUND_PLAN_FILES" "$QA_ROUND_PLAN_FILES"; do
    if [ -n "$_extra_plans" ]; then
      if [ -n "$ALL_PLAN_FILES" ]; then
        ALL_PLAN_FILES=$(printf '%s\n%s' "$ALL_PLAN_FILES" "$_extra_plans")
      else
        ALL_PLAN_FILES="$_extra_plans"
      fi
    fi
  done
  SCOPE_HEADER="verify_scope=full"
  # Resolve UAT path via canonical resolver
  UAT_PATH=$(bash "${_CVC_SCRIPT_DIR}/resolve-artifact-path.sh" uat "$PHASE_DIR")
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
  # Try plan: first, fall back to round: (prefixed with R) for remediation plans
  PLAN_ID=$(awk '/^---$/{n++; next} n==1 && /^plan:/{v=$2; gsub(/^["'"'"']|["'"'"']$/, "", v); print v; exit}' "$plan_file" 2>/dev/null) || PLAN_ID=""
  if [ -z "$PLAN_ID" ]; then
    case "$(basename "$plan_file")" in
      R*-PLAN.md) PLAN_ID="$(basename "$plan_file" | sed 's/-PLAN\.md$//')" ;;
      *)
        PLAN_ID=$(awk '/^---$/{n++; next} n==1 && /^round:/{v=$2; gsub(/^["'"'"']|["'"'"']$/, "", v); print "R" v; exit}' "$plan_file" 2>/dev/null) || PLAN_ID=""
        ;;
    esac
  fi
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
  # Legacy phase-root plan: PLAN.md → SUMMARY.md (same dir)
  # Round-dir plans: R{RR}-PLAN.md → R{RR}-SUMMARY.md (same dir)
  PLAN_BASE=$(basename "$plan_file" | sed 's/-PLAN\.md$//')
  PLAN_DIR=$(dirname "$plan_file")
  if [ "$(basename "$plan_file")" = "PLAN.md" ] && [ -f "$PLAN_DIR/SUMMARY.md" ]; then
    SUMMARY_FILE="$PLAN_DIR/SUMMARY.md"
  elif [[ "$PLAN_DIR" == */round-* ]] && [[ "$PLAN_BASE" =~ ^R[0-9][0-9](-.*)?$ ]]; then
    ROUND_SUMMARY_BASE=$(printf '%s' "$PLAN_BASE" | sed 's/^\(R[0-9][0-9]\).*/\1/')
    SUMMARY_FILE="$PLAN_DIR/${ROUND_SUMMARY_BASE}-SUMMARY.md"
  else
    SUMMARY_FILE=$(find "$PLAN_DIR" -maxdepth 1 ! -name '.*' -name "${PLAN_BASE}-SUMMARY.md" 2>/dev/null | head -1)
  fi

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

    # Extract frontmatter files_modified array when present. This is the canonical
    # source for remediation summaries, which aggregate changed files in YAML.
    FILES_MODIFIED=$(extract_frontmatter_array_items "$SUMMARY_FILE" files_modified | awk '
      {
        files = files (files ? ", " : "") $0
      }
      END { print files }
    ' 2>/dev/null) || FILES_MODIFIED=""

    # Extract "What Was Built" (first 5 lines after the heading)
    WHAT_BUILT=$(awk '
      /^## What Was Built/ { found=1; count=0; next }
      found && /^## / { exit }
      found && /^[[:space:]]*$/ { next }
      found { count++; if (count <= 5) print; if (count >= 5) exit }
    ' "$SUMMARY_FILE" 2>/dev/null) || WHAT_BUILT=""

    # Canonical remediation summaries keep build notes under per-task
    # sections (`### What Was Built`) rather than a top-level heading.
    if [ -z "$WHAT_BUILT" ]; then
      WHAT_BUILT=$(awk '
        /^### What Was Built/ { found=1; next }
        found && /^### / { found=0; next }
        found && /^## / { found=0; next }
        found && /^[[:space:]]*$/ { next }
        found {
          count++
          if (count <= 5) print
        }
      ' "$SUMMARY_FILE" 2>/dev/null) || WHAT_BUILT=""
    fi

    # Fallback for phase-root summaries that still list files in a body section.
    if [ -z "$FILES_MODIFIED" ]; then
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

    # Extract deviations from SUMMARY.md YAML frontmatter (block or flow arrays)
    DEVIATIONS=$(extract_frontmatter_array_items "$SUMMARY_FILE" deviations | awk '
      {
        lc = tolower($0)
        if (lc ~ /^none\.?$/ || lc ~ /^n\/a\.?$/ || lc ~ /^na\.?$/ || lc ~ /^no deviations/) next
        items = items (items ? "; " : "") $0
      }
      END { print items }
    ' 2>/dev/null) || DEVIATIONS=""

    # Fallback: extract deviations from body ## Deviations section
    # Dev agents frequently write deviations only in the body section,
    # omitting the YAML frontmatter array. This fallback ensures QA
    # always receives deviation data regardless of where Dev wrote it.
    if [ -z "$DEVIATIONS" ]; then
      DEVIATIONS=$(awk '
        BEGIN { found=0; in_comment=0 }
        /^## Deviations/ || /^### Deviations/ { found=1; in_comment=0; next }
        found && (/^## / || /^### /) { found=0; next }
        found && /^[[:space:]]*$/ { next }
        found && /^[[:space:]]*<!--/ {
          in_comment=1
          if ($0 ~ /-->/) in_comment=0
          next
        }
        found && in_comment {
          if ($0 ~ /-->/) in_comment=0
          next
        }
        found {
          line = $0
          sub(/^- /, "", line)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
          # Check bold label for None/N/A before stripping (e.g., **N/A**: not applicable)
          if (tolower(line) ~ /^\*\*n(one|\/a|a)\*\*/ || tolower(line) ~ /^\*\*no deviations\*\*/) next
          # Strip bold prefix so "**Foo**: bar" becomes "bar"
          sub(/^\*\*[^*]+\*\*:?[[:space:]]*/, "", line)
          if (line == "") next
          # Skip "None" / "None." / "N/A" / "None. <explanation>" / "No deviations" entries (case-insensitive)
          lc = tolower(line)
          if (lc ~ /^none(\.[[:space:]].*|\.?)$/ || lc ~ /^n\/a(\.[[:space:]].*|\.?)$/ || lc ~ /^na(\.[[:space:]].*|\.?)$/ || lc ~ /^no deviations($|[.:].*)/) next
          items = items (items ? "; " : "") line
        }
        END { print items }
      ' "$SUMMARY_FILE" 2>/dev/null) || DEVIATIONS=""
    fi

    # Extract pre-existing issues from canonical SUMMARY.md frontmatter first.
    PRE_EXISTING=$(extract_frontmatter_array_items "$SUMMARY_FILE" pre_existing_issues | while IFS= read -r item; do
      [ -n "$item" ] || continue
      if ! printf '%s' "$item" | jq -e '
        type == "object"
        and (.test | type == "string")
        and (.file | type == "string")
        and (.error | type == "string")
      ' >/dev/null 2>&1; then
        continue
      fi
      _pre_test=$(printf '%s' "$item" | jq -r '.test')
      _pre_file=$(printf '%s' "$item" | jq -r '.file')
      _pre_error=$(printf '%s' "$item" | jq -r '.error')
      if [ "$_pre_file" = "$_pre_test" ]; then
        printf '%s: %s\n' "$_pre_test" "$_pre_error"
      else
        printf '%s (%s): %s\n' "$_pre_test" "$_pre_file" "$_pre_error"
      fi
    done | awk '
      {
        items = items (items ? "; " : "") $0
      }
      END { print items }
    ' 2>/dev/null) || PRE_EXISTING=""

    # Brownfield fallback: extract pre-existing issues from the legacy body section.
    if [ -z "$PRE_EXISTING" ] && ! frontmatter_key_present "$SUMMARY_FILE" pre_existing_issues; then
      PRE_EXISTING=$(awk '
        /^## Pre-existing Issues/ { found=1; next }
        found && /^## / { exit }
        found && /^[[:space:]]*$/ { next }
        found && /^- / {
          line = $0
          sub(/^- /, "", line)
          items = items (items ? "; " : "") line
        }
        END { print items }
      ' "$SUMMARY_FILE" 2>/dev/null) || PRE_EXISTING=""
    fi
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
  echo "deviations: ${DEVIATIONS:-none}"
  echo "pre_existing_issues: ${PRE_EXISTING:-none}"
  echo ""
done <<< "$ALL_PLAN_FILES"

# --- Known Issues (phase-scoped machine state for QA remediation/UAT gating) ---
_cvc_known_issues_path="$PHASE_DIR/known-issues.json"
if [ -f "$_cvc_known_issues_path" ]; then
  if jq -e '.issues | type == "array"' "$_cvc_known_issues_path" >/dev/null 2>&1; then
    _cvc_known_issue_count=$(jq '.issues | length' "$_cvc_known_issues_path" 2>/dev/null || echo 0)
    if [ "${_cvc_known_issue_count:-0}" -gt 0 ] 2>/dev/null; then
      echo "=== KNOWN ISSUES ==="
      echo "known_issues_path=$(basename "$_cvc_known_issues_path")"
      echo "known_issue_count=${_cvc_known_issue_count}"
      jq -r '
        .issues[]
        | "KNOWN_ISSUE: test=" + (.test // "-")
          + " | file=" + (.file // "-")
          + " | error=" + (.error // "-")
          + " | first_seen_in=" + (.first_seen_in // "-")
          + " | last_seen_in=" + (.last_seen_in // "-")
          + " | times_seen=" + ((.times_seen // 1) | tostring)
          + " | first_seen_round=" + ((.first_seen_round // 0) | tostring)
          + " | last_seen_round=" + ((.last_seen_round // 0) | tostring)
      ' "$_cvc_known_issues_path" 2>/dev/null || true
      echo ""
    fi
  else
    echo "=== KNOWN ISSUES ==="
    echo "known_issues_error=malformed"
    echo ""
  fi
fi

# --- Verification History (compound for QA remediation rounds) ---
# Extracts FAIL rows from phase-level and per-round VERIFICATION.md files
# so each QA round has full visibility into what was originally broken
# and what prior rounds attempted/found.
_cvc_phase_verif=$(bash "${_CVC_SCRIPT_DIR}/resolve-verification-path.sh" phase "$PHASE_DIR" 2>/dev/null || true)
if [ -n "$_cvc_phase_verif" ] && [ ! -f "$_cvc_phase_verif" ]; then
  _cvc_phase_verif=""
fi

_cvc_source_fail_verif=$(bash "${_CVC_SCRIPT_DIR}/resolve-verification-path.sh" plan-input "$PHASE_DIR" 2>/dev/null || true)
if [ -n "$_cvc_source_fail_verif" ] && [ ! -f "$_cvc_source_fail_verif" ]; then
  _cvc_source_fail_verif=""
fi
_cvc_source_fail_verif_missing=false
_cvc_remediation_state_active=false
if [ -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ]; then
  _cvc_remediation_state_active=true
  _cvc_active_round=$(grep '^round=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  if [[ "${_cvc_active_round:-}" =~ ^[0-9]+$ ]] && [ "$((10#${_cvc_active_round}))" -gt 1 ] 2>/dev/null; then
    _cvc_prev_round=$(printf '%02d' "$((10#${_cvc_active_round} - 1))")
    _cvc_expected_source_verif="$PHASE_DIR/remediation/qa/round-${_cvc_prev_round}/R${_cvc_prev_round}-VERIFICATION.md"
    if [ ! -f "$_cvc_expected_source_verif" ]; then
      _cvc_source_fail_verif_missing=true
      _cvc_source_fail_verif=""
    fi
  fi
  if [[ "${_cvc_active_round:-}" =~ ^[0-9]+$ ]] && [ -z "$_cvc_source_fail_verif" ]; then
    _cvc_source_fail_verif_missing=true
  fi
fi
if [ "$_cvc_source_fail_verif_missing" = false ] && [ -z "$_cvc_source_fail_verif" ] && [ -n "$_cvc_phase_verif" ] && [ "$_cvc_remediation_state_active" = false ]; then
  _cvc_source_fail_verif="$_cvc_phase_verif"
fi

# QA round VERIFICATION.md files
_cvc_qa_round_verifs=$(find "$PHASE_DIR" -path '*/remediation/qa/round-*/R*-VERIFICATION.md' 2>/dev/null | sort)

_cvc_has_verif_history=false
if [ -n "$_cvc_phase_verif" ] && [ -f "$_cvc_phase_verif" ]; then
  _cvc_has_verif_history=true
fi
if [ -n "$_cvc_qa_round_verifs" ]; then
  _cvc_has_verif_history=true
fi
if [ "$_cvc_source_fail_verif_missing" = true ]; then
  _cvc_has_verif_history=true
fi

if [ "$_cvc_has_verif_history" = true ]; then
  echo "=== VERIFICATION HISTORY ==="

  # Phase-level (original findings)
  if [ -n "$_cvc_phase_verif" ] && [ -f "$_cvc_phase_verif" ]; then
    _cvc_vhist_result=$(awk '
      BEGIN { in_fm=0 }
      NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
      in_fm && /^---[[:space:]]*$/ { exit }
      in_fm && /^result:/ { sub(/^result:[[:space:]]*/, ""); print; exit }
    ' "$_cvc_phase_verif" 2>/dev/null) || _cvc_vhist_result=""
    echo "--- Phase VERIFICATION (${_cvc_vhist_result:-unknown}) ---"
    awk -F'|' '
      function trim(v) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        return v
      }
      /^\|/ {
        if ($0 ~ /^\|[[:space:]-]+(\|[[:space:]-]+)+\|?[[:space:]]*$/) next
        for (i = 2; i < NF; i++) {
          cell = trim($i)
          if (cell == "Status") {
            status_col = i
            next
          }
        }
        if (status_col > 0) {
          status = trim($(status_col))
          gsub(/\*+/, "", status)
          status = trim(status)
          if (status == "FAIL") print
        }
      }
    ' "$_cvc_phase_verif" 2>/dev/null || true

  fi

  # Emit structured FAIL resolution requirements from the current remediation
  # planning input (phase-level on round 01, previous round verification on
  # round 02+). QA uses this block as the authoritative set of FAIL_IDs that
  # must be resolved in the current remediation round.
  if [ "$_cvc_source_fail_verif_missing" = true ]; then
    echo "--- ORIGINAL FAIL RESOLUTION STATUS ---"
    echo "source_verification_missing=true"
  elif [ -n "$_cvc_source_fail_verif" ] && [ -f "$_cvc_source_fail_verif" ]; then
    echo "--- ORIGINAL FAIL RESOLUTION STATUS ---"
    awk -F'|' '
      function trim(v) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        return v
      }
      !/^\|/ { header_found = 0; next }
      /^\|/ {
        if ($0 ~ /^\|[[:space:]-]+(\|[[:space:]-]+)+\|?[[:space:]]*$/) next
        if (!header_found) {
          status_col = 0; id_col = 0; desc_col = 0
          for (i = 2; i < NF; i++) {
            cell = trim($i)
            if (cell == "Status") status_col = i
            if (cell == "ID") id_col = i
            if (cell == "Truth/Condition") desc_col = i
            if (cell == "Artifact") desc_col = i
            if (cell == "Convention") desc_col = i
            if (cell == "Description") desc_col = i
            if (cell == "Link") desc_col = i
            if (cell == "Pattern") desc_col = i
            if (cell == "Requirement") desc_col = i
            if (cell == "From") desc_col = i
          }
          if (status_col > 0) header_found = 1
          next
        }
        if (status_col > 0) {
          status = trim($(status_col))
          gsub(/\*+/, "", status)
          status = trim(status)
          if (status == "FAIL") {
            fail_index++
            fail_id = (id_col > 0) ? trim($(id_col)) : ""
            if (fail_id == "") fail_id = sprintf("FAIL-ROW-%02d", fail_index)
            desc = (desc_col > 0) ? trim($(desc_col)) : "No description"
            printf "FAIL_ID: %s | ORIGINAL: %s | RESOLUTION_REQUIRED: code-fix, plan-amendment, or documented process-exception\n", fail_id, desc
          }
        }
      }
    ' "$_cvc_source_fail_verif" 2>/dev/null || true
  fi

  # Per-round (chronological compounding)
  if [ -n "$_cvc_qa_round_verifs" ]; then
    while IFS= read -r _cvc_verif_file; do
      [ -f "$_cvc_verif_file" ] || continue
      _cvc_vhist_rr=$(basename "$_cvc_verif_file" | sed 's/^R\([0-9]*\).*/\1/')
      _cvc_vhist_rresult=$(awk '
        BEGIN { in_fm=0 }
        NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
        in_fm && /^---[[:space:]]*$/ { exit }
        in_fm && /^result:/ { sub(/^result:[[:space:]]*/, ""); print; exit }
      ' "$_cvc_verif_file" 2>/dev/null) || _cvc_vhist_rresult=""
      echo "--- Round ${_cvc_vhist_rr} VERIFICATION (${_cvc_vhist_rresult:-unknown}) ---"
      awk -F'|' '
        function trim(v) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
          return v
        }
        /^\|/ {
          if ($0 ~ /^\|[[:space:]-]+(\|[[:space:]-]+)+\|?[[:space:]]*$/) next
          for (i = 2; i < NF; i++) {
            cell = trim($i)
            if (cell == "Status") {
              status_col = i
              next
            }
          }
          if (status_col > 0) {
            status = trim($(status_col))
            gsub(/\*+/, "", status)
            status = trim(status)
            if (status == "FAIL") print
          }
        }
      ' "$_cvc_verif_file" 2>/dev/null || true
    done <<< "$_cvc_qa_round_verifs"
  fi

  echo ""
fi

echo "verify_plan_count=${PLAN_COUNT}"
