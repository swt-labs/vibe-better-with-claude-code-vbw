#!/usr/bin/env bash
# validate-uat-remediation-artifact.sh — deterministic gate for remediation artifacts.
#
# Usage:
#   validate-uat-remediation-artifact.sh <research|plan|summary> <absolute-artifact-path>
#
# UAT and QA remediation orchestrators use this before advancing persisted state
# so a sidechain/subagent artifact miss cannot be mistaken for a completed stage.

set -euo pipefail

ARTIFACT_TYPE="${1:-}"
ARTIFACT_PATH="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Set to "qa" or "uat" inside validate_common_path based on the artifact path structure;
# used by downstream artifact-type checks to allow per-kind variations (e.g. optional fields).
REMEDIATION_KIND=""

if [ -f "$SCRIPT_DIR/uat-utils.sh" ]; then
  # shellcheck source=scripts/uat-utils.sh
  source "$SCRIPT_DIR/uat-utils.sh"
fi

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

canonicalize_artifact_path() {
  local raw_path="$1" parent base parent_physical current link_target depth

  case "$raw_path" in
    /*) ;;
    *) return 1 ;;
  esac

  parent=$(dirname "$raw_path")
  base=$(basename "$raw_path")
  [ -d "$parent" ] || return 1
  parent_physical=$(cd "$parent" 2>/dev/null && pwd -P) || return 1
  current="$parent_physical/$base"

  depth=0
  while [ -L "$current" ]; do
    if [ "$depth" -ge 20 ]; then
      return 1
    fi
    link_target=$(readlink "$current" 2>/dev/null) || return 1
    case "$link_target" in
      /*) current="$link_target" ;;
      *) current="$(dirname "$current")/$link_target" ;;
    esac
    parent=$(dirname "$current")
    base=$(basename "$current")
    [ -d "$parent" ] || return 1
    parent_physical=$(cd "$parent" 2>/dev/null && pwd -P) || return 1
    current="$parent_physical/$base"
    depth=$((depth + 1))
  done

  printf '%s\n' "$current"
}

canonicalize_selected_path() {
  local selected_path="$1" canonical_path

  canonical_path=$(canonicalize_artifact_path "$selected_path") || return 1
  printf '%s\n' "$canonical_path"
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
  local phase_dir="$1"

  uat_phase_num_for_dir "$phase_dir"
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
  local phase_dir="$1" state_file legacy_state_file round="" layout

  state_file="$phase_dir/remediation/uat/.uat-remediation-stage"
  legacy_state_file="$phase_dir/.uat-remediation-stage"

  if [ -f "$state_file" ]; then
    round=$(grep '^round=' "$state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
  elif [ -f "$legacy_state_file" ]; then
    round=$(grep '^round=' "$legacy_state_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  fi

  layout=$(layout_for_phase_dir "$phase_dir")
  if [ "$layout" = "legacy" ]; then
    uat_resolve_legacy_round "$phase_dir" "$round"
  else
    echo "${round:-01}"
  fi
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
  local expected_suffix="$1" phase_dir phase_prefix artifact_basename layout selected_path selected_canonical_path

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
  selected_canonical_path=$(canonicalize_selected_path "$selected_path") \
    || emit_failure "state-selected legacy ${ARTIFACT_TYPE} artifact path is not canonical"

  if [ "$ARTIFACT_PATH" != "$selected_canonical_path" ]; then
    emit_failure "legacy artifact is stale; expected $selected_path"
  fi
}

validate_round_dir_artifact_path() {
  local remediation_kind="$1" expected_suffix="$2"
  local artifact_dir round_dir_base round_raw expected_round artifact_basename file_round shape_error mismatch_error

  artifact_dir=$(dirname "$ARTIFACT_PATH")
  round_dir_base=$(basename "$artifact_dir")
  round_raw="${round_dir_base#round-}"

  case "$remediation_kind" in
    qa)
      shape_error="artifact path must match the expected QA remediation plan filename shape"
      mismatch_error="QA remediation plan round token must match round directory"
      ;;
    *)
      shape_error="artifact path must match the expected round-dir ${expected_suffix} filename shape"
      mismatch_error="artifact round token must match round directory"
      ;;
  esac

  case "$round_dir_base" in
    round-[0-9]*) ;;
    *) emit_failure "$shape_error" ;;
  esac

  case "$round_raw" in
    ""|*[!0-9]*) emit_failure "$shape_error" ;;
  esac

  expected_round=$(printf "%02d" "$((10#$round_raw))")
  if [ "$round_raw" != "$expected_round" ]; then
    emit_failure "$shape_error"
  fi

  artifact_basename=$(basename "$ARTIFACT_PATH")
  file_round=$(printf '%s\n' "$artifact_basename" | sed -n "s/^R\([0-9][0-9]*\)-${expected_suffix}\.md$/\1/p")
  if [ -z "$file_round" ]; then
    emit_failure "$shape_error"
  fi

  if [ "$file_round" != "$expected_round" ]; then
    emit_failure "$mismatch_error"
  fi
}

validate_common_path() {
  local expected_suffix="$1" raw_artifact_path canonical_artifact_path

  case "$ARTIFACT_PATH" in
    /*) ;;
    *) emit_failure "artifact path must be absolute" ;;
  esac

  raw_artifact_path="$ARTIFACT_PATH"
  canonical_artifact_path=$(canonicalize_artifact_path "$ARTIFACT_PATH") \
    || emit_failure "artifact path parent directory does not exist or cannot be canonicalized"

  case "$canonical_artifact_path" in
    */.claude/worktrees/agent-*/*)
      emit_failure "artifact path points at a Claude sidechain; use the host repository path"
      ;;
  esac

  if [ "$raw_artifact_path" != "$canonical_artifact_path" ]; then
    emit_failure "artifact path must be the exact canonical host path"
  fi

  ARTIFACT_PATH="$canonical_artifact_path"

  case "$ARTIFACT_PATH" in
    */.claude/worktrees/agent-*/*)
      emit_failure "artifact path points at a Claude sidechain; use the host repository path"
      ;;
  esac

  case "$ARTIFACT_PATH" in
    */.vbw-planning/phases/*/remediation/uat/round-[0-9]*/*)
      REMEDIATION_KIND="uat"
      validate_round_dir_artifact_path "uat" "$expected_suffix"
      ;;
    */.vbw-planning/phases/*/remediation/qa/round-[0-9]*/*)
      REMEDIATION_KIND="qa"
      [ "$ARTIFACT_TYPE" = "plan" ] || emit_failure "QA remediation validation currently supports plan artifacts only"
      validate_round_dir_artifact_path "qa" "PLAN"
      ;;
    */.vbw-planning/phases/*/remediation/qa/*)
      emit_failure "artifact path must match the expected QA remediation plan filename shape"
      ;;
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
    contains_regex "$FRONTMATTER" '^known_issues_input:[[:space:]]*.*$' \
      || emit_failure "plan artifact missing known_issues_input metadata"
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
