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
  jq -e 'all(.plans[].status; . == "planned") and all(.phases[]; has("status") | not)' .vbw/record.json
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

@test "re-planning mid-milestone keeps started plans exactly as they are" {
  apply_plan
  edit_record '.plans[0].status = "done"'
  # A changed started plan is refused.
  run bash -c 'printf "%s" "$1" | "$2" apply' _ "$(printf '%s' "$PLAN" | jq '.plans[0].files += ["src/extra.txt"]')" "$VBW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"P1.1 is done: a plan that has started must stay as it is"* ]]
  # The same started plan plus a new one is accepted; the done plan stays done.
  run bash -c 'printf "%s" "$1" | "$2" apply' _ "$(printf '%s' "$PLAN" | jq '.plans += [{id: "P1.3", phase: "P1", title: "Refund", reqs: ["R2"], files: ["src/refund.txt"]}]')" "$VBW"
  [ "$status" -eq 0 ]
  jq -e '.plans[0].status == "done" and .plans[2].id == "P1.3" and .plans[2].status == "planned"' .vbw/record.json
}

@test "apply is refused while a build run is open" {
  apply_plan
  "$VBW" run start build P1.1 > /dev/null
  run bash -c 'printf "%s" "$1" | "$2" apply' _ "$PLAN" "$VBW"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a build run is open"* ]]
}

@test "a new milestone keeps the shipped one's phases, plans and checks; its checks keep guarding" {
  apply_plan
  edit_record '.plans[].status = "done" | .milestone.status = "shipped"
    | .shipped = [{id: "M1", title: "First milestone", at: "2026-10-01T09:00:00Z"}]'
  vbw_run milestone start "Exports"
  [ "$status" -eq 0 ]
  jq -e '.milestone == {id: "M2", title: "Exports", status: "active"}' .vbw/record.json
  vbw_run next --json
  echo "$output" | jq -e '.action == "spec"'
  "$VBW" spec add auto "A customer can export to CSV" > /dev/null
  jq -e '.requirements[-1] | .id == "R3" and .milestone == "M2"' .vbw/record.json
  run bash -c 'printf "%s" "$1" | "$2" apply' _ '{"phases": [{"id": "P2", "title": "Exports", "reqs": ["R3"]}],
    "plans": [{"id": "P2.1", "phase": "P2", "title": "CSV", "reqs": ["R3"], "files": ["src/csv.txt"]}],
    "checks": [{"id": "C3", "req": "R3", "run": ["true"]}]}' "$VBW"
  [ "$status" -eq 0 ]
  jq -e '[.phases[].id] == ["P1", "P2"] and [.plans[].id] == ["P1.1", "P1.2", "P2.1"]
         and [.checks[].id] == ["C1", "C2", "C3"] and .phases[1].milestone == "M2"' .vbw/record.json
  vbw_run status
  [[ "$output" == *"requirements: 0/1 proven"* ]]
  [[ "$output" == *"shipped: M1 First milestone"* ]]
}

@test "a milestone that has not shipped cannot be followed by another" {
  vbw_run milestone start "Too early"
  [ "$status" -eq 1 ]
  [[ "$output" == *"M1 is not shipped yet"* ]]
}

@test "the current milestone can be renamed until it ships" {
  vbw_run milestone rename "Checkout"
  [ "$status" -eq 0 ]
  jq -e '.milestone == {id: "M1", title: "Checkout", status: "active"}' .vbw/record.json
  edit_record '.milestone.status = "shipped" | .shipped = [{id: "M1", title: "Checkout", at: "2026-10-01T09:00:00Z"}]'
  vbw_run milestone rename "Other"
  [ "$status" -eq 1 ]
  [[ "$output" == *"M1 has shipped"* ]]
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

@test "plan done is verified: the checks of requirements it completes must pass" {
  apply_plan
  "$VBW" approve > /dev/null
  printf 'unpaid\n' > src/pay.txt
  "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  vbw_run plan done P1.1
  [ "$status" -eq 1 ]
  [[ "$output" == *"completes requirements whose checks do not pass: C1 fail"* ]]
  jq -e '.plans[0].status == "planned"' .vbw/record.json
}

@test "a plan that does not complete its requirement is not held to its checks" {
  PLAN=$(printf '%s' "$PLAN" | jq '.plans[1].reqs = ["R1", "R2"]')
  apply_plan
  "$VBW" approve > /dev/null
  printf 'unpaid\n' > src/pay.txt
  "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  vbw_run show plan P1.1 --json
  echo "$output" | jq -e '.requirements[0].other_open_plans == ["P1.2"]'
  vbw_run plan done P1.1
  [ "$status" -eq 0 ]
}

@test "plan done is verified: it needs a commit and no uncommitted changes" {
  apply_plan
  "$VBW" approve > /dev/null
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

@test "fix done is verified: no uncommitted changes, and finished work its files serve still passes" {
  # R1 and R2 share src/pay.txt; both are built. A fix for R2 that breaks R1 is refused.
  PLAN=$(printf '%s' "$PLAN" | jq '.plans[1].files = ["src/receipt.txt", "src/pay.txt"] | .plans[1].after = []')
  apply_plan
  "$VBW" approve > /dev/null
  printf 'paid\n' > src/pay.txt && printf 'sent\n' > src/receipt.txt
  git add src && git commit -q -m "feat: built"
  edit_record '.plans[].status = "done" | .fixes = [{id: "F1", req: "R2", attempts: 0, status: "open", note: "wording"}]'
  vbw_consent_contract
  printf 'refunded\n' > src/pay.txt
  vbw_run fix done F1
  [ "$status" -eq 1 ]
  [[ "$output" == *"F1 has uncommitted changes in: src/pay.txt"* ]]
  git commit -q -am "fix: wording"
  vbw_run fix done F1
  [ "$status" -eq 1 ]
  [[ "$output" == *"F1 broke finished work"*"C1 fail"* ]]
  jq -e '.fixes[0].status == "open"' .vbw/record.json
  printf 'paid\n' > src/pay.txt && git commit -q -am "fix: restore"
  vbw_run fix done F1
  [ "$status" -eq 0 ]
  jq -e '.fixes[0].status == "fixed"' .vbw/record.json
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
    and .requirements == [{id: "R2", text: "A customer gets a receipt", proof: "auto", other_open_plans: []}]
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
  edit_record '.plans[].status = "done"'
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

# --- VBW commits its own files ------------------------------------------------

@test "a run's end commits the spec, the record and the check files, and nothing else" {
  printf 'mine\n' > user-staged.txt && git add user-staged.txt
  printf 'draft\n' > user-unstaged.txt
  "$VBW" run start plan > /dev/null
  apply_plan
  vbw_run run end
  [ "$status" -eq 0 ]
  [[ "$(git log -1 --format=%s)" == "chore(vbw): record after plan-"* ]]
  git show --name-only --format= HEAD | LC_ALL=C sort > "$TEST_ROOT/committed"
  printf '%s\n' .vbw/.gitignore .vbw/record.json .vbw/spec.md tests/pay.sh tests/receipt.sh > "$TEST_ROOT/expected"
  diff "$TEST_ROOT/expected" "$TEST_ROOT/committed"
  git diff --cached --name-only | grep -qx user-staged.txt
  git status --porcelain | grep -q '^?? user-unstaged.txt'
}

@test "approval and ship commit the record; nothing changed means no commit" {
  apply_plan
  "$VBW" run start plan > /dev/null && "$VBW" run end > /dev/null
  local before
  before=$(git rev-parse HEAD)
  "$VBW" run start plan > /dev/null && "$VBW" run end > /dev/null
  "$VBW" approve > /dev/null
  [[ "$(git log -1 --format=%s)" == "chore(vbw): approve contract "* ]]
  [ "$(git rev-list --count "$before"..HEAD)" -eq 1 ]
}

@test "VBW never edits or commits the user's .gitignore" {
  printf 'node_modules/\n' > .gitignore && git add .gitignore && git commit -q -m "chore(repo): ignore"
  "$VBW" init > /dev/null
  [ "$(cat .gitignore)" = "node_modules/" ]
  printf 'my-own-edit/\n' >> .gitignore
  "$VBW" run start plan > /dev/null && "$VBW" run end > /dev/null
  ! git show --name-only --format= HEAD | grep -qx .gitignore
  git diff --name-only | grep -qx .gitignore
}

@test "the codebase map is committed with VBW's own files" {
  printf '## Stack and commands\n- npm test\n' > .vbw/map.md
  "$VBW" run start plan > /dev/null && "$VBW" run end > /dev/null
  git show --name-only --format= HEAD | grep -qx .vbw/map.md
}

@test "after an approval, show contract --changes lists only what changed since" {
  apply_plan
  vbw_run show contract --changes
  [[ "$output" == *"no earlier approval in this clone"* ]]
  "$VBW" approve > /dev/null
  vbw_run show contract --changes
  [ "$output" = "no changes since the last approval" ]
  # Re-plan: a new requirement with its check and plan, a reworded one, a changed test file.
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay by card\n- R2 [auto] A customer gets a receipt\n- R3 [auto] A customer can get a refund\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf 'grep -qx refunded src/refund.txt\n' > tests/refund.sh
  printf 'grep -qx sent src/receipt.txt # by email\n' > tests/receipt.sh
  printf '%s' "$PLAN" | jq '.phases[0].reqs += ["R3"]
    | .plans += [{id: "P1.3", phase: "P1", title: "Refund", reqs: ["R3"], files: ["src/refund.txt"]}]
    | .checks += [{id: "C3", req: "R3", run: ["sh", "tests/refund.sh"], files: ["tests/refund.sh"]}]' | "$VBW" apply > /dev/null
  vbw_run show contract --changes
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "changes since the last approval:" ]
  [[ "$output" == *"added requirement R3 [auto] A customer can get a refund"* ]]
  [[ "$output" == *"changed requirement R1: [auto] A customer can pay -> [auto] A customer can pay by card"* ]]
  [[ "$output" == *"added check C3 (R3): sh tests/refund.sh"* ]]
  [[ "$output" == *"changed test file tests/receipt.sh"* ]]
  [[ "$output" == *"added plan P1.3 Refund: src/refund.txt"* ]]
  [[ "$output" != *"R2"* ]]
}

@test "a kept VBW 1 folder changing never makes the evidence stale" {
  apply_plan
  "$VBW" approve > /dev/null
  printf 'paid\n' > src/pay.txt && "$VBW" commit P1.1 "feat(pay): pay" > /dev/null
  "$VBW" plan done P1.1 > /dev/null
  mkdir -p .vbw-planning && printf 'x\n' > .vbw-planning/.cost-ledger.json
  "$VBW" prove > /dev/null || true
  printf 'y\n' > .vbw-planning/.cost-ledger.json
  vbw_run next --json
  echo "$output" | jq -e '.action != "prove"'
}

@test "accepting a requirement closes a fix still open from its earlier rejection" {
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [human] It feels trustworthy\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  "$VBW" req reject R2 "too plain" > /dev/null
  jq -e '.fixes[0].status == "open"' .vbw/record.json
  vbw_run req accept R2
  [ "$status" -eq 0 ]
  jq -e '.requirements[1].status == "accepted" and .fixes[0].status == "closed"' .vbw/record.json
}
