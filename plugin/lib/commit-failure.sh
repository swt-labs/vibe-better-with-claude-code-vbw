#!/usr/bin/env bash
# A record commit that failed is a step of its own (R287, docs/next.md): record_commit keeps
# the failure in .vbw/runtime/commit-failed.json ({at, reason, files, message}) and the full
# text in .vbw/runtime/output/commit-failed.log; while it stands vbw next's step is it and
# vbw approve refuses. VBW never bypasses the project's hooks and never offers to: the user fixes what the hook flagged, allows it in the checker, or commits the files.

COMMIT_FAILED_LOG_REL=.vbw/runtime/output/commit-failed.log

commit_failure_file() { printf '%s/commit-failed.json' "$VBW_RUNTIME"; }

# commit_failure_head: the commit HEAD is on now, empty before the first commit.
commit_failure_head() { git -C "$VBW_ROOT" rev-parse --verify -q HEAD 2> /dev/null || true; }

# commit_failure_keep MESSAGE REASON FILE...: write the failure (REASON is git's and the hook's own text)
# with the commit it was made on (R298).
commit_failure_keep() {
  local msg="$1" reason="$2" out tmp
  shift 2
  out="$VBW_RUNTIME/output"
  tmp="$(commit_failure_file).$$"
  mkdir -p "$out" 2> /dev/null || return 0
  printf '%s\n' "$reason" > "$out/commit-failed.log" 2> /dev/null || return 0
  if printf '%s\0' "$@" | jq -Rs --arg at "$(vbw_now)" --arg msg "$msg" --arg head "$(commit_failure_head)" --rawfile reason "$out/commit-failed.log" \
    '{at: $at, reason: ($reason | sub("\n+$"; "")), files: (split("\u0000")[:-1]), message: $msg, head: $head}' > "$tmp" 2> /dev/null; then
    mv "$tmp" "$(commit_failure_file)"
  else
    rm -f "$tmp"
  fi
  return 0
}

# commit_failure_dirty: the files the kept failure names that still differ from HEAD (empty when none).
commit_failure_dirty() {
  local x files=()
  while IFS= read -r -d '' x; do files+=("$x"); done < <(jq -j '(.files // [])[] + "\u0000"' "$(commit_failure_file)" 2> /dev/null)
  (cd "$VBW_ROOT" && vbw_dirty_files ${files[@]+"${files[@]}"} 2> /dev/null) || true
}

# commit_failure_stands: 0 while the kept failure stands, changing nothing: a file it names
# differs from HEAD, or HEAD has not moved since it was made (a rolled-back approval leaves no
# file that differs, R298). It is over once a commit moved HEAD with its files clean.
commit_failure_stands() {
  [ -f "$(commit_failure_file)" ] || return 1
  [ -z "$(commit_failure_dirty)" ] || return 0
  [ "$(jq -r '.head // ""' "$(commit_failure_file)" 2> /dev/null)" = "$(commit_failure_head)" ]
}

# commit_failure_standing: commit_failure_stands, and an over failure is cleared.
commit_failure_standing() {
  commit_failure_stands && return 0
  commit_failure_clear
  return 1
}

# commit_failure_clear: a VBW commit that succeeded ends the failure (R298).
commit_failure_clear() { rm -f "$(commit_failure_file)" "$VBW_ROOT/$COMMIT_FAILED_LOG_REL"; }

# commit_failure_say: the failure in words for the user (the step's instruction and vbw approve's
# refusal): the hook's own message, at most 20 lines, then where the full text is kept.
commit_failure_say() {
  local f total
  f=$(commit_failure_file)
  total=$(jq -r '.reason | split("\n") | length' "$f")
  printf "VBW's files could not be committed (%s): the project's commit check refused them:\n" "$(jq -r '.files | join(", ")' "$f")"
  jq -r '.reason | split("\n")[:20][]' "$f"
  if [ "$total" -gt 20 ]; then
    printf '(%s more lines; the full text is kept in %s)\n' "$((total - 20))" "$COMMIT_FAILED_LOG_REL"
  fi
  if [ -z "$(commit_failure_dirty)" ]; then
    printf "Nothing is left to commit: fix what the hook flagged (or allow it in the checker's settings), then approve again (vbw approve); VBW tries the commit again."
  else
    printf "Three ways on: fix what the hook flagged; allow it in the checker's settings; or commit the VBW files yourself (git add .vbw, then git commit). Then run vbw next again."
  fi
}

# commit_failure_json: the standing failure for next.jq, {at, files, say}, or null.
commit_failure_json() {
  if commit_failure_standing; then
    jq -c --arg say "$(commit_failure_say)" '{at, files, say: $say}' "$(commit_failure_file)"
  else
    printf null
  fi
}

# commit_failure_retry: one more try of the same commit through the project's hooks (the user
# may have fixed what the hook flagged); record_commit clears the failure when it passes and
# keeps the new one when it does not.
commit_failure_retry() {
  local f msg files=() x
  commit_failure_standing || return 0
  [ -n "$(commit_failure_dirty)" ] || return 0
  f=$(commit_failure_file)
  msg=$(jq -r '.message' "$f")
  while IFS= read -r -d '' x; do files+=("$x"); done < <(jq -j '.files[] + "\u0000"' "$f")
  record_commit --strict "$msg" ${files[@]+"${files[@]}"} 2> /dev/null || true
}
