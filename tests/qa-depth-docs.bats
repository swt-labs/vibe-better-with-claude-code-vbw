#!/usr/bin/env bats
# R71 (docs/rigor.md): how deeply QA checks a phase follows the size and risk
# of its change: a small, low-risk change (at most two files, no risk path) gets
# a quick check and never a deep one; a medium one at most a standard one; a
# large or risky one the depth its tier and profile give. vbw next --json
# carries the depth per phase as round.tiers (the rigor cells stay as they are)
# and the QA workflow uses it. A change to wording or documentation alone
# needs no new check and is closed without one; a check that is there (a
# project rule requires one) is still run and still decides. L1.

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

edit_record() { jq "$1" .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json; }

# qa_next PROFILE TIER FILES_JSON REASONS_JSON: a built, proven phase whose QA
# verdict is on other code, so QA is next; prints vbw next --json.
qa_next() {
  jq --arg p "$1" --arg t "$2" --argjson f "$3" --argjson r "$4" '
      .requirements = [{id:"R1", text:"Pay", proof:"auto", status:"proven", milestone: "M1"}]
      | .checks = [{id:"C1", req:"R1", run:["true"]}]
      | .settings.profile = $p
      | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone: "M1", tier: $t, reasons: $r, predicted: $t}]
      | .plans = [{id:"P1.1", phase:"P1", title:"Form", reqs:["R1"], files:$f, after:[], status:"done"}]
      | .phases[0].qa = {result: "pass", tier: "standard", tree: ("e" * 40), at: "2026-10-01T09:00:00Z"}' .vbw/record.json > "$TEST_ROOT/e.json"
  cp "$TEST_ROOT/e.json" .vbw/record.json
  local hash tree
  hash=$(vbw_contract_hash)
  tree=$(vbw_code_tree)
  edit_record ".evidence = {at: \"2026-10-01T09:00:00Z\", contract: \"$hash\", tree: \"$tree\", passed: true, checks: {}, commands: {}, scope: []}"
  vbw_consent_contract
  "$VBW" next --json < /dev/null
}

NONE='["requirements: 1","files: 1 (10 bytes)","risk: none","breaks: none","tests: project test command"]'
RISKY='["requirements: 1","files: 1 (10 bytes)","risk: payments (src/pay.js)","breaks: none","tests: project test command"]'
TWO='["a.js","b.js"]'
FIVE='["a.js","b.js","c.js","d.js","e.js"]'
TWELVE='["a.js","b.js","c.js","d.js","e.js","f.js","g.js","h.js","i.js","j.js","k.js","l.js"]'

@test "R71: a change of one or two files at low risk gets a quick check, even where the profile would give deep" {
  run qa_next quality standard '["a.js"]' "$NONE"
  echo "$output" | jq -e '.action == "qa" and .round.tiers.P1 == "quick"' || { echo "$output"; false; }
  # The profile's cell is untouched and so is the step's detail.
  echo "$output" | jq -e '.rigor.P1.qa == "deep" and .detail == {phases: ["P1"], tier: "deep"}' || { echo "$output"; false; }
  run qa_next quality standard "$TWO" "$NONE"
  echo "$output" | jq -e '.round.tiers.P1 == "quick"' || { echo "$output"; false; }
}

@test "R71: a change of three to nine files at low risk gets at most a standard check" {
  run qa_next quality standard "$FIVE" "$NONE"
  echo "$output" | jq -e '.round.tiers.P1 == "standard"' || { echo "$output"; false; }
  run qa_next balanced standard "$FIVE" "$NONE"
  echo "$output" | jq -e '.round.tiers.P1 == "standard"' || { echo "$output"; false; }
}

@test "R71: a larger change gets the deeper check its tier and profile give" {
  run qa_next quality standard "$TWELVE" "$NONE"
  echo "$output" | jq -e '.round.tiers.P1 == "deep"' || { echo "$output"; false; }
}

@test "R71: a riskier change gets the deeper check, however few files it touches" {
  run qa_next quality deep '["src/pay.js"]' "$RISKY"
  echo "$output" | jq -e '.round.tiers.P1 == "deep"' || { echo "$output"; false; }
}

@test "R71: the size never raises the check above what the profile gives" {
  run qa_next budget standard "$FIVE" "$NONE"
  echo "$output" | jq -e '.round.tiers.P1 == "quick"' || { echo "$output"; false; }
}

@test "R71: the QA workflow uses the depth chosen for each phase" {
  command -v node > /dev/null 2>&1 || skip "node is not installed"
  run node "$RUN" "$PLUGIN_ROOT/workflows/verifying.js" '{"phases":["P1","P2"],"tier":"deep","rigor":{"P1":{"qa":"deep"},"P2":{"qa":"deep"}},"round":{"tiers":{"P1":"quick","P2":"standard"}}}' '{}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '(.calls[0].prompt | contains("at the quick tier")) and (.calls[1].prompt | contains("at the standard tier"))' || { echo "$output"; false; }
  run node "$RUN" "$PLUGIN_ROOT/workflows/verifying.js" '{"phases":["P1"],"tier":"deep","rigor":{"P1":{"qa":"deep"}}}' '{}'
  printf '%s' "$output" | jq -e '.calls[0].prompt | contains("at the deep tier")' || { echo "$output"; false; }
}

# --- documentation and wording: no new check ---------------------------------

docs_project() {
  printf '# Notes\n\n## Requirements\n\n- R1 [auto] The README says how to install\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf '# App\n' > README.md
  git add README.md && git commit -q -m "docs: readme"
  DOC='{"phases":[{"id":"P1","title":"Install notes","reqs":["R1"],"goal":"the README explains installing","criteria":["it does"]}],
    "plans":[{"id":"P1.1","phase":"P1","title":"Install notes","reqs":["R1"],"files":["README.md"],"after":[],"role":"docs","tasks":["describe the install"]}],
    "checks":[]}'
}

@test "R71: a documentation-only requirement needs no check: the contract can be approved without one" {
  docs_project
  printf '%s' "$DOC" | "$VBW" apply > /dev/null
  vbw_run next --json
  echo "$output" | jq -e '.action == "approve"' || { echo "$output"; false; }
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R71: a documentation-only change is built, proved and closed without a check, with no QA for a small one" {
  docs_project
  printf '%s' "$DOC" | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  jq -e '.phases[0].tier == "express"' .vbw/record.json
  printf '# App\n\nInstall: run the installer.\n' > README.md
  "$VBW" commit P1.1 "docs(readme): install notes" > /dev/null
  vbw_run plan done P1.1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.requirements[0].status == "proven" and .evidence.passed == true' .vbw/record.json
  vbw_run next --json
  echo "$output" | jq -e '.action == "ship"' || { echo "$output"; false; }
}

@test "R71: a change to code still needs its check: approval is refused without one" {
  printf '# Notes\n\n## Requirements\n\n- R1 [auto] Adding works\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf 'echo 1\n' > calc.sh
  git add calc.sh && git commit -q -m "feat: calc"
  printf '%s' '{"phases":[{"id":"P1","title":"Add","reqs":["R1"],"goal":"g","criteria":["c"]}],"plans":[{"id":"P1.1","phase":"P1","title":"Add","reqs":["R1"],"files":["calc.sh"],"after":[]}],"checks":[]}' | "$VBW" apply > /dev/null
  vbw_run approve
  [ "$status" -ne 0 ]
  [[ "$output" == *"R1 has no check"* ]]
}

@test "R71: a plan that changes documentation and code together is not exempt" {
  printf '# Notes\n\n## Requirements\n\n- R1 [auto] Adding works and is documented\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf 'echo 1\n' > calc.sh
  git add calc.sh && git commit -q -m "feat: calc"
  printf '%s' '{"phases":[{"id":"P1","title":"Add","reqs":["R1"],"goal":"g","criteria":["c"]}],"plans":[{"id":"P1.1","phase":"P1","title":"Add","reqs":["R1"],"files":["calc.sh","README.md"],"after":[]}],"checks":[]}' | "$VBW" apply > /dev/null
  vbw_run approve
  [ "$status" -ne 0 ]
  [[ "$output" == *"R1 has no check"* ]]
}

@test "R71: a documentation requirement next to a code requirement: apply with rules accepts the documentation one without rules" {
  printf '# Notes\n\n## Requirements\n\n- R1 [auto] The README says how to install\n- R2 [auto] Adding works\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf 'echo 1\n' > calc.sh
  printf 'exit 1\n' > t.sh
  printf '# App\n' > README.md
  git add calc.sh README.md t.sh && git commit -q -m "feat: files"
  run bash -c 'printf "%s" "$1" | "$2" apply' _ '{"phases":[{"id":"P1","title":"Install notes","reqs":["R1"],"goal":"g","criteria":["c"]},{"id":"P2","title":"Add","reqs":["R2"],"goal":"g","criteria":["c"]}],
    "plans":[{"id":"P1.1","phase":"P1","title":"Install notes","reqs":["R1"],"files":["README.md"],"after":[],"role":"docs"},{"id":"P2.1","phase":"P2","title":"Add","reqs":["R2"],"files":["calc.sh"],"after":[]}],
    "checks":[{"id":"C1","req":"R2","run":["sh","t.sh"],"files":["t.sh"]}],"rules":[{"req":"R2","text":"adding works","check":"C1"}]}' "$VBW"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "R71: when a project rule makes the Lead write a check for the documentation anyway, that check runs and decides" {
  docs_project
  printf 'grep -q Install README.md\n' > t.sh
  git add t.sh && git commit -q -m "test: readme says install"
  printf '%s' "$DOC" | jq -c '.checks = [{id: "C1", req: "R1", run: ["sh", "t.sh"], files: ["t.sh"]}] | .rules = [{req: "R1", text: "the README says how to install", check: "C1"}]' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf '# App\n\nNothing here.\n' > README.md
  "$VBW" commit P1.1 "docs(readme): nothing" > /dev/null
  vbw_run prove
  [ "$status" -ne 0 ]
  jq -e '.requirements[0].status == "failing" and .evidence.passed == false' .vbw/record.json
}

@test "R71: documentation alone is not 'standard' for lack of a project test command" {
  docs_project
  printf '%s' "$DOC" | "$VBW" apply > /dev/null
  jq -e '.phases[0].tier == "express"' .vbw/record.json
}

@test "R71: the Lead is told the documentation exemption and that a project rule requiring a check overrides it" {
  local f="$PLUGIN_ROOT/agents/lead.md"
  grep -qi 'documentation' "$f"
  grep -qi 'no new check' "$f"
  grep -qi 'project rule' "$f"
}
