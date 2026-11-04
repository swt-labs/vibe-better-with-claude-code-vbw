#!/usr/bin/env bash
# vbw spec check|sync|add: the user's spec.md is the source of the requirements
# (docs/proof.md). The kernel never rewrites it; `add` only inserts one line.

cmd_spec() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    check) [ $# -eq 0 ] || vbw_usage_error "usage: vbw spec check" ;;
    sync) [ $# -eq 0 ] || vbw_usage_error "usage: vbw spec sync" ;;
    add)
      [ $# -eq 2 ] && { [ "$1" = auto ] || [ "$1" = human ]; } \
        || vbw_usage_error "usage: vbw spec add auto|human TEXT"
      ;;
    *) vbw_usage_error "usage: vbw spec check | sync | add auto|human TEXT" ;;
  esac
  vbw_require_project
  local parsed
  parsed=$(spec_parse)
  case "$sub" in
    sync|check) spec_verify_leave_out "$parsed" ;;
  esac
  case "$sub" in
    check)
      printf '%s' "$parsed" | jq -r '(.requirements
        | "spec.md: \(length) requirements (\(map(select(.proof == "auto")) | length) auto, \(map(select(.proof == "human")) | length) human)")
        + (if .commands == null then "" else ", \(.commands | length) command\(if (.commands | length) == 1 then "" else "s" end)" end)
        + (if .leave_out == null then "" else ", \(.leave_out | length) path\(if (.leave_out | length) == 1 then "" else "s" end) left out of the clean copy" end)'
      spec_gone_notes "$parsed"
      ;;
    sync) spec_sync "$parsed" ;;
    add) spec_add "$parsed" "$1" "$2" ;;
  esac
}

# vbw_scratch VAR VALUE: write VALUE to a file in .vbw/runtime and set VAR to its
# path, for a jq call inside record_update (--slurpfile NAME "$VAR"): bash 3.2
# closes a <(...) descriptor before record_update's jq reads it. Removed by
# vbw_guard_drop, or by the interrupt cleanup.
vbw_scratch() {
  local f
  f=$(mktemp "$VBW_RUNTIME/arg.XXXXXX") || vbw_die "cannot create a temporary file in $VBW_RUNTIME"
  vbw_guard_add file "$f"
  printf '%s' "$2" > "$f"
  printf -v "$1" '%s' "$f"
}

# The parsed spec on stdout; every error on stderr and exit 1 if it is invalid.
spec_parse() {
  local spec="$VBW_DIR/spec.md" parsed
  [ -f "$spec" ] || vbw_die "no .vbw/spec.md (run /vbw:init)"
  parsed=$(jq -Rs -f "$VBW_LIB/spec.jq" < "$spec") || vbw_die "cannot read $spec"
  if ! printf '%s' "$parsed" | jq -e '.errors == []' > /dev/null; then
    printf '%s' "$parsed" | jq -r '.errors[] | "vbw: spec.md " + .' >&2
    exit 1
  fi
  printf '%s\n' "$parsed"
}

# Bring the record's requirements in line with the spec, in spec order. A new
# or changed [auto] requirement gets rules: [] (pending) once any requirement
# has a rules field; projects approved before rules existed are untouched (D53).
spec_sync() {
  local reqs blocked sf
  reqs=$(printf '%s' "$1" | jq -c '.requirements')
  # A requirement removed from the spec takes its checks with it, and the plans
  # that only served it, unless such a plan has already started: that work is
  # never thrown away without the user deciding.
  blocked=$(record_read | jq -r --slurpfile f_s <(printf '%s' "$reqs") '$f_s[0] as $s |
    [.requirements[].id | select(. as $id | any($s[]; .id == $id) | not)] as $gone
    | [.plans[] | select(.status != "planned")
        | select(all(.reqs[]; . as $q | any($gone[]; . == $q)))
        | "\(.id) (\(.status)) serves only \(.reqs | join(", "))"] | join("; ")')
  [ -z "$blocked" ] || vbw_die "the spec removes requirements whose plans have already started: $blocked. Keep them in the spec, or reset those plans first (vbw plan reset)"
  record_read | jq -r --slurpfile f_s <(printf '%s' "$reqs") '$f_s[0] as $s |
    . as $rec | .requirements as $old
    | ($s[] | . as $n | [$old[] | select(.id == $n.id)][0] as $o
       | if $o == null then "added \(.id)"
         elif $o.text != .text or $o.proof != .proof then "changed \(.id) (status reset to open)"
         else empty end),
      ($old[] | select(.id as $id | any($s[]; .id == $id) | not) | .id as $id
        | "removed \($id)" + ([$rec.checks[] | select(.req == $id) | .id] | if length > 0 then " and its checks \(join(", "))" else "" end))'
  vbw_scratch sf "$reqs"
  record_update '$f_s[0] as $s | .milestone.id as $m
    | .requirements as $old
    | [$old[].id | select(. as $id | any($s[]; .id == $id) | not)] as $gone
    | any($old[]; has("rules")) as $ruled
    | (.lease != null) as $open
    | def kept: . as $q | any($gone[]; . == $q) | not;
      .requirements = [$s[] | . as $n | [$old[] | select(.id == $n.id)][0] as $o
        | if $o == null or $o.text != $n.text or $o.proof != $n.proof
          then {id: $n.id, text: $n.text, proof: $n.proof, status: "open", milestone: $m}
            + (if $n.proof == "auto" and $ruled then {rules: []} else {} end)
            + (if $open and ($o == null or $o.queued == true) then {queued: true} else {} end)
          else $o end]
    | .checks = [.checks[] | select(.req | kept)]
    | .fixes = [.fixes[] | select((has("req") | not) or (.req | kept))]
    | .plans = [.plans[] | .reqs = [.reqs[] | select(kept)] | select(.reqs | length > 0)]
    | ([.plans[].id]) as $ids
    | .plans = [.plans[] | .after = [.after[] | select(. as $a | any($ids[]; . == $a))]]
    | .phases = [.phases[] | .reqs = [.reqs[] | select(kept)] | select(.reqs | length > 0)]' --slurpfile f_s "$sf"
  vbw_guard_drop "$sf"
  spec_sync_commands "$(printf '%s' "$1" | jq -c '.commands')"
  spec_sync_results "$(printf '%s' "$1" | jq -c '.results')"
  spec_sync_test_files "$(printf '%s' "$1" | jq -c '.test_files')"
  spec_sync_leave_out "$(printf '%s' "$1" | jq -c '(.leave_out // null) | if . == null then null else map(.path) end')"
  printf 'record has %s requirements\n' "$(jq '.requirements | length' "$VBW_RECORD")"
}

# Every Clean copy path must be git-ignored when something is there: only
# ignored paths are copied in, so only they can be left out. A path with nothing
# at it is accepted (nothing to leave out). Dies on the first refusal, before any write.
spec_verify_leave_out() {
  local line path p
  while IFS=$'\t' read -r line path; do
    p="${path%/}"
    [ -e "$VBW_ROOT/$p" ] || [ -L "$VBW_ROOT/$p" ] || continue
    if [ -n "$(git -C "$VBW_ROOT" ls-files -z -- "$p" | head -c 1)" ] \
      || [ -n "$(git -C "$VBW_ROOT" ls-files -z --others --exclude-standard -- "$p" | head -c 1)" ]; then
      vbw_die "spec.md line $line: $path is not git-ignored: only ignored paths are copied in, so only they can be left out"
    fi
    git -C "$VBW_ROOT" check-ignore -q -- "$p" \
      || [ -n "$(git -C "$VBW_ROOT" ls-files -z --others --ignored --exclude-standard -- "$p" | head -c 1)" ] \
      || vbw_die "spec.md line $line: $path is not git-ignored: only ignored paths are copied in, so only they can be left out"
  done < <(printf '%s' "$1" | jq -r '(.leave_out // [])[] | "\(.line)\t\(.path)"')
}

# vbw spec check notes each listed path with nothing at it, so a mistyped path is noticed.
spec_gone_notes() {
  local line path p
  printf '%s' "$1" | jq -r '(.leave_out // [])[] | "\(.line)\t\(.path)"' | while IFS=$'\t' read -r line path; do
    p="${path%/}"
    [ -e "$VBW_ROOT/$p" ] || [ -L "$VBW_ROOT/$p" ] || vbw_out "spec.md line $line: $path is not here now, so nothing is left out for it yet"
  done
}

# The record's project.leave_out becomes the spec's Clean copy paths, as written,
# and goes when the spec has no such section. A changed list needs the user's approval.
spec_sync_leave_out() {
  local lf
  record_read | jq -r --slurpfile f_l <(printf '%s' "$1") '$f_l[0] as $l | (.project.leave_out // null) as $o
    | select($o != $l)
    | if $l == null then "removed the clean copy list" else "clean copy leaves out: \($l | join(", "))" end'
  vbw_scratch lf "$1"
  record_update '$f_l[0] as $l | if $l == null then .project |= del(.leave_out) else .project.leave_out = $l end' --slurpfile f_l "$lf"
  vbw_guard_drop "$lf"
}

# The record's commands become exactly the spec's Commands section; a spec
# without that section leaves them as they are. A changed argv needs the user's
# approval before any proof runs it (vbw next asks for it).
spec_sync_commands() {
  local cf
  [ "$1" != null ] || return 0
  record_read | jq -r --slurpfile f_c <(printf '%s' "$1") '$f_c[0] as $c | .commands as $o
    | ($c | to_entries[] | if $o[.key] == null then "added command \(.key)"
        elif $o[.key] != .value then "changed command \(.key)" else empty end),
      ($o | keys[] | select(. as $k | $c | has($k) | not) | "removed command \(.)")'
  vbw_scratch cf "$1"
  record_update '$f_c[0] as $c | .commands = $c' --slurpfile f_c "$cf"
  vbw_guard_drop "$cf"
}

# The record's project.results becomes the spec's Test results folders, and
# goes when the spec names none. A changed list needs the user's approval.
spec_sync_results() {
  local lf
  record_read | jq -r --slurpfile f_l <(printf '%s' "$1") '$f_l[0] as $l | (.project.results // null) as $o
    | select($o != $l)
    | if $l == null then "removed the test results folders" else "test results folders: \($l | join(", "))" end'
  vbw_scratch lf "$1"
  record_update '$f_l[0] as $l | if $l == null then .project |= del(.results) else .project.results = $l end' --slurpfile f_l "$lf"
  vbw_guard_drop "$lf"
}

# The record's test_files becomes the spec's Test files form, and goes when the
# spec has no such section. A changed form needs the user's approval, like a command.
spec_sync_test_files() {
  local tf
  record_read | jq -r --slurpfile f_t <(printf '%s' "$1") '$f_t[0] as $t | (.test_files // null) as $o
    | select($o != $t)
    | if $t == null then "removed test file form"
      elif $o == null then "added test file form"
      else "changed test file form" end'
  vbw_scratch tf "$1"
  record_update '$f_t[0] as $t | if $t == null then del(.test_files) else .test_files = $t end' --slurpfile f_t "$tf"
  vbw_guard_drop "$tf"
}

# Insert "- R<next> [PROOF] TEXT" at the end of the Requirements section, then sync.
spec_add() {
  local parsed="$1" proof="$2" text id end line spec="$VBW_DIR/spec.md" tmp
  text=$(printf '%s' "$3" | tr -s '[:space:]' ' ')
  text=${text# }
  text=${text% }
  [ -n "$text" ] || vbw_usage_error "requirement text must not be empty"
  id=$(record_read | jq -r --slurpfile f_p <(printf '%s' "$parsed") \
    '$f_p[0] as $p | [((.requirements[], $p.requirements[]) | .id), ((.parked // [])[].ids[]? | select(startswith("R"))) | ltrimstr("R") | tonumber] | "R\((max // 0) + 1)"')
  line="- $id [$proof] $text"
  end=$(printf '%s' "$parsed" | jq -r '.end')
  tmp=$(mktemp "$VBW_RUNTIME/spec.XXXXXX") || vbw_die "cannot write $VBW_RUNTIME"
  # The line travels through the environment: awk -v would interpret backslashes.
  if [ "$(printf '%s' "$parsed" | jq '.requirements | length')" -eq 0 ]; then
    VBW_LINE=$'\n'"$line" awk -v n="$end" '{print} NR == n {print ENVIRON["VBW_LINE"]}' "$spec" > "$tmp"
  else
    VBW_LINE="$line" awk -v n="$end" '{print} NR == n {print ENVIRON["VBW_LINE"]}' "$spec" > "$tmp"
  fi
  cat "$tmp" > "$spec" && rm -f "$tmp"
  printf 'spec.md: %s\n' "$line"
  spec_sync "$(spec_parse)"
}
