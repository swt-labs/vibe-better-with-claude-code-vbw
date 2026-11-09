#!/usr/bin/env bash
# A record commit that failed is a step of its own (R287, docs/next.md): record_commit keeps
# the failure in .vbw/runtime/commit-failed.json ({at, reason, files, message}) and the full
# text in .vbw/runtime/output/commit-failed.log; while it stands vbw next's step is it and
# vbw approve refuses. VBW never bypasses the project's hooks and never offers to: the user fixes what the hook flagged, allows it in the checker, or commits the files.

COMMIT_FAILED_LOG_REL=.vbw/runtime/output/commit-failed.log

commit_failure_file() { printf '%s/commit-failed.json' "$VBW_RUNTIME"; }

# commit_failure_keep MESSAGE REASON FILE...: write the failure (REASON is git's and the hook's own text).
commit_failure_keep() {
  local msg="$1" reason="$2" out tmp
  shift 2
  out="$VBW_RUNTIME/output"
  tmp="$(commit_failure_file).$$"
  mkdir -p "$out" 2> /dev/null || return 0
  printf '%s\n' "$reason" > "$out/commit-failed.log" 2> /dev/null || return 0
  if printf '%s\0' "$@" | jq -Rs --arg at "$(vbw_now)" --arg msg "$msg" --rawfile reason "$out/commit-failed.log" \
    '{at: $at, reason: ($reason | sub("\n+$"; "")), files: (split("\u0000")[:-1]), message: $msg}' > "$tmp" 2> /dev/null; then
    mv "$tmp" "$(commit_failure_file)"
  else
    rm -f "$tmp"
  fi
  return 0
}

# commit_failure_standing: 0 while the kept failure stands (a file it names still differs from
# HEAD); once the files are committed (by the user, say) the failure is cleared and this is 1.
commit_failure_standing() {
  local f x files=() dirty
  f=$(commit_failure_file)
  [ -f "$f" ] || return 1
  while IFS= read -r -d '' x; do files+=("$x"); done < <(jq -j '(.files // [])[] + "\u0000"' "$f" 2> /dev/null)
  dirty=$(cd "$VBW_ROOT" && vbw_dirty_files ${files[@]+"${files[@]}"} 2> /dev/null) || dirty=
  if [ -z "$dirty" ]; then
    rm -f "$f" "$VBW_ROOT/$COMMIT_FAILED_LOG_REL"
    return 1
  fi
}

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
  printf "Three ways on: fix what the hook flagged; allow it in the checker's settings; or commit the VBW files yourself (git add .vbw, then git commit). Then run vbw next again."
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
  f=$(commit_failure_file)
  msg=$(jq -r '.message' "$f")
  while IFS= read -r -d '' x; do files+=("$x"); done < <(jq -j '.files[] + "\u0000"' "$f")
  record_commit --strict "$msg" ${files[@]+"${files[@]}"} 2> /dev/null || true
}
