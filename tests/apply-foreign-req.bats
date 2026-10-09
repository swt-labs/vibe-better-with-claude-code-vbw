#!/usr/bin/env bats
# R130 (L1): a full vbw apply (no --patch, no --add) refuses a phase that lists
# a requirement another milestone owns, or one a phase of another milestone
# already covers, with the message vbw apply --add gives, and the record is
# byte-for-byte unchanged. A full apply of the active milestone's own
# requirements is accepted as before. One rule serves both: the same bad
# document fed to both gets the same message.

load helper

# M1 shipped: its phase P1 covers R1 (plan P1.1 done); R2 stayed in M1 with no
# phase. R3 and R4 belong to the active milestone M2, which has no phase yet.
setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'true\n' > tests/t.sh
  printf '# Notes\n\n## Requirements\n\n- R1 [auto] Visitors read the first note\n- R2 [auto] Visitors read the second note\n- R3 [auto] Visitors read the third note\n- R4 [auto] Visitors read the fourth note\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq -nc '{phases: [{id: "P1", title: "Notes", reqs: ["R1"], goal: "Notes", criteria: ["notes"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "First", reqs: ["R1"], files: ["src/n1.txt"], after: [], tasks: ["first"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/t.sh"], files: ["tests/t.sh"]}],
    rules: [{req: "R1", text: "first", check: "C1"}]}' | "$VBW" apply > /dev/null
  jq '.shipped = [{id: "M1", title: "First", at: "2026-10-01T09:00:00Z"}]
    | .milestone = {id: "M2", title: "Second", status: "active"}
    | .requirements |= map(.milestone = (if .id == "R3" or .id == "R4" then "M2" else "M1" end))
    | (.plans[] | select(.id == "P1.1")).status = "done"' .vbw/record.json > "$TEST_ROOT/r.json"
  cp "$TEST_ROOT/r.json" .vbw/record.json
}

teardown() { vbw_teardown; }

# doc REQ...: a document with one phase P3 for the given requirements, one plan
# and one check (with a rule) for each requirement.
doc() {
  jq -nc '$ARGS.positional as $q | {phases: [{id: "P3", title: "Again", reqs: $q, tier: "standard"}],
    plans: [$q | to_entries[] | {id: "P3.\(.key + 1)", phase: "P3", title: "Part \(.key + 1)", reqs: [.value], files: ["src/p\(.key + 1).txt"], after: []}],
    checks: [$q | to_entries[] | {id: "C\(.key + 9)", req: .value, run: ["sh", "tests/t.sh"], files: ["tests/t.sh"]}],
    rules: [$q | to_entries[] | {req: .value, text: "part \(.key + 1)", check: "C\(.key + 9)"}]}' --args "$@"
}

# apply_refused MODE DOC: vbw apply (MODE "full") or vbw apply --add (MODE "add") of
# DOC; asserts it is refused and the record's bytes stay; prints the message.
apply_refused() {
  local before out code=0
  before=$(cksum < .vbw/record.json)
  if [ "$1" = add ]; then
    out=$(printf '%s' "$2" | "$VBW" apply --add 2>&1) || code=$?
  else
    out=$(printf '%s' "$2" | "$VBW" apply 2>&1) || code=$?
  fi
  [ "$code" -ne 0 ] || { echo "vbw apply ($1) accepted: $out"; return 1; }
  [ "$(cksum < .vbw/record.json)" = "$before" ] || { echo "vbw apply ($1) changed the record"; return 1; }
  printf '%s\n' "$out"
}

@test "R130: a full apply listing a requirement that belongs to another milestone is refused with the --add message, and nothing changes" {
  local full add
  full=$(apply_refused full "$(doc R3 R2)") || { echo "$full"; false; }
  [[ "$full" == *"R2 belongs to milestone M1"* ]] || { echo "$full"; false; }
  add=$(apply_refused add "$(doc R3 R2)") || { echo "$add"; false; }
  [ "$full" = "$add" ] || { printf 'full: %s\nadd:  %s\n' "$full" "$add"; false; }
}

@test "R130: a full apply listing a requirement a phase of another milestone covers is refused with the --add message, and nothing changes" {
  local full add
  full=$(apply_refused full "$(doc R1)") || { echo "$full"; false; }
  [[ "$full" == *"R1 is already covered by P1"* ]] || { echo "$full"; false; }
  add=$(apply_refused add "$(doc R1)") || { echo "$add"; false; }
  [ "$full" = "$add" ] || { printf 'full: %s\nadd:  %s\n' "$full" "$add"; false; }
}

@test "R130: the same bad document gets the same message from the full apply and from --add, for each kind of conflict" {
  local d full add
  for d in "$(doc R2)" "$(doc R1)" "$(doc R4 R1)" "$(doc R2 R3)"; do
    full=$(apply_refused full "$d") || { echo "$full"; false; }
    add=$(apply_refused add "$d") || { echo "$add"; false; }
    [ "$full" = "$add" ] || { printf 'doc: %s\nfull: %s\nadd:  %s\n' "$d" "$full" "$add"; false; }
  done
}

@test "R130: a full apply of the active milestone's own requirements is accepted, and so is planning them again" {
  run sh -c 'printf "%s" "$1" | "$2" apply' _ "$(doc R3 R4)" "$VBW"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '[.phases[] | select(.milestone == "M2") | .id] == ["P3"] and ([.phases[] | select(.milestone == "M1") | .id] == ["P1"])' .vbw/record.json
  run sh -c 'printf "%s" "$1" | "$2" apply' _ "$(doc R4 R3)" "$VBW"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '[.phases[] | select(.id == "P3") | .reqs] == [["R4", "R3"]]' .vbw/record.json
}
