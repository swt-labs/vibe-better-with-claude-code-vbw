#!/usr/bin/env bats
# Unit time (docs/proof.md, "Unit time and the budget per unit"): VBW reports
# what a project's tests cost, and never fails a proof on time. vbw prove (just
# before its "VBW's own work" line) and vbw fix done (just after its "ran
# again" line) name the three slowest units that ran and their share of the
# ran units' time; units over settings.check_budget (seconds, 120 when unset,
# vbw config set check_budget) are named over budget. vbw show evidence prints
# the total unit time of every current unit as it last ran, the ten slowest and
# every unit over the budget. vbw ship names the total and its change since the
# milestone started: vbw milestone start keeps the figure in the clone's git
# directory (vbw/unit-time.json), never in the record. L1.
#
# A unit's time is measured in tenths of a second: a unit that took 0.4 s is
# recorded and printed as 0.4 (under 10 s one decimal, from 10 s whole seconds),
# and every reader takes whole and decimal values alike, so a record written
# with whole seconds still reads and prints as before.
#
# One shippable project (an approved check, proved, QA passed) is built once
# for the file and copied for each case.

load helper

setup_file() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src
  printf 'paid\n' > src/pay.txt
  edit_record '.checks = [{id: "C1", req: "R1", run: ["grep", "-qx", "paid", "src/pay.txt"]}]
    | .phases = [{id: "P1", title: "Pay", reqs: ["R1"], milestone: "M1"}]
    | .plans = [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], status: "done"}]'
  "$VBW" approve > /dev/null
  git add src/pay.txt && git commit -q -m "feat: pay" -- src/pay.txt
  "$VBW" prove > /dev/null
  "$VBW" qa record P1 pass standard > /dev/null
  cp -Rp "$PROJECT" "$BATS_FILE_TMPDIR/project"
  vbw_teardown
}

setup() {
  vbw_setup
  cd "$TEST_ROOT" && rm -rf "$PROJECT"
  cp -Rp "$BATS_FILE_TMPDIR/project" "$PROJECT" && cd "$PROJECT"
}

teardown() { vbw_teardown; }

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

# ran_line BUDGET: the summary line for the evidence-shaped object on stdin.
ran_line() {
  bash -c '. "$1/lib/unittime.sh" && unittime_ran_line "$2"' _ "$PLUGIN_ROOT" "$1"
}

# nth K: line K of $output counted from its end (1 is the last line).
nth() { printf '%s\n' "$output" | tail -n "$1" | head -n 1; }

figures() { printf '%s/vbw/unit-time.json' "$(git rev-parse --path-format=absolute --git-common-dir)"; }

@test "unit time: the line names the three slowest units that ran, their share and those over the budget; reused, skipped and waiting units are left out" {
  ev='{"checks": {"C1": {"status": "pass", "seconds": 30}, "C2": {"status": "pass", "seconds": 500, "reused": true},
                  "C3": {"status": "waiting", "seconds": 0}, "C4": {"status": "fail", "seconds": 130}},
       "commands": {"test": {"status": "pass", "seconds": 900, "of_files": true}, "lint": {"status": "skipped", "seconds": 0},
                    "build": {"status": "pass", "seconds": 12}},
       "test_files": {"tests/a.bats": {"status": "pass", "seconds": 140}, "tests/b.bats": {"status": "pass", "seconds": 30}}}'
  run ran_line 120 <<< "$ev"
  [ "$output" = "slowest units: tests/a.bats 140 s, C4 130 s, C1 30 s (88% of 342 s unit time); over budget (more than 120 s): tests/a.bats, C4" ] || { echo "$output"; false; }
  # Five units over the budget are named, the rest counted; ties keep the evidence's order.
  run ran_line 100 <<< '{"checks": {"C1": {"status": "pass", "seconds": 200}, "C2": {"status": "pass", "seconds": 200},
    "C3": {"status": "pass", "seconds": 300}, "C4": {"status": "pass", "seconds": 101}, "C5": {"status": "pass", "seconds": 150}, "C6": {"status": "pass", "seconds": 110}}}'
  [ "$output" = "slowest units: C3 300 s, C1 200 s, C2 200 s (66% of 1061 s unit time); over budget (more than 100 s): C3, C1, C2, C5, C6 and 1 more (vbw show evidence)" ] || { echo "$output"; false; }
  run ran_line 120 <<< '{"checks": {"C1": {"status": "pass", "seconds": 0}}}'
  [ "$output" = "slowest units: C1 0 s (each under a second)" ] || { echo "$output"; false; }
  # Nothing ran: no line.
  run ran_line 120 <<< '{"checks": {"C1": {"status": "pass", "seconds": 9, "reused": true}}, "commands": {}}'
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$output"; false; }
}

@test "unit time: every reader takes decimal seconds beside whole ones, and sums are rounded to a tenth" {
  run ran_line 120 <<< '{"checks": {"C1": {"status": "pass", "seconds": 0.4}, "C2": {"status": "pass", "seconds": 1.26}}}'
  [ "$status" -eq 0 ] && [ "$output" = "slowest units: C2 1.3 s, C1 0.4 s (100% of 1.7 s unit time)" ] || { echo "$output"; false; }
  # 0.1 + 0.2 is not printed as 0.30000000000000004.
  run ran_line 120 <<< '{"checks": {"C1": {"status": "pass", "seconds": 0.1}, "C2": {"status": "pass", "seconds": 0.2}}}'
  [ "$output" = "slowest units: C2 0.2 s, C1 0.1 s (100% of 0.3 s unit time)" ] || { echo "$output"; false; }
  run vbw_kernel '. "$VBW_LIB/unittime.sh"; printf "%s" "{\"checks\": {\"C1\": {\"status\": \"pass\", \"seconds\": 0.4}, \"C2\": {\"status\": \"pass\", \"seconds\": 3}}}" | unittime_total'
  [ "$output" = '{"seconds":3.4,"units":2}' ] || { echo "$output"; false; }
}

@test "unit time: a unit under a second is recorded and printed in tenths, not as 0 s" {
  edit_record '.checks[0].run = ["sleep", "0.3"]'
  "$VBW" approve > /dev/null
  printf 'paid\nmore\n' > src/pay.txt
  git add src/pay.txt && git commit -q -m "feat: pay more" -- src/pay.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.checks.C1.seconds | . >= 0.3 and . < 1.5 and (. * 10 | round) == (. * 10)' .vbw/record.json || { jq .evidence.checks .vbw/record.json; false; }
  printf '%s\n' "$output" | grep -qE '^  C1 pass [0-9]\.[0-9]s' || { echo "$output"; false; }
  jq -e '.runs["check:C1"].seconds | . >= 0.3 and . < 1.5' "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json" || { cat "$(git rev-parse --path-format=absolute --git-common-dir)/vbw/runs.json"; false; }
}

@test "unit time: vbw prove prints the line just before VBW's own work, and the summary reads check_budget" {
  printf 'paid\nmore\n' > src/pay.txt
  git add src/pay.txt && git commit -q -m "feat: pay more" -- src/pay.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # A fast unit counts 0 or 1 s (whole seconds), so the integration cases pin the place, not the share.
  [[ "$(nth 4)" =~ ^slowest\ units:\ C1\ [01]\ s\ \( ]] || { echo "$output"; false; }
  [[ "$(nth 3)" == "VBW's own work: "* ]] || { echo "$output"; false; }
  "$VBW" config set check_budget 10 > /dev/null
  edit_record '.evidence.checks.C1 |= (.seconds = 42 | del(.reused))'
  run vbw_kernel '. "$VBW_LIB/cmd-prove.sh"; prove_summary ""'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qxF 'slowest units: C1 42 s (100% of 42 s unit time); over budget (more than 10 s): C1' || { echo "$output"; false; }
}

@test "unit time: vbw fix done prints the line just after its ran again line" {
  edit_record '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "a"}]'
  printf 'paid\nmore\n' > src/pay.txt
  git add src/pay.txt && git commit -q -m "fix: pay" -- src/pay.txt
  vbw_run fix "done" F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  n=$(printf '%s\n' "$output" | grep -n '^ran again: ' | cut -d: -f1)
  [ -n "$n" ] || { echo "$output"; false; }
  # The place is the claim, not the figure: a unit's time prints with a decimal when it is short (0.1 s).
  [[ "$(printf '%s\n' "$output" | sed -n "$((n + 1))p")" =~ ^slowest\ units:\ C1\ [0-9.]+\ s\ \( ]] || { echo "$output"; false; }
}

@test "unit time: vbw show evidence prints the total of every current unit as it last ran, the ten slowest and every unit over the budget" {
  "$VBW" config set check_budget 50 > /dev/null
  edit_record '.evidence.checks = ([range(1; 13) | {key: "C\(.)", value: {status: "pass", exit: 0, seconds: (. * 10), tail: ""}}] | from_entries)
      + {C13: {status: "pass", exit: 0, seconds: 70, tail: "", reused: true, at: "2026-10-21T00:00:00Z"}}
    | .evidence.commands = {lint: {status: "skipped", exit: null, seconds: 0, tail: "not approved"},
        test: {status: "pass", exit: 0, seconds: 99, tail: "", of_files: true, command: "sh {file} (one test file per run)"}}
    | .evidence.test_files = {"tests/a.sh": {status: "pass", exit: 0, seconds: 65, tail: ""}}'
  vbw_run show evidence
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  block=$(printf '%s\n' "$output" | sed -n '/^  unit time: /,/^  over budget /p')
  want='  unit time: 915 s in 14 units, each as it last ran; the slowest:
    C12 120 s
    C11 110 s
    C10 100 s
    C9 90 s
    C8 80 s
    C7 70 s
    C13 70 s
    tests/a.sh 65 s
    C6 60 s
    C5 50 s
  over budget (more than 50 s a unit): 9'
  [ "$block" = "$want" ] || { echo "$output"; false; }
  over=$(printf '%s\n' "$output" | awk 'f && /^    /{printf "%s;", $0; next} f{exit} /^  over budget /{f=1}')
  [ "$over" = "    C12 120 s;    C11 110 s;    C10 100 s;    C9 90 s;    C8 80 s;    C7 70 s;    C13 70 s;    tests/a.sh 65 s;    C6 60 s;" ] || { echo "$output"; false; }
}

@test "unit time: check_budget is set, shown and reset with vbw config, refused out of range, and the validator refuses a bad value" {
  vbw_run config
  printf '%s\n' "$output" | grep -qx 'check_budget: 120 seconds a unit (reported, never enforced)' || { echo "$output"; false; }
  vbw_run config set check_budget 300
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.settings.check_budget == 300' .vbw/record.json
  vbw_run config
  printf '%s\n' "$output" | grep -qx 'check_budget: 300 seconds a unit (reported, never enforced)' || { echo "$output"; false; }
  for v in 0 012 86401 2.5 abc ""; do
    vbw_run config set check_budget "$v"
    [ "$status" -ne 0 ] && [[ "$output" == *"check_budget must be a whole number of seconds from 1 to 86400"* ]] || { echo "accepted '$v': $output"; false; }
  done
  jq -e '.settings.check_budget == 300' .vbw/record.json
  vbw_run config set check_budget default
  jq -e '.settings | has("check_budget") | not' .vbw/record.json
  edit_record '.settings.check_budget = 0'
  vbw_run config
  [ "$status" -ne 0 ] && [[ "$output" == *"settings.check_budget must be a whole number from 1 to 86400"* ]] || { echo "$output"; false; }
}

@test "unit time: vbw ship names the unit time and its change since the milestone started" {
  mkdir -p "$(dirname "$(figures)")"
  printf '{"milestones": {"M1": {"seconds": 40, "units": 2, "at": "2026-10-20T00:00:00Z"}}}\n' > "$(figures)"
  edit_record '.evidence.checks.C1.seconds = 25'
  vbw_run ship
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(nth 1)" = "unit time: 25 s in 1 unit, -15 s since M1 started (40 s in 2 units)" ] || { echo "$output"; false; }
}

@test "unit time: without a figure from the milestone's start vbw ship says so; vbw milestone start keeps the figure in the clone, not in the record" {
  edit_record '.evidence.checks.C1.seconds = 25'
  vbw_run ship
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(nth 1)" = "unit time: 25 s in 1 unit; this clone kept no figure from the start of M1" ] || { echo "$output"; false; }
  vbw_run milestone start "Refunds"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.milestones | keys == ["M2"] and .M2.seconds == 25 and .M2.units == 1 and (.M2.at | type == "string")' "$(figures)" || { cat "$(figures)"; false; }
  jq -e '[paths | .[-1] | strings | select(test("unit"))] == []' .vbw/record.json
}

@test "unit time: the docs say units are timed to a tenth of a second and how reports print them, and the fixed entry is gone" {
  tr '\n' ' ' < "$REPO_ROOT/docs/proof.md" | grep -qF "to a tenth of a second" || { echo "docs/proof.md"; false; }
  grep -qF 'C1 pass 0.4s' "$REPO_ROOT/docs/proof.md" || { echo "docs/proof.md example"; false; }
  grep -qF "to a tenth of a second (whole seconds in an older record)" "$REPO_ROOT/docs/record.md" || { echo "docs/record.md"; false; }
  ! grep -qF 'Unit times are whole seconds' "$REPO_ROOT/docs/known-issues.md" || { echo "the fixed entry is still listed"; false; }
}
