#!/usr/bin/env bats
# R182 (plugin/workflows/fixing.js, plugin/agents/dev.md, plugin/agents/lead.md):
# a fix round runs vbw fix done once, for every fix whose Dev reported done,
# after every Dev has returned. No Dev runs it: each commits its fix and checks
# it with vbw check on its own fixes' checks. With a session the closing Lead
# runs it before vbw run confirm and vbw run end; without one an agent of its
# own runs it. A fix whose Dev was blocked or stopped is left out and named with
# its status; the result says which fixes closed and which stayed open; an
# agent that stops or reports a failure leaves the exact command to run by
# hand, and the round is not complete. L1, with stubbed agents
# (tests/helpers/run-workflow.js): no model runs.

load helper

RUN="$BATS_TEST_DIRNAME/helpers/run-workflow.js"
WF="$PLUGIN_ROOT/workflows/fixing.js"
DEV="$PLUGIN_ROOT/agents/dev.md"
LEAD="$PLUGIN_ROOT/agents/lead.md"
DONE='{"status":"done","summary":"s","notes":[]}'
BLOCKED='{"status":"blocked","summary":"needs a decision","notes":[]}'
# R306: the closing (or fix done) agent also returns what vbw run state printed, as text.
ALL='{\"open\":false,\"recorded\":{\"F1\":true,\"F2\":true,\"F3\":true,\"F4\":true}}'
OK='{"fixdone":"ran","closed":["F1","F3","F2","F4"],"open":[],"ended":true,"recorded":true,"report":"all recorded; run ended","state":"'"$ALL"'"}'
ALONE='{"fixdone":"ran","closed":["F1","F3","F2","F4"],"open":[],"report":"all closed","state":"'"$ALL"'"}'

setup() { command -v node > /dev/null 2>&1 || skip "node is not installed"; }

# wf ARGS RESPONSES: the stubbed run of the fixing workflow, as JSON.
wf() { node "$RUN" "$WF" "$1" "$2"; }

# commands: every "vbw fix done F..." instruction in every prompt, as a JSON array of strings.
COMMANDS='[.calls[].prompt | scan("vbw fix done(?: F[0-9]+)+")]'

# three_groups RESPONSES [SESSION]: a round of three groups, every Dev answering as RESPONSES says.
three_groups() {
  local args='{"groups":[["F1","F3"],["F2"],["F4"]]}'
  [ -z "${2:-}" ] || args=$(jq -nc --arg s "$2" '{groups: [["F1","F3"],["F2"],["F4"]], session: $s}')
  wf "$args" "$1"
}

all_done() { jq -nc --argjson d "$DONE" --argjson k "${1:-$OK}" --argjson a "${2:-$ALONE}" '{"F1+F3": $d, "F2": $d, "F4": $d, "close run": $k, "fix done": $a}'; }

@test "R182: three groups: the prompts hold exactly one instruction to run vbw fix done, naming every done fix" {
  run three_groups "$(all_done)" s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e "$COMMANDS"' | length == 1' > /dev/null || { printf '%s' "$output" | jq -c "$COMMANDS"; false; }
  printf '%s' "$output" | jq -e "$COMMANDS"'[0] | ltrimstr("vbw fix done ") | split(" ") | sort == ["F1","F2","F3","F4"]' > /dev/null \
    || { printf '%s' "$output" | jq -c "$COMMANDS"; false; }
}

@test "R182: the round's vbw fix done comes after every Dev has returned" {
  run three_groups "$(all_done)" s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '
    [.calls | to_entries[] | select(.value.opts.agentType == "vbw:dev") | .key] as $devs
    | [.calls | to_entries[] | select(.value.prompt | test("vbw fix done F[0-9]")) | .key] as $fd
    | ($devs | length) == 3 and ($fd | length) == 1 and $fd[0] > ($devs | max)' > /dev/null || { echo "$output"; false; }
}

@test "R182: with one group (N = 1) the round still runs vbw fix done exactly once" {
  run wf '{"groups":[["F1"]],"session":"s1"}' "$(jq -nc --argjson d "$DONE" --argjson k "$OK" '{"F1": $d, "close run": $k}')"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e "$COMMANDS"' == ["vbw fix done F1"]' > /dev/null || { printf '%s' "$output" | jq -c "$COMMANDS"; false; }
}

@test "R182: with a session, the closing Lead runs vbw fix done first, then vbw run confirm and vbw run end" {
  run three_groups "$(all_done)" s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.calls[-1] as $c | $c.opts.label == "close run" and $c.opts.agentType == "vbw:lead"
    and ($c.prompt | test("vbw fix done F[0-9]"))
    and (($c.prompt | index("vbw fix done F")) < ($c.prompt | index("vbw run confirm")))
    and (($c.prompt | index("vbw run confirm")) < ($c.prompt | index("vbw run end")))' > /dev/null || { echo "$output"; false; }
}

@test "R182: a vbw fix done past one shell command's 10-minute limit is waited for, and its output read, before the run is confirmed" {
  run three_groups "$(all_done)" s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '[.calls[] | select(.prompt | test("vbw fix done F[0-9]"))][0].prompt
    | test("10.minute"; "i") and test("background"; "i") and test("wait"; "i") and test("whole output"; "i")' > /dev/null \
    || { echo "$output"; false; }
}

@test "R182: without a session the round's vbw fix done still runs, by an agent of its own, before the workflow returns" {
  run three_groups "$(all_done)"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e "$COMMANDS"' | length == 1' > /dev/null || { printf '%s' "$output" | jq -c "$COMMANDS"; false; }
  printf '%s' "$output" | jq -e '.calls[-1].opts.label == "fix done" and .calls[-1].opts.agentType == "vbw:lead"
    and (.calls[-1].opts.schema | type == "object")
    and ([.calls[] | select(.opts.label == "close run")] | length == 0)
    and .result.complete == true and (.result.fixdone.closed | sort) == ["F1","F2","F3","F4"]' > /dev/null || { echo "$output"; false; }
}

@test "R182: no Dev is told to run vbw fix done: each commits its fix and checks it with vbw check on its own fixes' checks" {
  run three_groups "$(all_done)" s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '[.calls[] | select(.opts.agentType == "vbw:dev") | .prompt] as $p
    | ($p | length) == 3
    and all($p[]; (test("vbw fix done F[0-9]") | not) and contains("Do not run vbw fix done")
      and test("commit"; "i") and contains("vbw check") and contains("only your fixes'"'"' checks")
      and contains("Do not run the project'"'"'s test command"))' > /dev/null || { echo "$output"; false; }
}

@test "R182: a blocked fix and a fix whose Dev stopped are left out of vbw fix done and named with their status" {
  run wf '{"groups":[["F1"],["F2"],["F3"]],"session":"s1"}' \
    "$(jq -nc --argjson d "$DONE" --argjson b "$BLOCKED" '{"F1": $d, "F2": $b, "close run": {fixdone: "ran", closed: ["F1"], open: [], ended: true, recorded: false, report: "F2: not recorded (open); F3: not recorded (open)"}}')"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e "$COMMANDS"' == ["vbw fix done F1"]' > /dev/null || { printf '%s' "$output" | jq -c "$COMMANDS"; false; }
  printf '%s' "$output" | jq -e '(.result.fixdone.left_out | sort_by(.fix)) == [{fix: "F2", status: "blocked"}, {fix: "F3", status: "interrupted"}]
    and (.calls[-1].prompt | contains("vbw run confirm F1 F2 F3"))
    and (.logs | any(contains("F2") and contains("blocked")) and any(contains("F3") and contains("interrupted")))
    and .result.complete == false' > /dev/null || { echo "$output"; false; }
}

@test "R182: when no Dev reported done, no vbw fix done runs" {
  run wf '{"groups":[["F1"],["F2"]],"session":"s1"}' \
    "$(jq -nc --argjson b "$BLOCKED" '{"F1": $b, "F2": $b, "close run": {fixdone: "ran", closed: [], open: [], ended: true, recorded: false, report: "F1, F2 not recorded"}}')"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e "$COMMANDS"' == []' > /dev/null || { printf '%s' "$output" | jq -c "$COMMANDS"; false; }
  printf '%s' "$output" | jq -e '(.result.fixdone.left_out | length) == 2 and .result.complete == false' > /dev/null || { echo "$output"; false; }
}

@test "R182: the result says which fixes closed and which stayed open, each open one with its reason" {
  local k='{"fixdone":"ran","closed":["F1","F3","F4"],"open":[{"fix":"F2","reason":"F2 broke finished work: C3 fail"}],"ended":true,"recorded":false,"report":"F2: not recorded (open)","state":"{\"open\":false,\"recorded\":{\"F1\":true,\"F2\":false,\"F3\":true,\"F4\":true}}"}'
  run three_groups "$(all_done "$k")" s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '(.result.fixdone.closed | sort) == ["F1","F3","F4"]
    and .result.fixdone.open == [{fix: "F2", reason: "F2 broke finished work: C3 fail"}]
    and (.logs | any(contains("F2") and contains("broke finished work: C3 fail")))
    and .result.complete == false' > /dev/null || { echo "$output"; false; }
}

@test "R182: the agent answering for vbw fix done is asked which fixes closed and which stayed open" {
  run three_groups "$(all_done)" s1
  printf '%s' "$output" | jq -e '.calls[-1].opts.schema.required as $r | ($r | index("fixdone")) != null and ($r | index("closed")) != null and ($r | index("open")) != null' > /dev/null \
    || { echo "$output"; false; }
  run three_groups "$(all_done)"
  printf '%s' "$output" | jq -e '.calls[-1].opts.schema.required as $r | ($r | index("fixdone")) != null and ($r | index("closed")) != null and ($r | index("open")) != null' > /dev/null \
    || { echo "$output"; false; }
}

@test "R182: when the closing Lead stops, the log gives the exact vbw fix done to run by hand, and the round is not complete" {
  run three_groups "$(jq -nc --argjson d "$DONE" '{"F1+F3": $d, "F2": $d, "F4": $d, "close run": null}')" s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '[.logs[] | select(test("run by hand")) | scan("vbw fix done(?: F[0-9]+)+")] as $m
    | ($m | length) >= 1 and ($m[0] | ltrimstr("vbw fix done ") | split(" ") | sort) == ["F1","F2","F3","F4"]
    and .result.complete == false' > /dev/null || { echo "$output"; false; }
}

@test "R182: when the agent reports that vbw fix done failed, the log gives the command to run by hand, and the round is not complete" {
  local k='{"fixdone":"failed","closed":[],"open":[],"ended":true,"recorded":false,"report":"vbw fix done stopped with an error"}'
  run three_groups "$(all_done "$k")" s1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '[.logs[] | select(test("run by hand")) | scan("vbw fix done(?: F[0-9]+)+")] | length >= 1' > /dev/null || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.result.complete == false' > /dev/null || { echo "$output"; false; }
}

@test "R182: without a session, a stopped or failed vbw fix done agent leaves the command to run by hand, and the round is not complete" {
  run three_groups "$(all_done "$OK" 'null')"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '([.logs[] | select(test("run by hand")) | scan("vbw fix done(?: F[0-9]+)+")] | length >= 1) and .result.complete == false' > /dev/null \
    || { echo "$output"; false; }
  run three_groups "$(all_done "$OK" '{"fixdone":"failed","closed":[],"open":[],"report":"it stopped"}')"
  printf '%s' "$output" | jq -e '([.logs[] | select(test("run by hand")) | scan("vbw fix done(?: F[0-9]+)+")] | length >= 1) and .result.complete == false' > /dev/null \
    || { echo "$output"; false; }
}

@test "R182: dev.md never tells the Dev to run vbw fix done: the workflow runs it once for the round" {
  local bad
  bad=$(grep -n 'vbw fix done' "$DEV" | grep -viE 'never|workflow|round' || true)
  [ -z "$bad" ] || { echo "lines telling the Dev to run vbw fix done: $bad"; false; }
}

@test "R182: dev.md names vbw check for a fixing Dev's own checks" {
  grep -qF 'vbw check' "$DEV"
}

@test "R182: the Lead's own Close a run instructions include the fix round's vbw fix done" {
  local section
  section=$(sed -n '/^## Close a run/,/^## /p' "$LEAD")
  printf '%s' "$section" | grep -q 'vbw fix done' || { echo "$section"; false; }
}

@test "R182: without a session, complete follows the plan: an open fix and a blocked Dev give the same value, true" {
  local k='{"fixdone":"ran","closed":["F1"],"open":[{"fix":"F2","reason":"uncommitted changes"}],"report":"F2 open","state":"{\"open\":false,\"recorded\":{\"F1\":true,\"F2\":false}}"}'
  run wf '{"groups":[["F1"],["F2"]]}' "$(jq -nc --argjson d "$DONE" --argjson k "$k" '{"F1": $d, "F2": $d, "fix done": $k}')"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.result.fixdone.open == [{fix: "F2", reason: "uncommitted changes"}] and .result.complete == true' > /dev/null || { echo "$output"; false; }
  run wf '{"groups":[["F1"],["F2"]]}' "$(jq -nc --argjson d "$DONE" --argjson b "$BLOCKED" --argjson a "$ALONE" '{"F1": $d, "F2": $b, "fix done": $a}')"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '(.result.fixdone.left_out | length) == 1 and .result.complete == true' > /dev/null || { echo "$output"; false; }
}
