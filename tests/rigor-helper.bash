# shellcheck shell=bash
# Shared fixtures for the adaptive-rigor tests (M4). Load after helper:
#   load helper
#   load rigor-helper

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

phase_json() { # JQ_EXPR: evaluate against phase P1 of the record
  jq -e "$1" .vbw/record.json
}

# rigor_project N [human]: a git project with requirements R1..RN, all [auto]
# (the last one [human] when "human" is given), synced into the record.
rigor_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p tests src
  local n=$1 i kind
  {
    printf '# Notes\n\n## Requirements\n\n'
    for ((i = 1; i <= n; i++)); do
      kind=auto
      [ "${2:-}" = human ] && [ "$i" -eq "$n" ] && kind=human
      printf -- '- R%d [%s] Visitors can read note number %d\n' "$i" "$kind" "$i"
    done
  } > .vbw/spec.md
  "$VBW" spec sync > /dev/null
}

# rigor_doc NREQS TIER FILE...: a vbw apply document for one phase P1 over
# R1..RNREQS with one plan P1.1 writing FILE...; TIER "" leaves the tier to
# the kernel. No checks. PH and R0 override the phase id and the first
# requirement number.
rigor_doc() {
  local ph=${PH:-P1} r0=${R0:-1} n=$1 tier=$2
  shift 2
  jq -nc --arg ph "$ph" --argjson r0 "$r0" --argjson n "$n" --arg tier "$tier" '
    [range($r0; $r0 + $n) | "R\(.)"] as $reqs
    | {phases: [{id: $ph, title: "Notes", reqs: $reqs, goal: "Notes work", criteria: ["it works"]}
                + (if $tier == "" then {} else {tier: $tier} end)],
       plans: [{id: ($ph + ".1"), phase: $ph, title: "Notes", reqs: $reqs, files: $ARGS.positional, after: []}],
       checks: []}' --args "$@"
}

rigor_apply() { printf '%s' "$1" | "$VBW" apply; }

# rigor_second_milestone: M1 is shipped with R1 proven by plan P1.1 (file
# src/old.js, done); M2 is current. New requirements start at R2.
rigor_second_milestone() {
  edit_record '.shipped = [{id: "M1", title: "First", at: "2026-10-01T09:00:00Z"}]
    | .milestone = {id: "M2", title: "Second", status: "active"}
    | .requirements = [{id: "R1", text: "Old behaviour", proof: "auto", status: "proven", milestone: "M1"}]
        + [.requirements[1:][] | .milestone = "M2"]
    | .phases = [{id: "P1", title: "Old", reqs: ["R1"], milestone: "M1"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "Old", reqs: ["R1"], files: ["src/old.js"], after: [], status: "done"}]
    | .checks = [{id: "C1", req: "R1", run: ["true"]}]'
}

# rigor_flow_doc [human]: the apply document of the tiny real flow.
rigor_flow_doc() {
  local reqs='["R1"]'
  [ "${1:-}" = human ] && reqs='["R1","R2"]'
  printf '%s' '{"phases":[{"id":"P1","title":"Greeting","reqs":'"$reqs"',"goal":"A greeting exists","criteria":["it says hello"]}],
    "plans":[{"id":"P1.1","phase":"P1","title":"Greeting","reqs":["R1"],"files":["src/greet.txt"],"after":[]}],
    "checks":[{"id":"C1","req":"R1","run":["sh","tests/greet.sh"],"files":["tests/greet.sh"]}]}'
}

# rigor_flow_setup [human]: project and plan applied (one auto requirement,
# plus one [human] when asked); the contract is not approved yet.
rigor_flow_setup() {
  if [ "${1:-}" = human ]; then rigor_project 2 human; else rigor_project 1; fi
  printf 'grep -qx hello src/greet.txt\n' > tests/greet.sh
  rigor_flow_doc "${1:-}" | "$VBW" apply > /dev/null
}

# rigor_flow_approve, rigor_flow_work, rigor_flow_build: approve; build the
# plan and prove it; both.
rigor_flow_approve() { "$VBW" approve > /dev/null; }
rigor_flow_work() {
  printf 'hello\n' > src/greet.txt
  "$VBW" commit P1.1 "feat(greet): hello" > /dev/null
  "$VBW" plan done P1.1 > /dev/null
  "$VBW" prove > /dev/null
}
rigor_flow_build() { rigor_flow_approve; rigor_flow_work; }
