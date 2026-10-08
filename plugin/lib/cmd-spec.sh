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
    check)
      printf '%s' "$parsed" | jq -r '(.requirements
        | "spec.md: \(length) requirements (\(map(select(.proof == "auto")) | length) auto, \(map(select(.proof == "human")) | length) human)")
        + (if .commands == null then "" else ", \(.commands | length) command\(if (.commands | length) == 1 then "" else "s" end)" end)'
      ;;
    sync) spec_sync "$parsed" ;;
    add) spec_add "$parsed" "$1" "$2" ;;
  esac
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
  local reqs blocked
  reqs=$(printf '%s' "$1" | jq -c '.requirements')
  # A requirement removed from the spec takes its checks with it, and the plans
  # that only served it, unless such a plan has already started: that work is
  # never thrown away without the user deciding.
  blocked=$(record_read | jq -r --argjson s "$reqs" '
    [.requirements[].id | select(. as $id | any($s[]; .id == $id) | not)] as $gone
    | [.plans[] | select(.status != "planned")
        | select(all(.reqs[]; . as $q | any($gone[]; . == $q)))
        | "\(.id) (\(.status)) serves only \(.reqs | join(", "))"] | join("; ")')
  [ -z "$blocked" ] || vbw_die "the spec removes requirements whose plans have already started: $blocked. Keep them in the spec, or reset those plans first (vbw plan reset)"
  record_read | jq -r --argjson s "$reqs" '
    . as $rec | .requirements as $old
    | ($s[] | . as $n | [$old[] | select(.id == $n.id)][0] as $o
       | if $o == null then "added \(.id)"
         elif $o.text != .text or $o.proof != .proof then "changed \(.id) (status reset to open)"
         else empty end),
      ($old[] | select(.id as $id | any($s[]; .id == $id) | not) | .id as $id
        | "removed \($id)" + ([$rec.checks[] | select(.req == $id) | .id] | if length > 0 then " and its checks \(join(", "))" else "" end))'
  record_update '.milestone.id as $m
    | .requirements as $old
    | [$old[].id | select(. as $id | any($s[]; .id == $id) | not)] as $gone
    | any($old[]; has("rules")) as $ruled
    | def kept: . as $q | any($gone[]; . == $q) | not;
      .requirements = [$s[] | . as $n | [$old[] | select(.id == $n.id)][0] as $o
        | if $o == null or $o.text != $n.text or $o.proof != $n.proof
          then {id: $n.id, text: $n.text, proof: $n.proof, status: "open", milestone: $m}
            + (if $n.proof == "auto" and $ruled then {rules: []} else {} end)
          else $o end]
    | .checks = [.checks[] | select(.req | kept)]
    | .fixes = [.fixes[] | select((has("req") | not) or (.req | kept))]
    | .plans = [.plans[] | .reqs = [.reqs[] | select(kept)] | select(.reqs | length > 0)]
    | ([.plans[].id]) as $ids
    | .plans = [.plans[] | .after = [.after[] | select(. as $a | any($ids[]; . == $a))]]
    | .phases = [.phases[] | .reqs = [.reqs[] | select(kept)] | select(.reqs | length > 0)]' --argjson s "$reqs"
  spec_sync_commands "$(printf '%s' "$1" | jq -c '.commands')"
  spec_sync_results "$(printf '%s' "$1" | jq -c '.results')"
  printf 'record has %s requirements\n' "$(jq '.requirements | length' "$VBW_RECORD")"
}

# The record's commands become exactly the spec's Commands section; a spec
# without that section leaves them as they are. A changed argv needs the user's
# approval before any proof runs it (vbw next asks for it).
spec_sync_commands() {
  [ "$1" != null ] || return 0
  record_read | jq -r --argjson c "$1" '.commands as $o
    | ($c | to_entries[] | if $o[.key] == null then "added command \(.key)"
        elif $o[.key] != .value then "changed command \(.key)" else empty end),
      ($o | keys[] | select(. as $k | $c | has($k) | not) | "removed command \(.)")'
  record_update '.commands = $c' --argjson c "$1"
}

# The record's project.results becomes the spec's Test results folders, and
# goes when the spec names none. A changed list needs the user's approval.
spec_sync_results() {
  record_read | jq -r --argjson l "$1" '(.project.results // null) as $o
    | select($o != $l)
    | if $l == null then "removed the test results folders" else "test results folders: \($l | join(", "))" end'
  record_update 'if $l == null then .project |= del(.results) else .project.results = $l end' --argjson l "$1"
}

# Insert "- R<next> [PROOF] TEXT" at the end of the Requirements section, then sync.
spec_add() {
  local parsed="$1" proof="$2" text id end line spec="$VBW_DIR/spec.md" tmp
  text=$(printf '%s' "$3" | tr -s '[:space:]' ' ')
  text=${text# }
  text=${text% }
  [ -n "$text" ] || vbw_usage_error "requirement text must not be empty"
  id=$(record_read | jq -r --argjson p "$parsed" \
    '[(.requirements[], $p.requirements[]) | .id | ltrimstr("R") | tonumber] | "R\((max // 0) + 1)"')
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
