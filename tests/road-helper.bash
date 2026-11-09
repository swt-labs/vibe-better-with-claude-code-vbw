#!/usr/bin/env bash
# Shared by the R191 tests (tests/step-units-history.bats, tests/step-ladder.bats,
# tests/step-proof-units.bats, tests/road-next.bats, tests/road-note.bats; L1),
# loaded after helper and step-helper. Seeds the clone's step history with the
# units R191 records (a build's plans with their tier, tasks and own seconds; a
# fix round's tier; a proof's units with their own seconds; planning's requirement
# count; QA's phases with their tiers), the per-unit runs store (runs.json beside
# steps.json) and projects whose phases carry tiers and whose plans carry tasks.
#
# A history entry: {kind, run, started_at, ended_at, seconds, parts?} as before, plus
#   build  units: [{id, tier, tasks?, seconds}]   (one per plan done in the run)
#   fix    fixes: [ids], tier?                     (the highest tier of their phases)
#   proof  units: [{name, seconds}]                (check:ID, file:PATH, command:NAME)
#   plan   reqs                                    (open requirements it planned)
#   qa     phases: [{id, tier}]

# hist_add JSON: append one finished step (an object with at least kind and
# seconds) to the history; run, start and end are filled in when missing.
hist_add() {
  mkdir -p "$(dirname "$STEPS")"
  [ -f "$STEPS" ] || printf '{"steps": []}\n' > "$STEPS"
  jq --argjson e "$1" '(.steps | length) as $n
    | .steps += [{run: "\($e.kind)-seed-\($n)", started_at: "2026-01-01T00:00:00Z",
                  ended_at: ("2026-01-01T00:00:00Z" | fromdateiso8601 + $e.seconds | todateiso8601)} + $e]' "$STEPS" > "$TEST_ROOT/hist.json"
  cp "$TEST_ROOT/hist.json" "$STEPS"
}

# hist_build TIER TASKS SECONDS COUNT: COUNT finished builds of one plan each, the
# plan at TIER with TASKS tasks ("-": none recorded), done SECONDS after the run
# started; the build's own seconds are the same.
hist_build() {
  local i
  for ((i = 0; i < $4; i++)); do
    hist_add "$(jq -nc --arg t "$1" --arg k "$2" --argjson s "$3" '{kind: "build", seconds: $s, parts: 1,
      units: [{id: "P7.1", tier: $t, seconds: $s} + (if $k == "-" then {} else {tasks: ($k | tonumber)} end)]}')"
  done
}

# hist_fix TIER SECONDS COUNT: COUNT finished fix rounds of one fix at TIER ("-":
# no tier recorded), each SECONDS long.
hist_fix() {
  local i
  for ((i = 0; i < $3; i++)); do
    hist_add "$(jq -nc --arg t "$1" --argjson s "$2" '{kind: "fix", seconds: $s, parts: 1, fixes: ["F7"]}
      + (if $t == "-" then {} else {tier: $t} end)')"
  done
}

# hist_plan REQS SECONDS COUNT: COUNT finished planning steps that planned REQS open
# requirements ("-": no count recorded), each SECONDS long.
hist_plan() {
  local i
  for ((i = 0; i < $3; i++)); do
    hist_add "$(jq -nc --arg r "$1" --argjson s "$2" '{kind: "plan", seconds: $s}
      + (if $r == "-" then {} else {reqs: ($r | tonumber)} end)')"
  done
}

# hist_qa TIER SECONDS COUNT: COUNT finished QA steps that checked one phase at TIER
# ("-": no phases recorded), each SECONDS long.
hist_qa() {
  local i
  for ((i = 0; i < $3; i++)); do
    hist_add "$(jq -nc --arg t "$1" --argjson s "$2" '{kind: "qa", seconds: $s}
      + (if $t == "-" then {} else {phases: [{id: "P7", tier: $t}]} end)')"
  done
}

# hist_proof UNITS WALL COUNT: COUNT finished proofs that ran UNITS (a JSON array of
# {name, seconds}) in WALL seconds of wall time.
hist_proof() {
  local i
  for ((i = 0; i < $3; i++)); do
    hist_add "$(jq -nc --argjson u "$1" --argjson s "$2" '{kind: "proof", seconds: $s, parts: ($u | length), units: $u}')"
  done
}

# runs_seed JSON: the per-unit store, runs.json beside steps.json, from an object
# name -> seconds, and its run times beside it (run-times.json), as a save writes
# them. Its fingerprints match nothing, so every unit still runs.
runs_seed() {
  mkdir -p "$(dirname "$STEPS")"
  jq -nc --argjson u "$1" '{runs: ($u | with_entries(.value = {fp: "seed", tree: "seed", status: "pass",
    at: "2026-01-01T00:00:00Z", seconds: .value, tail: "", reads: null, dirs: [], git: false}))}' > "$(dirname "$STEPS")/runs.json"
  jq -nc --argjson u "$1" '{runs: ($u | map_values({seconds: .}))}' > "$(dirname "$STEPS")/run-times.json"
}

# tiered_project: step_project with P1 at standard and tasks on its plans: P1.1
# two, P1.2 five, P1.3 three (standard: vbw plan done asks no mutation breaks).
tiered_project() {
  step_project
  step_edit '.phases[0].tier = "standard"
    | (.plans[] | select(.id == "P1.1")).tasks = ["a", "b"]
    | (.plans[] | select(.id == "P1.2")).tasks = ["a", "b", "c", "d", "e"]
    | (.plans[] | select(.id == "P1.3")).tasks = ["a", "b", "c"]'
  git add -A
  git commit -q -m "chore(vbw): tiers and tasks"
  "$VBW" approve > /dev/null
}

# road_project: two requirements, two phases and two build waves: P1 (deep, R1)
# with P1.1 (two tasks, src/a.txt) and P1.2 (five tasks, src/b.txt); P2 (standard,
# R2) with P2.1 (three tasks, src/c.txt) after P1.1; checks C1 (R1) and C2 (R2),
# both approved.
road_project() {
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src
  printf 'a\n' > src/a.txt
  printf 'b\n' > src/b.txt
  printf 'c\n' > src/c.txt
  step_edit '.checks = [{id: "C1", req: "R1", run: ["true"]}, {id: "C2", req: "R2", run: ["true"]}]
    | .phases = [{id: "P1", title: "Pay", reqs: ["R1"], milestone: "M1", tier: "deep"},
                 {id: "P2", title: "Receipt", reqs: ["R2"], milestone: "M1", tier: "standard"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "A", reqs: ["R1"], files: ["src/a.txt"], after: [], status: "planned", tasks: ["a", "b"]},
                {id: "P1.2", phase: "P1", title: "B", reqs: ["R1"], files: ["src/b.txt"], after: [], status: "planned", tasks: ["a", "b", "c", "d", "e"]},
                {id: "P2.1", phase: "P2", title: "C", reqs: ["R2"], files: ["src/c.txt"], after: ["P1.1"], status: "planned", tasks: ["a", "b", "c"]}]'
  git add -A
  git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  STEPS="$(git rev-parse --path-format=absolute --git-common-dir)/vbw/steps.json"
  NOTE="$PROJECT/.vbw/runtime/step.json"
  export STEPS NOTE
}

# outcomes_seed TIER ROUNDS...: one finished phase per ROUNDS, in a shipped
# milestone M0, each at TIER with outcome.fix_rounds set to it.
outcomes_seed() {
  local tier="$1" n
  shift
  step_edit '.shipped = ((.shipped // []) | if any(.[]; .id == "M0") then . else . + [{id: "M0", title: "Before", at: "2025-12-01T00:00:00Z"}] end)'
  for n in "$@"; do
    step_edit "(.phases | length) as \$k | .phases += [{id: \"P9\(\$k)\", title: \"Old \(\$k)\", reqs: [\"R1\"], milestone: \"M0\", tier: \"$tier\",
      qa: {result: \"pass\", tier: \"deep\", tree: \"old\", at: \"2025-12-01T00:00:00Z\"},
      outcome: {tier: \"$tier\", predicted: \"$tier\", held: true, fix_rounds: $n, qa_findings: 0, escalations: 0}}]"
  done
}

# road_hist [PER_TASK]: the history every road test starts from (ROAD_HIST_RUNS runs of each, 3 unless set; 5 agreeing runs make an estimate a single figure, R270). A deep plan task
# and a standard one each take PER_TASK seconds (100; three plans of one task per
# tier); a deep QA check 200 s and a standard one 100 s; a deep fix round 300 s and a
# standard one 150 s; three proofs whose wall time equals their units' time (ratio
# 1); the runs store knows check:C1 at 10 s and check:C2 at 20 s.
road_hist() {
  local per="${1:-100}" runs="${ROAD_HIST_RUNS:-3}"
  hist_build deep 1 "$per" "$runs"
  hist_build standard 1 "$per" "$runs"
  hist_qa deep 200 "$runs"
  hist_qa standard 100 "$runs"
  hist_fix deep 300 "$runs"
  hist_fix standard 150 "$runs"
  hist_proof '[{"name": "check:C1", "seconds": 50}, {"name": "check:C2", "seconds": 50}]' 100 "$runs"
  runs_seed '{"check:C1": 10, "check:C2": 20}'
}

# road_of: the road vbw next --json carries now.
road_of() { "$VBW" next --json | jq -c '.road'; }
