#!/usr/bin/env bats
# R107 (docs/workflows.md; L1): every agent call of every workflow passes the
# effort level the profile gives for its role and step (args.effort, from
# vbw next --json or vbw config effort) through the per-agent effort option;
# without an effort table, or with a gap in it, agents run as they did before,
# with no error and no warning. The runtime is stubbed
# (tests/helpers/run-workflow-all.js): no model runs; each table value is
# "<role>.<step>", so a wrong role or step shows in the value that arrives.

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow-all.js"
WF="$PLUGIN_ROOT/workflows"
OK='{"ended":true,"recorded":true,"report":"all recorded; run ended"}'
DONE='{"status":"done","summary":"s","notes":[],"verdict":"pass","checks":[]}'
GENERIC='{"findings":["a"],"map":"m","picks":[],"hypotheses":[],"answer":"a","confidence":"high","root_cause":"r","evidence":"e","rejected":[],"fix":"f","unknowns":[],"status":"fixed","summary":"s","files":[],"commit":"c","regression_test":"t","notes":[]}'
TABLE='{"architect":{"decide":"architect.decide","scope":"architect.scope"},"lead":{"plan":"lead.plan","close":"lead.close"},"dev":{"build":"dev.build","fix":"dev.fix"},"docs":{"build":"docs.build"},"qa":{"verify":"qa.verify"},"scout":{"survey":"scout.survey","merge":"scout.merge"},"debugger":{"investigate":"debugger.investigate","diagnose":"debugger.diagnose","fix":"debugger.fix"}}'
REQS='[{"id":"R1","proof":"auto","text":"x"}]'

setup() { command -v node > /dev/null 2>&1 || skip "node is not installed"; }

# run NAME ARGS: the stubbed run of workflow NAME with ARGS (a JSON object); every agent answers GENERIC,
# except the planning and closing agents.
run_wf() {
  local responses
  responses=$(jq -nc --argjson g "$GENERIC" --argjson d "$DONE" --argjson k "$OK" \
    '{"*": ($g + $d), "close run": $k, "architect (decide)": {decisions: []},
      "architect (scope)": {phases: [{id: "P70", title: "t", reqs: ["R1"], goal: "g", criteria: ["c"]}], notes: []},
      "lead": {applied: true, summary: "s", blockers: []}}')
  node "$RUN" "$WF/$1.js" "$2" "$responses"
}

# The effort every call should carry: "<role>.<step>" from its agent type and label.
EXPECT='def step($wf): (.opts.agentType | ltrimstr("vbw:")) as $role | .opts.label as $l
  | (if $l == "close run" then "close"
     elif $role == "architect" then (if ($l | test("decide")) then "decide" else "scope" end)
     elif $role == "lead" then "plan"
     elif $role == "dev" then (if $wf == "fixing" then "fix" else "build" end)
     elif $role == "docs" then "build"
     elif $role == "qa" then "verify"
     elif $role == "scout" then (if $l == "scout merge" or $l == "scout answer" then "merge" else "survey" end)
     elif $l == "debugger diagnose" then "diagnose"
     elif $l == "debugger fix" then "fix"
     else "investigate" end) as $s
  | "\($role).\($s)";'

# arrive WF ARGS MIN: every call carries its own "<role>.<step>" as effort, and there are at least MIN calls.
arrive() {
  local out
  out=$(run_wf "$1" "$(jq -nc --argjson t "$TABLE" --argjson x "$2" '{effort: $t, session: "s"} + $x')") || { echo "$out"; return 1; }
  printf '%s' "$out" | jq -e --arg wf "$1" --argjson min "$3" "$EXPECT"'
    (.calls | length) >= $min and all(.calls[]; (.opts.effort // "none") == step($wf))' > /dev/null \
    || { printf '%s' "$out" | jq -c --arg wf "$1" "$EXPECT"'[.calls[] | {label: .opts.label, got: .opts.effort, want: step($wf)}]'; return 1; }
}

@test "R107: planning passes each step's effort: decide, scope, plan and close" {
  arrive planning "$(jq -nc --argjson r "$REQS" '{requirements: $r}')" 4
}

@test "R107: planning again (decided) passes the efforts too" {
  arrive planning "$(jq -nc --argjson r "$REQS" '{requirements: $r, decided: true}')" 3
}

@test "R107: building passes the Dev's and the Docs agent's effort, and the close step's" {
  arrive building '{"plans":["P1.1","P2.1"],"docs":["P2.1"]}' 3
}

@test "R107: fixing passes the Dev's fix effort and the close step's" {
  arrive fixing '{"groups":[["F1"],["F2","F3"]]}' 3
}

@test "R107: verifying passes QA's effort and the close step's" {
  arrive verifying '{"phases":["P1","P2"],"tier":"standard"}' 3
}

@test "R107: mapping passes the Scouts' survey and merge efforts and the close step's" {
  arrive mapping '{}' 7
}

@test "R107: researching passes the Scouts' survey and answer efforts" {
  arrive researching '{"question":"which test runner?"}' 5
}

@test "R107: tool search passes the Scouts' survey effort" {
  arrive tooling '{"stack":"a Python web app"}' 4
}

@test "R107: investigating passes the Debuggers' investigate and diagnose efforts" {
  arrive investigating '{"problem":"the page is blank"}' 4
}

@test "R107: fixing a bug with a diagnosis passes the Debugger's fix effort" {
  arrive investigating '{"problem":"the page is blank","fix":{"root_cause":"r","fix":"f"}}' 1
}

@test "R107: the effort is the only new option on a call; the model, label and schema stay as they were" {
  local out
  out=$(run_wf building "$(jq -nc --argjson t "$TABLE" '{plans: ["P1.1"], effort: $t, models: {dev: "sonnet"}}')")
  printf '%s' "$out" | jq -e '[.calls[] | .opts | keys] | all(.[]; . - ["agentType", "label", "phase", "schema", "model", "effort"] == [])' || { echo "$out"; false; }
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "dev P1.1")][0].opts | .model == "sonnet" and .effort == "dev.build"' || { echo "$out"; false; }
}

@test "R107: with no effort table, agents run as before: no effort option, no error, nothing logged about it" {
  local w out
  for w in planning building fixing verifying mapping researching tooling investigating; do
    out=$(run_wf "$w" "$(jq -nc --argjson r "$REQS" '{requirements: $r, plans: ["P1.1"], groups: [["F1"]], phases: ["P1"], question: "q", stack: "s", problem: "p", session: "s"}')") || { echo "$w: $out"; false; }
    printf '%s' "$out" | jq -e '(.calls | length) > 0 and all(.calls[]; .opts | has("effort") | not)' > /dev/null || { echo "$w: $out"; false; }
    printf '%s' "$out" | jq -e '[.logs[] | select(test("effort"; "i"))] == []' > /dev/null || { echo "$w: $out"; false; }
  done
}

@test "R107: a gap in the table leaves that call as before, and the others still get theirs" {
  local out
  out=$(run_wf building "$(jq -nc --argjson t "$TABLE" '{plans: ["P1.1"], session: "s", effort: ($t | del(.dev))}')")
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "dev P1.1")][0].opts | has("effort") | not' || { echo "$out"; false; }
  printf '%s' "$out" | jq -e '[.calls[] | select(.opts.label == "close run")][0].opts.effort == "lead.close"' || { echo "$out"; false; }
}

@test "R107: an effort that is not a table (text, null, a list) is ignored without an error" {
  local v out
  for v in '"high"' 'null' '["high"]' '7'; do
    out=$(run_wf verifying "$(jq -nc --argjson e "$v" '{phases: ["P1"], effort: $e}')") || { echo "$v: $out"; false; }
    printf '%s' "$out" | jq -e 'all(.calls[]; .opts | has("effort") | not)' > /dev/null || { echo "$v: $out"; false; }
  done
}
