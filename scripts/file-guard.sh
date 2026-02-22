#!/bin/bash
set -u
# file-guard.sh — PreToolUse guard for undeclared file modifications
#
# NOTE: Worktree isolation has shipped (worktree_isolation config flag).
# When worktree_isolation is enabled, git worktrees provide filesystem
# isolation by construction. This guard remains active as a secondary
# enforcement layer (belt-and-suspenders) for both modes.
#
# Blocks Write/Edit to files not declared in active plan's files_modified.
# V2 enhancement: also checks forbidden_paths from active contract when v2_hard_contracts=true.
# Fail-open design: exit 0 on any error, exit 2 only on definitive violations

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
[ -z "$FILE_PATH" ] && exit 0

# Exempt planning artifacts — these are always allowed
case "$FILE_PATH" in
  *.vbw-planning/milestones/*/phases/*)
    # Archived milestone phase artifacts are read-only after archival.
    # Block writes to prevent execution from corrupting archived plans/summaries.
    # All other milestone root files are allowed (fall through to the
    # general .vbw-planning/* exemption below) because Archive mode
    # writes SHIPPED.md and moves STATE.md/ROADMAP.md during archival.
    echo "Blocked: writes to archived milestone phases are not allowed ($FILE_PATH)" >&2
    exit 2
    ;;
  *.vbw-planning/*|*SUMMARY.md|*VERIFICATION.md|*STATE.md|*CLAUDE.md|*.execution-state.json)
    exit 0
    ;;
esac

# Find project root by walking up from $PWD
find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.vbw-planning/phases" ]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

PROJECT_ROOT=$(find_project_root) || exit 0
PHASES_DIR="$PROJECT_ROOT/.vbw-planning/phases"
[ ! -d "$PHASES_DIR" ] && exit 0

# Normalize path helper
normalize_path() {
  local p="$1"
  if [ -n "$PROJECT_ROOT" ]; then
    p="${p#"$PROJECT_ROOT"/}"
  fi
  p="${p#./}"
  echo "$p"
}

# Best-effort absolute path resolver for boundary checks.
# - Relative paths are resolved from current working directory.
# - Non-existent paths still get a stable absolute lexical form.
to_abs_path() {
  local p="$1"
  local base dir file resolved_dir
  [ -z "$p" ] && {
    echo ""
    return 0
  }

  case "$p" in
    /*) base="$p" ;;
    *)  base="$PWD/${p#./}" ;;
  esac

  dir=$(dirname "$base")
  file=$(basename "$base")
  resolved_dir=$(cd "$dir" 2>/dev/null && pwd) || resolved_dir="$dir"
  echo "${resolved_dir%/}/$file"
}

NORM_TARGET=$(normalize_path "$FILE_PATH")

# --- Worktree boundary enforcement ---
CONFIG_PATH="$PROJECT_ROOT/.vbw-planning/config.json"
WORKTREE_ISOLATION="off"
if command -v jq >/dev/null 2>&1 && [ -f "$CONFIG_PATH" ]; then
  WORKTREE_ISOLATION=$(jq -r '.worktree_isolation // "off"' "$CONFIG_PATH" 2>/dev/null) || WORKTREE_ISOLATION="off"
fi
if [ "$WORKTREE_ISOLATION" != "off" ] && [ -n "${VBW_AGENT_ROLE:-}" ]; then
  case "${VBW_AGENT_ROLE:-}" in
    dev|debugger)
      AGENT_NAME_SHORT=$(echo "${VBW_AGENT_NAME:-}" | sed 's/.*vbw-//')
      WORKTREE_MAP_FILE="$PROJECT_ROOT/.vbw-planning/.agent-worktrees/${AGENT_NAME_SHORT}.json"
      if [ -f "$WORKTREE_MAP_FILE" ]; then
        WORKTREE_PATH=$(jq -r '.worktree_path // ""' "$WORKTREE_MAP_FILE" 2>/dev/null) || WORKTREE_PATH=""
        if [ -n "$WORKTREE_PATH" ]; then
          WORKTREE_ABS=$(to_abs_path "$WORKTREE_PATH")
          TARGET_ABS=$(to_abs_path "$FILE_PATH")
          case "$TARGET_ABS" in
            "$WORKTREE_ABS"/*|"$WORKTREE_ABS")
              : # inside worktree — allowed
              ;;
            *)
              echo "Blocked: write outside worktree boundary (expected prefix: $WORKTREE_ABS, got: $TARGET_ABS)" >&2
              exit 2
              ;;
          esac
        fi
      fi
      ;;
  esac
fi

# --- V2 forbidden_paths check from active contract ---
# v2_hard_contracts is now always enabled (graduated)

# Contract enforcement is now unconditional
if true; then
  CONTRACT_DIR="$PROJECT_ROOT/.vbw-planning/.contracts"
  if [ -d "$CONTRACT_DIR" ]; then
    # Find active contract: match the first plan without a SUMMARY
    # zsh compat: if no PLAN files exist, glob literal fails -f test and is skipped
    for PLAN_FILE in "$PHASES_DIR"/*/*-PLAN.md; do
      [ ! -f "$PLAN_FILE" ] && continue
      SUMMARY_FILE="${PLAN_FILE%-PLAN.md}-SUMMARY.md"
      if [ ! -f "$SUMMARY_FILE" ]; then
        # Extract phase and plan numbers from filename
        BASENAME=$(basename "$PLAN_FILE")
        PHASE_NUM=$(echo "$BASENAME" | sed 's/^\([0-9]*\)-.*/\1/')
        PLAN_NUM=$(echo "$BASENAME" | sed 's/^[0-9]*-\([0-9]*\)-.*/\1/')
        CONTRACT_FILE="${CONTRACT_DIR}/${PHASE_NUM}-${PLAN_NUM}.json"
        if [ -f "$CONTRACT_FILE" ]; then
          # Check forbidden_paths
          FORBIDDEN=$(jq -r '.forbidden_paths[]' "$CONTRACT_FILE" 2>/dev/null) || FORBIDDEN=""
          if [ -n "$FORBIDDEN" ]; then
            while IFS= read -r forbidden; do
              [ -z "$forbidden" ] && continue
              NORM_FORBIDDEN="${forbidden#./}"
              NORM_FORBIDDEN="${NORM_FORBIDDEN%/}"
              if [ "$NORM_TARGET" = "$NORM_FORBIDDEN" ] || [[ "$NORM_TARGET" == "$NORM_FORBIDDEN"/* ]]; then
                echo "Blocked: $NORM_TARGET is a forbidden path in contract (${CONTRACT_FILE})" >&2
                exit 2
              fi
            done <<< "$FORBIDDEN"
          fi
          # Check allowed_paths — file must be in contract scope (only if allowed_paths is specified)
          # Note: allowed_paths is optional; if empty, fall through to plan files_modified check
          ALLOWED=$(jq -r '.allowed_paths[]' "$CONTRACT_FILE" 2>/dev/null) || ALLOWED=""
          if [ -n "$ALLOWED" ]; then
            IN_SCOPE=false
            while IFS= read -r allowed; do
              [ -z "$allowed" ] && continue
              NORM_ALLOWED="${allowed#./}"
              if [ "$NORM_TARGET" = "$NORM_ALLOWED" ]; then
                IN_SCOPE=true
                break
              fi
            done <<< "$ALLOWED"
            if [ "$IN_SCOPE" = "false" ]; then
              echo "Blocked: $NORM_TARGET not in contract allowed_paths (${CONTRACT_FILE})" >&2
              exit 2
            fi
          fi
        fi
        break
      fi
    done
  fi
fi

# --- V2 role isolation: check agent role against path rules ---
# v2_role_isolation is now always enabled (graduated)
AGENT_ROLE="${VBW_AGENT_ROLE:-}"
if [ -n "$AGENT_ROLE" ]; then
  case "$AGENT_ROLE" in
    lead|architect|qa)
      # Planning roles can only write to .vbw-planning/ (already exempted above, so reaching here means non-planning path)
      echo "Blocked: role '${AGENT_ROLE}' cannot write outside .vbw-planning/" >&2
      exit 2
      ;;
    scout)
      # Scout is read-only — block all non-planning writes
      echo "Blocked: role 'scout' is read-only" >&2
      exit 2
      ;;
    dev|debugger)
      # Dev/debugger allowed — contract allowed_paths enforced above
      ;;
    *)
      # Unknown role — fail-open
      ;;
  esac
fi
# No role set — fail-open

# --- Original file-guard: check files_modified from active plan ---
ACTIVE_PLAN=""
# zsh compat: if no PLAN files exist, glob literal fails -f test and is skipped
for PLAN_FILE in "$PHASES_DIR"/*/*-PLAN.md; do
  [ ! -f "$PLAN_FILE" ] && continue
  SUMMARY_FILE="${PLAN_FILE%-PLAN.md}-SUMMARY.md"
  if [ ! -f "$SUMMARY_FILE" ]; then
    ACTIVE_PLAN="$PLAN_FILE"
    break
  fi
done

# No active plan found — fail-open
[ -z "$ACTIVE_PLAN" ] && exit 0

# Extract files_modified from YAML frontmatter
DECLARED_FILES=$(awk '
  BEGIN { in_front=0; in_files=0 }
  /^---$/ {
    if (in_front == 0) { in_front=1; next }
    else { exit }
  }
  in_front && /^files_modified:/ { in_files=1; next }
  in_front && in_files && /^[[:space:]]+- / {
    sub(/^[[:space:]]+- /, "")
    gsub(/["'"'"']/, "")
    print
    next
  }
  in_front && in_files && /^[^[:space:]]/ { in_files=0 }
' "$ACTIVE_PLAN" 2>/dev/null) || exit 0

# No files_modified declared — fail-open
[ -z "$DECLARED_FILES" ] && exit 0

# Check if target file is in declared files
while IFS= read -r declared; do
  [ -z "$declared" ] && continue
  NORM_DECLARED=$(normalize_path "$declared")
  if [ "$NORM_TARGET" = "$NORM_DECLARED" ]; then
    exit 0
  fi
done <<< "$DECLARED_FILES"

# File not declared — block the write
echo "Blocked: $NORM_TARGET is not in active plan's files_modified ($ACTIVE_PLAN)" >&2
exit 2
