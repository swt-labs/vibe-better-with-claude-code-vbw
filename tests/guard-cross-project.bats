#!/usr/bin/env bats
# R254 (T233; docs/guards.md): a write is judged by the project it lands in. The
# Bash and file guards resolve every write target to its own project (the nearest
# folder above the target holding .vbw/record.json beside .git): a path after cd,
# an absolute path and a path reached from a linked worktree included, and judge
# it by that project's record and lease exactly as a write from inside that
# project, with the same refusal texts. A target inside a worktree with a record
# of its own is judged by that record; a target outside every project is judged as
# today (R177); when the target's record cannot be read while its run is open the
# call is refused fail-closed with today's text. The extra record read happens only
# when the target leaves the hook's project (the bench's cross-project case,
# tools/bench-hooks.sh). L1: the hooks.json commands run as Claude Code runs them
# (sh -c, hook input on stdin) with a linked worktree as the project folder.

load helper
load fixture-helper

# built: an approved shop whose record is committed with no lease. Each test gets
# MAIN, a copy of it, a linked worktree WT of MAIN beside it (its own record is the
# committed one, with no lease) and a build run of P1.1 open in MAIN (lease files
# src/pay.txt; tests/c1.sh protected).
built() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/c1.sh
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "pay", criteria: ["pays"], tier: "express"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]}],
    rules: [{req: "R1", text: "paid is written", check: "C1"}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  [ -z "$(git status --porcelain)" ] || { git add -A && git commit -q -m "feat(shop): start"; }
}

setup_file() { fixture_build built built; }
# The worktree and the run are made on the copy at hand: a fixture never holds its
# own path, and a worktree's .git file names the repository's.
setup() {
  fixture_copy built
  MAIN=$PWD
  WT="$TEST_ROOT/work tree"
  git worktree add -q "$WT" -b wt > /dev/null 2>&1
  jq -e '.lease == null' "$WT/.vbw/record.json" > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  mkdir -p "$TEST_ROOT/elsewhere"
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# hook DIR TOOL INPUT_JSON: the shipped hooks.json command for TOOL, run as Claude
# Code runs it with DIR as the project folder. Sets CODE, OUT (stdout) and ERR.
hook() {
  local cmd
  cmd=$(jq -r --arg t "$2" '[.hooks.PreToolUse[] | select((.matcher // "") as $m | $t | test("^(" + $m + ")$"))][0].hooks[0].command' "$PLUGIN_ROOT/hooks/hooks.json")
  CODE=0
  OUT=$(printf '%s' "$3" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$1" sh -c "$cmd" 2> "$TEST_ROOT/err") || CODE=$?
  ERR=$(cat "$TEST_ROOT/err")
}
bash_in() { jq -nc --arg d "$1" --arg c "$2" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "Bash", agent_id: "a1", agent_type: "vbw:dev", tool_input: {command: $c}}'; }
edit_in() { jq -nc --arg d "$1" --arg p "$2" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "Edit", agent_id: "a1", agent_type: "vbw:dev", tool_input: {file_path: $p, old_string: "a", new_string: "b"}}'; }
reason() { printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'; }
denied() { [ "$CODE" -eq 0 ] && [ "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty')" = deny ] || { echo "not denied (exit $CODE): $OUT $ERR"; return 1; }; }
allowed() { [ "$CODE" -eq 0 ] && [ -z "$OUT" ] || { echo "not allowed (exit $CODE): $OUT $ERR"; return 1; }; }

PY_WRITE=$'python3 - <<\'EOF\'\nopen("tests/x.sh", "w").write("x")\nEOF'

# same_as DIR TOOL INPUT WANT_TOOL WANT_INPUT: the call from DIR is refused with
# exactly the reason the second call gets from inside MAIN.
same_as() {
  local got want
  hook "$MAIN" "$4" "$5"
  denied || return 1
  want=$(reason)
  hook "$1" "$2" "$3"
  denied || return 1
  got=$(reason)
  [ "$got" = "$want" ] || { printf 'the reasons differ\n  from the worktree: %s\n  from MAIN:         %s\n' "$got" "$want"; return 1; }
}

@test "R254: from a linked worktree, a cd into MAIN followed by a program write, a shell write by absolute path and an Edit by absolute path of a file outside MAIN's lease are refused under MAIN's build run with the very reasons the same calls get inside MAIN" {
  same_as "$WT" Bash "$(bash_in "$WT" "cd \"$MAIN\" && $PY_WRITE")" Bash "$(bash_in "$MAIN" "$PY_WRITE")"
  same_as "$WT" Bash "$(bash_in "$WT" "echo x > \"$MAIN/tests/x.sh\"")" Bash "$(bash_in "$MAIN" 'echo x > tests/x.sh')"
  same_as "$WT" Edit "$(edit_in "$WT" "$MAIN/tests/x.sh")" Edit "$(edit_in "$MAIN" "$MAIN/tests/x.sh")"
  # A protected check file of MAIN gets MAIN's protected-file refusal.
  same_as "$WT" Edit "$(edit_in "$WT" "$MAIN/tests/c1.sh")" Edit "$(edit_in "$MAIN" "$MAIN/tests/c1.sh")"
  same_as "$WT" Bash "$(bash_in "$WT" "printf x >> \"$MAIN/tests/c1.sh\"")" Bash "$(bash_in "$MAIN" 'printf x >> tests/c1.sh')"
  [[ "$(reason)" == *"protected check file"* ]]
  # A path reached through MAIN with .. from the worktree is the same target.
  same_as "$WT" Bash "$(bash_in "$WT" "echo x > \"$MAIN/src/../tests/x.sh\"")" Bash "$(bash_in "$MAIN" 'echo x > tests/x.sh')"
}

@test "R254: the same three calls are allowed once MAIN has no run open; the worktree's own copy is judged by its own record (no lease), and a target outside every project is judged as today" {
  hook "$WT" Edit "$(edit_in "$WT" "$WT/tests/c1.sh")"
  allowed
  hook "$WT" Bash "$(bash_in "$WT" 'echo x > tests/x.sh')"
  allowed
  hook "$WT" Bash "$(bash_in "$WT" "$PY_WRITE")"
  allowed
  # Outside every project: as today, refused under MAIN's run from MAIN, allowed from the worktree.
  hook "$MAIN" Edit "$(edit_in "$MAIN" "$TEST_ROOT/elsewhere/x.txt")"
  denied && [[ "$(reason)" == *"outside the project"* ]] || { echo "$OUT"; false; }
  hook "$WT" Edit "$(edit_in "$WT" "$TEST_ROOT/elsewhere/x.txt")"
  allowed
  (cd "$MAIN" && VBW_SESSION_ID=s1 "$VBW" run end > /dev/null)
  hook "$WT" Bash "$(bash_in "$WT" "cd \"$MAIN\" && $PY_WRITE")"
  allowed
  hook "$WT" Bash "$(bash_in "$WT" "echo x > \"$MAIN/tests/x.sh\"")"
  allowed
  hook "$WT" Edit "$(edit_in "$WT" "$MAIN/tests/x.sh")"
  allowed
}

@test "R254: a target in MAIN whose record cannot be read while MAIN's run is open is refused fail-closed with today's text, from the worktree as from MAIN" {
  rm -f "$MAIN/.vbw/runtime/glance.json"
  printf '{' > "$MAIN/.vbw/record.json"
  hook "$MAIN" Edit "$(edit_in "$MAIN" "$MAIN/tests/x.sh")"
  [ "$CODE" -eq 2 ] && [[ "$ERR" == *"VBW guard: the guard failed while a run is open"* ]] || { echo "exit $CODE: $OUT $ERR"; false; }
  hook "$WT" Edit "$(edit_in "$WT" "$MAIN/tests/x.sh")"
  [ "$CODE" -eq 2 ] && [[ "$ERR" == *"VBW guard: the guard failed while a run is open"* ]] || { echo "exit $CODE: $OUT $ERR"; false; }
  hook "$WT" Bash "$(bash_in "$WT" "echo x > \"$MAIN/tests/x.sh\"")"
  [ "$CODE" -eq 2 ] && [[ "$ERR" == *"VBW guard: the guard failed while a run is open"* ]] || { echo "exit $CODE: $OUT $ERR"; false; }
  # The worktree's own files are still judged by its own, readable record.
  hook "$WT" Edit "$(edit_in "$WT" "$WT/tests/x.sh")"
  allowed
}

@test "R254: tools/bench-hooks.sh has a cross-project case beside the same-project ones" {
  run env VBW_BENCH_ONLY='guard (cross-project' VBW_BENCH_RUNS=2 VBW_HOOK_BUDGET_MS=100000 bash "$BATS_TEST_DIRNAME/../tools/bench-hooks.sh"
  [ "$status" -eq 0 ] || { echo "$status: $output"; false; }
  [[ "$output" == *$'\nguard (cross-project'* ]] || { echo "$output"; false; }
}
