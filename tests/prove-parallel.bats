#!/usr/bin/env bats
# R69 and R81 (docs/proof.md): vbw prove runs the approved checks in parallel,
# except checks marked alone, which still run by themselves; the passed and
# failed checks and their recorded results equal those of a sequential run; a
# proof of many checks finishes in a fraction of the sequential time; the
# project setting check_jobs (vbw config set check_jobs N, 1 to 64, default 4)
# limits how many run at once, and 1 is sequential; an invalid value is refused
# with a message and changes nothing. L1: shell scripts that record how many
# of them overlap, on a fixture.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  CONC="$TEST_ROOT/conc"
  mkdir -p "$CONC"
  export CONC
  # Each check registers itself, records how many checks are registered
  # (itself included), waits, and unregisters. An alone check must be the only
  # one registered and no other check may start while it is registered.
  cat > tests/conc.sh << 'SH'
touch "$CONC/run.$$"
n=$(ls "$CONC" | grep -c '^run\.')
echo "$n" >> "$CONC/seen"
[ -z "$(ls "$CONC" | grep '^alone\.')" ] || echo "started beside an alone check" >> "$CONC/violation"
sleep "${NAP:-0.4}"
rm -f "$CONC/run.$$"
grep -qx paid src/pay.txt
SH
  cat > tests/alone.sh << 'SH'
touch "$CONC/run.$$" "$CONC/alone.$$"
n=$(ls "$CONC" | grep -c '^run\.')
[ "$n" -eq 1 ] || echo "alone check ran beside $n" >> "$CONC/violation"
sleep 0.4
rm -f "$CONC/run.$$" "$CONC/alone.$$"
SH
  cat > tests/bad.sh << 'SH'
echo "bad on purpose"
exit 3
SH
}

teardown() { vbw_teardown; }

# project N [ALONE_AT] [BAD_AT]: N checks C1..CN of R1; check ALONE_AT is alone,
# check BAD_AT fails; approved and committed.
project() {
  local n=$1 i checks='[]' run
  for i in $(seq 1 "$n"); do
    run='["sh","tests/conc.sh"]'
    [ "$i" = "${3:-}" ] && run='["sh","tests/bad.sh"]'
    [ "$i" = "${2:-}" ] && run='["sh","tests/alone.sh"]'
    checks=$(printf '%s' "$checks" | jq -c --arg id "C$i" --argjson run "$run" '. + [{id: $id, req: "R1", run: $run, files: ["tests/conc.sh", "tests/alone.sh", "tests/bad.sh"]}]')
  done
  if [ -n "${2:-}" ]; then checks=$(printf '%s' "$checks" | jq -c --arg id "C$2" 'map(if .id == $id then . + {alone: true} else . end)'); fi
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq --argjson c "$checks" '.checks = $c
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | .schema = (if any(.checks[]; .alone == true) then 2 else 1 end)
    | del(.requirements[]?.rules)' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

peak() { sort -n "$CONC/seen" | tail -n 1; }

results() { jq -c '.evidence | {passed, checks: (.checks | map_values({status, exit}))}' .vbw/record.json; }

@test "R69: checks run in parallel, by default up to four at a time" {
  project 12
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(wc -l < "$CONC/seen" | tr -d ' ')" = 12 ]
  [ "$(peak)" -ge 2 ]
  [ "$(peak)" -le 4 ]
}

@test "R69: a proof of 24 checks takes a fraction of the sequential time" {
  project 24
  # 24 checks of one second each take at least 24 s one after another, so any
  # proof under 24 s ran checks side by side. The bound is that floor, not a
  # guess of this machine's speed: VBW's own work per check (a shell, git, jq)
  # comes on top and is several seconds on a slow CI runner (15 s on macOS CI,
  # 2026-10-09), while 4 at a time sleeps only 6 s.
  NAP=1 run bash -c 'start=$(date +%s); "$1" prove > /dev/null; echo $(( $(date +%s) - start ))' _ "$VBW"
  [ "$status" -eq 0 ]
  [ "$output" -lt 24 ] || { echo "took $output s"; false; }
  jq -e '.evidence.passed == true and (.evidence.checks | length) == 24' .vbw/record.json
}

@test "R69: checks marked alone run by themselves, never beside another check" {
  project 9 5
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -s "$CONC/violation" ] || { cat "$CONC/violation"; false; }
  [ "$(wc -l < "$CONC/seen" | tr -d ' ')" = 8 ]
  jq -e '.evidence.checks.C5.status == "pass"' .vbw/record.json
}

@test "R69: the passed and failed checks and their recorded results equal those of a sequential run" {
  project 10 "" 4
  "$VBW" config set check_jobs 1 > /dev/null
  vbw_run prove
  [ "$status" -ne 0 ]
  local seq
  seq=$(results)
  "$VBW" config set check_jobs 6 > /dev/null
  vbw_run prove
  [ "$status" -ne 0 ]
  [ "$(results)" = "$seq" ]
  [ "$seq" = '{"passed":false,"checks":{"C1":{"status":"pass","exit":0},"C2":{"status":"pass","exit":0},"C3":{"status":"pass","exit":0},"C4":{"status":"fail","exit":3},"C5":{"status":"pass","exit":0},"C6":{"status":"pass","exit":0},"C7":{"status":"pass","exit":0},"C8":{"status":"pass","exit":0},"C9":{"status":"pass","exit":0},"C10":{"status":"pass","exit":0}}}' ]
  jq -e '.evidence.checks | keys_unsorted == ["C1","C2","C3","C4","C5","C6","C7","C8","C9","C10"]' .vbw/record.json
}

@test "R81: a limit of 1 behaves like sequential: never two at once" {
  project 8
  "$VBW" config set check_jobs 1 > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(peak)" = 1 ]
}

@test "R81: never more checks run at once than the setting says" {
  project 12
  "$VBW" config set check_jobs 2 > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(wc -l < "$CONC/seen" | tr -d ' ')" = 12 ]
  [ "$(peak)" = 2 ]
}

@test "R81: the setting is shown by vbw config, remembered, and removed with default" {
  vbw_run config
  [[ "$output" == *"check_jobs: 4"* ]]
  "$VBW" config set check_jobs 3 > /dev/null
  vbw_run config
  [[ "$output" == *"check_jobs: 3"* ]]
  "$VBW" config set check_jobs default > /dev/null
  vbw_run config
  [[ "$output" == *"check_jobs: 4"* ]]
}

@test "R81: an invalid value is refused with a clear message and changes nothing" {
  "$VBW" config set check_jobs 3 > /dev/null
  local v before
  before=$(cksum < .vbw/record.json)
  for v in 0 -1 abc 1.5 "" 65 100000 "2 3"; do
    vbw_run config set check_jobs "$v"
    [ "$status" -ne 0 ] || { echo "accepted: '$v'"; false; }
    [[ "$output" == *check_jobs* ]]
    [[ "$output" == *"1"* && "$output" == *"64"* ]]
  done
  vbw_run config
  [[ "$output" == *"check_jobs: 3"* ]]
  [ "$(cksum < .vbw/record.json)" = "$before" ]
}

@test "R81: the setting is the clone's own: it is not written into the shared record" {
  "$VBW" config set check_jobs 2 > /dev/null
  ! grep -q check_jobs .vbw/record.json
  jq -e '.schema == 1 or .schema == 2' .vbw/record.json
}
