#!/usr/bin/env bats
# The project's commands live in .vbw/spec.md (## Commands), like the
# requirements: vbw init writes the detected ones there as a suggestion, the
# user edits or deletes lines, vbw spec sync brings the record in line, and a
# command the user has not approved sends vbw next back to approval.

load helper

setup() {
  vbw_setup
  vbw_git_project
}

teardown() { vbw_teardown; }

# commands_section BODY: replace (or add) the ## Commands section of spec.md.
commands_section() {
  awk 'BEGIN { skip = 0 } /^## / { skip = ($0 ~ /^## Commands[ \t]*$/) } !skip' .vbw/spec.md > "$TEST_ROOT/s.md"
  printf '\n## Commands\n\n%s\n' "$1" >> "$TEST_ROOT/s.md"
  cp "$TEST_ROOT/s.md" .vbw/spec.md
}

@test "init writes the detected commands into spec.md and the record" {
  printf '[pytest]\n' > pytest.ini
  "$VBW" init > /dev/null
  grep -qx '## Commands' .vbw/spec.md
  grep -qx -- '- test: python -m pytest' .vbw/spec.md
  jq -e '.commands == {test: ["python", "-m", "pytest"]}' .vbw/record.json
  vbw_run spec check
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 command"* ]]
}

@test "sync makes the record's commands exactly the spec's: changed, added and removed" {
  printf '[pytest]\n' > pytest.ini
  "$VBW" init > /dev/null
  commands_section '- test: cargo test --locked --workspace --manifest-path market_recorder/Cargo.toml
- pytest: conda run -n portfolium python -m pytest -q market_recorder/'
  vbw_run spec sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"changed command test"* && "$output" == *"added command pytest"* ]]
  jq -e '.commands == {
    test: ["cargo", "test", "--locked", "--workspace", "--manifest-path", "market_recorder/Cargo.toml"],
    pytest: ["conda", "run", "-n", "portfolium", "python", "-m", "pytest", "-q", "market_recorder/"]}' .vbw/record.json
  commands_section '- pytest: conda run -n portfolium python -m pytest -q market_recorder/'
  vbw_run spec sync
  [[ "$output" == *"removed command test"* ]]
  jq -e '.commands | keys == ["pytest"]' .vbw/record.json
}

@test "an empty Commands section removes every command" {
  printf '[pytest]\n' > pytest.ini
  "$VBW" init > /dev/null
  commands_section ''
  "$VBW" spec sync > /dev/null
  jq -e '.commands == {}' .vbw/record.json
}

@test "a spec without a Commands section leaves the record's commands as they are" {
  printf '[pytest]\n' > pytest.ini
  "$VBW" init > /dev/null
  awk 'BEGIN { skip = 0 } /^## / { skip = ($0 ~ /^## Commands/) } !skip' .vbw/spec.md > "$TEST_ROOT/s.md"
  cp "$TEST_ROOT/s.md" .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq -e '.commands == {test: ["python", "-m", "pytest"]}' .vbw/record.json
}

@test "a JSON array keeps an argument that contains spaces" {
  "$VBW" init > /dev/null
  commands_section '- test: ["sh", "run tests.sh", "--fast"]'
  "$VBW" spec sync > /dev/null
  jq -e '.commands == {test: ["sh", "run tests.sh", "--fast"]}' .vbw/record.json
}

@test "malformed command lines and duplicate names are errors with line numbers; nothing changes" {
  printf '[pytest]\n' > pytest.ini
  "$VBW" init > /dev/null
  commands_section '- test
- lint: ["unclosed"
- build: make
- build: make all'
  vbw_run spec sync
  [ "$status" -eq 1 ]
  [[ "$output" == *"line "*"- name: command"* ]]
  [[ "$output" == *"build is defined twice"* ]]
  jq -e '.commands == {test: ["python", "-m", "pytest"]}' .vbw/record.json
}

@test "after the commands change, next asks for approval until the user approves them" {
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] Pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id: "C1", req: "R1", run: ["true"]}]
    | .phases = [{id: "P1", title: "Pay", reqs: ["R1"], milestone: "M1"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["pay.txt"], after: [], status: "planned"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  "$VBW" approve > /dev/null
  vbw_run next --json
  echo "$output" | jq -e '.action == "build"'
  commands_section '- test: cargo test --manifest-path market_recorder/Cargo.toml'
  "$VBW" spec sync > /dev/null
  vbw_run next --json
  echo "$output" | jq -e '.action == "approve"'
  vbw_run show contract
  [[ "$output" == *"test: cargo test --manifest-path market_recorder/Cargo.toml"* ]]
  "$VBW" approve > /dev/null
  vbw_run next --json
  echo "$output" | jq -e '.action == "build"'
}

@test "approval is refused while the spec's commands and the record's differ" {
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] Pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id: "C1", req: "R1", run: ["true"]}]' .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  commands_section '- test: make test'
  vbw_run approve
  [ "$status" -eq 1 ]
  [[ "$output" == *"spec.md and the record differ (vbw spec sync)"* ]]
}

@test "vbw config rigor re-tiers unstarted phases only, forced or recomputed" {
  load rigor-helper
  rigor_project 1
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  edit_record '.phases[0].tier = "express"'
  "$VBW" config rigor deep > /dev/null
  jq -e '.phases[0].tier == "deep" and (.phases[0].reasons | index("forced: vbw config rigor deep"))' .vbw/record.json
  "$VBW" config rigor auto > /dev/null
  jq -e '.phases[0].tier == "express" and (.phases[0].reasons | any(.[]; test("forced")) | not)' .vbw/record.json
  edit_record '.plans[0].status = "done"'
  "$VBW" config rigor deep > /dev/null
  jq -e '.phases[0].tier == "express"' .vbw/record.json
  edit_record '.plans[0].status = "planned" | .phases[0].escalations = [{at: "2026-10-03T10:00:00Z", from: "express", to: "standard", reason: "x"}]'
  "$VBW" config rigor standard > /dev/null
  jq -e '.phases[0].tier == "express"' .vbw/record.json
}

@test "a phase the Architect raised to deep is deep again after config rigor express then auto" {
  load rigor-helper
  rigor_project 1
  rigor_apply "$(rigor_doc 1 deep src/note.txt)" > /dev/null
  jq -e '.phases[0].tier == "deep" and .phases[0].proposed == "deep"' .vbw/record.json
  "$VBW" config rigor express > /dev/null
  jq -e '.phases[0].tier == "express"' .vbw/record.json
  "$VBW" config rigor auto > /dev/null
  jq -e '.phases[0].tier == "deep" and (.phases[0].reasons | index("raised by the Architect")) and (.phases[0].reasons | any(.[]; test("forced")) | not)' .vbw/record.json
  rigor_apply "$(rigor_doc 1 "" src/note.txt)" > /dev/null
  jq -e '.phases[0] | has("proposed") | not' .vbw/record.json
}
