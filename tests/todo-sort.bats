#!/usr/bin/env bats
# R127 (L1): vbw todo sort ID next|later small|medium|large sets the sort and
# size of an open backlog item already in the record, which then lists with
# them (vbw todo list, vbw triage --json, the backlog lines the recommending
# workflow gives the Architect). An unknown or closed item, a value outside
# those, a missing value or an extra argument is refused and the record is
# byte-for-byte unchanged. The usage text, vbw help and the user docs name it.

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  "$VBW" todo add "Dark mode" > /dev/null
  "$VBW" todo add --sort later --size large "Gift cards" > /dev/null
  "$VBW" todo add "CSV export" > /dev/null
}

teardown() { vbw_teardown; }

# refused ARGS...: vbw todo ARGS exits non-zero and leaves the record's bytes as they were.
refused() {
  local before
  before=$(cksum < .vbw/record.json)
  run "$VBW" todo "$@" < /dev/null
  [ "$status" -ne 0 ] || { echo "vbw todo $* was accepted: $output"; return 1; }
  [ "$(cksum < .vbw/record.json)" = "$before" ] || { echo "vbw todo $* changed the record"; return 1; }
}

@test "R127: every pairing of next or later with small, medium or large is recorded on an open item, and the item lists with them" {
  local sort size
  for sort in next later; do
    for size in small medium large; do
      run "$VBW" todo sort T1 "$sort" "$size" < /dev/null
      [ "$status" -eq 0 ] || { echo "sort T1 $sort $size: $output"; false; }
      jq -e --arg s "$sort" --arg z "$size" '.todos[] | select(.id == "T1") | .sort == $s and .size == $z' .vbw/record.json \
        || { echo "T1 was not recorded as $sort, $size"; false; }
      run "$VBW" todo list < /dev/null
      [ "$status" -eq 0 ]
      printf '%s\n' "$output" | grep -qxF "T1 [$sort, $size] Dark mode" || { echo "$output"; false; }
    done
  done
}

@test "R127: an item sorted next lists in the next group, before later and unsorted items" {
  run "$VBW" todo sort T3 next small < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$VBW" todo list < /dev/null
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "T3 [next, small] CSV export" ] || { echo "$output"; false; }
  [ "${lines[1]}" = "T2 [later, large] Gift cards" ] || { echo "$output"; false; }
  [ "${lines[2]}" = "T1 Dark mode" ] || { echo "$output"; false; }
}

@test "R127: sorting an item that has a sort and size replaces both; its id, text and status stay" {
  local before
  before=$(jq -c '.todos[] | select(.id == "T2") | {id, text, status}' .vbw/record.json)
  run "$VBW" todo sort T2 next small < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.todos[] | select(.id == "T2") | .sort == "next" and .size == "small"' .vbw/record.json
  [ "$(jq -c '.todos[] | select(.id == "T2") | {id, text, status}' .vbw/record.json)" = "$before" ]
  [ "$(jq '[.todos[] | select(.id == "T2")] | length' .vbw/record.json)" -eq 1 ]
}

@test "R127: sorting an item that does not exist is refused with a message naming the id, and nothing changes" {
  refused sort T9 next small
  [[ "$output" == *T9* ]] || { echo "$output"; false; }
}

@test "R127: sorting a done or dropped item is refused with a message saying it is closed, and nothing changes" {
  # shellcheck disable=SC1010 # "todo done" is a vbw subcommand
  "$VBW" todo done T1 > /dev/null
  "$VBW" todo drop T2 > /dev/null
  refused sort T1 next small
  printf '%s' "$output" | grep -qi 'closed' || { echo "$output"; false; }
  refused sort T2 later medium
  printf '%s' "$output" | grep -qi 'closed' || { echo "$output"; false; }
}

@test "R127: a wrong sort or size, a missing one, or extra arguments is refused with the usage line, and nothing changes" {
  local args
  for args in "T1 soon small" "T1 next tiny" "T1 small next" "T1 next" "T1" "" "T1 next small extra" "T1 NEXT small"; do
    # shellcheck disable=SC2086 # the words of each case are its arguments
    refused sort $args
    [[ "$output" == *"usage: vbw todo sort"* ]] || { echo "vbw todo sort $args: $output"; false; }
  done
}

@test "R127: a sorted item shows its sort and size in vbw triage --json and in the backlog the recommending workflow gives the Architect" {
  command -v node > /dev/null || skip "node is not installed"
  "$VBW" todo sort T1 next small > /dev/null
  local summary out prompt
  summary=$("$VBW" triage --json < /dev/null)
  printf '%s' "$summary" | jq -e '.todos[] | select(.id == "T1") | .sort == "next" and .size == "small"' || { echo "$summary"; false; }
  out=$(node "$RUN" "$PLUGIN_ROOT/workflows/recommending.js" "$(jq -nc --argjson s "$summary" '{summary: $s, declined: []}')" '{}')
  prompt=$(printf '%s' "$out" | jq -r '.calls[0].prompt')
  [[ "$prompt" == *"- T1: Dark mode (sort: next, size: small)"* ]] || { echo "$prompt"; false; }
}

@test "R127: the todo usage text, vbw help and the user docs name vbw todo sort" {
  run "$VBW" todo nonsense < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"sort ID next|later small|medium|large"* ]] || { echo "$output"; false; }
  run "$VBW" help
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -E '^  todo ' | grep -qF 'sort ID next|later small|medium|large' || { echo "$output"; false; }
  grep -qF 'vbw todo sort' "$REPO_ROOT/docs/triage.md"
  grep -qF 'vbw todo sort' "$REPO_ROOT/docs/record.md"
}
