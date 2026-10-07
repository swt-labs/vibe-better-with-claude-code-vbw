#!/usr/bin/env bats
# R102 (L1): the approval view (vbw show contract) shows the number of build
# waves and how many plans the widest wave runs at once, counted as vbw next
# schedules them: a plan waits for its "after" plans, and plans that share a
# file never run in the same wave. A phase that cannot be split shows one plan
# per wave honestly. Format: "build waves: N (the widest runs M plan(s) at once)".

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
}
teardown() { vbw_teardown; }

# plans JSON_ARRAY: the milestone's plans, as [{id, files, after}].
plans() {
  jq --argjson p "$1" '.checks = [{id:"C1", req:"R1", run:["true"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [$p[] | {id, phase:"P1", title:.id, reqs:["R1"], files, after:(.after // []), status:(.status // "planned")}]' \
    .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
}

waves_line() { "$VBW" show contract < /dev/null | grep '^build waves:'; }

@test "R102: independent plans on separate files are one wave that runs them all at once" {
  plans '[{"id":"P1.1","files":["a.js"]},{"id":"P1.2","files":["b.js"]},{"id":"P1.3","files":["c.js"]},{"id":"P1.4","files":["d.js"]}]'
  [ "$(waves_line)" = "build waves: 1 (the widest runs 4 plans at once)" ]
}

@test "R102: plans that wait for others and plans that share a file fall into later waves" {
  plans '[{"id":"P1.1","files":["a.js"]},{"id":"P1.2","files":["b.js"]},{"id":"P1.3","files":["c.js"],"after":["P1.1","P1.2"]},{"id":"P1.4","files":["a.js"]}]'
  [ "$(waves_line)" = "build waves: 2 (the widest runs 2 plans at once)" ]
}

@test "R102: a phase that cannot be split shows one plan per wave, not an inflated figure" {
  plans '[{"id":"P1.1","files":["a.js"]},{"id":"P1.2","files":["b.js"],"after":["P1.1"]},{"id":"P1.3","files":["c.js"],"after":["P1.2"]}]'
  [ "$(waves_line)" = "build waves: 3 (the widest runs 1 plan at once)" ]
  plans '[{"id":"P1.1","files":["a.js"]},{"id":"P1.2","files":["a.js"]}]'
  [ "$(waves_line)" = "build waves: 2 (the widest runs 1 plan at once)" ]
}

@test "R102: a plan on a directory shares a file with plans under it" {
  plans '[{"id":"P1.1","files":["src/"]},{"id":"P1.2","files":["src/x.js"]}]'
  [ "$(waves_line)" = "build waves: 2 (the widest runs 1 plan at once)" ]
}

@test "R102: the line comes with the plans, before the approval question" {
  plans '[{"id":"P1.1","files":["a.js"]}]'
  run "$VBW" show contract < /dev/null
  [[ "$output" == *"plans:"*"build waves:"*"approval question:"* ]] || { echo "$output"; false; }
}

@test "R102: a blocked plan is skipped, as vbw next skips it" {
  plans '[{"id":"P1.1","files":["a.js"]},{"id":"P1.2","files":["b.js"],"status":"blocked"},{"id":"P1.3","files":["c.js"]}]'
  [ "$(waves_line)" = "build waves: 1 (the widest runs 2 plans at once)" ]
}

@test "R102: the waves line and vbw next share one wave rule (D166): no copy of it in cmd-show.sh or next.jq" {
  ! grep -qE 'def (overlaps|wave)\(' "$PLUGIN_ROOT/lib/cmd-show.sh" "$PLUGIN_ROOT/lib/next.jq"
  grep -qE 'def wave\(' "$PLUGIN_ROOT/lib/record.sh"
  plans '[{"id":"P1.1","files":["a.js"]},{"id":"P1.2","files":["a.js"]},{"id":"P1.3","files":["b.js"]}]'
  git add -A > /dev/null && git commit -q -m "chore(vbw): plan" && "$VBW" approve > /dev/null
  [ "$("$VBW" next --json < /dev/null | jq -r '.detail.plans | length')" = 2 ]
  [ "$(waves_line)" = "build waves: 2 (the widest runs 2 plans at once)" ]
}
