#!/usr/bin/env bats
# R124 (L1): the What's next section keeps the panel within its budgets: the
# panel bench measures a refresh that draws a stored recommendation, within
# VBW_PANEL_BUDGET_MS, and all mod JavaScript (plugin/hooks/*.js) stays within
# 3,500 lines. docs/panel.md describes the section and the Suggest next button.
# The section's behaviour is in tests/panel/whats-next.test.mjs.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

BENCH="$BATS_TEST_DIRNAME/../tools/bench-panel.sh"
DOC="$REPO_ROOT/docs/panel.md"

flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
has() { flat "$1" | grep -qE -- "$2" || { echo "docs/panel.md lacks: $2"; return 1; }; }

@test "R124: the panel bench measures a refresh that draws the What's next section, within the budget" {
  command -v node > /dev/null 2>&1 || { echo "node is needed for the panel bench"; false; }
  VBW_BENCH_RUNS=30 run bash "$BENCH"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" =~ (^|$'\n')"refresh with what's next: "[0-9.]+" ms CPU" ]] || { echo "$output"; false; }
  grep -q 'recommendation' "$REPO_ROOT/tools/bench-panel.mjs"
}

@test "R124: all mod JavaScript stays within 3,500 lines" {
  local total=0 file n
  while IFS= read -r file; do
    n=$(grep -cvE '^[[:space:]]*(//|$)' "$file" || true)
    total=$((total + n))
  done < <(find "$PLUGIN_ROOT/hooks" -type f -name '*.js')
  echo "mod lines: $total"
  [ "$total" -le 3500 ]
}

@test "R124: docs/panel.md describes the What's next section and the Suggest next button" {
  has "$DOC" "what's next"
  has "$DOC" 'suggest next'
  has "$DOC" 'top pick'
  has "$DOC" 'runners-up'
  has "$DOC" "/vbw:vibe what's next"
  has "$DOC" '(never|does not|without) send'
  has "$DOC" 'none yet'
  has "$DOC" 'shimmer'
  has "$DOC" 'pulse'
  has "$DOC" 'motion'
}
