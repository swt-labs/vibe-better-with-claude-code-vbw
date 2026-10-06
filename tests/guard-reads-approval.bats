#!/usr/bin/env bats
# R77 (docs/guards.md): reading the plan of record (copying or printing it) is
# never refused as a write, and naming the approval command in plain text (a
# message, a commit message, an echo) is never refused as an approval. Writing
# the record and running the approval stay refused. L1: the real guard hook.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
}

teardown() { vbw_teardown; }

bash_call() {
  jq -nc --arg c "$1" --arg d "$PROJECT" '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $d, tool_input: {command: $c}}' \
    | vbw_hook PreToolUse Bash
}

denied() { [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')" = deny ]; }

@test "R77: copying or printing the plan of record is allowed" {
  local c
  for c in 'cp .vbw/record.json backup.json' 'cp .vbw/record.json "$HOME/record-copy.json"' 'cp -p .vbw/record.json /tmp/r.json' \
           'cat .vbw/record.json' 'cat .vbw/record.json | jq .plans' 'jq . .vbw/record.json' 'jq .plans .vbw/record.json > plans.json' \
           'sort .vbw/record.json' 'awk 1 .vbw/record.json' 'rsync .vbw/record.json out/' 'tail -n 5 .vbw/record.json' \
           'diff .vbw/record.json backup.json' 'cmp .vbw/record.json backup.json'; do
    run bash_call "$c"
    [ -z "$output" ] || { echo "refused: $c -> $output"; false; }
  done
}

@test "R77: writing the plan of record stays refused, whatever program does it" {
  local c
  for c in 'cp backup.json .vbw/record.json' 'mv backup.json .vbw/record.json' 'jq .plans .vbw/record.json > .vbw/record.json' \
           'echo {} > .vbw/record.json' 'tee .vbw/record.json < backup.json' 'sed -i "" s/a/b/ .vbw/record.json' 'rm .vbw/record.json' \
           'rsync backup.json .vbw/record.json'; do
    run bash_call "$c"
    denied || { echo "not refused: $c"; false; }
    [[ "$output" == *"record.json"* ]]
  done
}

@test "R77: naming the approval command in plain text is not an approval" {
  local c
  for c in 'echo vbw approve' 'echo "run vbw approve when ready"' 'git commit -m "docs: tell users to run vbw approve"' \
           'git commit -m "docs: run \`vbw approve\` after planning"' 'echo "see \`vbw approve\` in the docs"' \
           'git commit -m "feat: x" -m "Then the user types
vbw approve
and builds start $(date)"' \
           'echo "typed: \$(vbw approve)"' 'printf "%s\n" "vbw approve"' "echo 'vbw approve' > notes.txt" 'grep -rn "vbw approve" docs' \
           'echo "a
vbw approve now $(date)"'; do
    run bash_call "$c"
    [ -z "$output" ] || { echo "refused: $c -> $output"; false; }
  done
}

@test "R77: actually running the approval is still refused, wherever it is hidden" {
  local c
  for c in 'vbw approve' 'echo "$(vbw approve)"' 'echo `vbw approve`' 'sh -c "vbw approve"' 'cd x && vbw approve' 'echo ok; vbw approve --hash abcdef012345' \
           'git commit -m "msg" -m "$(vbw approve)"' 'echo "text $(vbw approve) more"'; do
    run bash_call "$c"
    denied || { echo "not refused: $c"; false; }
    [[ "$output" == *"/vbw:approve"* ]]
  done
}
