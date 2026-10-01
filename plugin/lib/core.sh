#!/usr/bin/env bash
# Shared helpers for the vbw kernel. Sourced by bin/vbw; never executed alone.
# Exit codes: 0 ok, 1 error, 2 usage, 3 corrupt record.

vbw_die() {
  printf 'vbw: %s\n' "$1" >&2
  exit "${2:-1}"
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
# committed or not, ignored files and .vbw/ excluded): a content fingerprint
# that no commit changes. Built in a temporary index seeded from the real one,
# so only changed files are rehashed; the user's index and files are untouched.
vbw_code_tree() {
  local idx real
  idx=$(mktemp "$VBW_RUNTIME/index.XXXXXX") || return 1
  real=$(git -C "$VBW_ROOT" rev-parse --path-format=absolute --git-path index)
  if [ -f "$real" ]; then cp "$real" "$idx"; else rm -f "$idx"; fi
  (
    cd "$VBW_ROOT" || exit 1
    export GIT_INDEX_FILE="$idx"
    git add -A -- . ':(exclude).vbw' > /dev/null 2>&1 &&
      git rm -r -q --cached --ignore-unmatch -- .vbw > /dev/null 2>&1 &&
      git write-tree
  )
  local status=$?
  rm -f "$idx"
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
