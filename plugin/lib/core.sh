#!/usr/bin/env bash
# Shared helpers for the vbw kernel. Sourced by bin/vbw; never executed alone.
# Exit codes: 0 ok, 1 error, 2 usage, 3 corrupt record, 4 record written by a newer VBW.

vbw_die() {
  printf 'vbw: %s\n' "$1" >&2
  vbw_guard_run
  exit "${2:-1}"
}

# Interrupt-safe cleanup. Temporary files and held lock directories are
# registered here; INT, TERM and HUP remove them and exit (so the caller's own
# EXIT trap still runs), and so does vbw_die. An EXIT trap is installed only
# when the process has none (the vbw entry point), so a caller's EXIT trap is
# never replaced or cleared, and no trap text is ever evaluated.
VBW_GUARD_FILES=()
VBW_GUARD_LOCKS=()
VBW_GUARD_DIRS=()
VBW_GUARD_EXIT=0

# vbw_guard_add KIND PATH: remove PATH on interrupt, die or vbw_guard_drop.
# KIND is file, lock (a lock directory, rmdir) or dir (a directory tree, rm -rf;
# rm never follows a symlink inside it).
vbw_guard_add() {
  local kind="$1" path="$2"
  case "$kind" in
    lock) VBW_GUARD_LOCKS+=("$path") ;;
    dir) VBW_GUARD_DIRS+=("$path") ;;
    *) VBW_GUARD_FILES+=("$path") ;;
  esac
  trap 'vbw_guard_run; exit 130' INT
  trap 'vbw_guard_run; exit 143' TERM
  trap 'vbw_guard_run; exit 129' HUP
  if [ "$VBW_GUARD_EXIT" -eq 0 ] && [ -z "$(trap -p EXIT)" ]; then
    trap vbw_guard_run EXIT
    VBW_GUARD_EXIT=1
  fi
}

# Forget everything registered (a subshell calls this: it owns none of it).
vbw_guard_reset() {
  VBW_GUARD_FILES=()
  VBW_GUARD_LOCKS=()
  VBW_GUARD_DIRS=()
  VBW_GUARD_EXIT=0
}

# Remove everything registered (files with rm, locks with rmdir).
vbw_guard_run() {
  local p
  for p in ${VBW_GUARD_FILES[@]+"${VBW_GUARD_FILES[@]}"}; do rm -f "$p" 2>/dev/null || true; done
  for p in ${VBW_GUARD_LOCKS[@]+"${VBW_GUARD_LOCKS[@]}"}; do rmdir "$p" 2>/dev/null || true; done
  for p in ${VBW_GUARD_DIRS[@]+"${VBW_GUARD_DIRS[@]}"}; do chmod -R u+rwx "$p" 2>/dev/null || true; rm -rf "$p" 2>/dev/null || true; done
  VBW_GUARD_FILES=()
  VBW_GUARD_LOCKS=()
  VBW_GUARD_DIRS=()
}

# vbw_guard_drop PATH: clean up one registered path now (file or lock dir);
# when nothing is left, the traps are removed again.
vbw_guard_drop() {
  local p keep=()
  for p in ${VBW_GUARD_DIRS[@]+"${VBW_GUARD_DIRS[@]}"}; do [ "$p" != "$1" ] || { chmod -R u+rwx "$1" 2>/dev/null; rm -rf "$1" 2>/dev/null; } || true; done
  rm -f "$1" 2>/dev/null || true
  rmdir "$1" 2>/dev/null || true
  for p in ${VBW_GUARD_FILES[@]+"${VBW_GUARD_FILES[@]}"}; do [ "$p" = "$1" ] || keep+=("$p"); done
  VBW_GUARD_FILES=(${keep[@]+"${keep[@]}"})
  keep=()
  for p in ${VBW_GUARD_LOCKS[@]+"${VBW_GUARD_LOCKS[@]}"}; do [ "$p" = "$1" ] || keep+=("$p"); done
  VBW_GUARD_LOCKS=(${keep[@]+"${keep[@]}"})
  keep=()
  for p in ${VBW_GUARD_DIRS[@]+"${VBW_GUARD_DIRS[@]}"}; do [ "$p" = "$1" ] || keep+=("$p"); done
  VBW_GUARD_DIRS=(${keep[@]+"${keep[@]}"})
  [ $(( ${#VBW_GUARD_FILES[@]} + ${#VBW_GUARD_LOCKS[@]} + ${#VBW_GUARD_DIRS[@]} )) -eq 0 ] || return 0
  trap - INT TERM HUP
  if [ "$VBW_GUARD_EXIT" -eq 1 ]; then trap - EXIT; VBW_GUARD_EXIT=0; fi
}

vbw_usage_error() {
  printf 'vbw: %s\n' "$1" >&2
  printf 'usage: vbw <command> [args]   (vbw help for the list)\n' >&2
  exit 2
}

# The calling Claude Code session: VBW_SESSION_ID (skills pass ${CLAUDE_SESSION_ID}),
# else CLAUDE_CODE_SESSION_ID, else empty (unknown).
vbw_session() {
  printf '%s' "${VBW_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
}

vbw_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# vbw_step_add LEASE_JSON: one finished step (kind, run, start, end, seconds)
# in the clone's cache $(git-common-dir)/vbw/steps.json, the latest 50. Best
# effort: a missing, damaged or unwritable cache never fails the caller.
vbw_step_add() {
  local common file now tmp
  common=$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || return 0
  file="$common/vbw/steps.json"
  now=$(vbw_now)
  tmp="$file.$$"
  mkdir -p "$common/vbw" 2> /dev/null || return 0
  { jq -c --arg now "$now" --slurpfile old <(jq -c 'select(type == "object" and (.steps | type) == "array")' "$file" 2> /dev/null) '
      {steps: ((($old[0].steps // []) + [{kind, run, started_at, ended_at: $now,
        seconds: (($now | fromdateiso8601) - (.started_at | fromdateiso8601))}]) | .[-50:])}' <<< "$1" > "$tmp" \
    && mv -f "$tmp" "$file"; } 2> /dev/null || rm -f "$tmp" 2> /dev/null || true
  return 0
}

# This clone's own settings: $(git-common-dir)/vbw/settings.json (shared by the
# clone's worktrees, never in the shared record). Today: check_jobs, how many
# checks run at the same time (1 to 64, default 4; 1 is sequential).
vbw_clone_settings_file() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || vbw_die "not a git repository"
  printf '%s/vbw/settings.json\n' "$common"
}

# vbw_check_jobs: the one reader of check_jobs; a missing or damaged file or
# an out-of-range value gives the default.
vbw_check_jobs() {
  local file n
  file=$(vbw_clone_settings_file) || return 1
  n=$(jq -r '.check_jobs // empty' "$file" 2> /dev/null) || n=""
  case "$n" in
    [1-9] | [1-5][0-9] | 6[0-4]) printf '%s\n' "$n" ;;
    *) printf '4\n' ;;
  esac
}

# vbw_check_jobs_set N|default: atomic, locked change of check_jobs.
vbw_check_jobs_set() {
  local file tmp lock
  file=$(vbw_clone_settings_file)
  mkdir -p "${file%/*}"
  lock="${file%/*}/settings.lock"
  vbw_lock_take "$lock" "this clone's settings"
  [ -f "$file" ] || printf '{}\n' > "$file"
  tmp=$(mktemp "${file%/*}/settings.XXXXXX") || vbw_die "cannot write ${file%/*}"
  vbw_guard_add file "$tmp"
  if [ "$1" = default ]; then
    jq 'del(.check_jobs)' "$file" > "$tmp" 2> /dev/null
  else
    jq --argjson n "$1" '.check_jobs = $n' "$file" > "$tmp" 2> /dev/null
  fi || vbw_die "this clone's settings file is damaged ($file); delete it and set again"
  mv "$tmp" "$file"
  vbw_guard_drop "$tmp"
  vbw_guard_drop "$lock"
}

# Absolute path of the enclosing git repository, or die.
vbw_git_root() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || vbw_die "not a git repository (VBW needs git: it commits with provenance)"
  printf '%s\n' "$root"
}

# Sets VBW_ROOT, VBW_DIR, VBW_RECORD and VBW_RUNTIME for the current project.
vbw_project() {
  VBW_ROOT=$(vbw_git_root)
  VBW_DIR="$VBW_ROOT/.vbw"
  VBW_RECORD="$VBW_DIR/record.json"
  VBW_RUNTIME="$VBW_DIR/runtime"
}

vbw_require_project() {
  vbw_project
  [ -f "$VBW_RECORD" ] || vbw_die "not a VBW project (run /vbw:init)"
  mkdir -p "$VBW_RUNTIME"
}

# SHA-256 hex digest of stdin (GNU coreutils or BSD/macOS shasum).
vbw_sha256() {
  local out
  if command -v sha256sum > /dev/null 2>&1; then
    out=$(sha256sum)
  else
    out=$(shasum -a 256)
  fi
  printf '%s\n' "${out%% *}"
}

# The git tree id of the project's files as they are now (tracked and new,
# committed or not; ignored files, .vbw/ and a kept VBW 1 .vbw-planning/
# excluded): a content fingerprint that no commit changes. Built in a temporary
# index seeded from the real one, so only changed files are rehashed; the
# user's index and files are untouched.
# vbw_head_tree: the tree of the committed code (HEAD, without .vbw and
# .vbw-planning), which is what vbw prove runs on: the fingerprint of what a
# proof proved. Prints nothing when there is no commit yet.
vbw_head_tree() {
  local idx status
  git -C "$VBW_ROOT" rev-parse -q --verify HEAD > /dev/null 2>&1 || return 0
  idx=$(mktemp "$VBW_RUNTIME/index.XXXXXX") || return 1
  vbw_guard_add file "$idx"
  (
    cd "$VBW_ROOT" || exit 1
    export GIT_INDEX_FILE="$idx"
    git read-tree HEAD &&
      git rm -r -q --cached --ignore-unmatch -- .vbw .vbw-planning > /dev/null 2>&1 &&
      git write-tree
  )
  status=$?
  vbw_guard_drop "$idx"
  return $status
}

vbw_code_tree() {
  local idx real
  idx=$(mktemp "$VBW_RUNTIME/index.XXXXXX") || return 1
  vbw_guard_add file "$idx"
  real=$(git -C "$VBW_ROOT" rev-parse --path-format=absolute --git-path index)
  if [ -f "$real" ]; then cp "$real" "$idx"; else rm -f "$idx"; fi
  (
    cd "$VBW_ROOT" || exit 1
    export GIT_INDEX_FILE="$idx"
    git add -A -- . ':(exclude).vbw' ':(exclude).vbw-planning' > /dev/null 2>&1 &&
      git rm -r -q --cached --ignore-unmatch -- .vbw .vbw-planning > /dev/null 2>&1 &&
      git write-tree
  )
  local status=$?
  vbw_guard_drop "$idx"
  return $status
}

# Modification time in epoch seconds. GNU stat first: on Linux, BSD's `stat -f`
# means "file system status" and succeeds with other output, while macOS rejects
# GNU's `-c`. Only a number is ever returned (0 when it cannot be read).
vbw_mtime() {
  local t
  t=$(stat -c %Y "$1" 2>/dev/null) || t=$(stat -f %m "$1" 2>/dev/null) || t=0
  case "$t" in "" | *[!0-9]*) t=0 ;; esac
  printf '%s\n' "$t"
}

# vbw_dirty_files FILE...: those of the project-relative FILEs that differ from
# HEAD or are new, comma-separated.
vbw_dirty_files() {
  [ $# -gt 0 ] || return 0
  local f out=""
  while IFS= read -r -d '' f; do out="$out${out:+, }$f"; done \
    < <(cd "$VBW_ROOT" && { git diff --name-only -z HEAD -- "$@"; git ls-files -z --others --exclude-standard -- "$@"; })
  printf '%s' "$out"
}
