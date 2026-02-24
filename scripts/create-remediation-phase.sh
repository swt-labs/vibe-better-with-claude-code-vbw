#!/usr/bin/env bash
set -euo pipefail

# create-remediation-phase.sh — create an active remediation phase from archived milestone UAT
#
# Usage:
#   create-remediation-phase.sh PLANNING_DIR MILESTONE_PHASE_DIR
#
# Output (stdout):
#   phase=<NN>
#   phase_dir=<path>
#   source_uat=<path|none>

PLANNING_DIR="${1:-}"
MILESTONE_PHASE_DIR="${2:-}"

if [[ -z "$PLANNING_DIR" || -z "$MILESTONE_PHASE_DIR" ]]; then
  echo "Usage: create-remediation-phase.sh PLANNING_DIR MILESTONE_PHASE_DIR" >&2
  exit 1
fi

if [[ ! -d "$PLANNING_DIR" ]]; then
  echo "Error: planning dir not found: $PLANNING_DIR" >&2
  exit 1
fi

if [[ ! -d "$MILESTONE_PHASE_DIR" ]]; then
  echo "Error: milestone phase dir not found: $MILESTONE_PHASE_DIR" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/uat-utils.sh"

list_child_dirs_sorted() {
  local parent="$1"
  [ -d "$parent" ] || return 0

  find "$parent" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null |
    (sort -V 2>/dev/null || awk -F/ '{n=$NF; gsub(/[^0-9].*/,"",n); if (n == "") n=0; print (n+0)"\t"$0}' | sort -n -k1,1 -k2,2 | cut -f2-)
}

extract_frontmatter_value() {
  local file="$1"
  local key="$2"

  [ -f "$file" ] || return 0

  awk -v k="$key" '
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm {
      pattern = "^" k "[[:space:]]*:[[:space:]]*"
      if ($0 ~ pattern) {
        value = $0
        sub(pattern, "", value)
        gsub(/[[:space:]]+$/, "", value)
        gsub(/^"|"$/, "", value)
        print value
        exit
      }
    }
  ' "$file" 2>/dev/null || true
}

humanize_slug() {
  local text="$1"
  text=$(printf '%s' "$text" | tr '-' ' ')
  text=$(printf '%s' "$text" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  printf '%s' "$text"
}

find_progress_row_for_phase() {
  local rows="$1"
  local target_phase="$2"

  printf '%s\n' "$rows" | awk -v target="$target_phase" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }

    {
      row = $0
      if (row !~ /^[[:space:]]*\|/) {
        next
      }

      split(row, cols, /\|/)
      if (length(cols) < 3) {
        next
      }

      phase = trim(cols[2])
      if (phase ~ /^[0-9]+$/ && (phase + 0) == (target + 0)) {
        print row
        exit
      }
    }
  '
}

all_active_phases_are_remediation() {
  local phases_dir="$PLANNING_DIR/phases"
  local canonical_count=0

  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    base=$(basename "$dir")
    num=$(echo "$base" | sed 's/[^0-9].*//')
    if [[ -z "$num" || ! "$num" =~ ^[0-9]+$ ]]; then
      continue
    fi
    canonical_count=$((canonical_count + 1))
    slug=$(echo "$base" | sed 's/^[0-9]*-//')
    case "$slug" in
      remediate-*) ;;
      *) return 1 ;;
    esac
  done < <(list_child_dirs_sorted "$phases_dir")

  [ "$canonical_count" -gt 0 ]
}

extract_project_name() {
  local project_file="$PLANNING_DIR/PROJECT.md"
  local project_name="VBW Project"

  if [ -f "$project_file" ]; then
    heading=$(awk '/^# / {sub(/^# /, "", $0); print; exit }' "$project_file" 2>/dev/null || true)
    if [ -n "$heading" ]; then
      project_name="$heading"
    fi
  fi

  printf '%s' "$project_name"
}

seed_remediation_roadmap_and_state() {
  local phases_dir="$PLANNING_DIR/phases"
  local roadmap_file="$PLANNING_DIR/ROADMAP.md"
  local state_file="$PLANNING_DIR/STATE.md"

  all_active_phases_are_remediation || return 0
  command -v jq >/dev/null 2>&1 || return 0

  phases_json=$(mktemp)
  printf '[]' > "$phases_json"

  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    [ -d "$dir" ] || continue

    base=$(basename "$dir")
    num=$(echo "$base" | sed 's/[^0-9].*//')
    if [[ -z "$num" || ! "$num" =~ ^[0-9]+$ ]]; then
      continue
    fi

    slug=$(echo "$base" | sed 's/^[0-9]*-//')
    phase_name="$(humanize_slug "$slug")"

    ctx_file=$(ls -1 "$dir"/[0-9]*-CONTEXT.md 2>/dev/null | sort | head -1 || true)
    source_phase=$(extract_frontmatter_value "$ctx_file" "source_phase")
    source_milestone=$(extract_frontmatter_value "$ctx_file" "source_milestone")

    if [ -n "$source_phase" ]; then
      source_phase_human=$(humanize_slug "${source_phase#*-}")
      [ -n "$source_phase_human" ] && phase_name="$source_phase_human"
    fi

    if [ -z "$source_milestone" ]; then
      source_milestone="archived milestone"
    fi
    if [ -z "$source_phase" ]; then
      source_phase="$base"
    fi

    goal="Resolve unresolved UAT issues from ${source_milestone} (${source_phase})."
    success_1="All source UAT issues for ${source_phase} are fixed and re-verified."
    success_2="No regressions are introduced while remediating ${source_phase}."

    phase_obj=$(jq -n \
      --arg name "$phase_name" \
      --arg goal "$goal" \
      --arg req "REQ-UAT" \
      --arg success1 "$success_1" \
      --arg success2 "$success_2" \
      '{name: $name, goal: $goal, requirements: [$req], success_criteria: [$success1, $success2]}')

    updated=$(jq --argjson phase "$phase_obj" '. + [$phase]' "$phases_json" 2>/dev/null || echo "")
    if [ -n "$updated" ]; then
      printf '%s\n' "$updated" > "$phases_json"
    fi
  done < <(list_child_dirs_sorted "$phases_dir")

  phase_count=$(jq 'length' "$phases_json" 2>/dev/null || echo 0)
  if [ "$phase_count" -gt 0 ]; then
    # Preserve existing progress rows from ROADMAP.md (avoid clobbering
    # progress when re-entering idempotently or adding new phases).
    existing_progress=""
    if [ -f "$roadmap_file" ]; then
      existing_progress=$(grep -E '^[[:space:]]*\|[[:space:]]*[0-9]+[[:space:]]*\|' "$roadmap_file" 2>/dev/null || true)
    fi

    {
      echo "# UAT Remediation Roadmap"
      echo ""
      echo "**Goal:** Resolve unresolved UAT issues recovered from archived milestone phases."
      echo ""
      echo "**Scope:** ${phase_count} phases"
      echo ""
      echo "## Progress"
      echo "| Phase | Status | Plans | Tasks | Commits |"
      echo "|-------|--------|-------|-------|---------|"
      for i in $(seq 0 $((phase_count - 1))); do
        phase_num=$((i + 1))
        preserved=$(find_progress_row_for_phase "$existing_progress" "$phase_num")
        if [ -n "$preserved" ]; then
          echo "$preserved"
        else
          echo "| ${phase_num} | Pending | 0 | 0 | 0 |"
        fi
      done
      echo ""
      echo "---"
      echo ""
      echo "## Phase List"
      for i in $(seq 0 $((phase_count - 1))); do
        phase_num=$((i + 1))
        phase_name=$(jq -r ".[$i].name" "$phases_json")
        phase_slug=$(printf '%s' "$phase_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')
        echo "- [ ] [Phase ${phase_num}: ${phase_name}](#phase-${phase_num}-${phase_slug})"
      done
      echo ""
      echo "---"
      echo ""

      for i in $(seq 0 $((phase_count - 1))); do
        phase_num=$((i + 1))
        phase_name=$(jq -r ".[$i].name" "$phases_json")
        phase_goal=$(jq -r ".[$i].goal" "$phases_json")
        phase_reqs=$(jq -r ".[$i].requirements // [] | join(\", \")" "$phases_json")
        criteria_count=$(jq ".[$i].success_criteria // [] | length" "$phases_json")

        echo "## Phase ${phase_num}: ${phase_name}"
        echo ""
        echo "**Goal:** ${phase_goal}"
        echo ""
        if [ -n "$phase_reqs" ]; then
          echo "**Requirements:** ${phase_reqs}"
          echo ""
        fi
        echo "**Success Criteria:**"
        for j in $(seq 0 $((criteria_count - 1))); do
          criterion=$(jq -r ".[$i].success_criteria[$j]" "$phases_json")
          echo "- ${criterion}"
        done
        echo ""
        if [ "$phase_num" -eq 1 ]; then
          echo "**Dependencies:** None"
        else
          echo "**Dependencies:** Phase $((phase_num - 1))"
        fi
        echo ""

        if [ "$i" -lt $((phase_count - 1)) ]; then
          echo "---"
          echo ""
        fi
      done
    } > "$roadmap_file"

    project_name=$(extract_project_name)

    # Preserve existing STATE.md phase statuses when the remediation milestone
    # is already seeded (avoid resetting progress on re-entry or phase addition).
    if [ -f "$state_file" ] && grep -q '^\*\*Milestone:\*\* UAT Remediation$' "$state_file" 2>/dev/null; then
      existing_phase_lines=$(awk '
        BEGIN { count = 0 }
        /^- \*\*Phase [0-9]+:\*\*/ { count++ }
        END { print count + 0 }
      ' "$state_file" 2>/dev/null)
      existing_phase_lines="${existing_phase_lines:-0}"
      if [ "$phase_count" -gt "$existing_phase_lines" ]; then
        # Append/repair phase entries after the last existing "- **Phase N:**"
        # line, or directly after "## Phase Status" when bullet lines are
        # missing in brownfield STATE.md files.
        awk -v start="$((existing_phase_lines + 1))" -v end="$phase_count" '
          /^## Phase Status$/ { phase_status_header = NR }
          /^- \*\*Phase [0-9]+:\*\*/ { last_phase_line = NR }
          { lines[NR] = $0; count = NR }
          END {
            inserted = 0
            for (i = 1; i <= count; i++) {
              print lines[i]
              if (last_phase_line > 0 && i == last_phase_line) {
                for (p = start; p <= end; p++) {
                  print "- **Phase " p ":** Pending"
                }
                inserted = 1
              } else if (last_phase_line == 0 && phase_status_header > 0 && i == phase_status_header) {
                for (p = start; p <= end; p++) {
                  print "- **Phase " p ":** Pending"
                }
                inserted = 1
              }
            }

            if (!inserted && start <= end) {
              if (count > 0 && lines[count] !~ /^$/) {
                print ""
              }
              print "## Phase Status"
              for (p = start; p <= end; p++) {
                print "- **Phase " p ":** Pending"
              }
            }
          }
        ' "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
      fi
    else
      bash "$SCRIPT_DIR/bootstrap/bootstrap-state.sh" "$state_file" "$project_name" "UAT Remediation" "$phase_count"
    fi
  fi

  rm -f "$phases_json"
}

# Idempotency: if this milestone phase already maps to a previously created
# remediation phase dir, return that mapping instead of creating duplicates.
EXISTING_MARKER_FILE="$MILESTONE_PHASE_DIR/.remediated"
if [[ -f "$EXISTING_MARKER_FILE" ]]; then
  EXISTING_TARGET_DIR=$(head -n1 "$EXISTING_MARKER_FILE" 2>/dev/null || true)
  if [[ -n "$EXISTING_TARGET_DIR" && -d "$EXISTING_TARGET_DIR" ]]; then
    EXISTING_PHASE=$(basename "$EXISTING_TARGET_DIR" | sed 's/-.*//')
    EXISTING_SOURCE_UAT=$(ls -1 "$EXISTING_TARGET_DIR"/[0-9]*-SOURCE-UAT.md 2>/dev/null | sort | tail -1 || true)
    if [[ -n "$EXISTING_SOURCE_UAT" && -f "$EXISTING_SOURCE_UAT" ]]; then
      EXISTING_SOURCE_UAT_OUT="$EXISTING_SOURCE_UAT"
    else
      EXISTING_SOURCE_UAT_OUT="none"
    fi
    seed_remediation_roadmap_and_state
    echo "phase=${EXISTING_PHASE}"
    echo "phase_dir=${EXISTING_TARGET_DIR}"
    echo "source_uat=${EXISTING_SOURCE_UAT_OUT}"
    exit 0
  fi
fi

PHASES_DIR="$PLANNING_DIR/phases"
mkdir -p "$PHASES_DIR"

# Determine next phase number from existing active phases.
MAX_PHASE=0
for d in "$PHASES_DIR"/*/; do
  [[ -d "$d" ]] || continue
  base=$(basename "$d")
  num=$(echo "$base" | sed 's/[^0-9].*//')
  [[ -n "$num" ]] || continue
  # Force base-10 to avoid octal interpretation for leading zeroes.
  n=$((10#$num))
  if [[ "$n" -gt "$MAX_PHASE" ]]; then
    MAX_PHASE="$n"
  fi
done

NEXT_PHASE=$((MAX_PHASE + 1))
NEXT_PHASE_PADDED=$(printf "%02d" "$NEXT_PHASE")

SOURCE_PHASE_SLUG=$(basename "$MILESTONE_PHASE_DIR" | sed 's/^[0-9]*-//')
SOURCE_MILESTONE_SLUG=$(basename "$(dirname "$(dirname "$MILESTONE_PHASE_DIR")")")
RAW_SLUG="remediate-${SOURCE_MILESTONE_SLUG}-${SOURCE_PHASE_SLUG}"
PHASE_SLUG=$(echo "$RAW_SLUG" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')

if [ ${#PHASE_SLUG} -gt 60 ]; then
  PHASE_SLUG_TRUNC=$(printf '%s' "$PHASE_SLUG" | cut -c1-60 | sed 's/-$//')
  PHASE_SLUG_WORD_SAFE=$(printf '%s' "$PHASE_SLUG_TRUNC" | sed 's/-[^-]*$//')
  if [[ -n "$PHASE_SLUG_WORD_SAFE" && "$PHASE_SLUG_WORD_SAFE" != "$PHASE_SLUG_TRUNC" ]]; then
    PHASE_SLUG="$PHASE_SLUG_WORD_SAFE"
  else
    PHASE_SLUG="$PHASE_SLUG_TRUNC"
  fi
fi

TARGET_PHASE_DIR="$PHASES_DIR/${NEXT_PHASE_PADDED}-${PHASE_SLUG}"
mkdir -p "$TARGET_PHASE_DIR"

SOURCE_UAT=$(latest_non_source_uat "$MILESTONE_PHASE_DIR")

# Extract UAT issues content to inline into CONTEXT.md as pre-seeded discussion
UAT_CONTENT=""
if [[ -n "$SOURCE_UAT" && -f "$SOURCE_UAT" ]]; then
  UAT_CONTENT=$(cat "$SOURCE_UAT")
fi

SOURCE_PHASE_BASENAME=$(basename "$MILESTONE_PHASE_DIR")

CONTEXT_FILE="$TARGET_PHASE_DIR/${NEXT_PHASE_PADDED}-CONTEXT.md"

cat > "$CONTEXT_FILE" <<CTXEOF
---
phase: ${NEXT_PHASE_PADDED}
title: Milestone UAT remediation
source_milestone: ${SOURCE_MILESTONE_SLUG}
source_phase: ${SOURCE_PHASE_BASENAME}
pre_seeded: true
---

# Phase ${NEXT_PHASE_PADDED}: UAT Remediation — Context

## User Vision

Fix unresolved UAT issues from archived milestone \`${SOURCE_MILESTONE_SLUG}\` (phase \`${SOURCE_PHASE_BASENAME}\`).

## Essential Features

All issues identified in the source UAT report must be resolved.

## Boundaries

Only address the issues listed below. Do not refactor or add features beyond what is needed to fix these issues.

## Acceptance Criteria

All UAT issues below are resolved and verified.

## Source UAT Report

CTXEOF

# Append UAT content verbatim — do not use unquoted heredoc to avoid
# shell expansion of $, backticks, or $() inside UAT report content.
if [ -n "$UAT_CONTENT" ]; then
  printf '%s\n' "$UAT_CONTENT" >> "$CONTEXT_FILE"
else
  printf '%s\n' 'No UAT report found in source phase.' >> "$CONTEXT_FILE"
fi

if [[ -n "$SOURCE_UAT" && -f "$SOURCE_UAT" ]]; then
  cp "$SOURCE_UAT" "$TARGET_PHASE_DIR/${NEXT_PHASE_PADDED}-SOURCE-UAT.md"
  SOURCE_UAT_OUT="$TARGET_PHASE_DIR/${NEXT_PHASE_PADDED}-SOURCE-UAT.md"
else
  SOURCE_UAT_OUT="none"
fi

# Mark the source milestone phase as remediated so phase-detect.sh
# won't trigger repeated milestone UAT recovery for the same issues.
echo "${TARGET_PHASE_DIR}" > "$MILESTONE_PHASE_DIR/.remediated"

seed_remediation_roadmap_and_state

echo "phase=${NEXT_PHASE_PADDED}"
echo "phase_dir=${TARGET_PHASE_DIR}"
echo "source_uat=${SOURCE_UAT_OUT}"

exit 0
