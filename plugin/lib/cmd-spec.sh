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
      printf '%s' "$parsed" | jq -r '.requirements
        | "spec.md: \(length) requirements (\(map(select(.proof == "auto")) | length) auto, \(map(select(.proof == "human")) | length) human)"'
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

# Bring the record's requirements in line with the spec, in spec order.
spec_sync() {
  local reqs
  reqs=$(printf '%s' "$1" | jq -c '.requirements')
  record_read | jq -r --argjson s "$reqs" '
    .requirements as $old
    | ($s[] | . as $n | [$old[] | select(.id == $n.id)][0] as $o
       | if $o == null then "added \(.id)"
         elif $o.text != .text or $o.proof != .proof then "changed \(.id) (status reset to open)"
         else empty end),
      ($old[] | select(.id as $id | any($s[]; .id == $id) | not) | "removed \(.id)")'
  record_update '.requirements as $old
    | .requirements = [$s[] | . as $n | [$old[] | select(.id == $n.id)][0] as $o
        | if $o == null or $o.text != $n.text or $o.proof != $n.proof
          then {id: $n.id, text: $n.text, proof: $n.proof, status: "open"}
          else $o end]' --argjson s "$reqs"
  printf 'record has %s requirements\n' "$(jq '.requirements | length' "$VBW_RECORD")"
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
