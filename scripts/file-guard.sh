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

# Block misnamed plan/summary/context files in phase dirs (type-first format)
# Must precede the .vbw-planning/* exemption which exits 0 for all planning artifacts.
# Case-insensitive on extension (.md/.MD/.Md) to prevent bypass.
# Normalize path: resolve .. components so traversal paths are matched intentionally,
# not via accidental * matching across / separators.
_FG_NORMALIZED=$(echo "$FILE_PATH" | sed 's#/[^/]*/\.\./#/#g')
FILE_PATH_LC=$(echo "$_FG_NORMALIZED" | tr '[:upper:]' '[:lower:]')
case "$FILE_PATH_LC" in
  *.vbw-planning/phases/*/plan-[0-9]*.md|*.vbw-planning/phases/*/summary-[0-9]*.md|*.vbw-planning/phases/*/context-[0-9]*.md)
    _BASENAME_CHECK=$(basename "$FILE_PATH" 2>/dev/null) || _BASENAME_CHECK="$FILE_PATH"
    _BASENAME_LC=$(echo "$_BASENAME_CHECK" | tr '[:upper:]' '[:lower:]')
    # Only block exact type-first patterns (type-NN.md) and known compounds (plan-NN-summary.md, plan-NN-context.md).
    # Allow arbitrary filenames like plan-01-review.md through.
    if echo "$_BASENAME_LC" | grep -qE '^(plan|summary|context)-[0-9]+\.md$' || \
       echo "$_BASENAME_LC" | grep -qE '^plan-[0-9]+-(summary|context)\.md$'; then
      # Detect the artifact type for a precise error message
      _FG_TYPE="PLAN"
      case "$_BASENAME_LC" in
        summary-*|*-summary.*) _FG_TYPE="SUMMARY" ;;
        context-*|*-context.*) _FG_TYPE="CONTEXT" ;;
      esac
      echo "Blocked: wrong naming convention for $_FG_TYPE artifact. Use {NN}-${_FG_TYPE}.md (e.g., 01-${_FG_TYPE}.md), not ${_FG_TYPE}-{NN}.md ($_BASENAME_CHECK)" >&2
      exit 2
    fi
    ;;
esac

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
  *.vbw-planning/*/remediation/round-*/R[0-9]*-SUMMARY.md)
    # Remediation round summaries have an incremental lifecycle:
    # task 1 Dev creates with status: in-progress, subsequent Devs append,
    # Lead finalizes to terminal status. Exempt from terminal-status guard.
    exit 0
    ;;
  *.vbw-planning/*-SUMMARY.md)
    # Block SUMMARY.md writes with non-terminal status values (prevent stub SUMMARYs)
    _FG_SUM_STATUS=$(echo "$INPUT" | jq -r '.tool_input.content // ""' 2>/dev/null | sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' | head -1 | tr -d '[:space:]')
    if [ -n "$_FG_SUM_STATUS" ]; then
      case "$_FG_SUM_STATUS" in
        complete|completed|partial|failed) ;;  # terminal — allow
        *)
          echo "Blocked: SUMMARY.md status '${_FG_SUM_STATUS}' is not terminal (must be complete|partial|failed)" >&2
          exit 2
          ;;
      esac
    fi
    # If status can't be parsed (e.g. Edit tool without full content), fail-open
    exit 0
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

# Source shared summary-status helpers (fail-open: inline fallback if lib unavailable)
_FG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_FG_STATUS_LIB="${_FG_SCRIPT_DIR}/summary-utils.sh"
if [ -f "$_FG_STATUS_LIB" ]; then
  # shellcheck source=summary-utils.sh
  source "$_FG_STATUS_LIB"
  is_plan_finalized() { is_summary_terminal "$1"; }
else
  # Safe default: treat plans as not finalized when helpers unavailable
  is_plan_finalized() { return 1; }
fi

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
    # Find active contract: match the first plan without a finalized SUMMARY
    # A plan is active if its SUMMARY doesn't exist or has a non-terminal status.
    # zsh compat: if no PLAN files exist, glob literal fails -f test and is skipped
    for PLAN_FILE in "$PHASES_DIR"/*/*-PLAN.md; do
      [ ! -f "$PLAN_FILE" ] && continue
      SUMMARY_FILE="${PLAN_FILE%-PLAN.md}-SUMMARY.md"
      if ! is_plan_finalized "$SUMMARY_FILE"; then
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

# --- Orchestrator delegation guard (delegated workflows) ---
# When a VBW delegated workflow is active (execute, fix, debug) and the caller is
# the orchestrator (no VBW_AGENT_ROLE), block product-file writes. The orchestrator
# must delegate to Dev/Debugger subagents via Task tool. Subagents (with a role set)
# are unaffected. Turbo/direct effort modes where the orchestrator is expected to
# implement are exempt.
#
# Fail-open: missing/malformed/stale state files skip the guard.
#
# NOTE: VBW_AGENT_ROLE is NOT set by the Claude Code runtime for PreToolUse hooks.
# Subagent detection uses .active-agent-count (written by agent-start.sh, decremented
# by agent-stop.sh). If count > 0, at least one VBW subagent is running and this
# hook invocation is from that subagent context — skip the orchestrator block.
#
# Agent Teams bypass: SubagentStart hooks do NOT fire for agent team teammates
# (teammates are separate Claude Code sessions, not subagents spawned via the
# Agent tool). PreToolUse hooks can't distinguish orchestrator from teammate —
# no agent_id/agent_type fields are present for teammates. When prefer_teams is
# configured (not "never"), skip the guard entirely. The teams coordination
# mechanism replaces the subagent delegation model this guard was designed for.
if [ -z "${VBW_AGENT_ROLE:-}" ]; then
  # Check .active-agent-count: if VBW subagents are active, this write is from
  # a subagent (PreToolUse hooks don't carry agent identity). Skip the guard.
  _DG_COUNT_FILE="$PROJECT_ROOT/.vbw-planning/.active-agent-count"
  if [ -f "$_DG_COUNT_FILE" ]; then
    _DG_AGENT_COUNT=$(cat "$_DG_COUNT_FILE" 2>/dev/null | tr -d '[:space:]')
    if echo "$_DG_AGENT_COUNT" | grep -Eq '^[0-9]+$' && [ "$_DG_AGENT_COUNT" -gt 0 ]; then
      # VBW subagent is active — allow the write
      exit 0
    fi
  fi

  # Check prefer_teams: if agent teams are configured, this write may be from a
  # teammate session. SubagentStart never fires for teammates, so .active-agent-count
  # won't reflect them. Fail-open to avoid blocking legitimate teammate writes.
  _DG_CONFIG="$PROJECT_ROOT/.vbw-planning/config.json"
  if [ -f "$_DG_CONFIG" ]; then
    _DG_PREFER_TEAMS=$(jq -r '.prefer_teams // "auto"' "$_DG_CONFIG" 2>/dev/null) || _DG_PREFER_TEAMS="auto"
    case "$_DG_PREFER_TEAMS" in
      never) ;; # Teams disabled — keep the guard active for subagent model
      *) exit 0 ;; # Teams may be active — can't distinguish orchestrator from teammate
    esac
  fi

  _DG_BLOCK=false
  _DG_EFFORT=""

  # Source 1: .execution-state.json (execute/remediation paths)
  _EXEC_STATE_FILE="$PROJECT_ROOT/.vbw-planning/.execution-state.json"
  if [ -f "$_EXEC_STATE_FILE" ]; then
    _EXEC_STATUS=$(jq -r '.status // ""' "$_EXEC_STATE_FILE" 2>/dev/null) || _EXEC_STATUS=""
    if [ "$_EXEC_STATUS" = "running" ]; then
      # Staleness check: skip if file older than 4 hours (14400s)
      _DG_NOW=$(date +%s 2>/dev/null || echo 0)
      if [ "$(uname)" = "Darwin" ]; then
        _DG_MTIME=$(stat -f %m "$_EXEC_STATE_FILE" 2>/dev/null || echo 0)
      else
        _DG_MTIME=$(stat -c %Y "$_EXEC_STATE_FILE" 2>/dev/null || echo 0)
      fi
      _DG_AGE=$((_DG_NOW - _DG_MTIME))
      if [ "$_DG_AGE" -ge 0 ] && [ "$_DG_AGE" -lt 14400 ]; then
        _DG_BLOCK=true
        _DG_EFFORT=$(jq -r '.effort // ""' "$_EXEC_STATE_FILE" 2>/dev/null) || _DG_EFFORT=""
      fi
    fi
  fi

  # Source 2: .delegated-workflow.json (fix/debug ad-hoc paths)
  if [ "$_DG_BLOCK" = false ]; then
    _DELEG_FILE="$PROJECT_ROOT/.vbw-planning/.delegated-workflow.json"
    if [ -f "$_DELEG_FILE" ]; then
      _DELEG_ACTIVE=$(jq -r '.active // false' "$_DELEG_FILE" 2>/dev/null) || _DELEG_ACTIVE="false"
      if [ "$_DELEG_ACTIVE" = "true" ]; then
        # Staleness check: skip if file older than 4 hours
        _DG_NOW=$(date +%s 2>/dev/null || echo 0)
        if [ "$(uname)" = "Darwin" ]; then
          _DG_MTIME=$(stat -f %m "$_DELEG_FILE" 2>/dev/null || echo 0)
        else
          _DG_MTIME=$(stat -c %Y "$_DELEG_FILE" 2>/dev/null || echo 0)
        fi
        _DG_AGE=$((_DG_NOW - _DG_MTIME))
        if [ "$_DG_AGE" -ge 0 ] && [ "$_DG_AGE" -lt 14400 ]; then
          _DG_BLOCK=true
          _DG_EFFORT=$(jq -r '.effort // ""' "$_DELEG_FILE" 2>/dev/null) || _DG_EFFORT=""
        fi
      fi
    fi
  fi

  # If delegated workflow active, check if effort allows direct orchestrator writes
  if [ "$_DG_BLOCK" = true ]; then
    # Turbo/direct: orchestrator implements directly — no block
    # Resolve effective effort: state file > config fallback
    if [ -z "$_DG_EFFORT" ] || [ "$_DG_EFFORT" = "null" ]; then
      _DG_EFFORT=$(jq -r '.effort // "balanced"' "$PROJECT_ROOT/.vbw-planning/config.json" 2>/dev/null) || _DG_EFFORT="balanced"
    fi
    case "$_DG_EFFORT" in
      turbo|direct)
        : # Turbo/direct — orchestrator is expected to write, allow
        ;;
      *)
        echo "Blocked: orchestrator cannot write product files during delegated workflow (effort=$_DG_EFFORT). Delegate via Task tool to Dev/Debugger subagent." >&2
        exit 2
        ;;
    esac
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
# A plan is active if its SUMMARY doesn't exist or has a non-terminal status.
# zsh compat: if no PLAN files exist, glob literal fails -f test and is skipped
for PLAN_FILE in "$PHASES_DIR"/*/*-PLAN.md; do
  [ ! -f "$PLAN_FILE" ] && continue
  SUMMARY_FILE="${PLAN_FILE%-PLAN.md}-SUMMARY.md"
  if ! is_plan_finalized "$SUMMARY_FILE"; then
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
