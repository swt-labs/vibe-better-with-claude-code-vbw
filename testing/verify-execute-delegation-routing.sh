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

first_matching_line_number() {
  local text="$1"
  local needle="$2"

  awk -v needle="$needle" '
    index($0, needle) && first == 0 {
      first = NR
    }

    END {
      if (first > 0) print first
    }
  ' <<< "$text"
}

first_matching_regex_line_number() {
  local text="$1"
  local regex="$2"

  awk -v regex="$regex" '
    $0 ~ regex && first == 0 {
      first = NR
    }

    END {
      if (first > 0) print first
    }
  ' <<< "$text"
}

check_literal_before_literal() {
  local label="$1"
  local text="$2"
  local before="$3"
  local after="$4"
  local before_line after_line

  before_line=$(first_matching_line_number "$text" "$before")
  after_line=$(first_matching_line_number "$text" "$after")

  if [ -n "$before_line" ] && [ -n "$after_line" ] && [ "$before_line" -lt "$after_line" ]; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_literal_before_regex() {
  local label="$1"
  local text="$2"
  local before="$3"
  local after_regex="$4"
  local before_line after_line

  before_line=$(first_matching_line_number "$text" "$before")
  after_line=$(first_matching_regex_line_number "$text" "$after_regex")

  if [ -n "$before_line" ] && [ -n "$after_line" ] && [ "$before_line" -lt "$after_line" ]; then
    pass "$label"
  else
    fail "$label"
  fi
}

extract_protocol_block() {
  local start="$1"
  local end="$2"

  awk -v start="$start" -v end="$end" '
    index($0, start) { in_block = 1 }
    in_block && end != "" && index($0, end) { in_block = 0 }
    in_block { print }
  ' "$EXECUTE_PROTOCOL"
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

EXECUTE_PROTOCOL_TEXT=$(cat "$EXECUTE_PROTOCOL")
QA_REMEDIATION_BLOCK=$(extract_protocol_block 'QA Remediation Loop (inline, same session):' '### Step 4.5')
QA_REMEDIATION_EXECUTE_BLOCK=$(awk '
  /\*\*stage=execute:/ { in_block = 1 }
  /\*\*stage=verify:/ { in_block = 0 }
  in_block { print }
' <<< "$QA_REMEDIATION_BLOCK")
QA_REMEDIATION_VERIFY_BLOCK=$(awk '
  /\*\*stage=verify:/ { in_block = 1 }
  in_block { print }
' <<< "$QA_REMEDIATION_BLOCK")

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

if grep -Fq 'platform/tool provisioning failure' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'tools, Bash, filesystem, edits, or API-session access are unavailable' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'Do not consume the normal retry budget' "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol fails fast on no-tool Dev subagent returns"
else
  fail "execute-protocol missing no-tool Dev fail-fast return handling"
fi

check_literal_before_literal "execute-protocol inspects Dev return before blocker retry handling" "$EXECUTE_PROTOCOL_TEXT" 'When a Dev subagent Task returns, inspect the result immediately' '2. **blocker_report received:**'
check_literal_before_literal "execute-protocol handles no-tool Dev return before normal blocker retry handling" "$EXECUTE_PROTOCOL_TEXT" '1. **platform/tool provisioning failure:**' '2. **blocker_report received:**'

if grep -Fq '**Non-team spawn-shape rule:**' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'whether the live tool is `Agent` or `TaskCreate`' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'omit `team_name`, per-agent `name`, `run_in_background`, and `isolation`' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'Prepared VBW worktree targeting means the `Working directory:` and `Worktree targeting:` lines in the task description' "$EXECUTE_PROTOCOL" \
  && grep -Fq '`.execution-state.json` `worktree_path` and `scripts/worktree-target.sh`' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'it is not an `isolation` or `cwd` field on the spawn call' "$EXECUTE_PROTOCOL" \
  && grep -Fq '.claude/worktrees/agent-*' "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol documents non-team Agent/TaskCreate isolation-safe spawn shape"
else
  fail "execute-protocol missing non-team Agent/TaskCreate isolation-safe spawn guidance"
fi

if grep -Fq 'When VBW `worktree_isolation` is off, omit Claude worktree isolation entirely' "$EXECUTE_PROTOCOL" \
  || grep -Fq 'unless a section is explicitly in true team mode or has prepared VBW worktree targeting' "$EXECUTE_PROTOCOL"; then
  fail "execute-protocol must not preserve stale off-only or prepared-targeting isolation allowance"
else
  pass "execute-protocol rejects stale off-only or prepared-targeting isolation allowance"
fi

if grep -Fq '<qa_remediation_artifact_contract>' "$EXECUTE_PROTOCOL" \
  && grep -Fq '`round_dir`, `source_verification_path`, `known_issues_path`, and `verification_path` from `qa-remediation-state.sh` metadata are authoritative host-repository paths' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'never rewrite them relative to the current CWD' "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol documents QA remediation authoritative host artifact paths"
else
  fail "execute-protocol missing QA remediation authoritative host artifact path contract"
fi

if grep -Fq '<qa_remediation_spawn_contract>' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'QA remediation uses plain sequential subagent calls' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'Do not pass team metadata (`team_name`), per-agent names (`name`), `run_in_background`, `isolation`, or worktree cwd fields (`cwd`, `working_dir`, `workingDirectory`, `workdir`)' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'VBW worktree targeting is task prompt/state metadata, not a spawn isolation or cwd handoff' "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol documents QA remediation non-team spawn shape"
else
  fail "execute-protocol missing QA remediation non-team spawn shape contract"
fi

if grep -Fq 'future section explicitly prepares VBW worktree targeting' <<< "$QA_REMEDIATION_BLOCK" \
  || grep -Fq 'unless a future section' <<< "$QA_REMEDIATION_BLOCK" \
  || grep -Fq 'prepared VBW worktree target' <<< "$QA_REMEDIATION_BLOCK"; then
  fail "execute-protocol QA remediation must not preserve worktree-targeting spawn exceptions"
else
  pass "execute-protocol QA remediation rejects worktree-targeting spawn exceptions"
fi

if grep -Fq '<qa_remediation_no_tool_circuit_breaker>' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'STOP without advancing `.qa-remediation-stage`' "$EXECUTE_PROTOCOL" \
  && grep -Fq 'do not retry the same prompt' "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol documents QA remediation no-tool circuit breaker"
else
  fail "execute-protocol missing QA remediation no-tool circuit breaker"
fi

check_literal_before_regex "execute-protocol QA no-tool breaker appears before remediation state advance" "$QA_REMEDIATION_BLOCK" '<qa_remediation_no_tool_circuit_breaker>' 'qa-remediation-state\.sh.*advance'
check_literal_before_literal "execute-protocol QA no-tool breaker appears before deterministic gate" "$QA_REMEDIATION_BLOCK" '<qa_remediation_no_tool_circuit_breaker>' 'qa-result-gate.sh'
check_literal_before_regex "execute-protocol QA execute Dev breaker appears before execute-stage state advance" "$QA_REMEDIATION_EXECUTE_BLOCK" 'After Dev returns, apply the QA remediation no-tool circuit breaker' 'qa-remediation-state\.sh.*advance'
check_literal_before_literal "execute-protocol QA verify breaker appears before known-issue sync" "$QA_REMEDIATION_VERIFY_BLOCK" 'After QA returns, apply the QA remediation no-tool circuit breaker' 'track-known-issues.sh" sync-verification'
check_literal_before_literal "execute-protocol QA verify breaker appears before known-issue promotion" "$QA_REMEDIATION_VERIFY_BLOCK" 'After QA returns, apply the QA remediation no-tool circuit breaker' 'track-known-issues.sh" promote-todos'
check_literal_before_literal "execute-protocol QA verify breaker appears before deterministic gate" "$QA_REMEDIATION_VERIFY_BLOCK" 'After QA returns, apply the QA remediation no-tool circuit breaker' 'qa-result-gate.sh'

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
