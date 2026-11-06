#!/usr/bin/env bats
# R145 (docs/rigor.md): a phase VBW raised to a higher tier (an escalation: a
# blocked plan, a fix needing another round, a failed QA) is verified at the QA
# depth of its raised tier's cell, whatever its number of files; the
# small-change discount (R71: at most two files and no risk path is quick,
# three to nine at most standard) applies only to phases that never escalated.
# A tier forced with vbw config rigor is not an escalation. vbw next --json
# carries the depth per phase as round.tiers at the qa step. L1.

load helper
load rigor-helper
load fixture-helper

# The tiny flow's project, planned and not yet approved: built once per file.
setup_file() { fixture_build flow rigor_flow_setup; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# to_qa: from the record as the real flow left it, make the phase built,
# proven and due for QA again (its pass is on other code), with a fresh full
# proof; prints vbw next --json. The new evidence drops what a real proof wrote
# (own.copy_slots), so the schema goes back to the floor.
to_qa() {
  edit_record '.plans |= map(.status = "done") | .requirements |= map(.status = "proven")
    | .fixes |= map(.status = "closed") | .lease = null
    | .phases[0].qa = {result: "pass", tier: "standard", tree: ("e" * 40), at: "2026-10-01T09:00:00Z"}'
  local hash tree
  hash=$(vbw_contract_hash)
  tree=$(vbw_code_tree)
  edit_record ".evidence = {at: \"2026-10-01T09:00:00Z\", contract: \"$hash\", tree: \"$tree\", full: true, passed: true, checks: {}, commands: {}, scope: []} | .schema = 4"
  vbw_consent_contract
  "$VBW" next --json < /dev/null
}

# qa_next PROFILE TIER FILES_JSON ESCALATIONS_JSON [REASONS_JSON]: in a new
# project under TEST_ROOT (vbw_setup first), a built, proven phase P1 with these
# files and escalations, due for QA; prints vbw next --json.
qa_next() {
  cd "$(mktemp -d "$TEST_ROOT/project.XXXXXX")" || return 1
  vbw_git_project
  "$VBW" init > /dev/null
  jq --arg p "$1" --arg t "$2" --argjson f "$3" --argjson e "$4" --argjson r "${5:-$NONE}" '
      .requirements = [{id:"R1", text:"Pay", proof:"auto", status:"proven", milestone: "M1"}]
      | .checks = [{id:"C1", req:"R1", run:["true"]}]
      | .settings.profile = $p
      | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone: "M1", tier: $t, reasons: $r, predicted: "express"}
                   + (if ($e | length) > 0 then {escalations: $e} else {} end)]
      | .plans = [{id:"P1.1", phase:"P1", title:"Form", reqs:["R1"], files:$f, after:[], status:"done"}]
      | .phases[0].qa = {result: "pass", tier: "standard", tree: ("e" * 40), at: "2026-10-01T09:00:00Z"}' .vbw/record.json > "$TEST_ROOT/e.json"
  cp "$TEST_ROOT/e.json" .vbw/record.json
  local hash tree
  hash=$(vbw_contract_hash)
  tree=$(vbw_code_tree)
  edit_record ".evidence = {at: \"2026-10-01T09:00:00Z\", contract: \"$hash\", tree: \"$tree\", full: true, passed: true, checks: {}, commands: {}, scope: []}"
  vbw_consent_contract
  "$VBW" next --json < /dev/null
}

NONE='["requirements: 1","files: 1 (10 bytes)","risk: none","breaks: none","tests: project test command"]'
FORCED='["requirements: 1","files: 5 (50 bytes)","risk: none","breaks: none","tests: project test command","forced: vbw config rigor deep"]'
FIVE='["a.js","b.js","c.js","d.js","e.js"]'
TO_DEEP='[{"at":"2026-10-01T08:00:00Z","from":"express","to":"standard","reason":"plan P1.1 blocked: needs the API key"},
          {"at":"2026-10-01T08:30:00Z","from":"standard","to":"deep","reason":"fix F1 needs a second round"}]'
TO_STANDARD='[{"at":"2026-10-01T08:00:00Z","from":"express","to":"standard","reason":"QA found a problem in R1"}]'

# depth: the QA depth vbw next gave phase P1 in the last output.
depth() { printf '%s' "$output" | jq -r '.round.tiers.P1'; }

@test "R145: the flow's phase is small and low-risk (one file, no risk path), so only an escalation can keep it from the quick check" {
  fixture_copy flow
  rigor_flow_approve
  phase_json '.phases[0].tier == "express" and (.phases[0].reasons | index("risk: none")) != null
    and ([.plans[] | select(.phase == "P1") | .files[]] | length) == 1'
}

@test "R145: a phase raised by a blocked plan is verified at its raised tier's depth, not quick" {
  fixture_copy flow
  rigor_flow_approve
  "$VBW" plan block P1.1 "needs the API key" > /dev/null
  phase_json '.phases[0].tier == "standard" and (.phases[0].escalations | length) == 1'
  run to_qa
  printf '%s' "$output" | jq -e '.action == "qa"' > /dev/null || { echo "$output"; false; }
  [ "$(depth)" = "$(printf '%s' "$output" | jq -r '.rigor.P1.qa')" ] || { echo "$output"; false; }
  [ "$(depth)" = standard ] || { echo "$output"; false; }
}

@test "R145: a phase raised by a fix needing a second round is verified at its raised tier's depth, not quick" {
  fixture_copy flow
  rigor_flow_approve
  printf 'wrong\n' > src/greet.txt
  "$VBW" commit P1.1 "feat(greet): wrong" > /dev/null
  edit_record '.plans[0].status = "done"'
  "$VBW" prove > /dev/null || true
  edit_record '.fixes[0].status = "fixed"'
  "$VBW" prove > /dev/null || true
  phase_json '.phases[0].tier == "standard" and (.phases[0].escalations[-1].reason | contains("second round"))'
  run to_qa
  [ "$(depth)" = standard ] || { echo "$output"; false; }
}

@test "R145: a phase raised by a failed QA is verified at its raised tier's depth, not quick" {
  fixture_copy flow
  rigor_flow_build
  "$VBW" qa finding R1 "the greeting is missing" > /dev/null
  phase_json '.phases[0].tier == "standard" and (.phases[0].escalations[-1].reason | contains("QA"))'
  run to_qa
  [ "$(depth)" = standard ] || { echo "$output"; false; }
}

@test "R145: an escalated phase of three to nine files with no risk path raised to deep is verified at deep, not capped at standard" {
  vbw_setup
  run qa_next balanced deep "$FIVE" "$TO_DEEP"
  [ "$(depth)" = deep ] || { echo "$output"; false; }
  run qa_next quality standard "$FIVE" "$TO_STANDARD"
  [ "$(depth)" = deep ] || { echo "$output"; false; }
}

@test "R145: an escalated phase of one or two files is never lowered to quick" {
  vbw_setup
  run qa_next balanced deep '["a.js"]' "$TO_DEEP"
  [ "$(depth)" = deep ] || { echo "$output"; false; }
  run qa_next balanced standard '["a.js","b.js"]' "$TO_STANDARD"
  [ "$(depth)" = standard ] || { echo "$output"; false; }
}

@test "R145: the raised depth never exceeds what the profile's cell gives the raised tier" {
  vbw_setup
  run qa_next budget standard "$FIVE" "$TO_STANDARD"
  [ "$(depth)" = quick ] || { echo "$output"; false; }
}

@test "R145: a phase that never escalated keeps the small-change discount" {
  vbw_setup
  run qa_next balanced deep '["a.js","b.js"]' '[]'
  [ "$(depth)" = quick ] || { echo "$output"; false; }
  run qa_next balanced deep "$FIVE" '[]'
  [ "$(depth)" = standard ] || { echo "$output"; false; }
}

@test "R145: a tier forced with vbw config rigor, never escalated, keeps the small-change discount" {
  fixture_copy flow
  "$VBW" config rigor deep > /dev/null
  rigor_flow_approve
  phase_json '.phases[0].tier == "deep" and ((.phases[0].escalations // []) | length) == 0'
  run to_qa
  [ "$(depth)" = quick ] || { echo "$output"; false; }
  run qa_next balanced deep "$FIVE" '[]' "$FORCED"
  [ "$(depth)" = standard ] || { echo "$output"; false; }
}

@test "R145: the QA round's tier is the raised depth when an escalated phase is among those to verify" {
  vbw_setup
  run qa_next balanced deep "$FIVE" "$TO_DEEP"
  printf '%s' "$output" | jq -e '.action == "qa" and .detail.tier == "deep" and .round.tiers.P1 == "deep"' || { echo "$output"; false; }
}
