#!/usr/bin/env bats
# R250 (docs/guards.md): vbw apply is refused to every run agent, with one exception:
# the Lead, under a plan run, may run it plain, with --patch and with --add, because
# applying the plan is its job (plugin/agents/lead.md, planning.js). --amend stays the
# main session's, and under build, fix and qa runs, or from any other agent, the two-line
# refusal stands. L1: the real PreToolUse Bash hook.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}
teardown() { vbw_teardown; }

# lease KIND: an open run of KIND in the record, as vbw run start leaves it.
lease() {
  jq --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg k "$1" \
    '{schema: 4, lease: {run: "r1", kind: $k, started_at: $at, files: []}, protected: []} + del(.schema, .lease, .protected)' .vbw/record.json > "$TEST_ROOT/l.json"
  cp "$TEST_ROOT/l.json" .vbw/record.json
  mkdir -p .vbw/runtime && : > .vbw/runtime/run-open
}

# verdict AGENT COMMAND: allow, or the refusal's reason.
verdict() {
  jq -nc --arg a "$1" --arg c "$2" --arg d "$PROJECT" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $d, agent_id: "a1", agent_type: $a, tool_input: {command: $c}}' \
    | vbw_hook PreToolUse Bash | jq -rn '[inputs][0].hookSpecificOutput.permissionDecisionReason // "allow"'
}

@test "R250: under a plan run the Lead may run vbw apply, vbw apply --patch and vbw apply --add, but not --amend" {
  lease plan
  local c
  for c in 'vbw apply <<EOF
{}
EOF' 'vbw apply --patch < doc.json' 'vbw apply --add < doc.json' 'cat doc.json | vbw apply --patch'; do
    [ "$(verdict vbw:lead "$c")" = allow ] || { echo "the Lead was refused: $c"; false; }
  done
  [ "$(verdict vbw:lead 'vbw apply --amend < doc.json')" != allow ] || { echo "the Lead may amend"; false; }
}

@test "R250: the same calls stay refused under build, fix and qa runs, and from every other agent under a plan run" {
  local k a
  for k in build fix qa; do
    lease "$k"
    [ "$(verdict vbw:lead 'vbw apply --patch < doc.json')" != allow ] || { echo "the Lead may apply under $k"; false; }
  done
  lease plan
  for a in vbw:dev vbw:docs vbw:qa vbw:scout vbw:debugger workflow-subagent; do
    [[ "$(verdict "$a" 'vbw apply < doc.json')" == *"only the main session runs it"* ]] || { echo "$a was not refused"; false; }
  done
}
