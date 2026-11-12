#!/usr/bin/env bats
# R178 (F202; docs/proof.md, An approval whose commit fails): a project command
# or test-file form changed after the contract was approved is approved on its
# own by the user's vbw approve, with its decision ("Project commands approved:
# ...") and its commit ("chore(vbw): approve commands") before the consent, as
# the loop does with its own words (tests/loop-approve.bats); a failed commit
# leaves no decision and no consent; a second approve adds nothing. L1: a git
# hook makes the commit fail.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"planned"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  HOOK="$(git rev-parse --git-path hooks)/pre-commit"
  mkdir -p "$(dirname "$HOOK")"
  printf '#!/bin/sh\necho "refused by the project hook: lint failed" >&2\nexit 1\n' > "$HOOK"
  chmod +x "$HOOK"
}

teardown() { vbw_teardown; }

consent() { cat "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/consent.json"; }
command_decisions() { jq '[.decisions[] | select(.text | startswith("Project commands approved"))] | length' .vbw/record.json; }
# with_commands: after the contract's approval, a project command is added to the spec and synced, so only it awaits approval.
with_commands() {
  rm -f "$HOOK"
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  printf 'true\n' > tests/run.sh
  printf '\n## Commands\n\n- test: sh tests/run.sh\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore(test): a test command"
  vbw_run next --json
  echo "$output" | jq -e '.action == "approve"' > /dev/null || { echo "$output"; return 1; }
}

@test "R178 (F202): a project command changed after the approval is approved on its own by vbw approve, with its decision and commit; a second approve adds nothing" {
  with_commands
  local d
  d=$(jq '.decisions | length' .vbw/record.json)
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq '.decisions | length' .vbw/record.json)" -eq $((d + 1)) ]
  jq -e '.decisions[-1].text | startswith("Project commands approved: ") and contains("test (sh tests/run.sh)") and (contains("by the loop") | not)' .vbw/record.json || { jq '.decisions[-1]' .vbw/record.json; false; }
  [ "$(git log -1 --format=%s)" = "chore(vbw): approve commands" ] || { git log -3 --format=%s; false; }
  consent | jq -e 'any(.granted[]; .kind == "command" and .detail.name == "test")'
  [ -z "$(git status --porcelain -- .vbw)" ]
  vbw_run next --json
  echo "$output" | jq -e '.action != "approve"' > /dev/null || { echo "$output"; false; }
  vbw_run approve
  [ "$status" -eq 0 ]
  [ "$(jq '.decisions | length' .vbw/record.json)" -eq $((d + 1)) ]
  [ "$(git log -1 --format=%s)" = "chore(vbw): approve commands" ]
}

@test "R178 (F202): when the commit of a command's approval fails, no decision and no consent are kept, and the next try starts clean" {
  with_commands
  local d
  d=$(jq '.decisions | length' .vbw/record.json)
  printf '#!/bin/sh\necho "refused by the project hook: lint failed" >&2\nexit 1\n' > "$HOOK"
  chmod +x "$HOOK"
  vbw_run approve
  [ "$status" -ne 0 ]
  [[ "$output" == *"lint failed"* && "$output" == *"the commands are not approved"* ]] || { echo "$output"; false; }
  [ "$(jq '.decisions | length' .vbw/record.json)" -eq "$d" ]
  [ "$(command_decisions)" -eq 0 ]
  ! consent | jq -e 'any(.granted[]; .kind == "command")' > /dev/null || false
  # The refused commit stays the next step until a commit succeeds, and says to approve again (R298).
  vbw_run next --json
  echo "$output" | jq -e '.action == "commit" and (.instruction | contains("vbw approve"))' > /dev/null || { echo "$output"; false; }
  rm -f "$HOOK"
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(command_decisions)" -eq 1 ]
  consent | jq -e 'any(.granted[]; .kind == "command" and .detail.name == "test")'
}

@test "R178 (F202): docs/proof.md describes the approval of a changed command and its failing commit" {
  grep -q 'Project commands approved' "$REPO_ROOT/docs/proof.md"
  grep -q 'chore(vbw): approve commands' "$REPO_ROOT/docs/proof.md"
  grep -q 'the commands are not' "$REPO_ROOT/docs/proof.md"
}
