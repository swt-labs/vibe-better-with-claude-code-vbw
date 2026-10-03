#!/usr/bin/env bats
# tools/baseline/bench.sh with a stub claude and a stub l3 driver (L1): record
# fields for both arms, resume, rerun, and the usage-limit stop.

load helper

BENCH="$BATS_TEST_DIRNAME/../tools/baseline/bench.sh"
SOLUTION="$BATS_TEST_DIRNAME/../tools/baseline/cases/fix-oneshot/solution.sh"

setup() {
  vbw_setup
  STUB="$PROJECT/stub"
  mkdir -p "$STUB/screens"
  # Stub claude: applies the known solution (BENCH_STUB_FIX=1) and prints the JSON result.
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
if [ -n "\${BENCH_STUB_LIMIT:-}" ]; then echo "You've hit your usage limit"; exit 1; fi
if [ -n "\${BENCH_STUB_FIX:-}" ]; then bash "$SOLUTION"; fi
echo '{"total_cost_usd":0.25,"usage":{"input_tokens":10,"output_tokens":20,"cache_creation_input_tokens":30,"cache_read_input_tokens":40}}'
EOF
  # Stub l3: logs every call; "wait" prints the next screen file (the last repeats);
  # "start" records the directory; "type /cost" makes the next wait print a cost line.
  cat > "$STUB/l3.sh" <<EOF
#!/usr/bin/env bash
cmd=\$1; shift
echo "\$cmd \$*" >> "$STUB/calls"
case "\$cmd" in
  start) echo "\$2" > "$STUB/ws" ;;
  type) [ "\$2" != "/cost" ] || touch "$STUB/cost"
    # The session sets VBW up when asked (BENCH_STUB_VBW=1).
    [ -z "\${BENCH_STUB_VBW:-}" ] || mkdir -p "\$(cat "$STUB/ws")/.vbw" ;;
  wait)
    if [ -e "$STUB/cost" ]; then echo "Total cost:            \\\$1.50"; exit 0; fi
    n=\$(cat "$STUB/n" 2>/dev/null || echo 1)
    f="$STUB/screens/\$n"; [ -e "\$f" ] || { n=\$((n - 1)); f="$STUB/screens/\$n"; }
    cat "\$f"; echo \$((n + 1)) > "$STUB/n"
    if [ -n "\${BENCH_STUB_FIX:-}" ]; then (cd "\$(cat "$STUB/ws")" && bash "$SOLUTION"); fi ;;
esac
exit 0
EOF
  # Stub next: VBW's next action in the workspace, one line of $STUB/actions per
  # call (the last repeats).
  cat > "$STUB/next" <<EOF
#!/usr/bin/env bash
n=\$(cat "$STUB/an" 2>/dev/null || echo 1)
a=\$(sed -n "\${n}p" "$STUB/actions"); [ -n "\$a" ] || a=\$(tail -1 "$STUB/actions")
echo \$((n + 1)) > "$STUB/an"
echo "\$a"
EOF
  printf 'ship\n' > "$STUB/actions"
  chmod +x "$STUB/claude" "$STUB/l3.sh" "$STUB/next"
  export BENCH_CLAUDE="$STUB/claude" BENCH_L3="$STUB/l3.sh" BENCH_NEXT="$STUB/next"
  export BENCH_RUNS_DIR="$PROJECT/runs" BENCH_SCRATCH="$PROJECT/scratch"
  export BENCH_CONFIG_DIR="$PROJECT/config"
}
teardown() { vbw_teardown; }

@test "plain arm writes an L2 record with tokens, cost and a graded pass" {
  BENCH_STUB_FIX=1 run bash "$BENCH" plain sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  f="$PROJECT/runs/plain-sonnet-5.5-fix-oneshot-1.json"
  run jq -c '[.arm,.model,.case,.run,.pass,.tokens,.cost_usd,.user_inputs,.level,.fixture]' "$f"
  [ "$output" = '["plain","sonnet-5.5","fix-oneshot",1,true,100,0.25,0,"L2","fix-oneshot"]' ]
}

@test "plain arm records pass false when the case check fails" {
  run bash "$BENCH" plain opus-5.5 fix-oneshot 2
  [ "$status" -eq 0 ]
  run jq -r '.pass' "$PROJECT/runs/plain-opus-5.5-fix-oneshot-2.json"
  [ "$output" = "false" ]
}

# vbw2_transcript: a transcript of the session (main and subagent), 10 tokens each.
vbw2_transcript() {
  local ws enc u
  ws="$PROJECT/scratch/vbw2-sonnet-5.5-fix-oneshot-1"
  mkdir -p "$ws"; ws=$(cd "$ws" && pwd -P)
  enc=$(printf '%s' "$ws" | sed 's/[^A-Za-z0-9]/-/g')
  mkdir -p "$PROJECT/config/projects/$enc/s1/subagents"
  u='"usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":3,"cache_read_input_tokens":4}'
  echo "{\"type\":\"assistant\",\"message\":{\"id\":\"a\",$u}}" > "$PROJECT/config/projects/$enc/s1.jsonl"
  echo "{\"type\":\"assistant\",\"message\":{\"id\":\"b\",$u}}" > "$PROJECT/config/projects/$enc/s1/subagents/agent-1.jsonl"
  # Written by this run's session: newer than the run's start.
  touch -t 209901010000 "$PROJECT/config/projects/$enc/s1.jsonl" "$PROJECT/config/projects/$enc/s1/subagents/agent-1.jsonl"
}

@test "vbw2 arm follows VBW's next step to the end, counts the user's inputs and records L3" {
  # A question; then VBW asks for approval; a run works in the background (wait,
  # type nothing); the session goes quiet (continue with /vbw:vibe); then ship.
  printf 'Pick one\n 1. A (Recommended)\nEnter to select\n' > "$STUB/screens/1"
  printf 'Plan ready.\n' > "$STUB/screens/2"
  printf 'Building...\n' > "$STUB/screens/3"
  printf 'Waiting.\n' > "$STUB/screens/4"
  printf 'Done. All checks pass.\n' > "$STUB/screens/5"
  printf 'spec\napprove\nrun\nbuild\nship\n' > "$STUB/actions"
  vbw2_transcript
  BENCH_STUB_FIX=1 run bash "$BENCH" vbw2 sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  run jq -c '[.arm,.pass,.tokens,.cost_usd,.user_inputs,.level]' "$PROJECT/runs/vbw2-sonnet-5.5-fix-oneshot-1.json"
  [ "$output" = '["vbw2",true,20,1.50,3,"L3"]' ]
  grep -q '^type bench-sonnet-5-5-fix-oneshot-1 /vbw:vibe ' "$STUB/calls"
  grep -q '^keys bench-sonnet-5-5-fix-oneshot-1 Enter' "$STUB/calls"
  grep -q '^type bench-sonnet-5-5-fix-oneshot-1 /vbw:approve' "$STUB/calls"
  [ "$(grep -c '^type bench-sonnet-5-5-fix-oneshot-1 /vbw:vibe$' "$STUB/calls")" -eq 1 ]
  # tmux reads a dot in a session name as a window.pane separator.
  ! grep -q '^[a-z]* [^ ]*[.]' "$STUB/calls" || { cat "$STUB/calls"; false; }
}

@test "a transcript left by an earlier run of the same workspace is not counted" {
  printf 'Done. All checks pass.\n' > "$STUB/screens/1"
  printf 'ship\n' > "$STUB/actions"
  vbw2_transcript
  enc=$(printf '%s' "$(cd "$PROJECT/scratch/vbw2-sonnet-5.5-fix-oneshot-1" && pwd -P)" | sed 's/[^A-Za-z0-9]/-/g')
  u='"usage":{"input_tokens":100,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}'
  echo "{\"type\":\"assistant\",\"message\":{\"id\":\"old\",$u}}" > "$PROJECT/config/projects/$enc/s0.jsonl"
  touch -t 200001010000 "$PROJECT/config/projects/$enc/s0.jsonl"
  BENCH_STUB_FIX=1 run bash "$BENCH" vbw2 sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  run jq '.tokens' "$PROJECT/runs/vbw2-sonnet-5.5-fix-oneshot-1.json"
  [ "$output" = "20" ]
}

@test "a finished run stops even with a question on screen, without answering it" {
  printf 'Ship M1?\n 1. Ship M1\nEnter to select\n' > "$STUB/screens/1"
  printf 'ship\n' > "$STUB/actions"
  vbw2_transcript
  BENCH_STUB_FIX=1 run bash "$BENCH" vbw2 sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  ! grep -q '^keys bench-sonnet-5-5-fix-oneshot-1 Enter' "$STUB/calls"
  run jq -r '.user_inputs' "$PROJECT/runs/vbw2-sonnet-5.5-fix-oneshot-1.json"
  [ "$output" = 0 ]
}

@test "a Claude Code dialog that is not a VBW question is dismissed with Escape, not answered" {
  printf 'Teach auto mode about your environment?\n  Continue\n<-/-> to change . Enter to continue . Esc to cancel\n' > "$STUB/screens/1"
  printf 'Done.\n' > "$STUB/screens/2"
  printf 'build\nship\n' > "$STUB/actions"
  vbw2_transcript
  BENCH_STUB_FIX=1 run bash "$BENCH" vbw2 sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  grep -q '^keys bench-sonnet-5-5-fix-oneshot-1 Escape' "$STUB/calls"
  ! grep -q '^keys bench-sonnet-5-5-fix-oneshot-1 Enter' "$STUB/calls"
  run jq -r '.user_inputs' "$PROJECT/runs/vbw2-sonnet-5.5-fix-oneshot-1.json"
  [ "$output" = 0 ]
}

@test "a run that makes no progress after three nudges ends, bounded" {
  printf 'Idle.\n' > "$STUB/screens/1"
  printf 'build\n' > "$STUB/actions"
  vbw2_transcript
  BENCH_STUB_FIX=1 run bash "$BENCH" vbw2 sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  [ "$(grep -c '^type bench-sonnet-5-5-fix-oneshot-1 /vbw:vibe$' "$STUB/calls")" -eq 3 ]
  run jq -r '.user_inputs' "$PROJECT/runs/vbw2-sonnet-5.5-fix-oneshot-1.json"
  [ "$output" = 3 ]
}

@test "a run where VBW was never set up is recorded as not engaged" {
  printf 'Fixed it directly.\n' > "$STUB/screens/1"
  printf 'none\n' > "$STUB/actions"
  vbw2_transcript
  BENCH_STUB_FIX=1 run bash "$BENCH" vbw2 sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  run jq -c '[.pass, .vbw_engaged]' "$PROJECT/runs/vbw2-sonnet-5.5-fix-oneshot-1.json"
  [ "$output" = '[true,false]' ]
}

@test "a run where VBW was set up is recorded as engaged" {
  printf 'Done.\n' > "$STUB/screens/1"
  printf 'ship\n' > "$STUB/actions"
  vbw2_transcript
  BENCH_STUB_FIX=1 BENCH_STUB_VBW=1 run bash "$BENCH" vbw2 sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  run jq -r '.vbw_engaged' "$PROJECT/runs/vbw2-sonnet-5.5-fix-oneshot-1.json"
  [ "$output" = true ]
}

@test "a session that cannot start writes no record (harness fault, exit 70)" {
  printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/l3.sh"
  run bash "$BENCH" vbw2 sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 70 ]
  [ ! -e "$PROJECT/runs/vbw2-sonnet-5.5-fix-oneshot-1.json" ]
}

@test "a vbw2 run with no session tokens writes no record (harness fault, exit 70)" {
  printf 'Done.\n' > "$STUB/screens/1"
  run bash "$BENCH" vbw2 sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 70 ]
  [ ! -e "$PROJECT/runs/vbw2-sonnet-5.5-fix-oneshot-1.json" ]
}

@test "an existing record is skipped, never overwritten" {
  mkdir -p "$PROJECT/runs"
  echo '{"keep":true}' > "$PROJECT/runs/plain-sonnet-5.5-fix-oneshot-1.json"
  run bash "$BENCH" plain sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  [ "$(jq -c . "$PROJECT/runs/plain-sonnet-5.5-fix-oneshot-1.json")" = '{"keep":true}' ]
}

@test "rerun writes a new record with rerun_of and keeps the original" {
  BENCH_STUB_FIX=1 bash "$BENCH" plain sonnet-5.5 fix-oneshot 1
  run bash "$BENCH" rerun plain sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  [ "$(jq -r '.rerun_of' "$PROJECT/runs/plain-sonnet-5.5-fix-oneshot-1-rerun1.json")" = "plain-sonnet-5.5-fix-oneshot-1.json" ]
  [ "$(jq -r '.pass' "$PROJECT/runs/plain-sonnet-5.5-fix-oneshot-1.json")" = "true" ]
}

@test "regrade re-checks the saved workspace: a new record, same tokens and cost, the original kept" {
  run bash "$BENCH" plain sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  orig="$PROJECT/runs/plain-sonnet-5.5-fix-oneshot-1.json"
  [ "$(jq -r .pass "$orig")" = false ]
  # The check is corrected after the run: here, the saved workspace now passes.
  (cd "$PROJECT/scratch/plain-sonnet-5.5-fix-oneshot-1" && bash "$SOLUTION")
  run bash "$BENCH" regrade plain sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  new="$PROJECT/runs/plain-sonnet-5.5-fix-oneshot-1-rerun1.json"
  run jq -c '[.pass, .tokens, .cost_usd, .user_inputs, .level, .rerun_of, .regraded]' "$new"
  [ "$output" = '[true,100,0.25,0,"L2","plain-sonnet-5.5-fix-oneshot-1.json",true]' ]
  [ "$(jq -r .pass "$orig")" = false ]
}

@test "regrade of a VBW 2 run records whether VBW was set up, from its workspace" {
  printf 'Done.\n' > "$STUB/screens/1"
  vbw2_transcript
  BENCH_STUB_FIX=1 BENCH_STUB_VBW=1 run bash "$BENCH" vbw2 sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  # An earlier record without the field, as the first runs wrote them.
  f="$PROJECT/runs/vbw2-sonnet-5.5-fix-oneshot-1.json"
  jq 'del(.vbw_engaged)' "$f" > "$f.n" && mv "$f.n" "$f"
  run bash "$BENCH" regrade vbw2 sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  run jq -r '.vbw_engaged' "$PROJECT/runs/vbw2-sonnet-5.5-fix-oneshot-1-rerun1.json"
  [ "$output" = true ]
}

@test "regrade without a saved workspace or record is refused" {
  run bash "$BENCH" regrade plain sonnet-5.5 fix-oneshot 2
  [ "$status" -ne 0 ]
  [ ! -e "$PROJECT/runs/plain-sonnet-5.5-fix-oneshot-2-rerun1.json" ]
}

@test "a usage limit stops with exit 75 and writes no record" {
  BENCH_STUB_LIMIT=1 run bash "$BENCH" plain sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 75 ]
  [ -z "$(ls "$PROJECT/runs" 2>/dev/null)" ]
  printf 'You have reached your usage limit\n' > "$STUB/screens/1"
  run bash "$BENCH" vbw2 sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 75 ]
  [ -z "$(ls "$PROJECT/runs" 2>/dev/null)" ]
}

@test "all stops on a usage limit without writing records" {
  BENCH_STUB_LIMIT=1 run bash "$BENCH" all sonnet-5.5
  [ "$status" -eq 75 ]
  [ -z "$(ls "$PROJECT/runs" 2>/dev/null)" ]
}

@test "bad arguments are refused" {
  run bash "$BENCH" bogus sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 2 ]
  run bash "$BENCH" plain gpt fix-oneshot 1
  [ "$status" -eq 2 ]
}

# l3_start [ARG...]: tools/l3.sh start with a stub tmux that logs its arguments
# (L1; no session runs).
l3_start() {
  mkdir -p "$STUB/bin"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/tmux"\n[ "$1" != capture-pane ] || echo welcome\nexit 0\n' "$STUB" > "$STUB/bin/tmux"
  chmod +x "$STUB/bin/tmux"
  PATH="$STUB/bin:$PATH" run bash "$BATS_TEST_DIRNAME/../tools/l3.sh" start t "$PROJECT" sonnet "$@"
  [ "$status" -eq 0 ]
}

@test "l3 start excludes the VBW repository's own CLAUDE.md and AGENTS.md" {
  l3_start
  root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  line=$(grep 'new-session' "$STUB/tmux")
  settings=$(printf '%s' "$line" | sed -n "s/.*--settings '\\(.*\\)' --debug-file.*/\\1/p")
  run jq -c '.claudeMdExcludes' <<< "$settings"
  [ "$output" = "[\"$root/CLAUDE.md\",\"$root/AGENTS.md\"]" ]
  [ "$(jq -r '.sandbox.enabled' <<< "$settings")" = true ]
}

@test "l3 start loads the plugin by default and not in plain mode" {
  l3_start
  grep 'new-session' "$STUB/tmux" | grep -q -- '--plugin-dir'
  rm "$STUB/tmux"
  l3_start plain
  ! grep 'new-session' "$STUB/tmux" | grep -q -- '--plugin-dir'
  grep 'new-session' "$STUB/tmux" | grep -q 'claudeMdExcludes'
}

@test "the headless plain arm also excludes the VBW repository's instruction files" {
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/args"\necho "{\\"total_cost_usd\\":0.25,\\"usage\\":{}}"\n' "$STUB" > "$STUB/claude"
  run bash "$BENCH" plain sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  s=$(grep claudeMdExcludes "$STUB/args")
  [ "$(jq -c '.claudeMdExcludes' <<< "$s")" = "[\"$root/CLAUDE.md\",\"$root/AGENTS.md\"]" ]
}

@test "plain-ui arm types the bare request, answers questions, and records arm plain at L3" {
  printf 'Pick one\n 1. A (Recommended)\nEnter to select\n' > "$STUB/screens/1"
  printf 'Done.\n' > "$STUB/screens/2"
  ws="$PROJECT/scratch/plain-ui-sonnet-5.5-fix-oneshot-1"
  mkdir -p "$ws"; ws=$(cd "$ws" && pwd -P)
  enc=$(printf '%s' "$ws" | sed 's/[^A-Za-z0-9]/-/g')
  mkdir -p "$PROJECT/config/projects/$enc"
  echo '{"type":"assistant","message":{"id":"a","usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":3,"cache_read_input_tokens":4}}}' > "$PROJECT/config/projects/$enc/s.jsonl"
  touch -t 209901010000 "$PROJECT/config/projects/$enc/s.jsonl"
  BENCH_STUB_FIX=1 run bash "$BENCH" plain-ui sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 0 ]
  run jq -c '[.arm,.pass,.tokens,.cost_usd,.user_inputs,.level]' "$PROJECT/runs/plain-sonnet-5.5-fix-oneshot-1.json"
  [ "$output" = '["plain",true,10,1.50,1,"L3"]' ]
  grep -q '^start bench-plain-sonnet-5-5-fix-oneshot-1 .* claude-sonnet-5-5 plain' "$STUB/calls"
  ! grep -q '/vbw:' "$STUB/calls"
  grep -q '^type bench-plain-sonnet-5-5-fix-oneshot-1 ' "$STUB/calls"
}

@test "plain-ui arm stops on a usage limit with no record" {
  printf 'You have reached your usage limit\n' > "$STUB/screens/1"
  run bash "$BENCH" plain-ui sonnet-5.5 fix-oneshot 1
  [ "$status" -eq 75 ]
  [ -z "$(ls "$PROJECT/runs" 2>/dev/null)" ]
}
