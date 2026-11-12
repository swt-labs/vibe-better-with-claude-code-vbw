#!/usr/bin/env bats
# R308 (docs/guards.md): the Bash guard reads a comment as bash does, in a command and
# in a script file it reads (R255). Outside quotes, a # at the start of a word starts a
# comment that runs to the end of the line, and a quote mark inside a comment pairs
# with nothing. So no code after a comment is read as quoted text (a write there is
# judged, never missed), and no quoted text is read as code (a script run by name is
# never refused for a write it does not make). A # inside a word, a quoted string or
# a parameter expansion starts nothing. L1: the shipped hooks.json command run as
# Claude Code runs it (vbw_hook) under a build lease whose protected list holds
# tests/c1.sh and whose plan files are src/ and tests/.

load helper
load protected-helper
load fixture-helper

built_project() {
  vbw_setup
  protected_base
  protected_apply 2 '.plans[0].files = ["src/", "tests/"]'
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  mkdir -p .vbw/runtime/scratch
}

setup_file() { fixture_build built built_project; }
setup() { fixture_copy built; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# call COMMAND: the Bash guard's answer for a build agent's COMMAND, in ANSWER and
# its reason in REASON; FIRST is the reason's first line. Fails on any stderr.
call() {
  ANSWER=$(jq -nc --arg c "$1" --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "Bash",
      agent_id: "a1", agent_type: "vbw:dev", tool_input: {command: $c}}' \
    | HOOK_PROJECT_DIR="$PROJECT" vbw_hook PreToolUse Bash 2> "$TEST_ROOT/err")
  [ ! -s "$TEST_ROOT/err" ] || { echo "the hook wrote to stderr:"; cat "$TEST_ROOT/err"; return 1; }
  REASON=$(printf '%s' "$ANSWER" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
  FIRST=${REASON%%$'\n'*}
}
denied() { [[ "$ANSWER" == *'"deny"'* ]] || { echo "not denied: $1"; echo "  answer: $ANSWER"; return 1; }; }
allowed() { [ -z "$ANSWER" ] || { echo "not allowed: $1"; echo "  answer: $ANSWER"; return 1; }; }
first() { [ "$FIRST" = "$1" ] || { printf 'the first line differs\n  got:  %s\n  want: %s\n' "$FIRST" "$1"; return 1; }; }
has() { [[ "$REASON" == *"$1"* ]] || { printf 'the reason lacks: %s\n  reason: %s\n' "$1" "$REASON"; return 1; }; }

PROTECTED='tests/c1.sh is a protected check file: a protected check file is never edited during a build'

@test "R308: a quote mark in a script file's comment pairs with nothing: a write between two such comments is judged, on a line of its own or after code that ends in a comment" {
  printf '%s\n' "# the bench's note" 'echo x > tests/c1.sh' "# it's done" > .vbw/runtime/scratch/c.sh
  call 'bash .vbw/runtime/scratch/c.sh'
  denied "a write between two comments holding an apostrophe"
  first "VBW guard: .vbw/runtime/scratch/c.sh (run by bash): echo x > tests/c1.sh writes tests/c1.sh: $PROTECTED"
  printf '%s\n' "echo paid > src/pay.txt # the plan's file" "echo x > tests/c1.sh # that's the check" > .vbw/runtime/scratch/t.sh
  call 'sh .vbw/runtime/scratch/t.sh'
  denied "a write on a line after a code line ending in a comment with an apostrophe"
  first "VBW guard: .vbw/runtime/scratch/t.sh (run by sh): echo x > tests/c1.sh writes tests/c1.sh: $PROTECTED"
}

@test "R308: quoted text in a script file is never read as code: a > inside quotes between comments holding apostrophes, or double-quoted strings holding ':' and '|', in a script writing only the plan's files, pass" {
  printf '%s\n' "# the case's label" "echo 'save with > \$HOME/y' > src/pay.txt" "# the bench's note" > .vbw/runtime/scratch/q.sh
  call 'bash .vbw/runtime/scratch/q.sh'
  allowed "a quoted > between two comments holding an apostrophe"
  printf '%s\n' "# the case's label" \
    "printf \"end it with ':' to name only that case; join several with '|'):\\n\" >&2" \
    "echo 'save with > \$HOME/y' > src/pay.txt" \
    "# the bench's reference" \
    "printf 'done\\n'" > .vbw/runtime/scratch/ok.sh
  call 'bash .vbw/runtime/scratch/ok.sh'
  allowed "quoted ':' and '|' and a quoted > beside comments holding apostrophes"
}

@test "R308: a comment in a command is read as in a script: a write after a commented line holding an apostrophe is judged" {
  call $'# the fixture\'s step\necho x > tests/c1.sh\n# that\'s all'
  denied "a command whose write sits between two comments holding an apostrophe"
  first "VBW guard: $PROTECTED"
  call $'echo paid > src/pay.txt # the plan\'s file\necho x > tests/c1.sh # it\'s the check'
  denied "a command line ending in a comment, then a write"
  first "VBW guard: $PROTECTED"
}

@test "R308: a # that does not start a word starts no comment: inside a word, a quoted string or a parameter expansion, a write after it on the same line is judged" {
  call 'echo a#b > tests/c1.sh'
  denied "a # inside a word"
  first "VBW guard: $PROTECTED"
  call 'echo "# x" > tests/c1.sh'
  denied "a # inside a double-quoted string"
  first "VBW guard: $PROTECTED"
  call "echo '# x' > tests/c1.sh"
  denied "a # inside a single-quoted string"
  first "VBW guard: $PROTECTED"
  call 'x=ab; echo ${#x} > tests/c1.sh'
  denied "the length expansion \${#x}"
  first "VBW guard: $PROTECTED"
  call 'echo $# > tests/c1.sh'
  denied "the parameter \$#"
  first "VBW guard: $PROTECTED"
}
