#!/usr/bin/env bash
set -euo pipefail

# planning-git.sh — Manage planning artifact git behavior from config.
#
# Usage:
#   planning-git.sh sync-ignore [CONFIG_FILE]
#   planning-git.sh commit-boundary <action> [CONFIG_FILE]
#   planning-git.sh push-after-phase [CONFIG_FILE]


COMMAND="${1:-}"
ARG2="${2:-}"
ARG3="${3:-}"

is_git_repo() {
  git rev-parse --git-dir >/dev/null 2>&1
}

read_config() {
  local config_file="$1"

  CFG_PLANNING_TRACKING="manual"
  CFG_AUTO_PUSH="never"

  if [ -f "$config_file" ] && command -v jq >/dev/null 2>&1; then
    CFG_PLANNING_TRACKING=$(jq -r '.planning_tracking // "manual"' "$config_file" 2>/dev/null || echo "manual")
    CFG_AUTO_PUSH=$(jq -r '.auto_push // "never"' "$config_file" 2>/dev/null || echo "never")
  fi
}

ensure_transient_ignore() {
  local planning_dir="${VBW_PLANNING_DIR:-.vbw-planning}"
  local ignore_file="$planning_dir/.gitignore"

  [ -d "$planning_dir" ] || return 0

  cat > "$ignore_file" <<'EOF'
# VBW transient runtime artifacts
.execution-state.json
.execution-state.json.tmp
.context-*.md
.context-usage
.contracts/
.locks/
.token-state/

# Session & agent tracking
.vbw-context
.vbw-session
.active-agent
.active-agents/
.active-agent-count
.active-agent-roles
.active-agent-role-pids
.active-agent-count.lock/
.agent-pids
.task-verify-seen

# Metrics & cost tracking
.metrics/
.cost-ledger.json

# Caching
.cache/

# Artifacts & events (v2/v3 feature-gated)
.artifacts/
.events/
.event-log.jsonl

# Snapshots & recovery
.snapshots/

# Logging & markers
.hook-errors.log
.hook-debug.log
.skill-decisions.log
.compaction-marker
.session-log.jsonl
.session-log.jsonl.tmp
.notification-log.jsonl
.watchdog-pid
.watchdog.log
.claude-md-migrated
.tmux-mode-patched
.delegated-workflow.json

# Baselines
.baselines/

# Codebase mapping
codebase/
EOF
}

sync_root_ignore() {
  local mode="$1"
  local root_ignore=".gitignore"

  if [ "$mode" = "ignore" ]; then
    if [ ! -f "$root_ignore" ]; then
      printf '.vbw-planning/\n' > "$root_ignore"
      return 0
    fi

    if ! grep -qx '\.vbw-planning/' "$root_ignore"; then
      printf '\n.vbw-planning/\n' >> "$root_ignore"
    fi
    return 0
  fi

  if [ "$mode" = "commit" ] && [ -f "$root_ignore" ]; then
    local tmp
    tmp=$(mktemp)
    awk '$0 != ".vbw-planning/"' "$root_ignore" > "$tmp"
    mv "$tmp" "$root_ignore"
  fi
}

push_if_configured() {
  local push_mode="$1"
  [ "$push_mode" = "always" ] || return 0

  # Skip if current branch has no upstream yet.
  if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    return 0
  fi

  git push
}

if [ -z "$COMMAND" ]; then
  echo "Usage: planning-git.sh sync-ignore [CONFIG_FILE] | commit-boundary <action> [CONFIG_FILE] | push-after-phase [CONFIG_FILE]" >&2
  exit 1
fi

# --- Submodule-safe rooting (#640) ------------------------------------------
# Planning artifacts live in the workspace that OWNS .vbw-planning, which can be
# an ancestor of the caller's CWD — e.g. when a /vbw:* command runs from inside a
# git submodule, the parent workspace (and its repo) sits ABOVE the submodule.
# Every git operation below (add/commit/push, .gitignore writes) must target that
# workspace repo, not the submodule the caller happens to sit in. Resolve the
# planning dir, then cd to the workspace root and pin VBW_PLANNING_DIR to its
# absolute path so all consumers reference the correct repo and work tree.
# Passing $PLANNING_ROOT from commands alone is NOT enough while this script
# stays rooted at the caller's CWD — the rooting must happen here.
_pg_script_dir="$(cd "$(dirname "$0")" && pwd)"
_pg_pdir="${VBW_PLANNING_DIR:-}"
if [ -z "$_pg_pdir" ]; then
  _pg_pdir="$(bash "$_pg_script_dir/resolve-planning-root.sh" 2>/dev/null || echo ".vbw-planning")"
fi
case "$_pg_pdir" in
  /*) : ;;
  *)  _pg_pdir="$PWD/$_pg_pdir" ;;
esac
if [ -d "$_pg_pdir" ]; then
  _pg_abs="$(cd "$_pg_pdir" 2>/dev/null && pwd)" || _pg_abs="$_pg_pdir"
  cd "$(dirname "$_pg_abs")" 2>/dev/null || true
  VBW_PLANNING_DIR="$_pg_abs"
  export VBW_PLANNING_DIR
  unset _pg_abs
fi
unset _pg_script_dir _pg_pdir
# ----------------------------------------------------------------------------

case "$COMMAND" in
  sync-ignore)
    CONFIG_FILE="${ARG2:-${VBW_PLANNING_DIR:-.vbw-planning}/config.json}"

    if ! is_git_repo; then
      exit 0
    fi

    read_config "$CONFIG_FILE"
    sync_root_ignore "$CFG_PLANNING_TRACKING"
    ensure_transient_ignore
    ;;

  commit-boundary)
    ACTION="${ARG2:-}"
    CONFIG_FILE="${ARG3:-${VBW_PLANNING_DIR:-.vbw-planning}/config.json}"

    if [ -z "$ACTION" ]; then
      echo "Usage: planning-git.sh commit-boundary <action> [CONFIG_FILE]" >&2
      exit 1
    fi

    if ! is_git_repo; then
      exit 0
    fi

    read_config "$CONFIG_FILE"

    if [ "$CFG_PLANNING_TRACKING" != "commit" ]; then
      exit 0
    fi

    ensure_transient_ignore

    _pg_planning_dir="${VBW_PLANNING_DIR:-.vbw-planning}"
    if [ -d "$_pg_planning_dir" ]; then
      git add "$_pg_planning_dir"
    fi

    if [ -f "CLAUDE.md" ]; then
      git add CLAUDE.md
    fi

    if git diff --cached --quiet; then
      exit 0
    fi

    git commit -m "chore(vbw): $ACTION"
    push_if_configured "$CFG_AUTO_PUSH"
    ;;

  push-after-phase)
    CONFIG_FILE="${ARG2:-${VBW_PLANNING_DIR:-.vbw-planning}/config.json}"

    if ! is_git_repo; then
      exit 0
    fi

    read_config "$CONFIG_FILE"

    if [ "$CFG_AUTO_PUSH" = "after_phase" ]; then
      # Skip if current branch has no upstream yet.
      if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        git push
      fi
    fi
    ;;

  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Usage: planning-git.sh sync-ignore [CONFIG_FILE] | commit-boundary <action> [CONFIG_FILE] | push-after-phase [CONFIG_FILE]" >&2
    exit 1
    ;;
esac

exit 0
