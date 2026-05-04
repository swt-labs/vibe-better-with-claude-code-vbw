#!/usr/bin/env bash
# validate-uat-remediation-artifact.sh — deterministic gate for UAT remediation artifacts.
#
# Usage:
#   validate-uat-remediation-artifact.sh <research|plan|summary> <absolute-artifact-path>
#
# The UAT remediation orchestrator uses this before advancing persisted state so
# a sidechain/subagent artifact miss cannot be mistaken for a completed stage.

set -euo pipefail

ARTIFACT_TYPE="${1:-}"
ARTIFACT_PATH="${2:-}"

usage() {
  echo "Usage: validate-uat-remediation-artifact.sh <research|plan|summary> <absolute-artifact-path>" >&2
}

emit_failure() {
  local message="$1"

  echo "artifact_valid=false"
  echo "artifact_type=${ARTIFACT_TYPE}"
  echo "artifact_path=${ARTIFACT_PATH}"
  echo "artifact_error=${message}"
  exit 1
}

contains_regex() {
  local text="$1"
  local regex="$2"

  grep -Eq -- "$regex" <<< "$text"
}

extract_frontmatter() {
  local file="$1"

  awk '
    BEGIN { delimiter_count = 0 }
    /^---[[:space:]]*$/ {
      delimiter_count++
      if (delimiter_count == 2) exit
      next
    }
    delimiter_count == 1 { print }
  ' "$file"
}

artifact_phase_dir() {
  local path="$1" root suffix phase_slug

  case "$path" in
    */.vbw-planning/phases/*/*) ;;
    *) return 1 ;;
  esac

  root="${path%%/.vbw-planning/phases/*}"
  suffix="${path#*/.vbw-planning/phases/}"
  phase_slug="${suffix%%/*}"

  [ -n "$root" ] || return 1
  [ -n "$phase_slug" ] || return 1
  printf '%s/.vbw-planning/phases/%s\n' "$root" "$phase_slug"
}

phase_prefix_for_dir() {
  local phase_dir="$1" phase_basename

  phase_basename=$(basename "$phase_dir")
  printf '%s\n' "$phase_basename" | sed 's/-[^0-9].*//'
}

layout_for_phase_dir() {
  local phase_dir="$1" state_file legacy_state_file layout=""

  state_file="$phase_dir/remediation/uat/.uat-remediation-stage"
  legacy_state_file="$phase_dir/.uat-remediation-stage"

  if [ -f "$state_file" ]; then
    layout=$(grep '^layout=' "$state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
    echo "${layout:-round-dir}"
  elif [ -f "$legacy_state_file" ]; then
    layout=$(grep '^layout=' "$legacy_state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
    echo "${layout:-legacy}"
  else
    echo "round-dir"
  fi
}

round_for_phase_dir() {
  local phase_dir="$1" state_file legacy_state_file round=""

  state_file="$phase_dir/remediation/uat/.uat-remediation-stage"
  legacy_state_file="$phase_dir/.uat-remediation-stage"

  if [ -f "$state_file" ]; then
    round=$(grep '^round=' "$state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
  elif [ -f "$legacy_state_file" ]; then
    round=$(grep '^round=' "$legacy_state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  fi

  echo "${round:-01}"
}

selected_legacy_artifact_path() {
  local phase_dir="$1" artifact_type="$2" phase_prefix round round_dir_artifact phase_root_artifact

  phase_prefix=$(phase_prefix_for_dir "$phase_dir")
  round=$(round_for_phase_dir "$phase_dir")
  case "$artifact_type" in
    research)
      round_dir_artifact="$phase_dir/remediation/uat/round-${round}/R${round}-RESEARCH.md"
      if [ -f "$round_dir_artifact" ]; then
        echo "$round_dir_artifact"
        return 0
      fi

      phase_root_artifact=$(find "$phase_dir" -maxdepth 1 -name "${phase_prefix}-*-RESEARCH.md" ! -name '.*' 2>/dev/null | sort | tail -1)
      if [ -n "$phase_root_artifact" ] && [ -f "$phase_root_artifact" ]; then
        echo "$phase_root_artifact"
        return 0
      fi

      phase_root_artifact="$phase_dir/${phase_prefix}-RESEARCH.md"
      if [ -f "$phase_root_artifact" ]; then
        echo "$phase_root_artifact"
        return 0
      fi
      ;;
    plan)
      round_dir_artifact="$phase_dir/remediation/uat/round-${round}/R${round}-PLAN.md"
      if [ -f "$round_dir_artifact" ]; then
        echo "$round_dir_artifact"
        return 0
      fi

      phase_root_artifact=$(find "$phase_dir" -maxdepth 1 -name "${phase_prefix}-*-PLAN.md" ! -name '.*' 2>/dev/null | sort | tail -1)
      if [ -n "$phase_root_artifact" ] && [ -f "$phase_root_artifact" ]; then
        echo "$phase_root_artifact"
        return 0
      fi
      ;;
  esac

  return 1
}

validate_legacy_phase_root_path() {
  local expected_suffix="$1" phase_dir phase_prefix artifact_basename layout selected_path

  if [ "$ARTIFACT_TYPE" = "summary" ]; then
    emit_failure "summary artifacts must use the round-dir layout"
  fi

  phase_dir=$(artifact_phase_dir "$ARTIFACT_PATH") \
    || emit_failure "artifact path must point at an active .vbw-planning/phases/ artifact"

  if [ "$(dirname "$ARTIFACT_PATH")" != "$phase_dir" ]; then
    emit_failure "legacy phase-root artifacts must be direct children of the active phase directory"
  fi

  phase_prefix=$(phase_prefix_for_dir "$phase_dir")
  artifact_basename=$(basename "$ARTIFACT_PATH")
  case "$ARTIFACT_TYPE:$artifact_basename" in
    research:"${phase_prefix}-RESEARCH.md"|research:"${phase_prefix}"-*-RESEARCH.md|plan:"${phase_prefix}"-*-PLAN.md) ;;
    *) emit_failure "artifact path must match the expected legacy ${expected_suffix} filename shape" ;;
  esac

  layout=$(layout_for_phase_dir "$phase_dir")
  if [ "$layout" != "legacy" ]; then
    emit_failure "legacy phase-root artifacts require layout=legacy"
  fi

  selected_path=$(selected_legacy_artifact_path "$phase_dir" "$ARTIFACT_TYPE") \
    || emit_failure "no current legacy ${ARTIFACT_TYPE} artifact is selected by state metadata"

  if [ "$ARTIFACT_PATH" != "$selected_path" ]; then
    emit_failure "legacy artifact is stale; expected $selected_path"
  fi
}

validate_common_path() {
  local expected_suffix="$1"

  case "$ARTIFACT_PATH" in
    /*) ;;
    *) emit_failure "artifact path must be absolute" ;;
  esac

  case "$ARTIFACT_PATH" in
    */.claude/worktrees/agent-*/*)
      emit_failure "artifact path points at a Claude sidechain; use the host repository path"
      ;;
  esac

  case "$ARTIFACT_PATH" in
    */.vbw-planning/phases/*/remediation/uat/round-[0-9][0-9]/R[0-9][0-9]-"$expected_suffix".md) ;;
    *) validate_legacy_phase_root_path "$expected_suffix" ;;
  esac

  if [ ! -f "$ARTIFACT_PATH" ]; then
    emit_failure "artifact file does not exist"
  fi

  if [ ! -s "$ARTIFACT_PATH" ]; then
    emit_failure "artifact file is empty"
  fi
}

validate_frontmatter() {
  local frontmatter="$1"

  if [ -z "$frontmatter" ]; then
    emit_failure "artifact missing YAML frontmatter"
  fi

  contains_regex "$frontmatter" '^phase:[[:space:]]*[0-9]+([[:space:]]*(#.*)?)?$' \
    || emit_failure "artifact frontmatter missing numeric phase"
  contains_regex "$frontmatter" '^round:[[:space:]]*[0-9]+([[:space:]]*(#.*)?)?$' \
    || emit_failure "artifact frontmatter missing numeric round"
  contains_regex "$frontmatter" '^title:[[:space:]]*.+' \
    || emit_failure "artifact frontmatter missing title"
}

if [ -z "$ARTIFACT_TYPE" ] || [ -z "$ARTIFACT_PATH" ]; then
  usage
  exit 1
fi

case "$ARTIFACT_TYPE" in
  research|plan|summary) ;;
  *)
    usage
    exit 1
    ;;
esac

expected_suffix=""
case "$ARTIFACT_TYPE" in
  research) expected_suffix="RESEARCH" ;;
  plan) expected_suffix="PLAN" ;;
  summary) expected_suffix="SUMMARY" ;;
esac

validate_common_path "$expected_suffix"
FRONTMATTER=$(extract_frontmatter "$ARTIFACT_PATH")
validate_frontmatter "$FRONTMATTER"

case "$ARTIFACT_TYPE" in
  research)
    contains_regex "$FRONTMATTER" '^type:[[:space:]]*remediation-research([[:space:]]*(#.*)?)?$' \
      || emit_failure "research artifact type must be remediation-research"
    grep -Eq '^## Findings[[:space:]]*$' "$ARTIFACT_PATH" \
      || emit_failure "research artifact missing Findings section"
    grep -Eq '^## Root Cause Assessment[[:space:]]*$' "$ARTIFACT_PATH" \
      || emit_failure "research artifact missing Root Cause Assessment section"
    ;;
  plan)
    contains_regex "$FRONTMATTER" '^type:[[:space:]]*remediation([[:space:]]*(#.*)?)?$' \
      || emit_failure "plan artifact type must be remediation"
    contains_regex "$FRONTMATTER" '^fail_classifications:[[:space:]]*.*$' \
      || emit_failure "plan artifact missing fail_classifications metadata"
    contains_regex "$FRONTMATTER" '^known_issue_resolutions:[[:space:]]*.*$' \
      || emit_failure "plan artifact missing known_issue_resolutions metadata"
    grep -Eq '^<tasks>[[:space:]]*$' "$ARTIFACT_PATH" \
      || emit_failure "plan artifact missing tasks block"
    grep -Eq '^<verification>[[:space:]]*$' "$ARTIFACT_PATH" \
      || emit_failure "plan artifact missing verification block"
    ;;
  summary)
    contains_regex "$FRONTMATTER" '^type:[[:space:]]*remediation([[:space:]]*(#.*)?)?$' \
      || emit_failure "summary artifact type must be remediation"
    contains_regex "$FRONTMATTER" '^status:[[:space:]]*(complete|partial|failed)([[:space:]]*(#.*)?)?$' \
      || emit_failure "summary artifact status must be complete, partial, or failed before state advance"
    contains_regex "$FRONTMATTER" '^tasks_completed:[[:space:]]*[0-9]+([[:space:]]*(#.*)?)?$' \
      || emit_failure "summary artifact missing tasks_completed metadata"
    contains_regex "$FRONTMATTER" '^tasks_total:[[:space:]]*[0-9]+([[:space:]]*(#.*)?)?$' \
      || emit_failure "summary artifact missing tasks_total metadata"
    contains_regex "$FRONTMATTER" '^known_issue_outcomes:[[:space:]]*.*$' \
      || emit_failure "summary artifact missing known_issue_outcomes metadata"
    ;;
esac

echo "artifact_valid=true"
echo "artifact_type=${ARTIFACT_TYPE}"
echo "artifact_path=${ARTIFACT_PATH}"
