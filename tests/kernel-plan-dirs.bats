#!/usr/bin/env bats
# A plan entry ending in "/" names a directory: it covers every file under it,
# for the guards, the proof's scope check, wave scheduling and the run lease.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] Cases\n- R2 [auto] More\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests
  printf 'true\n' > tests/ok.sh
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/ok.sh"], files:["tests/ok.sh"]},
                          {id:"C2", req:"R2", run:["sh","tests/ok.sh"], files:["tests/ok.sh"]}]
    | .phases = [{id:"P1", title:"Cases", reqs:["R1","R2"], milestone: "M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Cases", reqs:["R1"], files:["cases/x/"], after:[], status:"planned"},
                {id:"P1.2", phase:"P1", title:"More", reqs:["R2"], files:["cases/x/a.sh"], after:[], status:"planned"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# write_decision SESSION PATH [AGENT_TYPE]: the guard's decision on a Write.
write_decision() {
  local out
  out=$(jq -nc --arg s "$1" --arg p "$PROJECT/$2" --arg d "$PROJECT" --arg a "${3:-}" \
    '{hook_event_name: "PreToolUse", tool_name: "Write", cwd: $d, session_id: $s, tool_input: {file_path: $p}}
     + (if $a == "" then {} else {agent_id: "x1", agent_type: $a} end)' | vbw_hook PreToolUse Write)
  if [ -z "$out" ]; then echo allow; else printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'; fi
}

@test "an agent may write any file under a directory its plan lists, and nothing beside it" {
  VBW_SESSION_ID=sA "$VBW" run start build P1.1 > /dev/null
  [ "$(write_decision sA cases/x/a.sh vbw:dev)" = allow ]
  [ "$(write_decision sA cases/x/deep/b.txt vbw:dev)" = allow ]
  [ "$(write_decision sA cases/xy/c.sh vbw:dev)" = deny ]
  [ "$(write_decision sA cases/other.sh vbw:dev)" = deny ]
}

@test "another session cannot write under a directory a live run lists" {
  VBW_SESSION_ID=sA "$VBW" run start build P1.1 > /dev/null
  [ "$(write_decision sB cases/x/new.sh)" = deny ]
  [ "$(write_decision sB cases/xy/c.sh)" = allow ]
}

@test "a VBW commit of a file under its plan's directory is in scope" {
  mkdir -p cases/x/deep
  printf 'a\n' > cases/x/deep/a.sh
  "$VBW" commit P1.1 "feat(cases): a" > /dev/null
  git log -1 --name-only --format= | grep -qx 'cases/x/deep/a.sh'
  "$VBW" approve > /dev/null
  vbw_run prove
  [[ "$output" != *"which is not in the plan"* ]]
}

@test "a directory and a file inside it never build in the same wave" {
  vbw_run run start build P1.1 P1.2
  [ "$status" -eq 1 ]
  [[ "$output" == *"more than one plan in this wave writes"* ]]
  "$VBW" approve > /dev/null
  vbw_run next --json
  echo "$output" | jq -e '.action == "build" and .detail.plans == ["P1.1"]'
}
