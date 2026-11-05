#!/usr/bin/env bats
# R76 (docs/guards.md): a Dev's command that writes a file outside its plan
# through a program (Python, Node, Perl, Ruby or similar) is refused exactly
# like a shell write outside its plan; the same program writing a file inside
# its plan is allowed, and programs that only read stay allowed. R219 (F323):
# a program whose file-writing call names its target through a variable, an
# expression or another call is refused under a run lease, since the guard
# cannot read where it writes; a program that writes nothing still passes, and
# the words of the user docs and the Dev brief state the rule. L1: the real
# guard hook on a run lease.

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

# R219 (F323): a write whose target the guard cannot read (a variable, an
# expression, another call) is refused under a run lease, naming the call as
# written and the fix; the R76 judgment of literal paths stays as it is.

# reason: the guard's whole reason for the last call.
reason() { printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason'; }
# unreadable CMD: the last call (CMD) got the unreadable-target refusal.
unreadable() {
  denied || { echo "not refused: $1 -> $output"; return 1; }
  [[ "$(reason)" == *"writes a file the guard cannot name"* ]] || { echo "not the unreadable-target refusal: $1 -> $output"; return 1; }
}
# allowed CMD: a build agent's CMD passes the guard.
allowed() {
  run dev_shell "$1"
  [ -z "$output" ] || { echo "refused: $1 -> $output"; return 1; }
}
# lease KIND FILES_JSON: the record's lease is a KIND run of sessA writing FILES_JSON (null: any project file).
lease() {
  jq --arg k "$1" --argjson f "$2" '.lease = {run: ($k + "-1"), kind: $k, session: "sessA", started_at: (now | todate), files: $f}' \
    .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
}

@test "R219: a program naming its write target through a variable, an expression or another call is refused on a build lease whose files do not hold the file" {
  local c
  # The F323 shape: a Python heredoc computes the path and opens it for writing.
  c=$'python3 - <<\'EOF\'\nimport os\np = os.path.join("tests", "x.bats")\nwith open(p, "w") as f:\n    f.write("x")\nEOF'
  run dev_shell "$c"
  unreadable "$c"
  for c in "python3 -c \"open(path, 'w').write('x')\"" \
           "python3 -c \"p = 'src/other.py'; open(p, 'w').write('x')\"" \
           "python3 -c \"open(f\\\"{d}/x\\\", 'w').write('x')\"" \
           "python3 -c \"open('src/pay.py', m).write('x')\"" \
           "python3 -c \"from pathlib import Path; Path(d, 'x').write_text('x')\"" \
           "python3 -c \"(root / 'x').write_text('x')\"" \
           "python3 -c \"import shutil; shutil.copy('a', dst)\"" \
           "python3 -c \"import os; os.makedirs(d)\"" \
           "node -e \"fs.writeFileSync(path.join(d, 'x'), 'y')\"" \
           "node -e \"fs.writeFileSync(\\\`\\\${d}/x\\\`, 'y')\"" \
           "ruby -e 'File.write(p, \"x\")'" \
           "perl -e 'open(F, \">\", \$p); print F \"x\"'" \
           "php -r 'file_put_contents(\$p, \"x\");'" \
           "python3 -c \"import pathlib; pathlib.Path(p).write_text(1)\"" \
           "python3 -c \"import pathlib; pathlib.Path(d, 'x').unlink()\"" \
           "node -e \"require('fs').writeFileSync(p, 'x')\"" \
           "node -e \"const {writeFileSync} = require('fs'); writeFileSync(p, 'x')\"" \
           "node -e \"w.writeFile(p, 'x')\"" \
           "ruby -e 'File.write p, \"x\"'" \
           "ruby -e 'File.delete p'" \
           "ruby -e 'FileUtils.rm_rf d'" \
           "perl -e 'open FH, \">\", \$p'"; do
    run dev_shell "$c"
    unreadable "$c"
  done
}

@test "R219: the reason names the call as written and ends with its own Next line; the user sees the call text first" {
  local c first next
  c=$'python3 - <<\'EOF\'\np = "tests/x.bats"\nwith open(p, "w") as f:\n    f.write("x")\nEOF'
  run dev_shell "$c"
  denied
  first='open(p, "w") writes a file the guard cannot name: the program gives its target through a variable, an expression or another call, so the guard cannot read where it writes'
  next='Next: name the file as a literal path in the program, or write it with the Edit tool (Write for a new file)'
  [ "$(reason)" = "VBW guard: $first"$'\n'"$next" ] || { echo "the reason is not the pinned words:"; reason; false; }
  [ "$(printf '%s' "$output" | jq -r '.systemMessage')" = "VBW guard blocked this call: $first" ] || { echo "$output"; false; }
}

@test "R219: both inline forms of every interpreter the guard reads are judged, under build, fix, qa, map and plan leases; outside a run programs are not judged" {
  local c kind
  for c in "python3 -c \"open(p, 'w')\"" "python -c \"open(p, 'w')\"" "node -e \"fs.writeFileSync(p, 'x')\"" \
           "perl -e 'unlink(\$p)'" "ruby -e 'File.write(p, \"x\")'" "php -r 'file_put_contents(\$p, \"x\");'" \
           "lua -e 'os.remove(p)'" "deno eval \"import fs from 'node:fs'; fs.writeFileSync(p, 'x')\"" "bun -e \"fs.writeFileSync(p, 'x')\"" \
           $'python3 - <<\'EOF\'\nopen(p, "w").write("x")\nEOF' \
           $'node <<\'EOF\'\nconst fs = require("fs");\nfs.writeFileSync(p, "x");\nEOF'; do
    run dev_shell "$c"
    unreadable "$c"
  done
  c=$'python3 - <<\'EOF\'\nopen(p, "w").write("x")\nEOF'
  for kind in fix qa map plan; do
    case $kind in fix) lease fix '["src/pay.py"]' ;; plan) lease plan null ;; *) lease "$kind" '[]' ;; esac
    run dev_shell "$c"
    unreadable "$kind lease: $c"
  done
  jq '.lease = null' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  allowed "$c"
}

@test "R219: the R76 order is kept: a literal path outside the plan gets the R76 refusal naming the path, and an unreadable target is refused even when the lease allows any project file" {
  local c
  c="python3 -c \"open('src/other.py', 'w').write('x'); open(p, 'w').write('x')\""
  run dev_shell "$c"
  denied
  [[ "$(reason)" == *"src/other.py"*"outside this run's files"* ]] || { echo "not the R76 refusal of the literal path: $(reason)"; false; }
  [[ "$(reason)" != *"cannot name"* ]] || { echo "the unreadable target was judged before the literal path: $(reason)"; false; }
  lease build null
  allowed "python3 -c \"open('docs/notes.md', 'w').write('x')\""
  c="python3 -c \"open(p, 'w').write('x')\""
  run dev_shell "$c"
  unreadable "lease.files null: $c"
}

@test "R219: a program that writes nothing, a heredoc fed to a non-interpreter, a script file run by name and a string method on a bare variable pass" {
  local c
  mkdir -p tools
  printf 'print(1)\n' > tools/x.py
  for c in "python3 -c \"print(p)\"" \
           "python3 -c \"import json; d = json.load(open(p))\"" \
           "python3 -c \"open(p)\"" "python3 -c \"open(p, 'r')\"" "python3 -c \"open(p, 'rb')\"" \
           "node -e \"console.log(fs.readFileSync(p, 'utf8'))\"" \
           "python3 -c \"from pathlib import Path; print(Path(p).read_text())\"" \
           $'cat <<\'EOF\'\nopen(p, "w").write("x")\nfs.writeFileSync(p, "x")\nEOF' \
           $'tee <<\'EOF\'\nopen(p, "w").write("x")\nEOF' \
           "python3 tools/x.py tests/x.bats" \
           "python3 -c \"s = 'a'; t = s.replace('a', 'b'); u = s.rename(x, y)\""; do
    allowed "$c"
  done
}

@test "R219: the guard's header states the unreadable-target rule beside the heredoc-as-data rule, and the hook benchmark's program command holds a literal path and a path held in a variable" {
  local head prog
  head=$(sed -n '1,/^include/p' "$PLUGIN_ROOT/hooks/guard-bash.jq" | grep '^#')
  printf '%s\n' "$head" | grep -q 'D281' || { echo "the header no longer names the heredoc-as-data rule (D281)"; false; }
  printf '%s\n' "$head" | grep -qi 'variable' || { echo "the header does not state the rule on a write target held in a variable"; false; }
  printf '%s\n' "$head" | grep -qi 'literal' || { echo "the header does not say a literal path is what the guard reads"; false; }
  prog=$(awk '/A build agent running Python/ { p = 1 } p { print } /interp\.json/ { exit }' "$REPO_ROOT/tools/bench-hooks.sh")
  printf '%s\n' "$prog" | grep -Fq 'open(\"src/pay.py\", \"w\")' || { echo "the benchmark's program no longer writes a literal path"; false; }
  printf '%s\n' "$prog" | grep -Eq 'open\([A-Za-z_][A-Za-z0-9_]*, ' || { echo "the benchmark's program has no write through a variable"; false; }
}

# paragraph FILE TEXT: the paragraph of docs/FILE (lines up to a blank one) holding TEXT, as one line.
paragraph() {
  awk -v t="$2" 'BEGIN { RS = "" } index($0, t) { gsub(/\n/, " "); print; exit }' "$REPO_ROOT/docs/$1"
}

@test "R219 words: docs/guards.md states the rule, docs/workflows.md's refusal table carries the Guards row with the guard's Next text, and the Dev brief says a program names its file as a literal path" {
  local p row line
  p=$(paragraph guards.md 'Programs that write files')
  [ -n "$p" ] || { echo "docs/guards.md: no paragraph 'Programs that write files'"; false; }
  [[ "$p" != *"stays a guard rail"* ]] || { echo "docs/guards.md still leaves a path held in a variable to the guard rail"; false; }
  printf '%s\n' "$p" | grep -q 'cannot read' || { echo "docs/guards.md does not say the guard cannot read such a target"; false; }
  printf '%s\n' "$p" | grep -Eq 'refuse[sd]' || { echo "docs/guards.md does not say the write is refused"; false; }
  printf '%s\n' "$p" | grep -q 'writes nothing' || { echo "docs/guards.md does not say a program that writes nothing passes"; false; }
  printf '%s\n' "$p" | grep -q 'by name' || { echo "docs/guards.md does not say a script file run by name is not read"; false; }
  row=$(awk '/^### Every refusal and its next step/ { p = 1; next } p && /^### / { exit } p && /^\| Guards/ { print }' "$REPO_ROOT/docs/workflows.md" \
    | grep -F 'cannot name' | sed -e 's/^| .* | //' -e 's/ |$//')
  [ -n "$row" ] || { echo "docs/workflows.md: no Guards row for a program writing a file the guard cannot name"; false; }
  [ "$row" = 'name the file as a literal path in the program, or write it with the Edit tool (Write for a new file)' ] || { echo "the row's Next text is not the guard's: $row"; false; }
  line=$(grep -F 'Write only inside the project' "$PLUGIN_ROOT/agents/dev.md")
  [ -n "$line" ] || { echo "plugin/agents/dev.md: no 'Write only inside the project' line"; false; }
  printf '%s\n' "$line" | grep -q 'Edit' || { echo "the Dev brief's writing rule does not name the Edit tool"; false; }
  printf '%s\n' "$line" | grep -q 'literal path' || { echo "the Dev brief's writing rule does not say a program names its file as a literal path"; false; }
  printf '%s\n' "$line" | grep -Eq 'cannot (read|name)' || { echo "the Dev brief's writing rule does not give the reason (the guard cannot read the target)"; false; }
}
