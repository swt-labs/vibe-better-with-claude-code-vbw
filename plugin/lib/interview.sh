#!/usr/bin/env bash
# The interview's answers (level, depth, involvement; docs/interview.md). Kept
# private in $(git-common-dir)/vbw/profile.json (shared by the clone's
# worktrees, never in the project) or shared in record.project.interview. The
# private file is a locked read-modify-write; the shared copy goes through
# record_update. Allowed values: lib/interview.json.

interview_private_file() {
  local common
  common=$(git -C "$VBW_ROOT" rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || vbw_die "not a git repository"
  printf '%s/vbw/profile.json\n' "$common"
}

# interview_private_update FILTER [jq options]: atomic, locked change of the
# private answers file (created as {} when missing).
interview_private_update() {
  local filter="$1" file tmp lock
  shift
  file=$(interview_private_file)
  mkdir -p "${file%/*}"
  lock="${file%/*}/profile.lock"
  vbw_lock_take "$lock" "the interview answers"
  [ -f "$file" ] || printf '{}\n' > "$file"
  tmp=$(mktemp "${file%/*}/profile.XXXXXX") || vbw_die "cannot write ${file%/*}"
  vbw_guard_add file "$tmp"
  jq "$@" "$filter" "$file" > "$tmp" 2> /dev/null || vbw_die "the interview answers file is damaged ($file); delete it and answer again"
  mv "$tmp" "$file"
  vbw_guard_drop "$tmp"
  vbw_guard_drop "$lock"
}

# interview_effective [RECORD]: {kept, interviewed, level, depth, involvement,
# pending} on stdout (RECORD: the record's JSON when the caller has it).
# Private answers marked kept win over the project's; private answers not yet
# kept (an interview in progress) are shown with kept null and, once all three
# are given, pending "keep" (the interview's last question: where to keep them).
interview_effective() {
  local priv rec="${1:-$(record_read)}"
  priv=$(jq -c 'if type == "object" then . else {} end' "$(interview_private_file)" 2> /dev/null) || priv='{}'
  printf '%s' "$rec" | jq -c --argjson p "$priv" '
    ["level","depth","involvement"] as $k
    | def pick($o): $o | with_entries(select(.key as $x | $k | any(. == $x)) | select(.value | type == "string"));
    (pick($p)) as $pp | (pick(.project.interview // {})) as $sp
    | (if ($pp | length) == 3 and $p.done == true then {kept: "private", a: $pp} elif ($pp | length) > 0 then {kept: null, a: $pp}
       elif ($sp | length) == 3 then {kept: "project", a: $sp} else {kept: null, a: {}} end) as $e
    | {kept: $e.kept, interviewed: ($e.kept != null)} + ($k | map({key: ., value: ($e.a[.] // null)}) | from_entries)
      + {pending: (($k | map(select($e.a[.] == null)) | .[0]) // (if $e.kept == null then "keep" else null end))}'
}
