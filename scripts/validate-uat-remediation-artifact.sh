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

validate_common_path() {
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
    */.vbw-planning/phases/*/remediation/uat/round-[0-9][0-9]/R[0-9][0-9]-"$1".md) ;;
    *) emit_failure "artifact path must point at the expected active-phase UAT remediation round file" ;;
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
