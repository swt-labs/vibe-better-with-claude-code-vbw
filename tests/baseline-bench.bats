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
  type) [ "\$2" != "/cost" ] || touch "$STUB/cost" ;;
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
}

@test "vbw2 arm follows VBW's next step to the end, counts the user's inputs and records L3" {
  # A question; then VBW asks for approval; a run works in the background (wait,
  # type nothing); the session goes quiet (continue with /vbw:vibe); then ship.
  printf 'Pick one\n 1. A (Recommended)\nEnter to select\n' > "$STUB/screens/1"
  printf 'Plan ready.\n' > "$STUB/screens/2"
  printf 'Building...\n' > "$STUB/screens/3"
  printf 'Waiting.\n' > "$STUB/screens/4"
  printf 'Done. All checks pass.\n' > "$STUB/screens/5"
  printf 'approve\nrun\nbuild\nship\n' > "$STUB/actions"
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
