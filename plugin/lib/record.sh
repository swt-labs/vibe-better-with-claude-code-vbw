#!/usr/bin/env bash
# The single writer of .vbw/record.json. Every mutation goes through
# record_update: lock, apply one jq program, validate, rename into place.

VBW_LOCK_STALE_SECONDS=30

# Print the first violation of FILE (empty output = valid). Status 1 if invalid.
record_violation() {
  local out
  if ! out=$(jq -c -f "$VBW_LIB/record.jq" "$1" 2>/dev/null); then
    printf 'unparseable JSON\n'
    return 1
  fi
  [ "$out" = "[]" ] && return 0
  printf '%s\n' "$out" | jq -r '.[0]'
  return 1
}

# The validated record on stdout; exit 3 if it is corrupt.
record_read() {
  local v
  v=$(record_violation "$VBW_RECORD") || vbw_die "record is corrupt: $v ($VBW_RECORD)" 3
  cat "$VBW_RECORD"
}

record_unlock() {
  rmdir "$VBW_RUNTIME/lock" 2>/dev/null || true
}

vbw_is_stale() {
  [ -d "$1" ] && [ $(( $(date +%s) - $(vbw_mtime "$1") )) -gt "$VBW_LOCK_STALE_SECONDS" ]
}

# Take the project lock. A lock older than VBW_LOCK_STALE_SECONDS belongs to a
# crashed writer (writes take milliseconds) and is broken, but only while
# holding the "break" mutex and after re-checking that it is still stale, so two
# processes can never both break it and one delete the other's fresh lock.
# No process probing and no signals.
record_lock() {
  local lock="$VBW_RUNTIME/lock" brk="$VBW_RUNTIME/lock.break" deadline
  # A held lock is released or becomes breakable within the stale window, so
  # waiting twice that long is always enough, even under heavy load.
  deadline=$(( $(date +%s) + 2 * VBW_LOCK_STALE_SECONDS ))
  mkdir -p "$VBW_RUNTIME"
  until mkdir "$lock" 2>/dev/null; do
    if vbw_is_stale "$lock"; then
      vbw_is_stale "$brk" && rmdir "$brk" 2>/dev/null || true
      if mkdir "$brk" 2>/dev/null; then
        vbw_is_stale "$lock" && rmdir "$lock" 2>/dev/null || true
        rmdir "$brk" 2>/dev/null || true
        continue
      fi
    fi
    [ "$(date +%s)" -le "$deadline" ] || vbw_die "record is locked by another vbw process ($lock)"
    sleep 0.05
  done
}

# record_update FILTER [jq options...]: apply FILTER to the record atomically.
# The new record must validate, or nothing changes and the violation is shown.
record_update() {
  local filter="$1" tmp v
  shift
  record_lock
  trap record_unlock EXIT
  v=$(record_violation "$VBW_RECORD") || vbw_die "record is corrupt: $v ($VBW_RECORD)" 3
  tmp=$(mktemp "$VBW_RUNTIME/record.XXXXXX") || vbw_die "cannot create a temporary file in $VBW_RUNTIME"
  if ! jq "$@" "$filter" "$VBW_RECORD" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    vbw_die "internal error: record update failed"
  fi
  if ! v=$(record_violation "$tmp"); then
    rm -f "$tmp"
    vbw_die "refused: $v"
  fi
  mv "$tmp" "$VBW_RECORD"
  record_unlock
  trap - EXIT
}

# record_commit MESSAGE: commit VBW's own files that changed (.vbw/spec.md,
# .vbw/record.json, the protected check files, and a .gitignore only if VBW
# created it) with `git commit --only`, so the user's staged work stays staged.
# Called when a run ends, at approval and at ship. Nothing changed: no commit.
# A failing commit (no git identity, a hook) warns and never undoes the step.
record_commit() {
  local msg="$1" own=() changed=() untracked=() f
  (
    cd "$VBW_ROOT" || exit 1
    for f in .vbw/spec.md .vbw/record.json; do [ -f "$f" ] && own+=("$f"); done
    while IFS= read -r -d '' f; do [ -f "$f" ] && own+=("$f"); done \
      < <(jq -j '[.checks[].files // [] | .[]] | unique[] | . + "\u0000"' "$VBW_RECORD")
    if [ -f .gitignore ] && ! git ls-files -z --error-unmatch .gitignore > /dev/null 2>&1; then own+=(.gitignore); fi
    [ ${#own[@]} -gt 0 ] || exit 0
    while IFS= read -r -d '' f; do changed+=("$f"); done < <(git diff --name-only -z HEAD -- "${own[@]}" 2> /dev/null)
    while IFS= read -r -d '' f; do untracked+=("$f"); changed+=("$f"); done \
      < <(git ls-files -z --others --exclude-standard -- "${own[@]}")
    [ ${#changed[@]} -gt 0 ] || exit 0
    record_lock
    trap record_unlock EXIT
    { [ ${#untracked[@]} -eq 0 ] || git add -- "${untracked[@]}"; } &&
      git commit --quiet --only -m "$msg" -- "${changed[@]}" > /dev/null 2>&1 \
      || printf 'vbw: warning: could not commit VBW files (%s); commit them yourself\n' "$msg" >&2
  )
}

# jq helper, prepended to update filters: the next free id with prefix P.
# shellcheck disable=SC2016,SC2034 # jq text, not shell; used by the cmd-*.sh files
VBW_JQ_DEFS='def next_id($p): (([.[]?.id | ltrimstr($p) | tonumber?] | max) // 0) + 1 | "\($p)\(.)";'
