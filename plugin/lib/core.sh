#!/usr/bin/env bash
# Shared helpers for the vbw kernel. Sourced by bin/vbw; never executed alone.
# Exit codes: 0 ok, 1 error, 2 usage, 3 corrupt record.

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
VBW_GUARD_EXIT=0

# vbw_guard_add FILE|LOCKDIR...: remove these on interrupt, die or vbw_guard_drop.
# Kind is the first argument: file or lock.
vbw_guard_add() {
  local kind="$1" path="$2"
  if [ "$kind" = lock ]; then VBW_GUARD_LOCKS+=("$path"); else VBW_GUARD_FILES+=("$path"); fi
  trap 'vbw_guard_run; exit 130' INT
  trap 'vbw_guard_run; exit 143' TERM
  trap 'vbw_guard_run; exit 129' HUP
  if [ "$VBW_GUARD_EXIT" -eq 0 ] && [ -z "$(trap -p EXIT)" ]; then
    trap vbw_guard_run EXIT
    VBW_GUARD_EXIT=1
  fi
}

# Remove everything registered (files with rm, locks with rmdir).
vbw_guard_run() {
  local p
  for p in ${VBW_GUARD_FILES[@]+"${VBW_GUARD_FILES[@]}"}; do rm -f "$p" 2>/dev/null || true; done
  for p in ${VBW_GUARD_LOCKS[@]+"${VBW_GUARD_LOCKS[@]}"}; do rmdir "$p" 2>/dev/null || true; done
  VBW_GUARD_FILES=()
  VBW_GUARD_LOCKS=()
}

# vbw_guard_drop PATH: clean up one registered path now (file or lock dir);
# when nothing is left, the traps are removed again.
vbw_guard_drop() {
  local p keep=()
  rm -f "$1" 2>/dev/null || true
  rmdir "$1" 2>/dev/null || true
  for p in ${VBW_GUARD_FILES[@]+"${VBW_GUARD_FILES[@]}"}; do [ "$p" = "$1" ] || keep+=("$p"); done
  VBW_GUARD_FILES=(${keep[@]+"${keep[@]}"})
  keep=()
  for p in ${VBW_GUARD_LOCKS[@]+"${VBW_GUARD_LOCKS[@]}"}; do [ "$p" = "$1" ] || keep+=("$p"); done
  VBW_GUARD_LOCKS=(${keep[@]+"${keep[@]}"})
  [ $(( ${#VBW_GUARD_FILES[@]} + ${#VBW_GUARD_LOCKS[@]} )) -eq 0 ] || return 0
  trap - INT TERM HUP
  if [ "$VBW_GUARD_EXIT" -eq 1 ]; then trap - EXIT; VBW_GUARD_EXIT=0; fi
}

vbw_usage_error() {
  printf 'vbw: %s\n' "$1" >&2
  printf 'usage: vbw <command> [args]   (vbw help for the list)\n' >&2
  exit 2
}

vbw_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
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
