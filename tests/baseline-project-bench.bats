#!/usr/bin/env bats
# bench.sh runs a multi-requirement project (tools/baseline/projects) like a
# case, and report-projects.sh prints both arms side by side (L1, stubs and
# synthetic records).

load helper

BENCH="$BATS_TEST_DIRNAME/../tools/baseline/bench.sh"
REPORT="$BATS_TEST_DIRNAME/../tools/baseline/report-projects.sh"
SOLUTION="$BATS_TEST_DIRNAME/../tools/baseline/projects/data-migration/solution.sh"

setup() {
  vbw_setup
  STUB="$PROJECT/stub"
  mkdir -p "$STUB"
  cat > "$STUB/claude" <<EOT
#!/usr/bin/env bash
if [ -n "\${BENCH_STUB_FIX:-}" ]; then bash "$SOLUTION"; fi
echo '{"total_cost_usd":0.5,"usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":3,"cache_read_input_tokens":4}}'
EOT
  chmod +x "$STUB/claude"
  export BENCH_CLAUDE="$STUB/claude" BENCH_RUNS_DIR="$PROJECT/runs" BENCH_SCRATCH="$PROJECT/scratch"
  export BENCH_CONFIG_DIR="$PROJECT/config"
}
teardown() { vbw_teardown; }

@test "bench.sh runs a project from tools/baseline/projects and grades it with the project's check" {
  BENCH_STUB_FIX=1 run bash "$BENCH" plain sonnet-5.5 data-migration 1
  [ "$status" -eq 0 ]
  run jq -c '[.arm,.case,.pass,.tokens,.fixture]' "$PROJECT/runs/plain-sonnet-5.5-data-migration-1.json"
  [ "$output" = '["plain","data-migration",true,10,"data-migration"]' ]
}

@test "a project the solution did not touch fails its check, and an unknown name is refused" {
  run bash "$BENCH" plain sonnet-5.5 protected-feature 1
  [ "$status" -eq 0 ]
  run jq -r '.pass' "$PROJECT/runs/plain-sonnet-5.5-protected-feature-1.json"
  [ "$output" = "false" ]
  run bash "$BENCH" plain sonnet-5.5 no-such-project 1
  [ "$status" -eq 2 ]
}

# rec ARM MODEL PROJECT RUN PASS TOKENS COST
rec() {
  mkdir -p "$PROJECT/runs"
  jq -n --arg arm "$1" --arg model "$2" --arg case "$3" --argjson run "$4" --argjson pass "$5" \
    --argjson tokens "$6" --argjson cost "$7" \
    '{arm:$arm,model:$model,case:$case,run:$run,pass:$pass,tokens:$tokens,cost_usd:$cost,user_inputs:0,level:"L3"}' \
    > "$PROJECT/runs/$1-$2-$3-$4.json"
}

@test "report-projects prints a table per project and model with both arms" {
  rec plain sonnet-5.5 data-migration 1 true 1000 1.00
  rec plain sonnet-5.5 data-migration 2 false 3000 3.00
  rec vbw2 sonnet-5.5 data-migration 1 true 5000 2.50
  run bash "$REPORT" "$PROJECT/runs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Project: data-migration"* ]]
  [[ "$output" == *"### sonnet-5.5"* ]]
  [[ "$output" == *"| plain Claude Code | 1/2 | \$2.00 | 2000 |"* ]]
  [[ "$output" == *"| VBW 2 | 1/1 | \$2.50 | 5000 |"* ]]
}

@test "report-projects names a missing arm and ignores the cases that are not projects" {
  rec plain sonnet-5.5 non-ui-pipeline 1 true 1000 1.00
  rec plain sonnet-5.5 fix-oneshot 1 true 1000 1.00
  run bash "$REPORT" "$PROJECT/runs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No VBW 2 runs yet"* ]]
  [[ "$output" != *"fix-oneshot"* ]]
}
