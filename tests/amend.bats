#!/usr/bin/env bats
# R250 (T225, T228; docs/record.md, docs/guards.md, docs/workflows.md): an
# amendment is a correction that changes what no check asserts: a file added to a
# plan's files (never a protected check file), a file added to a check's files, or a
# plan made to await another plan's check. The main session records one with
# vbw apply --amend while the contract stays approved and an open run stays open;
# it is recorded on the plan or check (what, when, by which session's short id,
# never a name, D445) and listed at the next gate as the amendments made since
# approval, which the approval then clears. A change to a check's command, its
# expected result, a plan's title or a requirement's text is never an amendment.
# A plan that awaits a check reaches plan done with that check unrun when its own
# checks are green, reads "built, awaiting Cn" until the check passes, and the
# requirement stays unproven until then. A check change on a started plan
# (vbw apply --patch) keeps the plan's progress and the run open. The record's
# schema 9 carries these fields. The guard's part (vbw apply refused to run agents,
# the protected check file's one-line rule) is in tests/hooks-guard.bats and
# tests/guard-protected.bats. L1: the kernel on a two-phase shop fixture.

load helper
load fixture-helper

# shop: two express phases (an express phase has one plan and asks no mutation
# break): P1 Pay (R1: C1 reads src/pay.txt, C3 reads src/receipt.txt, so C3 is green
# only once P2 is built) and P2 Receipt (R2: C2). Committed and approved.
shop() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'grep -qx sent src/receipt.txt\n' > tests/receipt.sh
  printf 'grep -qx sent src/receipt.txt\n' > tests/pay-receipt.sh
  printf 'data\n' > tests/pay-data.txt
  jq -nc '{phases: [{id: "P1", title: "Pay", reqs: ["R1"], goal: "pay", criteria: ["pays"], tier: "express"},
                    {id: "P2", title: "Receipt", reqs: ["R2"], goal: "receipt", criteria: ["sends"], tier: "express"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay"]},
            {id: "P2.1", phase: "P2", title: "Receipt", reqs: ["R2"], files: ["src/receipt.txt"], after: ["P1.1"], role: "dev", tasks: ["send"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]},
             {id: "C3", req: "R1", run: ["sh", "tests/pay-receipt.sh"], files: ["tests/pay-receipt.sh"]}],
    rules: [{req: "R1", text: "paid is written", check: "C1"}, {req: "R1", text: "the receipt names the payment", check: "C3"},
            {req: "R2", text: "sent is written", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
}

setup_file() { fixture_build shop shop; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

SESSION=0123456789abcdef-aaaa
as_main() { VBW_SESSION_ID="$SESSION" "$VBW" "$@"; }
# amend DOC: vbw apply --amend with DOC on stdin, as the main session; sets status and output.
amend() { run bash -c 'printf "%s" "$1" | VBW_SESSION_ID="$2" "$3" apply --amend' _ "$1" "$SESSION" "$VBW"; }
edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}
approved() { "$VBW" show contract | head -n 1 | grep -qE '^contract [0-9a-f]{12} \(approved\)$'; }
table() { jq -r -n -L "$PLUGIN_ROOT/lib" "include \"record-schema\"; $1"; }

# --- schema 9 (check: R250 schema) --------------------------------------------------

@test "R250 schema: schema 9 is one row of the table, 'an amendment, an awaited check or a queued requirement', VBW_SCHEMA_MAX reads it, and record.jq's key lists hold queued, amendments and awaits (the shape tests/standards.bats pins)" {
  # A later row may top the table; the table's top is VBW_SCHEMA_MAX (record-schema.bats).
  [ "$(sed -n 's/^VBW_SCHEMA_MAX=//p' "$PLUGIN_ROOT/lib/record.sh")" -ge 9 ]
  [ "$(table '[schema_features[] | select(.schema == 9) | .feature] | join(" | ")')" = "an amendment, an awaited check or a queued requirement" ]
  [ "$(table '{plans: [{amendments: []}]} | schema_of')" = 9 ]
  [ "$(table '{plans: [{awaits: ["C3"]}]} | schema_of')" = 9 ]
  [ "$(table '{checks: [{amendments: []}]} | schema_of')" = 9 ]
  [ "$(table '{requirements: [{queued: true}]} | schema_of')" = 9 ]
  [ "$(table '{plans: [{mutations: [{tree: "t"}]}], checks: [{id: "C1"}], requirements: [{id: "R1"}]} | schema_of')" = 8 ]
  grep -qF 'field_rule(["id","text","proof","status","milestone","rules","skipped","later","queued","reworded"])' "$PLUGIN_ROOT/lib/record.jq"
  grep -qF 'field_rule(["id","req","run","files","exit","output","timeout","alone","fix","amendments"])' "$PLUGIN_ROOT/lib/record.jq"
  grep -qF 'field_rule(["id","phase","title","reqs","files","after","status","note","tasks","role","mutations","amendments","awaits","red_runs"])' "$PLUGIN_ROOT/lib/record.jq"
  grep -qF '(keys | sort) == ["at","session","what"]' "$PLUGIN_ROOT/lib/record.jq"
}

@test "R250 schema: the validator accepts amendments {what, at, session or null} on plans and checks, a plan's awaits naming checks of its own requirements and a requirement's queued: true; the next write raises the schema to 9; a malformed one is corrupt" {
  edit_record '.plans[0].amendments = [{what: "file src/card.txt added", at: "2026-11-03T10:00:00Z", session: "01234567"}, {what: "awaits C3", at: "2026-11-03T10:01:00Z", session: null}]
    | .plans[0].awaits = ["C3"] | .checks[0].amendments = [{what: "file tests/pay-data.txt added", at: "2026-11-03T10:02:00Z", session: "01234567"}]
    | .requirements[1].queued = true'
  jq -e '.schema == 4' .vbw/record.json
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  "$VBW" todo add "raise the schema" > /dev/null
  jq -e '.schema == 9 and .plans[0].awaits == ["C3"] and .requirements[1].queued == true' .vbw/record.json
  local bad
  for bad in '.plans[0].amendments[0].name = "Tiago"' '.plans[0].amendments[0].at = "yesterday"' '.plans[0].amendments[0].session = 1' \
             '.plans[0].amendments[0] |= del(.what)' '.checks[0].amendments = "none"' '.plans[0].awaits = ["C2"]' '.plans[0].awaits = ["C9"]' \
             '.plans[0].awaits = "C3"' '.requirements[1].queued = false' '.requirements[0].queued = "yes"'; do
    cp .vbw/record.json "$TEST_ROOT/good.json"
    edit_record "$bad"
    vbw_run status
    [ "$status" -eq 3 ] && [[ "$output" == *"corrupt"* ]] || { echo "accepted: $bad -> $status $output"; false; }
    cp "$TEST_ROOT/good.json" .vbw/record.json
  done
  edit_record 'del(.plans[0].amendments, .plans[0].awaits, .checks[0].amendments, .requirements[1].queued)'
  vbw_run status
  [ "$status" -eq 3 ] && [[ "$output" == *"schema 9 is only for an amendment, an awaited check or a queued requirement"* ]] || { echo "$status: $output"; false; }
}

# --- vbw apply --amend (check: R250 amend) ------------------------------------------

@test "R250 amend: during a build run, vbw apply --amend adds a file to a plan (the lease follows), a file to a check (protected follows) and a plan's awaits; the run stays open, the contract stays approved, and each amendment is recorded with what, when and the session's short id, never a name" {
  as_main run start build P1.1 > /dev/null
  amend '{"plans": [{"id": "P1.1", "files": ["src/pay.txt", "src/card.txt"]}]}'
  [ "$status" -eq 0 ] && [[ "$output" == *"P1.1"* && "$output" == *"src/card.txt"* ]] || { echo "$status: $output"; false; }
  jq -e '.lease.kind == "build" and (.lease.files | index("src/card.txt")) and .plans[0].files == ["src/pay.txt", "src/card.txt"]
    and .plans[0].status == "building" and (.plans[0].amendments | length == 1)
    and (.plans[0].amendments[0] | (.what | test("src/card.txt")) and (.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")) and .session == "01234567")' .vbw/record.json \
    || { jq '.lease, .plans[0]' .vbw/record.json; false; }
  approved || { "$VBW" show contract | head -n 3; false; }
  amend '{"checks": [{"id": "C1", "files": ["tests/pay.sh", "tests/pay-data.txt"]}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.checks[0].files == ["tests/pay.sh", "tests/pay-data.txt"] and (.protected | index("tests/pay-data.txt")) and (.checks[0].amendments | length == 1)
    and (.checks[0].amendments[0].what | test("tests/pay-data.txt")) and .checks[0].amendments[0].session == "01234567"' .vbw/record.json
  approved
  amend '{"plans": [{"id": "P1.1", "awaits": ["C3"]}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.plans[0].awaits == ["C3"] and (.plans[0].amendments | length == 2) and (.plans[0].amendments[1].what | test("C3")) and .schema == 9 and .lease.kind == "build"' .vbw/record.json
  approved
  jq -e '[.. | objects | has("session_name")] | any | not' .vbw/record.json
  jq -e --arg s "$SESSION" '[(.plans[], .checks[]) | (.amendments // [])[] | .session] | all(. != $s)' .vbw/record.json || { echo "an amendment carries the whole session id"; false; }
  vbw_run next --json
  [ "$(printf '%s' "$output" | jq -r .action)" != approve ] || { echo "$output"; false; }
}

@test "R250 amend: everything else is refused in one line naming the field and vbw apply --patch with approval: a plan's title, a check's command or exit, a file removed, a protected check file added to a plan, awaits naming another requirement's check, an unapproved contract" {
  as_main run start build P1.1 > /dev/null
  cp .vbw/record.json "$TEST_ROOT/before.json"
  local doc field
  while IFS='|' read -r doc field; do
    amend "$doc"
    [ "$status" -ne 0 ] || { echo "accepted as an amendment: $doc"; false; }
    [[ "${lines[0]}" == *"$field"* && "${lines[0]}" == *"--patch"* && "${lines[0]}" == *"approv"* ]] || { echo "the first line does not name $field and --patch with approval: $output"; false; }
    cmp -s .vbw/record.json "$TEST_ROOT/before.json" || { echo "the record changed on a refused amendment: $doc"; false; }
  done << 'DOCS'
{"plans": [{"id": "P1.1", "title": "Pay now"}]}|P1.1 title
{"plans": [{"id": "P1.1", "files": ["src/card.txt"]}]}|P1.1 files
{"plans": [{"id": "P1.1", "after": ["P2.1"]}]}|P1.1 after
{"checks": [{"id": "C1", "run": ["bash", "tests/pay.sh"]}]}|C1 run
{"checks": [{"id": "C1", "exit": 1}]}|C1 exit
{"checks": [{"id": "C1", "files": ["tests/pay-data.txt"]}]}|C1 files
{"rules": [{"req": "R1", "text": "paid is written twice", "check": "C1"}]}|rules
{"phases": [{"id": "P1", "title": "Pay", "reqs": ["R1"]}]}|phases
DOCS
  amend '{"plans": [{"id": "P1.1", "files": ["src/pay.txt", "tests/receipt.sh"]}]}'
  [ "$status" -ne 0 ] && [[ "${lines[0]}" == *"tests/receipt.sh"* && "${lines[0]}" == *"protected check file"* ]] || { echo "$status: $output"; false; }
  amend '{"plans": [{"id": "P1.1", "awaits": ["C2"]}]}'
  [ "$status" -ne 0 ] && [[ "${lines[0]}" == *"C2"* && "${lines[0]}" == *"R1"* ]] || { echo "$status: $output"; false; }
  amend '{"plans": [{"id": "P9.9", "files": ["src/x.txt"]}]}'
  [ "$status" -ne 0 ] && [[ "${lines[0]}" == *"P9.9"* ]] || { echo "$status: $output"; false; }
  cmp .vbw/record.json "$TEST_ROOT/before.json"
  # An unapproved contract has nothing to amend: the change goes through --patch and approval.
  as_main run end > /dev/null
  printf 'grep -qx paid src/pay.txt # changed\n' > tests/pay.sh
  amend '{"plans": [{"id": "P1.1", "files": ["src/pay.txt", "src/card.txt"]}]}'
  [ "$status" -ne 0 ] && [[ "${lines[0]}" == *"not approved"* && "${lines[0]}" == *"--patch"* ]] || { echo "$status: $output"; false; }
}

@test "R250 amend: with no run open an approved contract is amended the same way; vbw apply --amend refuses a run agent's document shape nothing else does: only plans and checks by id" {
  amend '{"plans": [{"id": "P2.1", "files": ["src/receipt.txt", "src/mail.txt"]}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.plans[1].files == ["src/receipt.txt", "src/mail.txt"] and (.plans[1].amendments | length == 1) and .lease == null' .vbw/record.json
  approved
  run bash -c 'printf "not json" | "$1" apply --amend' _ "$VBW"
  [ "$status" -ne 0 ]
}

@test "R250 amend: the next approval clears the recorded amendments" {
  as_main run start build P1.1 > /dev/null
  amend '{"plans": [{"id": "P1.1", "files": ["src/pay.txt", "src/card.txt"], "awaits": ["C3"]}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  amend '{"checks": [{"id": "C1", "files": ["tests/pay.sh", "tests/pay-data.txt"]}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '[.plans[], .checks[] | .amendments // [] | length] | add == 3' .vbw/record.json
  as_main run end > /dev/null
  # A check change needs approval; the approval takes the amendments with it.
  printf '{"checks": [{"id": "C2", "req": "R2", "run": ["bash", "tests/receipt.sh"], "files": ["tests/receipt.sh"]}]}' | "$VBW" apply --patch > /dev/null
  vbw_run approve
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '[.plans[], .checks[] | .amendments // [] | length] | add == 0' .vbw/record.json || { jq '[.plans[], .checks[] | .amendments]' .vbw/record.json; false; }
  jq -e '.plans[0].files == ["src/pay.txt", "src/card.txt"] and .plans[0].awaits == ["C3"] and .checks[0].files == ["tests/pay.sh", "tests/pay-data.txt"]' .vbw/record.json
  approved
}

@test "R250 amend: a check change on a started plan by vbw apply --patch keeps the plan's status, tasks and commits and the run open, and the contract then reads changed; a plan change while the run is open is refused as before" {
  as_main run start build P1.1 > /dev/null
  printf 'paid\n' > src/pay.txt
  as_main commit P1.1 "feat(pay): paid" > /dev/null
  run bash -c 'printf "%s" "$1" | "$2" apply --patch' _ '{"checks": [{"id": "C1", "req": "R1", "run": ["bash", "tests/pay.sh"], "files": ["tests/pay.sh"]}]}' "$VBW"
  [ "$status" -eq 0 ] || { echo "$status: $output"; false; }
  jq -e '.checks[0].run == ["bash", "tests/pay.sh"] and .lease.kind == "build" and .plans[0].status == "building" and .plans[0].tasks == ["pay"]' .vbw/record.json
  git log --format=%B -n 1 | grep -q 'VBW-Plan: P1.1'
  "$VBW" show contract | head -n 1 | grep -qE '^contract [0-9a-f]{12} \(NOT APPROVED\)' || { "$VBW" show contract | head -n 1; false; }
  run bash -c 'printf "%s" "$1" | "$2" apply --patch' _ '{"plans": [{"id": "P2.1", "phase": "P2", "title": "Receipt", "reqs": ["R2"], "files": ["src/receipt.txt", "src/mail.txt"], "after": ["P1.1"]}]}' "$VBW"
  [ "$status" -ne 0 ] && [[ "$output" == *"run is open"* ]] || { echo "$status: $output"; false; }
}

@test "R250 amend: vbw ship lists the amendments made since the last approval in the words of vbw show contract --changes: the shop is built, proved and shipped after a file was added to a plan and one to a check" {
  as_main run start build P1.1 > /dev/null
  amend '{"plans": [{"id": "P1.1", "files": ["src/pay.txt", "src/card.txt"]}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  amend '{"checks": [{"id": "C1", "files": ["tests/pay.sh", "tests/pay-data.txt"]}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf 'paid\n' > src/pay.txt
  printf 'card\n' > src/card.txt
  # C3 reads the receipt P2.1 writes: on disk for P1.1's plan done, committed by P2.1.
  printf 'sent\n' > src/receipt.txt
  as_main commit P1.1 "feat(pay): paid by card" > /dev/null
  as_main plan "done" P1.1 > /dev/null
  as_main run confirm P1.1 > /dev/null
  as_main run end > /dev/null
  as_main run start build P2.1 > /dev/null
  as_main commit P2.1 "feat(receipt): sent" > /dev/null
  as_main plan "done" P2.1 > /dev/null
  as_main run confirm P2.1 > /dev/null
  as_main run end > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  approved
  vbw_run show contract --changes
  local listing line
  listing=$(printf '%s\n' "$output" | sed -n '/^amendments since the last approval:/,/^[^ ]/p' | grep '^  ')
  [ -n "$listing" ] || { echo "show contract --changes lists no amendment lines (two-space indented) under its heading:"; echo "$output"; false; }
  vbw_run ship
  [ "$status" -eq 0 ] || { echo "$status: $output"; false; }
  [[ "$output" == *"amendments since the last approval:"* && "$output" == *"shipped M1"* ]] || { echo "$output"; false; }
  while IFS= read -r line; do
    [[ "$output" == *"$line"* ]] || { echo "the ship does not list: $line"; echo "$output"; false; }
  done <<< "$listing"
  [[ "$output" == *"P1.1"*"src/card.txt"* && "$output" == *"C1"*"tests/pay-data.txt"* ]] || { echo "$output"; false; }
  jq -e '.milestone.status == "shipped" and (.plans[0].amendments | length == 1) and (.checks[0].amendments | length == 1)' .vbw/record.json
}

# --- awaiting a check, and the amendment told once (check: R250 awaits) -------------

@test "R250 awaits: a plan that awaits a check reaches plan done with its own checks green, reads built, awaiting C3 in vbw status and vbw show roadmap, its requirement stays unproven until the check passes, and then the plan reads done without a second plan done" {
  # P2.1 builds what C3 reads, so it serves C3's requirement R1 as well.
  edit_record '.plans[0].awaits = ["C3"] | .plans[1].reqs = ["R1", "R2"]'
  as_main approve > /dev/null
  as_main run start build P1.1 > /dev/null
  printf 'paid\n' > src/pay.txt
  as_main commit P1.1 "feat(pay): paid" > /dev/null
  run as_main plan "done" P1.1
  [ "$status" -eq 0 ] || { echo "$status: $output"; false; }
  jq -e '.plans[0].status == "done" and .requirements[0].status != "proven"' .vbw/record.json
  vbw_run status
  [[ "$output" == *"P1.1 built, awaiting C3"* ]] || { echo "$output"; false; }
  vbw_run show roadmap
  [[ "$output" == *"P1.1 Pay [built, awaiting C3]"* ]] || { echo "$output"; false; }
  as_main run confirm P1.1 > /dev/null
  as_main run end > /dev/null
  vbw_run prove
  jq -e '.requirements[0].status != "proven" and .plans[0].status == "done"' .vbw/record.json
  # The awaited check is left unrun while P2.1 is not built: no fix opens for it, the plan keeps reading built.
  jq -e '(.fixes | length) == 0 and .evidence.checks.C3.status != "pass" and .evidence.checks.C3.status != "fail" and .requirements[0].status != "failing"' .vbw/record.json || { jq -c '[.fixes, .evidence.checks.C3, .requirements[0].status]' .vbw/record.json; false; }
  vbw_run status
  [[ "$output" == *"P1.1 built, awaiting C3"* ]] || { echo "$output"; false; }
  as_main run start build P2.1 > /dev/null
  printf 'sent\n' > src/receipt.txt
  as_main commit P2.1 "feat(receipt): sent" > /dev/null
  as_main plan "done" P2.1 > /dev/null
  as_main run confirm P2.1 > /dev/null
  as_main run end > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.requirements[0].status == "proven" and .requirements[1].status == "proven" and .plans[0].status == "done"' .vbw/record.json
  vbw_run show roadmap
  [[ "$output" == *"P1.1 Pay [done]"* && "$output" != *"awaiting"* ]] || { echo "$output"; false; }
  vbw_run status
  [[ "$output" != *"awaiting"* ]] || { echo "$output"; false; }
}

@test "R250 awaits: an awaited check is held only while a plan serving its requirement is not done: with P1.1 awaiting C3, P2.1 serving the same requirement done and an unrelated P3.1 still planned, every proof runs C3" {
  edit_record '.plans[0].awaits = ["C3"] | .plans[1].reqs = ["R1", "R2"]
    | .phases += [{id: "P3", title: "Later", reqs: ["R2"], goal: "later", criteria: ["later"], tier: "express", milestone: .milestone.id}]
    | .plans += [{id: "P3.1", phase: "P3", title: "Later", reqs: ["R2"], files: ["src/later.txt"], after: ["P2.1"], role: "dev", tasks: ["later"], status: "planned"}]'
  as_main approve > /dev/null
  printf 'paid\n' > src/pay.txt
  edit_record '.plans[0].status = "done" | .plans[1].status = "planned"'
  vbw_run prove
  jq -e '.evidence.checks.C3.status != "pass" and .evidence.checks.C3.status != "fail"' .vbw/record.json || { jq -c '.evidence.checks.C3' .vbw/record.json; false; }
  edit_record '.plans[1].status = "done"'
  jq -e '.plans[2].status != "done" and .plans[1].status == "done"' .vbw/record.json
  local n
  for n in 1 2; do
    vbw_run prove
    jq -e '.evidence.checks.C3.status == "pass" or .evidence.checks.C3.status == "fail"' .vbw/record.json || { jq -c '.evidence.checks.C3' .vbw/record.json; false; }
    edit_record 'del(.evidence.checks.C3)'
  done
}

@test "R250 awaits: the amendments made since approval are listed by vbw show contract --changes, never as changed checks or plans, and in the approval block of vbw show contract" {
  as_main run start build P1.1 > /dev/null
  amend '{"plans": [{"id": "P1.1", "files": ["src/pay.txt", "src/card.txt"], "awaits": ["C3"]}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  amend '{"checks": [{"id": "C1", "files": ["tests/pay.sh", "tests/pay-data.txt"]}]}'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  vbw_run show contract --changes
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"amendments since the last approval:"* ]] || { echo "$output"; false; }
  [[ "$output" == *"P1.1"*"src/card.txt"* && "$output" == *"P1.1"*"C3"* && "$output" == *"C1"*"tests/pay-data.txt"* ]] || { echo "$output"; false; }
  [[ "$output" != *"changed check C1"* && "$output" != *"changed plan P1.1"* ]] || { echo "an amendment is listed as a change: $output"; false; }
  as_main run end > /dev/null
  printf '{"checks": [{"id": "C2", "req": "R2", "run": ["bash", "tests/receipt.sh"], "files": ["tests/receipt.sh"]}]}' | "$VBW" apply --patch > /dev/null
  vbw_run show contract
  [[ "$output" == *"amendments since the last approval:"* && "$output" == *"src/card.txt"* && "$output" == *"approval question: Approve contract "* ]] || { echo "$output"; false; }
  vbw_run show contract --changes
  [[ "$output" == *"changed check C2"* && "$output" == *"amendments since the last approval:"* ]] || { echo "$output"; false; }
}

@test "R250 awaits: vbw next --json carries a new amendment once, so the router says one chat line (D586): the first answer after it names the plan and what changed, the next does not, and a later amendment is carried again" {
  edit_record '.plans[0].amendments = [{what: "file src/card.txt added", at: (now | todate), session: "01234567"}] | .plans[0].files += ["src/card.txt"]'
  vbw_run next --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.amendments | length == 1 and .[0].id == "P1.1" and (.[0].what | test("src/card.txt"))' > /dev/null || { echo "$output"; false; }
  vbw_run next --json
  printf '%s' "$output" | jq -e '(.amendments // []) | length == 0' > /dev/null || { echo "told twice: $output"; false; }
  edit_record '.checks[0].amendments = [{what: "file tests/pay-data.txt added", at: (now + 1 | todate), session: "01234567"}] | .checks[0].files += ["tests/pay-data.txt"] | .protected += ["tests/pay-data.txt"] | .protected |= (unique | sort)'
  vbw_run next --json
  printf '%s' "$output" | jq -e '.amendments | length == 1 and .[0].id == "C1" and (.[0].what | test("tests/pay-data.txt"))' > /dev/null || { echo "$output"; false; }
}
