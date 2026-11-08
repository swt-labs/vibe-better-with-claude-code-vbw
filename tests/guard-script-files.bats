#!/usr/bin/env bats
# R255 (T233; docs/guards.md): a program the agent wrote during the run is judged
# like an inline program. Under a run lease, when an interpreter or a shell runs a
# file by name (python FILE, python < FILE, node FILE, bash FILE), the Bash guard
# reads the program: from the heredoc, echo or printf that writes that file in the
# same command when there is one (no disk read), else from the file on disk when it
# is untracked, ignored or changed since the commit the run started on; a committed
# file unchanged since the run's start runs unread and allowed, as today, and a
# script committed during the run is still read (the comparison uses the run's
# starting commit, HEAD standing in when none was recorded). The program's writes
# are judged by the inline rules (R76, R219) with the lease's own texts; the refusal
# names the script file, the interpreter and the call as written before the rule.
# A script the guard cannot obtain under a lease is refused as unreadable. Outside a
# run nothing changes. L1: the shipped hooks.json command run as Claude Code runs
# it (vbw_hook) under a build lease whose protected list holds tests/c1.sh.

load helper
load protected-helper
load fixture-helper

# built: a build run of P1.1 (files src/ and tests/, so only protection stops a
# write to tests/c1.sh) in a project whose committed tools/x.py and tools/x.sh
# write that protected check file: the project's own scripts, allowed unread.
built_project() {
  vbw_setup
  protected_base
  mkdir -p tools
  printf 'open("tests/c1.sh", "w").write("x")\n' > tools/x.py
  printf 'echo x > tests/c1.sh\n' > tools/x.sh
  git add tools
  git commit -q -m "chore(tools): the project's own scripts"
  protected_apply 2 '.plans[0].files = ["src/", "tests/"]'
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  mkdir -p .vbw/runtime/scratch
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
  # Every git call the hook makes is logged: the lookup happens only on the script-file path.
  GIT_LOG="$TEST_ROOT/git.log"
  REAL_GIT=$(command -v git)
  mkdir -p "$TEST_ROOT/shim"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$GIT_LOG" "$REAL_GIT" > "$TEST_ROOT/shim/git"
  chmod +x "$TEST_ROOT/shim/git"
  export GIT_LOG
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# call COMMAND: the Bash guard's answer for a build agent's COMMAND, in ANSWER and
# its reason in REASON; FIRST is the reason's first line. Fails on any stderr.
call() {
  : > "$GIT_LOG"
  ANSWER=$(jq -nc --arg c "$1" --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "Bash",
      agent_id: "a1", agent_type: "vbw:dev", tool_input: {command: $c}}' \
    | PATH="$TEST_ROOT/shim:$PATH" HOOK_PROJECT_DIR="$PROJECT" vbw_hook PreToolUse Bash 2> "$TEST_ROOT/err")
  [ ! -s "$TEST_ROOT/err" ] || { echo "the hook wrote to stderr:"; cat "$TEST_ROOT/err"; return 1; }
  REASON=$(printf '%s' "$ANSWER" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
  FIRST=${REASON%%$'\n'*}
}
denied() { [[ "$ANSWER" == *'"deny"'* ]] || { echo "not denied: $1"; echo "  answer: $ANSWER"; return 1; }; }
allowed() { [ -z "$ANSWER" ] || { echo "not allowed: $1"; echo "  answer: $ANSWER"; return 1; }; }
# first TEXT: the reason's first line is exactly TEXT.
first() { [ "$FIRST" = "$1" ] || { printf 'the first line differs\n  got:  %s\n  want: %s\n' "$FIRST" "$1"; return 1; }; }
has() { [[ "$REASON" == *"$1"* ]] || { printf 'the reason lacks: %s\n  reason: %s\n' "$1" "$REASON"; return 1; }; }
git_calls() { [ "$(wc -l < "$GIT_LOG" | tr -d ' ')" -le "$1" ] || { echo "more than $1 git call(s):"; cat "$GIT_LOG"; return 1; }; }

PROTECTED='tests/c1.sh is a protected check file: a protected check file is never edited during a build'
PROTECTED_NEXT='Next: leave tests/c1.sh as it is; the main session changes the check with vbw apply --patch, then the user approves it'
UNREADABLE_NEXT='Next: write the program with the Edit tool and run it, or give the program inline (-c, or a heredoc on standard input)'
PY_WRITE='open("tests/c1.sh", "w").write("x")'

@test "R255: a Python file written in the same command (a heredoc into it, tee, or a printed literal) and run by python FILE is judged from that text, with no file on disk and no git call: the refusal names the script, the interpreter and the call" {
  call $'cat > .vbw/runtime/scratch/x.py <<\'EOF\'\n'"$PY_WRITE"$'\nEOF\npython3 .vbw/runtime/scratch/x.py'
  denied "heredoc into the file, then python3 FILE"
  first "VBW guard: .vbw/runtime/scratch/x.py (run by python3): open(\"tests/c1.sh\", \"w\") writes tests/c1.sh: $PROTECTED"
  has "$PROTECTED_NEXT"
  git_calls 0
  [ ! -e .vbw/runtime/scratch/x.py ]
  call $'cat <<\'EOF\' | tee .vbw/runtime/scratch/t.py > /dev/null\n'"$PY_WRITE"$'\nEOF\npython .vbw/runtime/scratch/t.py'
  denied "heredoc through tee, then python FILE"
  first "VBW guard: .vbw/runtime/scratch/t.py (run by python): open(\"tests/c1.sh\", \"w\") writes tests/c1.sh: $PROTECTED"
  call "printf '%s\\n' '$PY_WRITE' > .vbw/runtime/scratch/p.py && python3 .vbw/runtime/scratch/p.py"
  denied "printed literal into the file, then python3 FILE"
  first "VBW guard: .vbw/runtime/scratch/p.py (run by python3): open(\"tests/c1.sh\", \"w\") writes tests/c1.sh: $PROTECTED"
  # A target outside the plan's files gets the lease's outside text behind the same head.
  call $'cat > .vbw/runtime/scratch/o.py <<\'EOF\'\nopen("docs/x.md", "w").write("x")\nEOF\npython3 .vbw/runtime/scratch/o.py'
  denied "a write outside the plan's files"
  first 'VBW guard: .vbw/runtime/scratch/o.py (run by python3): open("docs/x.md", "w") writes docs/x.md: docs/x.md is outside this run'"'"'s files (src/, tests/): agents write only their plan'"'"'s files'
  # A program that writes only inside the plan's files, or nothing, passes.
  call $'cat > .vbw/runtime/scratch/ok.py <<\'EOF\'\nopen("src/pay.txt", "w").write("paid")\nprint(open("tests/c1.sh").read())\nEOF\npython3 .vbw/runtime/scratch/ok.py'
  allowed "a program writing only inside the plan's files"
}

@test "R255: a script written by an earlier call (untracked under .vbw/runtime/scratch) is read from disk when run by python FILE, python < FILE or node FILE; one that writes only the plan's files passes" {
  printf '%s\n' "$PY_WRITE" > .vbw/runtime/scratch/x.py
  printf 'const fs = require("fs");\nfs.writeFileSync("tests/c1.sh", "x");\n' > .vbw/runtime/scratch/w.js
  printf 'open("src/pay.txt", "w").write("paid")\n' > .vbw/runtime/scratch/ok.py
  call 'python3 .vbw/runtime/scratch/x.py'
  denied "python3 FILE on an untracked script"
  first "VBW guard: .vbw/runtime/scratch/x.py (run by python3): open(\"tests/c1.sh\", \"w\") writes tests/c1.sh: $PROTECTED"
  has "$PROTECTED_NEXT"
  call 'python3 < .vbw/runtime/scratch/x.py'
  denied "python3 < FILE"
  first "VBW guard: .vbw/runtime/scratch/x.py (run by python3): open(\"tests/c1.sh\", \"w\") writes tests/c1.sh: $PROTECTED"
  call 'python3 -u .vbw/runtime/scratch/x.py --verbose'
  denied "python3 FILE with an option before and after the file"
  first "VBW guard: .vbw/runtime/scratch/x.py (run by python3): open(\"tests/c1.sh\", \"w\") writes tests/c1.sh: $PROTECTED"
  call 'node .vbw/runtime/scratch/w.js'
  denied "node FILE"
  [[ "$FIRST" == 'VBW guard: .vbw/runtime/scratch/w.js (run by node): '*'writeFileSync("tests/c1.sh"'*" writes tests/c1.sh: $PROTECTED" ]] \
    || { echo "the node refusal has another form: $FIRST"; false; }
  # A write whose target the guard cannot name (a variable) is refused as unreadable, the call named (R219).
  printf 'p = "tests/c1.sh"\nopen(p, "w").write("x")\n' > .vbw/runtime/scratch/u.py
  call 'python3 .vbw/runtime/scratch/u.py'
  denied "a script whose write target is held in a variable"
  first 'VBW guard: .vbw/runtime/scratch/u.py (run by python3): open(p, "w") writes a file the guard cannot name: the program gives its target through a variable, an expression or another call, so the guard cannot read where it writes'
  has 'Next: name the file as a literal path in the program, or write it with the Edit tool (Write for a new file)'
  call 'python3 .vbw/runtime/scratch/ok.py'
  allowed "a script writing only inside the plan's files"
}

@test "R255: bash FILE or sh FILE on an untracked shell script is read as a command: a redirect into a protected check file is refused by name, a target holding a shell expansion as unresolvable, a nested interpreter program is read, and a script writing only the plan's files passes" {
  printf 'echo x > tests/c1.sh\n' > .vbw/runtime/scratch/s.sh
  printf 'echo x > "$OUT"\n' > .vbw/runtime/scratch/v.sh
  printf 'python3 - <<EOF\n%s\nEOF\n' "$PY_WRITE" > .vbw/runtime/scratch/n.sh
  printf 'echo paid > src/pay.txt\ncat tests/c1.sh\n' > .vbw/runtime/scratch/ok.sh
  call 'bash .vbw/runtime/scratch/s.sh'
  denied "bash FILE redirecting into a protected check file"
  first "VBW guard: .vbw/runtime/scratch/s.sh (run by bash): echo x > tests/c1.sh writes tests/c1.sh: $PROTECTED"
  has "$PROTECTED_NEXT"
  call 'sh .vbw/runtime/scratch/v.sh'
  denied "sh FILE redirecting into an expansion"
  [[ "$FIRST" == 'VBW guard: .vbw/runtime/scratch/v.sh (run by sh): echo x > "$OUT" writes $OUT: $OUT cannot be resolved by the guard (~ or a shell expansion), so it counts as outside the project'* ]] \
    || { echo "the unresolvable refusal has another form: $FIRST"; false; }
  call 'bash .vbw/runtime/scratch/n.sh'
  denied "bash FILE whose script feeds python a heredoc"
  has ".vbw/runtime/scratch/n.sh (run by bash): "
  has "writes tests/c1.sh: $PROTECTED"
  call 'bash .vbw/runtime/scratch/ok.sh'
  allowed "a shell script writing only inside the plan's files"
}

@test "R255: a committed script unchanged since the run started runs unread and allowed with one git lookup at most; a script changed on disk, or committed during the run, is read, because the comparison uses the run's starting commit" {
  call 'python3 tools/x.py'
  allowed "the project's own committed script"
  git_calls 2
  call 'bash tools/x.sh'
  allowed "the project's own committed shell script"
  git_calls 2
  # Changed on disk since the run started: read.
  printf '%s\n# tuned\n' "$PY_WRITE" > tools/x.py
  call 'python3 tools/x.py'
  denied "a committed script changed on disk"
  first "VBW guard: tools/x.py (run by python3): open(\"tests/c1.sh\", \"w\") writes tests/c1.sh: $PROTECTED"
  git checkout -q -- tools/x.py
  # Committed during the run (HEAD moved): still read, since the run's start is the reference.
  printf '%s\n' "$PY_WRITE" > tools/y.py
  git add tools/y.py
  git commit -q -m "feat(tools): a script written during the run"
  call 'python3 tools/y.py'
  denied "a script committed during the run"
  first "VBW guard: tools/y.py (run by python3): open(\"tests/c1.sh\", \"w\") writes tests/c1.sh: $PROTECTED"
  git_calls 2
  call 'python3 tools/x.py'
  allowed "the unchanged script, after HEAD moved"
}

@test "R255: a script the guard cannot obtain under a lease is refused as unreadable, naming the path and the next step: a shell expansion in the path, or a missing file no part of the command writes" {
  call 'python3 "$SCRIPT"'
  denied "a script path holding a shell expansion"
  first 'VBW guard: $SCRIPT (run by python3): a script the guard cannot read: its path holds a shell expansion, or no readable file is at it and this command does not write it'
  has "$UNREADABLE_NEXT"
  call 'python3 .vbw/runtime/scratch/missing.py'
  denied "a missing script"
  first 'VBW guard: .vbw/runtime/scratch/missing.py (run by python3): a script the guard cannot read: its path holds a shell expansion, or no readable file is at it and this command does not write it'
  has "$UNREADABLE_NEXT"
  call 'bash .vbw/runtime/scratch/missing.sh'
  denied "a missing shell script"
  first 'VBW guard: .vbw/runtime/scratch/missing.sh (run by bash): a script the guard cannot read: its path holds a shell expansion, or no readable file is at it and this command does not write it'
  call 'node ~/x.js'
  denied "a script path starting with ~"
  has "(run by node): a script the guard cannot read"
}

@test "R255: the inline forms answer as before with no git call; outside a run every case is allowed and nothing is read; the record and its schema are untouched; the bench measures the script-file input" {
  printf '%s\n' "$PY_WRITE" > .vbw/runtime/scratch/x.py
  printf 'echo x > tests/c1.sh\n' > .vbw/runtime/scratch/s.sh
  cp .vbw/record.json "$TEST_ROOT/record.before"
  call "python3 -c '$PY_WRITE'"
  denied "python3 -c writing a protected check file"
  has "tests/c1.sh is a protected check file"
  [[ "$FIRST" != *"(run by"* ]] || { echo "an inline program is named as a script: $FIRST"; false; }
  git_calls 0
  call $'python3 - <<\'EOF\'\n'"$PY_WRITE"$'\nEOF'
  denied "a heredoc on standard input writing a protected check file"
  git_calls 0
  call 'python3 -m pytest tests/'
  allowed "python3 -m"
  call 'bash -c "echo paid > src/pay.txt"'
  allowed "bash -c writing inside the plan's files"
  git_calls 0
  cmp -s .vbw/record.json "$TEST_ROOT/record.before" || { echo "the guard changed the record"; false; }
  # No run: the same commands pass, read nothing and look nothing up.
  record_edit '.lease = null'
  local c
  for c in 'python3 .vbw/runtime/scratch/x.py' 'bash .vbw/runtime/scratch/s.sh' 'python3 "$SCRIPT"' 'python3 .vbw/runtime/scratch/missing.py' \
           $'cat > .vbw/runtime/scratch/x.py <<\'EOF\'\n'"$PY_WRITE"$'\nEOF\npython3 .vbw/runtime/scratch/x.py' 'python3 tools/x.py'; do
    call "$c"
    allowed "outside a run: $c"
    git_calls 0
  done
  grep -qE '^GUARD_INPUTS=.*[" ]script[" ]' "$REPO_ROOT/tools/bench-hooks.sh" || { echo "tools/bench-hooks.sh has no script input in GUARD_INPUTS"; false; }
  grep -q 'script.json' "$REPO_ROOT/tools/bench-hooks.sh" || { echo "tools/bench-hooks.sh writes no script.json input"; false; }
}

# --- R273: a big script is read in time, a huge one refused by size --------------

# field_script FILE KB: a shell script of about KB kilobytes in the field report's shape
# (thousands of echo lines) whose last line writes the protected check file.
field_script() {
  awk -v n="$(( $2 * 1024 / 45 ))" 'BEGIN { for (i = 1; i <= n; i++) printf "echo \"step %06d: the build prints a line here\"\n", i; print "echo x > tests/c1.sh" }' > "$1"
}

@test "R273: a 264 KB shell script run by bash FILE is read to its end within the guard's time: the write on its last line is refused by name, not as a guard failure" {
  field_script .vbw/runtime/scratch/field.sh 264
  [ "$(wc -c < .vbw/runtime/scratch/field.sh)" -ge 262144 ]
  call 'bash .vbw/runtime/scratch/field.sh'
  denied "a 264 KB script whose last line writes a protected check file"
  first "VBW guard: .vbw/runtime/scratch/field.sh (run by bash): echo x > tests/c1.sh writes tests/c1.sh: $PROTECTED"
  has "$PROTECTED_NEXT"
}

@test "R273: a script too large to read before it runs is refused by its size, before any read, naming the file, its size in KB and the way out; committed during the run it is refused the same way, and only the project's own, unchanged since the run started, runs unread" {
  head -c 3145728 /dev/zero | tr '\0' '#' > .vbw/runtime/scratch/huge.sh
  printf '\necho x > tests/c1.sh\n' >> .vbw/runtime/scratch/huge.sh
  call 'bash .vbw/runtime/scratch/huge.sh'
  denied "a 3 MB script"
  first 'VBW guard: .vbw/runtime/scratch/huge.sh (3072 KB) is too large to read before it runs'
  has 'Next: run it in smaller parts, each under 512 KB'
  # Committed during the run it changed since the run's start, as R255 has it: refused, never run unread.
  cp .vbw/runtime/scratch/huge.sh tools/huge.sh
  git add tools/huge.sh && git commit -q -m "chore(tools): a huge script written during the run"
  call 'bash tools/huge.sh'
  denied "a huge script committed during the run"
  first 'VBW guard: tools/huge.sh (3072 KB) is too large to read before it runs'
  # A run that starts on that commit finds the project's own script, unchanged since its start: unread.
  VBW_SESSION_ID=s1 "$VBW" run end > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  call 'bash tools/huge.sh'
  allowed "the project's own huge script, committed and unchanged since the run started"
}

@test "R273 timed: tests/timed-guard-script.bats times the guard on an 80 KB and a 264 KB script: the big one within 5 s of CPU and within 1.5 times the size ratio of the small one's time, scaled by the bench's reference, skipped on a busy machine" {
  local f="$BATS_TEST_DIRNAME/timed-guard-script.bats"
  [ -f "$f" ] || { echo "no tests/timed-guard-script.bats"; false; }
  grep -qE '\b80\b' "$f" && grep -qE '\b264\b' "$f" || { echo "the timed test does not name the 80 KB and 264 KB scripts"; false; }
  grep -qE '1\.5' "$f" || { echo "the timed test has no 1.5 ratio rule"; false; }
  grep -qE '\b5000\b|\b5 ?s\b' "$f" || { echo "the timed test names no 5 s budget"; false; }
  grep -q 'NOMINAL_MS' "$f" || { echo "the timed test does not read the bench's NOMINAL_MS"; false; }
  grep -qi 'busy' "$f" || { echo "the timed test has no busy-machine rule"; false; }
  # The numbers sit in the code that judges, not only in the comments.
  grep -qE '^[[:space:]]*judge .*"\$big" 5000$' "$f" || { echo "the 264 KB time is not judged against 5000 ms"; false; }
  grep -qE '^[[:space:]]*limit=.*1\.5 \* \(264 / 80\) \* ' "$f" || { echo "the limit is not 1.5 x (264 / 80) x the 80 KB time"; false; }
  grep -qE '^[[:space:]]*(big|small)=\$\(guard_ms (264|80)\)$' "$f" || { echo "the guard is not timed on both script sizes"; false; }
  grep -qE '^[[:space:]]*echo "80 KB: \$small ms CPU; 264 KB: \$big ms CPU; ratio ' "$f" || { echo "the two measures and their ratio are not printed"; false; }
  bats --count "$f" > /dev/null
}
