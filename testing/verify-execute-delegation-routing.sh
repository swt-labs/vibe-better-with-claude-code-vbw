#!/usr/bin/env bash
set -euo pipefail

# verify-execute-delegation-routing.sh — dependency-aware Execute routing contract

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/scripts/resolve-execute-delegation-mode.sh"
GENERATE_CONTRACT="$ROOT/scripts/generate-contract.sh"
STATE_UPDATER="$ROOT/scripts/state-updater.sh"
EXECUTE_PROTOCOL="$ROOT/references/execute-protocol.md"

PASS=0
FAIL=0
TMPDIR_BASE=""

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

cleanup() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE" 2>/dev/null || true
}
trap cleanup EXIT

require_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    echo "ERROR: missing required file: $path" >&2
    exit 1
  fi
}

make_fixture() {
  local name="$1"
  local prefer="${2:-auto}"
  local effort="${3:-balanced}"
  FIXTURE="$TMPDIR_BASE/$name"
  PHASE_DIR="$FIXTURE/.vbw-planning/phases/01-test"
  mkdir -p "$PHASE_DIR" "$FIXTURE/.vbw-planning/.cache"
  printf '{"prefer_teams":%s,"effort":"%s"}\n' "$prefer" "$effort" > "$FIXTURE/.vbw-planning/config.json"
}

write_state() {
  local json="$1"
  printf '%s\n' "$json" > "$FIXTURE/.vbw-planning/.execution-state.json"
}

write_plan_inline() {
  local filename="$1"
  local phase="$2"
  local plan="$3"
  local depends="$4"
  cat > "$PHASE_DIR/$filename" <<PLAN
---
phase: $phase
plan: $plan
title: Plan $plan
depends_on: $depends
---
# Plan $plan

### Task 1: Work
- **Files:** \`src/$plan.txt\`
PLAN
}

write_plan_block() {
  local filename="$1"
  local phase="$2"
  local plan="$3"
  shift 3
  {
    printf '%s\n' '---'
    printf 'phase: %s\n' "$phase"
    printf 'plan: %s\n' "$plan"
    printf 'title: Plan %s\n' "$plan"
    printf '%s\n' 'depends_on:'
    local dep
    for dep in "$@"; do
      printf '  - %s\n' "$dep"
    done
    printf '%s\n' '---' '# Plan' '' '### Task 1: Work' '- **Files:** `src/file.txt`'
  } > "$PHASE_DIR/$filename"
}

run_helper() {
  (cd "$FIXTURE" && "$HELPER" --phase-dir .vbw-planning/phases/01-test "${@}")
}

json_field() {
  local json="$1"
  local expr="$2"
  jq -r "$expr" <<< "$json"
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

assert_json_array_eq() {
  local actual_json="$1"
  local expected_json="$2"
  local label="$3"
  if jq -ne --argjson actual "$actual_json" --argjson expected "$expected_json" '$actual == $expected' >/dev/null; then
    pass "$label"
  else
    fail "$label (expected $expected_json, got $actual_json)"
  fi
}

expect_helper_failure() {
  local label="$1"
  shift
  local out status reason
  set +e
  out=$(run_helper "$@" 2>/dev/null)
  status=$?
  set -e
  reason=$(jq -r '.reason // empty' <<< "$out" 2>/dev/null || true)
  if [ "$status" -ne 0 ] && [ "$reason" = "invalid_dependency_graph" ]; then
    pass "$label"
  else
    fail "$label (status=$status reason='${reason:-}' output='${out:-}')"
  fi
}

require_file "$HELPER"
require_file "$GENERATE_CONTRACT"
require_file "$STATE_UPDATER"
require_file "$EXECUTE_PROTOCOL"

TMPDIR_BASE=$(mktemp -d)

echo "=== Execute Delegation Routing Contract Tests ==="

# auto + linear two-plan chain -> subagent
make_fixture linear '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
write_plan_inline 01-02-PLAN.md 01 02 '["01-01"]'
out=$(run_helper)
assert_eq "$(json_field "$out" '.delegation_mode')" "subagent" "auto + linear graph -> subagent"
assert_eq "$(json_field "$out" '.max_parallel_width')" "1" "auto + linear graph has max_parallel_width=1"
assert_json_array_eq "$(jq -c '.dependency_waves' <<< "$out")" '[["01-01"],["01-02"]]' "auto + linear graph waves are serialized"

# auto + two independent delegate plans -> team
make_fixture independent '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
write_plan_inline 01-02-PLAN.md 01 02 '[]'
out=$(run_helper)
assert_eq "$(json_field "$out" '.delegation_mode')" "team" "auto + two independent delegate plans -> team"
assert_eq "$(json_field "$out" '.max_parallel_width')" "2" "independent graph has max_parallel_width=2"

# auto + completed prerequisite unlocks two delegate plans -> team
make_fixture completed-prereq '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"complete"},{"id":"01-02","status":"pending"},{"id":"01-03","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
write_plan_inline 01-02-PLAN.md 01 02 '["01-01"]'
write_plan_inline 01-03-PLAN.md 01 03 '["01-01"]'
out=$(run_helper)
assert_eq "$(json_field "$out" '.delegation_mode')" "team" "completed prerequisite unlocks two delegate plans -> team"
assert_eq "$(json_field "$out" '.max_parallel_width')" "2" "completed prerequisite graph has delegate width 2"

# auto + partial prerequisite unlocks dependent delegate plans
make_fixture partial-prereq '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"partial"},{"id":"01-02","status":"pending"},{"id":"01-03","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
write_plan_inline 01-02-PLAN.md 01 02 '["01-01"]'
write_plan_inline 01-03-PLAN.md 01 03 '["01-01"]'
out=$(run_helper)
assert_eq "$(json_field "$out" '.delegation_mode')" "team" "partial prerequisite unlocks dependent delegate plans for routing"
assert_json_array_eq "$(jq -c '.completed_satisfied_nodes' <<< "$out")" '["01-01"]' "partial prerequisite is reported as execute-satisfied"

# auto + single pending delegate plan -> subagent
make_fixture single '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
out=$(run_helper)
assert_eq "$(json_field "$out" '.delegation_mode')" "subagent" "auto + single pending delegate plan -> subagent"

# never + independent delegate plans -> subagent
make_fixture never '"never"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
write_plan_inline 01-02-PLAN.md 01 02 '[]'
out=$(run_helper)
assert_eq "$(json_field "$out" '.delegation_mode')" "subagent" "prefer_teams=never + independent plans -> subagent"

# always + linear delegate chain -> team unless excluded by turbo/direct
make_fixture always-linear '"always"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
write_plan_inline 01-02-PLAN.md 01 02 '["01-01"]'
out=$(run_helper)
assert_eq "$(json_field "$out" '.delegation_mode')" "team" "prefer_teams=always overrides delegate width for linear delegate graph"

# execution-state effort turbo overrides balanced config and bypasses team selection
make_fixture state-turbo '"always"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"}],"effort":"turbo","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
write_plan_inline 01-02-PLAN.md 01 02 '[]'
out=$(run_helper)
assert_eq "$(json_field "$out" '.effective_effort')" "turbo" "execution-state effort overrides config effort"
assert_eq "$(json_field "$out" '.delegation_mode')" "direct" "phase-level turbo bypasses team selection"
assert_eq "$(json_field "$out" '.requested_mode')" "turbo" "phase-level turbo reports requested_mode=turbo"

# single-plan smart-routed turbo bypasses always team override
make_fixture smart-turbo '"always"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
printf '{"plans":{"01-01":{"route":"turbo","reason":"smart_route"}}}\n' > "$FIXTURE/.vbw-planning/.cache/execute-route-map.json"
out=$(run_helper --route-map .vbw-planning/.cache/execute-route-map.json)
assert_eq "$(json_field "$out" '.delegation_mode')" "direct" "smart-routed turbo plan bypasses team even with prefer_teams=always"
assert_json_array_eq "$(jq -c '.turbo_plan_ids' <<< "$out")" '["01-01"]' "smart-routed turbo plan is reported"

# mixed routing: one turbo + one delegate -> no team for single delegate
make_fixture mixed-single-delegate '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
write_plan_inline 01-02-PLAN.md 01 02 '[]'
printf '{"plans":{"01-01":{"route":"turbo","reason":"smart_route"}}}\n' > "$FIXTURE/.vbw-planning/.cache/execute-route-map.json"
out=$(run_helper --route-map .vbw-planning/.cache/execute-route-map.json)
assert_eq "$(json_field "$out" '.delegate_count')" "1" "mixed turbo/delegate counts one delegate-eligible plan"
assert_eq "$(json_field "$out" '.delegation_mode')" "subagent" "mixed turbo + single delegate does not create team"

# mixed routing: direct excluded + two delegates independent -> team
make_fixture mixed-two-delegates '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"},{"id":"01-03","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
write_plan_inline 01-02-PLAN.md 01 02 '[]'
write_plan_inline 01-03-PLAN.md 01 03 '[]'
printf '{"plans":{"01-03":{"route":"direct","reason":"internal_direct"}}}\n' > "$FIXTURE/.vbw-planning/.cache/execute-route-map.json"
out=$(run_helper --route-map .vbw-planning/.cache/execute-route-map.json)
assert_eq "$(json_field "$out" '.delegate_count')" "2" "mixed direct/delegate counts two delegate-eligible plans"
assert_eq "$(json_field "$out" '.delegation_mode')" "team" "mixed direct + two independent delegates creates team"

# segment transitions: team -> direct, direct -> team, team -> subagent
make_fixture segment-team-direct '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"},{"id":"01-03","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
write_plan_inline 01-02-PLAN.md 01 02 '[]'
write_plan_inline 01-03-PLAN.md 01 03 '["01-01"]'
printf '{"plans":{"01-03":{"route":"direct","reason":"internal_direct"}}}\n' > "$FIXTURE/.vbw-planning/.cache/execute-route-map.json"
out=$(run_helper --route-map .vbw-planning/.cache/execute-route-map.json --segments)
assert_json_array_eq "$(jq -c '[.segments[].delegation_mode]' <<< "$out")" '["team","direct"]' "segments can transition team -> direct"

make_fixture segment-direct-team '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"},{"id":"01-03","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
write_plan_inline 01-02-PLAN.md 01 02 '["01-01"]'
write_plan_inline 01-03-PLAN.md 01 03 '["01-01"]'
printf '{"plans":{"01-01":{"route":"direct","reason":"internal_direct"}}}\n' > "$FIXTURE/.vbw-planning/.cache/execute-route-map.json"
out=$(run_helper --route-map .vbw-planning/.cache/execute-route-map.json --segments)
assert_json_array_eq "$(jq -c '[.segments[].delegation_mode]' <<< "$out")" '["direct","team"]' "segments can transition direct -> team"

make_fixture segment-team-subagent '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"},{"id":"01-03","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
write_plan_inline 01-02-PLAN.md 01 02 '[]'
write_plan_inline 01-03-PLAN.md 01 03 '["01-01", "01-02"]'
out=$(run_helper --segments)
assert_json_array_eq "$(jq -c '[.segments[].delegation_mode]' <<< "$out")" '["team","subagent"]' "segments can transition team -> subagent"

# invalid dependency graphs fail closed
make_fixture cyclic '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '["01-02"]'
write_plan_inline 01-02-PLAN.md 01 02 '["01-01"]'
expect_helper_failure "cyclic dependency graph fails closed with invalid_dependency_graph"

make_fixture unresolved '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '["01-99"]'
expect_helper_failure "unresolved dependency graph fails closed with invalid_dependency_graph"

make_fixture mismatch '"auto"' balanced
write_state '{"plans":[{"id":"01-02","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-02-PLAN.md 01 03 '[]'
expect_helper_failure "frontmatter plan mismatch fails closed with invalid_dependency_graph"

# malformed execution-state / route-map schemas fail closed before spawning
make_fixture valid-empty-plans '"auto"' balanced
write_state '{"plans":[],"effort":"balanced","phase_effort":"balanced"}'
out=$(run_helper)
assert_eq "$(json_field "$out" '.reason')" "no_remaining_plans" "valid empty execution-state plans array returns no_remaining_plans"

make_fixture missing-plans '"auto"' balanced
write_state '{"effort":"balanced","phase_effort":"balanced"}'
expect_helper_failure "missing execution-state plans fails closed with invalid_dependency_graph"

make_fixture scalar-plans '"auto"' balanced
write_state '{"plans":"oops","effort":"balanced","phase_effort":"balanced"}'
expect_helper_failure "scalar execution-state plans fails closed with invalid_dependency_graph"

make_fixture object-plans '"auto"' balanced
write_state '{"plans":{"01-01":{"status":"pending"}},"effort":"balanced","phase_effort":"balanced"}'
expect_helper_failure "object execution-state plans fails closed with invalid_dependency_graph"

make_fixture scalar-plan-entry '"auto"' balanced
write_state '{"plans":["01-01"],"effort":"balanced","phase_effort":"balanced"}'
expect_helper_failure "scalar execution-state plan entry fails closed with invalid_dependency_graph"

make_fixture missing-plan-id '"auto"' balanced
write_state '{"plans":[{"status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
expect_helper_failure "execution-state plan missing id fails closed with invalid_dependency_graph"

make_fixture empty-plan-id '"auto"' balanced
write_state '{"plans":[{"id":"","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
expect_helper_failure "execution-state plan empty id fails closed with invalid_dependency_graph"

make_fixture route-map-scalar-plans '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
printf '{"plans":"oops"}\n' > "$FIXTURE/.vbw-planning/.cache/execute-route-map.json"
expect_helper_failure "scalar route-map plans fails closed with invalid_dependency_graph" --route-map .vbw-planning/.cache/execute-route-map.json

make_fixture route-map-scalar-entry '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
printf '{"plans":{"01-01":"turbo"}}\n' > "$FIXTURE/.vbw-planning/.cache/execute-route-map.json"
expect_helper_failure "scalar route-map entry fails closed with invalid_dependency_graph" --route-map .vbw-planning/.cache/execute-route-map.json

make_fixture route-map-invalid-route '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
printf '{"plans":{"01-01":{"route":"parallel"}}}\n' > "$FIXTURE/.vbw-planning/.cache/execute-route-map.json"
expect_helper_failure "invalid route-map route fails closed with invalid_dependency_graph" --route-map .vbw-planning/.cache/execute-route-map.json

# prefer_teams canonicalization, including legacy aliases only in tests/helper code
for raw in '"when_parallel"' 'false' 'null' '""'; do
  make_fixture "canon-$raw" "$raw" balanced
  write_state '{"plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
  write_plan_inline 01-01-PLAN.md 01 01 '[]'
  write_plan_inline 01-02-PLAN.md 01 02 '[]'
  out=$(run_helper)
  assert_eq "$(json_field "$out" '.prefer_teams')" "auto" "prefer_teams $raw canonicalizes to auto"
done

make_fixture canon-true 'true' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
out=$(run_helper)
assert_eq "$(json_field "$out" '.prefer_teams')" "always" "prefer_teams true canonicalizes to always"
assert_eq "$(json_field "$out" '.delegation_mode')" "team" "prefer_teams true/always can force team for delegate work"

make_fixture canon-unknown '"surprise"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
write_plan_inline 01-02-PLAN.md 01 02 '[]'
out=$(run_helper)
assert_eq "$(json_field "$out" '.prefer_teams')" "surprise" "unknown prefer_teams value is preserved"
assert_eq "$(json_field "$out" '.delegation_mode')" "subagent" "unknown prefer_teams value returns subagent"
assert_eq "$(json_field "$out" '.reason')" "unknown_prefer_teams:surprise" "unknown prefer_teams emits diagnostic reason"

# Path resolution and dependency parser forms
make_fixture path-parser '"auto"' balanced
write_state '{"plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"},{"id":"01-03","status":"pending"}],"effort":"balanced","phase_effort":"balanced"}'
write_plan_inline 01-01-PLAN.md 01 01 '[]'
write_plan_block 02-PLAN.md 01 02 1
write_plan_inline 01-03-PLAN.md 01 03 '["01-02"]'
out=$(run_helper)
assert_json_array_eq "$(jq -c '.plans["01-02"].deps' <<< "$out")" '["01-01"]' "routing helper normalizes block numeric deps on legacy plan filename"
assert_json_array_eq "$(jq -c '.plans["01-03"].deps' <<< "$out")" '["01-02"]' "routing helper retains inline full-id string deps"

CONTRACT_FIXTURE="$TMPDIR_BASE/contract-parser"
mkdir -p "$CONTRACT_FIXTURE/.vbw-planning/phases/03-test"
printf '{"max_token_budget":50000,"task_timeout_seconds":600}\n' > "$CONTRACT_FIXTURE/.vbw-planning/config.json"
cat > "$CONTRACT_FIXTURE/.vbw-planning/phases/03-test/03-04-PLAN.md" <<'PLAN'
---
phase: 3
plan: 4
title: Contract Parser
depends_on:
  - 1
  - "03-02"
  - custom-id
---
# Plan

### Task 1: Work
- **Files:** `src/contract.txt`
PLAN
(cd "$CONTRACT_FIXTURE" && "$GENERATE_CONTRACT" .vbw-planning/phases/03-test/03-04-PLAN.md >/dev/null)
contract_deps=$(jq -c '.depends_on' "$CONTRACT_FIXTURE/.vbw-planning/.contracts/3-4.json")
assert_json_array_eq "$contract_deps" '["03-01","03-02","custom-id"]' "generate-contract retains normalized string dependency edges"

# state-updater: nonterminal/missing SUMMARY status must not mark complete or unlock dependents
STATE_FIXTURE="$TMPDIR_BASE/state-updater"
STATE_PHASE="$STATE_FIXTURE/.vbw-planning/phases/01-test"
mkdir -p "$STATE_PHASE"
printf '{"plans":[{"id":"01-01","status":"pending"}],"status":"running","phase":1}\n' > "$STATE_FIXTURE/.vbw-planning/.execution-state.json"
cat > "$STATE_PHASE/01-01-SUMMARY.md" <<'SUMMARY'
---
phase: 1
plan: 1
status: pending
---
Not terminal.
SUMMARY
printf '{"tool_input":{"file_path":"%s"}}\n' "$STATE_PHASE/01-01-SUMMARY.md" | (cd "$STATE_FIXTURE" && "$STATE_UPDATER")
state_status=$(jq -r '.plans[] | select(.id == "01-01") | .status' "$STATE_FIXTURE/.vbw-planning/.execution-state.json")
assert_eq "$state_status" "pending" "state-updater leaves nonterminal SUMMARY status unchanged"
cat > "$STATE_PHASE/01-01-SUMMARY.md" <<'SUMMARY'
---
phase: 1
plan: 1
status: partial
---
Partial but terminal.
SUMMARY
printf '{"tool_input":{"file_path":"%s"}}\n' "$STATE_PHASE/01-01-SUMMARY.md" | (cd "$STATE_FIXTURE" && "$STATE_UPDATER")
state_status=$(jq -r '.plans[] | select(.id == "01-01") | .status' "$STATE_FIXTURE/.vbw-planning/.execution-state.json")
assert_eq "$state_status" "partial" "state-updater writes verified terminal partial status"

# Protocol text invariants
if grep -q 'resolve-execute-delegation-mode\.sh' "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol references resolve-execute-delegation-mode.sh"
else
  fail "execute-protocol references resolve-execute-delegation-mode.sh"
fi

if grep -Fq "prefer_teams='auto': request team mode only when 2+ uncompleted plans remain" "$EXECUTE_PROTOCOL"; then
  fail "execute-protocol no longer contains stale 2+ uncompleted auto routing wording"
else
  pass "execute-protocol no longer contains stale 2+ uncompleted auto routing wording"
fi

if grep -q 'delegation_mode=team' "$EXECUTE_PROTOCOL" && grep -q 'TEAM_NAME' "$EXECUTE_PROTOCOL" && grep -q 'shutdown_request' "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol keys team shutdown off actual delegation_mode=team plus TEAM_NAME"
else
  fail "execute-protocol keys team shutdown off actual delegation_mode=team plus TEAM_NAME"
fi

if grep -Fq 'set execute {segment_effort} direct' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'set execute {segment_effort} subagent' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'For serialized delegate segments (`route=delegate`, `delegation_mode=subagent`)' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'For `turbo` or internal `direct` segments (`delegation_mode=direct`)' "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol persists direct/turbo and serialized subagent segments distinctly"
else
  fail "execute-protocol persists direct/turbo and serialized subagent segments distinctly"
fi

if grep -Fq 'Do not start a non-team segment while `.delegated-workflow.json` still reports a live team marker' "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol forbids non-team segment while live team marker exists"
else
  fail "execute-protocol forbids non-team segment while live team marker exists"
fi

if grep -Fq 'When true team mode is active, pass `team_name: "vbw-phase-{NN}"` and `name: "dev-{MM}"`' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'When true team mode is active, pass `team_name: "vbw-phase-{NN}"` and `name: "qa"`' "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol preserves team_name/name invariant for true team mode"
else
  fail "execute-protocol preserves team_name/name invariant for true team mode"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

[ "$FAIL" -eq 0 ] || exit 1

echo "All execute delegation routing contract checks passed."
exit 0
