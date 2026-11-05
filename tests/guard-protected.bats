#!/usr/bin/env bats
# R150 (decisions D232, D238; docs/guards.md): the Bash and file guards have one
# way to learn the protected check files: the protected list of a format-4
# record (read from the glance while it is current, else from the record). They
# never read the checks, and give today's answers
# for a build or fix agent, the main conversation, another session and calls
# outside a run. On a record an older VBW wrote (no list) the main conversation,
# other sessions and calls outside a run get the same answers as before, and a
# build or fix agent's file write is refused until this VBW has saved the
# record. L1.

load helper
load protected-helper
load fixture-helper

built_project() {
  vbw_setup
  FOUR="$TEST_ROOT/four/project with space"
  OLD="$TEST_ROOT/old/project with space"
  mkdir -p "$FOUR" "$TEST_ROOT/old"
  cd "$FOUR" || return 1
  protected_base
  # The plan may write src/ and tests/, so a check file is inside the run's
  # files and only its protection stops a write.
  protected_apply 3 '.plans[0].files = ["src/", "tests/"]'
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  cp -R "$FOUR" "$OLD"
  as_older "$OLD/.vbw/record.json"
  export FOUR OLD
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# answer DIR INPUT_JSON: the hook's answer in the project at DIR (its cwd set to
# DIR); stderr goes to $TEST_ROOT/err.
answer() {
  local tool
  tool=$(printf '%s' "$2" | jq -r .tool_name)
  printf '%s' "$2" | jq -c --arg d "$1" '.cwd = $d' \
    | HOOK_PROJECT_DIR="$1" vbw_hook PreToolUse "$tool" 2> "$TEST_ROOT/err"
}

# in4 INPUT_JSON: the answer on the format-4 record, with no error, left in ANSWER.
in4() {
  ANSWER=$(answer "$FOUR" "$1")
  [ ! -s "$TEST_ROOT/err" ] || { echo "error on schema 4:"; cat "$TEST_ROOT/err"; return 1; }
}

# same INPUT_JSON: the format-4 record and the older one give the same answer,
# with no error; the answer is left in ANSWER.
same() {
  local four old
  four=$(answer "$FOUR" "$1")
  [ ! -s "$TEST_ROOT/err" ] || { echo "error on schema 4:"; cat "$TEST_ROOT/err"; return 1; }
  old=$(answer "$OLD" "$1")
  [ ! -s "$TEST_ROOT/err" ] || { echo "error on the older record:"; cat "$TEST_ROOT/err"; return 1; }
  [ "$four" = "$old" ] || { printf 'answers differ for %s\nschema 4: %s\nolder: %s\n' "$1" "$four" "$old"; return 1; }
  ANSWER=$four
}

bash_in() { jq -nc --arg c "$1" --arg a "${2:-}" --arg s "${3:-s1}" '{hook_event_name: "PreToolUse", session_id: $s, tool_name: "Bash", tool_input: {command: $c}}
  + (if $a == "" then {} else {agent_id: "x1", agent_type: $a} end)'; }
file_in() { jq -nc --arg t "$1" --arg p "$2" --arg a "${3:-}" --arg s "${4:-s1}" '{hook_event_name: "PreToolUse", session_id: $s, tool_name: $t,
  tool_input: {file_path: $p, content: "x", old_string: "a", new_string: "b"}} + (if $a == "" then {} else {agent_id: "x1", agent_type: $a} end)'; }

# The message the guards give for a protected check file: the rule in one line and
# the next step (R250): the main session changes the check with vbw apply --patch,
# then the user approves it.
protected_denied() {
  [[ "$ANSWER" == *'"deny"'* && "$ANSWER" == *"is a protected check file: a protected check file is never edited during a build"* \
    && "$ANSWER" == *"Next: leave "*" as it is; the main session changes the check with vbw apply --patch, then the user approves it"* ]] \
    || { echo "not denied as protected: $ANSWER"; return 1; }
}
denied() { [[ "$ANSWER" == *'"deny"'* ]] || { echo "not denied: $ANSWER"; return 1; }; }
allowed() { [ -z "$ANSWER" ] || { echo "not allowed: $ANSWER"; return 1; }; }
unsaved_denied() {
  [[ "$ANSWER" == *'"deny"'* && "$ANSWER" == *"saved by this VBW"* ]] || { echo "not refused as an unsaved record: $ANSWER"; return 1; }
}

@test "R150: the fixture is a format-4 record of 3 checks beside the same project as an older VBW wrote it" {
  format4 "$FOUR/.vbw/record.json"
  jq -e '.lease.kind == "build" and (.checks | length) == 3' "$FOUR/.vbw/record.json"
  jq -e '.schema == 1 and (has("protected") | not) and .lease.kind == "build"' "$OLD/.vbw/record.json"
}

@test "R150: under a build run, an agent's Edit, Write or Bash change of a protected file is refused with today's message" {
  in4 "$(file_in Write tests/c1.sh workflow-subagent)"
  protected_denied
  in4 "$(file_in Edit tests/shared.sh workflow-subagent)"
  protected_denied
  in4 "$(file_in MultiEdit tests/c2.sh workflow-subagent)"
  protected_denied
  in4 "$(bash_in 'printf x > tests/c1.sh' workflow-subagent)"
  protected_denied
  in4 "$(bash_in 'printf x >> tests/shared.sh' workflow-subagent)"
  protected_denied
  in4 "$(bash_in "$(printf 'python3 - <<%s\nopen("tests/c2.sh", "w").write("x")\nEOF' "'EOF'")" workflow-subagent)"
  denied
}

@test "R150: under a build run, an unprotected file the run may write is not refused" {
  in4 "$(file_in Write src/pay.txt workflow-subagent)"
  allowed
  in4 "$(file_in Write tests/c3.sh workflow-subagent)"
  allowed
  in4 "$(file_in Write tests/new_test.sh workflow-subagent)"
  allowed
  in4 "$(bash_in 'printf "paid\n" > src/pay.txt' workflow-subagent)"
  allowed
  in4 "$(file_in Read tests/c1.sh workflow-subagent)"
  allowed
}

@test "R150: under a fix run, an agent's change of a protected file is refused and an unprotected one is not" {
  record_edit '.lease.kind = "fix" | .lease.files = null' "$FOUR/.vbw/record.json"
  format4 "$FOUR/.vbw/record.json"
  in4 "$(file_in Write tests/c1.sh workflow-subagent)"
  protected_denied
  in4 "$(bash_in 'printf x > tests/shared.sh' workflow-subagent)"
  protected_denied
  in4 "$(file_in Write src/pay.txt workflow-subagent)"
  allowed
}

@test "R150: the main conversation, another session and calls outside a run get the same answers on format 4 and on an older record" {
  same "$(file_in Write tests/c1.sh)"
  allowed
  same "$(bash_in 'printf x > tests/c1.sh')"
  allowed
  same "$(file_in Write src/pay.txt "" s2)"
  [[ "$ANSWER" == *"another session"* ]] || { echo "$ANSWER"; false; }
  same "$(file_in Write src/pay.txt workflow-subagent s2)"
  [[ "$ANSWER" == *"another session"* ]] || { echo "$ANSWER"; false; }
  same "$(file_in Write .vbw/record.json)"
  denied
  same "$(file_in Read .env)"
  denied
  record_edit '.lease = null' "$FOUR/.vbw/record.json"
  record_edit '.lease = null' "$OLD/.vbw/record.json"
  same "$(file_in Write tests/c1.sh workflow-subagent)"
  allowed
  same "$(bash_in 'printf x > tests/c1.sh' workflow-subagent)"
  allowed
  same "$(file_in Write .vbw/record.json workflow-subagent)"
  denied
}

@test "R150: under a build or fix run, an agent's file write on a record with no protected list is refused until this VBW saves it" {
  local kind
  for kind in build fix; do
    record_edit ".lease.kind = \"$kind\"" "$OLD/.vbw/record.json"
    ANSWER=$(answer "$OLD" "$(file_in Write src/pay.txt workflow-subagent)")
    unsaved_denied
    ANSWER=$(answer "$OLD" "$(file_in Edit tests/c1.sh workflow-subagent)")
    unsaved_denied
    ANSWER=$(answer "$OLD" "$(bash_in 'printf "paid\n" > src/pay.txt' workflow-subagent)")
    unsaved_denied
    # Reading stays allowed, and the main conversation is not held to the run.
    ANSWER=$(answer "$OLD" "$(file_in Read src/pay.txt workflow-subagent)")
    allowed
    ANSWER=$(answer "$OLD" "$(file_in Write src/pay.txt)")
    allowed
  done
  # Once this VBW has saved the record, the same write goes through.
  (cd "$OLD" && "$VBW" decide "saved again" > /dev/null)
  format4 "$OLD/.vbw/record.json"
  ANSWER=$(answer "$OLD" "$(file_in Write src/pay.txt workflow-subagent)")
  allowed
}

@test "R150: a file named only under checks, not on the protected list, is not seen by the guards" {
  record_edit '.checks[0].files += ["src/planted.txt"]' "$FOUR/.vbw/record.json"
  jq -e '(.protected | index("src/planted.txt")) == null' "$FOUR/.vbw/record.json"
  in4 "$(file_in Write src/planted.txt workflow-subagent)"
  allowed
  in4 "$(bash_in 'printf x > src/planted.txt' workflow-subagent)"
  allowed
  in4 "$(file_in Write tests/c1.sh workflow-subagent)"
  protected_denied
}

@test "R150: the guards' shared code holds no code that reads the checks and no 50-check threshold" {
  local code
  code=$(grep -v '^[[:space:]]*#' "$PLUGIN_ROOT/hooks/common.jq")
  ! printf '%s\n' "$code" | grep -nE 'check_files|"checks"|\.checks' || { echo "common.jq still reads the checks"; false; }
  ! grep -nE '>[[:space:]]*50([^0-9]|$)|\$big|50 checks' "$PLUGIN_ROOT/hooks/common.jq" || { echo "a 50-check threshold remains"; false; }
}
