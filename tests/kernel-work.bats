#!/usr/bin/env bats
# The kernel commands workflow agents use (docs/workflows.md): apply, run,
# plan, fix, check, show plan|fix, and evidence staleness (X9).

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p tests src
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'grep -qx sent src/receipt.txt\n' > tests/receipt.sh
  PLAN='{"phases": [{"id": "P1", "title": "Checkout", "reqs": ["R1", "R2"]}],
         "plans": [{"id": "P1.1", "phase": "P1", "title": "Pay", "reqs": ["R1"], "files": ["src/pay.txt"]},
                   {"id": "P1.2", "phase": "P1", "title": "Receipt", "reqs": ["R2"], "files": ["src/receipt.txt"], "after": ["P1.1"]}],
         "checks": [{"id": "C1", "req": "R1", "run": ["sh", "tests/pay.sh"], "files": ["tests/pay.sh"]},
                    {"id": "C2", "req": "R2", "run": ["sh", "tests/receipt.sh"], "files": ["tests/receipt.sh"]}]}'
}

teardown() { vbw_teardown; }

apply_plan() { printf '%s' "$PLAN" | "$VBW" apply > /dev/null; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# --- apply -------------------------------------------------------------------

@test "apply writes phases, plans and checks with kernel statuses" {
  run bash -c 'printf "%s" "$1" | "$2" apply' _ "$PLAN" "$VBW"
  [ "$status" -eq 0 ]
  [[ "$output" == *"applied 1 phases, 2 plans, 2 checks"* ]]
  jq -e '[.phases[].status, .plans[].status] | all(. == "planned")' .vbw/record.json
  jq -e '.plans[0].after == [] and .plans[1].after == ["P1.1"]' .vbw/record.json
  vbw_run next --json
  echo "$output" | jq -e '.action == "approve"'
}

@test "apply is loud about unknown fields and invalid plans, and changes nothing" {
  cp .vbw/record.json "$TEST_ROOT/before.json"
  run bash -c 'printf "%s" "$1" | "$2" apply' _ "$(printf '%s' "$PLAN" | jq '.plans[0].file = "x"')" "$VBW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"P1.1 has an unknown field: file"* ]]
  run bash -c 'printf "%s" "$1" | "$2" apply' _ "$(printf '%s' "$PLAN" | jq '.plans[0].reqs = ["R9"]')" "$VBW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"P1.1 references unknown requirement R9"* ]]
  run bash -c 'printf "%s" "$1" | "$2" apply' _ "$(printf '%s' "$PLAN" | jq '.plans[0].files = []')" "$VBW"
  [[ "$output" == *"P1.1 needs a non-empty files array"* ]]
  run bash -c 'printf "not json" | "$1" apply' _ "$VBW"
  [ "$status" -eq 1 ]
  cmp .vbw/record.json "$TEST_ROOT/before.json"
}

@test "apply is refused once the build has started" {
  apply_plan
  edit_record '.plans[0].status = "done"'
  run bash -c 'printf "%s" "$1" | "$2" apply' _ "$PLAN" "$VBW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"the build has started"* ]]
}

# --- run lease ---------------------------------------------------------------

@test "a build run leases exactly its plans' files and marks them building" {
  apply_plan
  vbw_run run start build P1.1
  [ "$status" -eq 0 ]
  jq -e '.lease.kind == "build" and .lease.files == ["src/pay.txt"] and (.lease.run | startswith("build-"))' .vbw/record.json
  jq -e '.plans[0].status == "building" and .plans[1].status == "planned"' .vbw/record.json
}

@test "a build run refuses plans that are not ready, unknown, or a second active run" {
  apply_plan
  vbw_run run start build P1.2
  [ "$status" -eq 1 ]
  [[ "$output" == *"P1.2 waits for P1.1"* ]]
  vbw_run run start build P9.9
  [[ "$output" == *"unknown plan P9.9"* ]]
  "$VBW" run start build P1.1 > /dev/null
  vbw_run run start plan
  [ "$status" -eq 1 ]
  [[ "$output" == *"a run is active"* ]]
}

@test "run end clears the lease and returns interrupted plans to the next wave" {
  apply_plan
  "$VBW" run start build P1.1 > /dev/null
  vbw_run run end
  [ "$status" -eq 0 ]
  jq -e '.lease == null and .plans[0].status == "planned"' .vbw/record.json
}

@test "a lease older than 24 hours never locks the project" {
  apply_plan
  edit_record '.lease = {run: "build-old", kind: "build", started_at: "2020-01-01T00:00:00Z", files: ["x"]}'
  vbw_run run start build P1.1
  [ "$status" -eq 0 ]
}

@test "a fix run leases the files of the plans serving its requirement; a command fix leases any file" {
  apply_plan
  edit_record '.fixes = [{id: "F1", req: "R2", attempts: 0, status: "open", note: "C2 fail"}]'
  "$VBW" run start fix F1 > /dev/null
  jq -e '.lease.kind == "fix" and .lease.files == ["src/receipt.txt"]' .vbw/record.json
  "$VBW" run end > /dev/null
  edit_record '.commands = {lint: ["true"]} | .fixes += [{id: "F2", command: "lint", attempts: 0, status: "open", note: "lint fail"}]'
  "$VBW" run start fix F2 > /dev/null
  jq -e '.lease.files == null' .vbw/record.json
}

# --- plan and fix outcomes ---------------------------------------------------

@test "plan done is verified: it needs a commit and no uncommitted changes" {
  apply_plan
  git add -A && git commit -q -m "chore(vbw): plan"
  vbw_run plan done P1.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"P1.1 has no commit yet"* ]]
  printf 'paid\n' > src/pay.txt
  "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  printf 'changed\n' > src/pay.txt
  vbw_run plan done P1.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted changes in: src/pay.txt"* ]]
  printf 'paid\n' > src/pay.txt
  vbw_run plan done P1.1
  [ "$status" -eq 0 ]
  jq -e '.plans[0].status == "done"' .vbw/record.json
}

@test "plan block records the reason and gates; reset returns it to the plan" {
  apply_plan
  vbw_run plan block P1.1 "the payment API key is missing"
  [ "$status" -eq 0 ]
  jq -e '.plans[0].status == "blocked" and .plans[0].note == "the payment API key is missing"' .vbw/record.json
  vbw_consent_contract
  vbw_run next --json
  echo "$output" | jq -e '.action == "unblock" and .detail.plans == ["P1.1"]'
  "$VBW" plan reset P1.1 > /dev/null
  jq -e '.plans[0].status == "planned" and (.plans[0] | has("note") | not)' .vbw/record.json
}

@test "fix done moves an open fix to fixed, and nothing else" {
  apply_plan
  edit_record '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"}]'
  vbw_run fix done F1
  [ "$status" -eq 0 ]
  jq -e '.fixes[0].status == "fixed"' .vbw/record.json
  vbw_run fix done F1
  [ "$status" -eq 1 ]
  [[ "$output" == *"F1 is not open"* ]]
}

# --- check -------------------------------------------------------------------

@test "check runs approved checks, reports, and writes nothing" {
  apply_plan
  vbw_run check C1
  [ "$status" -eq 1 ]
  [[ "$output" == *"not approved"* ]]
  "$VBW" approve > /dev/null
  cp .vbw/record.json "$TEST_ROOT/before.json"
  vbw_run check C1
  [ "$status" -eq 1 ]
  [[ "$output" == *"C1 fail"* ]]
  printf 'paid\n' > src/pay.txt
  vbw_run check C1
  [ "$status" -eq 0 ]
  [[ "$output" == *"C1 pass"* ]]
  vbw_run check --expect-red C2
  [ "$status" -eq 0 ]
  cmp .vbw/record.json "$TEST_ROOT/before.json"
  [ -z "$(ls .vbw/runtime | grep '^run\.' || true)" ]
}

# --- show plan / fix ---------------------------------------------------------

@test "show plan gives a builder its plan, requirements, checks and commands" {
  apply_plan
  vbw_run show plan P1.2 --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.plan.id == "P1.2" and .plan.files == ["src/receipt.txt"]
    and .requirements == [{id: "R2", text: "A customer gets a receipt", proof: "auto"}]
    and (.checks | map(.id)) == ["C2"] and .checks[0].last == null'
  vbw_run show plan P1.2
  [[ "$output" == *"P1.2 Receipt [planned]"* ]]
  [[ "$output" == *"after: P1.1"* ]]
  [[ "$output" == *"C2 (R2) sh tests/receipt.sh"* ]]
  vbw_run show plan P9.9
  [ "$status" -eq 1 ]
}

@test "show fix gives a builder the failure and the files it may touch" {
  apply_plan
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || true
  local f
  f=$(jq -r '.fixes[] | select(.req == "R2") | .id' .vbw/record.json)
  vbw_run show fix "$f" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.requirement.id == "R2" and .checks[0].last.status == "fail"
    and .plans == [{id: "P1.2", title: "Receipt", files: ["src/receipt.txt"]}]'
  vbw_run show fix "$f"
  [[ "$output" == *"requirement: R2 A customer gets a receipt"* ]]
  [[ "$output" == *"P1.2: src/receipt.txt"* ]]
}

# --- evidence staleness (X9) -------------------------------------------------

prove_all_green() {
  printf 'paid\n' > src/pay.txt
  printf 'sent\n' > src/receipt.txt
  edit_record '.plans[].status = "done"'
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null
}

@test "evidence is stale when code changes after the proof" {
  apply_plan
  prove_all_green
  vbw_run next --json
  echo "$output" | jq -e '.action == "ship"'
  printf 'more\n' >> src/pay.txt
  vbw_run next --json
  echo "$output" | jq -e '.action == "prove" and .detail.requirements == ["R1", "R2"]'
}

@test "committing proved work or the record never makes evidence stale" {
  apply_plan
  prove_all_green
  git add -A && git commit -q -m "feat(shop): checkout"
  vbw_run next --json
  echo "$output" | jq -e '.action == "ship"'
}

@test "files a check creates do not make its own evidence stale" {
  apply_plan
  edit_record '.checks[0].run = ["sh", "-c", "date > report.txt && grep -qx paid src/pay.txt"]'
  prove_all_green
  vbw_run next --json
  echo "$output" | jq -e '.action == "ship"'
}

@test "computing the fingerprint leaves the user's index untouched" {
  printf 'staged\n' > staged.txt
  git add staged.txt
  printf 'unstaged\n' > other.txt
  local before
  before=$(git diff --cached --name-only)
  vbw_code_tree > /dev/null
  [ "$(git diff --cached --name-only)" = "$before" ]
  git status --porcelain | grep -q '^?? other.txt'
}
