#!/usr/bin/env bats
# R76 (docs/guards.md): a Dev's command that writes a file outside its plan
# through a program (Python, Node, Perl, Ruby or similar) is refused exactly
# like a shell write outside its plan; the same program writing a file inside
# its plan is allowed, and programs that only read stay allowed. L1: the real
# guard hook on a build lease.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src
  jq '.lease = {run: "build-1", kind: "build", session: "sessA", started_at: (now | todate), files: ["src/pay.js", "src/pay.py"]}' \
    .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
}

teardown() { vbw_teardown; }

# dev_shell COMMAND: a Bash call from a build agent of the owning session.
dev_shell() {
  jq -nc --arg c "$1" --arg d "$PROJECT" \
    '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $d, session_id: "sessA", agent_id: "x1", agent_type: "workflow-subagent", tool_input: {command: $c}}' \
    | vbw_hook PreToolUse Bash
}

denied() { [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')" = deny ]; }

# The reason a plain shell write to src/other.txt gets.
shell_reason() {
  run dev_shell "echo x > src/other.txt"
  denied
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason'
}

@test "R76: Python writing a file outside the plan is refused" {
  run dev_shell "python3 -c \"open('src/other.py', 'w').write('x')\""
  denied
  [[ "$output" == *"src/other.py"* ]]
  [[ "$output" == *"outside this run's files"* ]]
  run dev_shell "python -c \"from pathlib import Path; Path('src/other.py').write_text('x')\""
  denied
  run dev_shell "python3 -c \"import os; os.remove('src/other.py')\""
  denied
}

@test "R76: a Python script read from standard input is judged too" {
  run dev_shell $'python3 - <<\'EOF\'\nwith open("src/other.py", "w") as f:\n    f.write("x")\nEOF'
  denied
  [[ "$output" == *"src/other.py"* ]]
}

@test "R76: Node, Perl and Ruby writing a file outside the plan are refused" {
  run dev_shell "node -e \"require('fs').writeFileSync('src/other.js', 'x')\""
  denied
  run dev_shell "node -e \"require('fs').appendFileSync('src/other.js', 'x')\""
  denied
  run dev_shell "perl -e 'open(F, \">src/other.pl\"); print F \"x\"; close F'"
  denied
  run dev_shell "perl -pi -e 's/a/b/' src/other.js"
  denied
  run dev_shell "ruby -e \"File.write('src/other.rb', 'x')\""
  denied
}

@test "R76: the refusal is the one a shell write outside the plan gets, for the same path" {
  local want got
  want=$(shell_reason)
  run dev_shell "python3 -c \"open('src/other.txt', 'w').write('x')\""
  denied
  got=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')
  [ "$got" = "$want" ]
}

@test "R76: the same programs writing a file inside the plan are allowed" {
  run dev_shell "python3 -c \"open('src/pay.py', 'w').write('x')\""
  [ -z "$output" ] || { echo "$output"; false; }
  run dev_shell "node -e \"require('fs').writeFileSync('src/pay.js', 'x')\""
  [ -z "$output" ] || { echo "$output"; false; }
  run dev_shell "perl -pi -e 's/a/b/' src/pay.js"
  [ -z "$output" ] || { echo "$output"; false; }
  run dev_shell "ruby -e \"File.write('src/pay.js', 'x')\""
  [ -z "$output" ] || { echo "$output"; false; }
  run dev_shell $'python3 - <<\'EOF\'\nopen("src/pay.py", "w").write("x")\nEOF'
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R76: programs that only read, or that run tests, are allowed" {
  local c
  for c in "python3 -c \"print(open('src/other.py').read())\"" \
           "node -e \"console.log(require('fs').readFileSync('src/other.js', 'utf8'))\"" \
           "python3 -m pytest tests" "node --test" "perl -e 'print 1'" "ruby -e 'puts 1'" \
           "python3 -c \"print(1)\" | tee /dev/null"; do
    run dev_shell "$c"
    [ -z "$output" ] || { echo "refused: $c -> $output"; false; }
  done
}

@test "R76: outside a run, programs are not judged at all" {
  jq '.lease = null' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  run dev_shell "python3 -c \"open('src/other.py', 'w').write('x')\""
  [ -z "$output" ]
}
