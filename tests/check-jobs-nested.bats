#!/usr/bin/env bats
# R257 (docs/proof.md, The computer-wide limit): a proof started inside another
# proof's unit takes one unit at a time by default. The outer run marks every unit's
# environment with VBW_PROOF_UNIT=1, whether or not the computer-wide store is in
# force and whatever Claude config folder the inner kernel uses (VBW_SLOT_STORE
# alone is not enough: an inner kernel with its own CLAUDE_CONFIG_DIR has another
# store). A kernel started inside a marked unit reads a check_jobs default of 1:
# vbw config shows it with its reason, and vbw prove, vbw check and vbw fix done
# run one unit at a time. A check_jobs value set in the project still wins over
# the nested default, so VBW's own tests of parallel lanes keep their lanes; a value
# outside 1 to 64 is refused as today. Without the mark nothing changes.
# tests/helper.bash never strips the mark. L1: the core-count stand-ins and the
# self-registering checks of tests/check-jobs-machine.bats.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  local bin="$TEST_ROOT/bin" tool
  mkdir -p "$bin"
  for tool in getconf nproc sysctl; do
    cat > "$bin/$tool" << 'SH'
#!/bin/sh
n=$(cat "$TEST_ROOT/cores")
[ "$n" != none ] || exit 1
printf '%s\n' "$n"
SH
    chmod +x "$bin/$tool"
  done
  PATH="$bin:$PATH"
  export PATH
  printf '10\n' > "$TEST_ROOT/cores"
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  CONC="$TEST_ROOT/conc"
  mkdir -p "$CONC"
  export CONC
  # Each check registers itself, records how many are registered, waits and leaves.
  cat > tests/conc.sh << 'SH'
touch "$CONC/run.$$"
ls "$CONC" | grep -c '^run\.' >> "$CONC/seen"
sleep 0.4
rm -f "$CONC/run.$$"
SH
  # tests/env.sh: what the unit's environment says about the mark.
  cat > tests/env.sh << 'SH'
printf 'mark=%s store=%s\n' "${VBW_PROOF_UNIT-unset}" "${VBW_SLOT_STORE-unset}" >> "$CONC/env"
SH
  local i checks='[]'
  for i in 1 2 3 4 5 6; do
    checks=$(printf '%s' "$checks" | jq -c --arg id "C$i" '. + [{id: $id, req: "R1", run: ["sh", "tests/conc.sh"], files: ["tests/conc.sh"]}]')
  done
  checks=$(printf '%s' "$checks" | jq -c '. + [{id: "C7", req: "R1", run: ["sh", "tests/env.sh"], files: ["tests/env.sh"]}]')
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq --argjson c "$checks" '.checks = $c
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | .fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "a"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
  # This file sets the mark itself where a case wants it; its own environment may
  # carry one when the suite runs inside a proof.
  unset VBW_PROOF_UNIT
  : > "$CONC/seen"
  : > "$CONC/env"
}
teardown() {
  chmod -R u+rwx "$TEST_ROOT" 2> /dev/null || true
  vbw_teardown
}
teardown_file() { fixture_teardown; }

peak() { sort -n "$CONC/seen" | tail -n 1; }
seen() { wc -l < "$CONC/seen" | tr -d ' '; }
jobs_line() { "$VBW" config < /dev/null | grep '^check_jobs:'; }
marked() { VBW_PROOF_UNIT=1 "$VBW" "$@" < /dev/null; }

@test "R257: vbw prove marks every unit's environment with VBW_PROOF_UNIT=1, with the computer-wide store on and with it off" {
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '^mark=1 store=/' "$CONC/env" || { echo "with the store on:"; cat "$CONC/env"; false; }
  : > "$CONC/env"
  # The store cannot be made: its folder's parent takes no new entries.
  rm -rf "$CLAUDE_CONFIG_DIR/vbw"
  chmod 500 "$CLAUDE_CONFIG_DIR"
  vbw_run prove
  chmod u+rwx "$CLAUDE_CONFIG_DIR"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"computer-wide limit was not in force"* ]] || { echo "the store was still on: $output"; false; }
  grep -q '^mark=1 store=unset' "$CONC/env" || { echo "with the store off:"; cat "$CONC/env"; false; }
}

@test "R257: inside a marked unit, vbw config shows check_jobs 1 and names the reason" {
  [[ "$(VBW_PROOF_UNIT=1 jobs_line)" == "check_jobs: 1 (inside another proof's unit"* ]] || { VBW_PROOF_UNIT=1 jobs_line; false; }
  # The reason is not "set" and not the machine default.
  [[ "$(VBW_PROOF_UNIT=1 jobs_line)" != *"(set"* && "$(VBW_PROOF_UNIT=1 jobs_line)" != *"machine default"* ]] || { VBW_PROOF_UNIT=1 jobs_line; false; }
}

@test "R257: inside a marked unit, vbw prove and vbw check run one unit at a time" {
  run marked prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(seen)" = 6 ] && [ "$(peak)" = 1 ] || { echo "prove: $(seen) ran, peak $(peak)"; false; }
  : > "$CONC/seen"
  run marked check C1 C2 C3 C4 C5 C6
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(seen)" = 6 ] && [ "$(peak)" = 1 ] || { echo "check: $(seen) ran, peak $(peak)"; false; }
}

@test "R257: inside a marked unit, vbw fix done runs one unit at a time" {
  run marked fix done F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(seen)" -ge 6 ] && [ "$(peak)" = 1 ] || { echo "fix done: $(seen) ran, peak $(peak)"; false; }
}

@test "R257: a check_jobs value set in the project wins over the nested default, and a value outside 1 to 64 is refused as today" {
  "$VBW" config set check_jobs 3 > /dev/null
  [[ "$(VBW_PROOF_UNIT=1 jobs_line)" == "check_jobs: 3 (set"* ]] || { VBW_PROOF_UNIT=1 jobs_line; false; }
  run marked prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(peak)" -le 3 ] || { echo "peak $(peak) with check_jobs 3"; false; }
  [ "$(peak)" -ge 2 ] || { echo "peak $(peak): the set value did not keep its lanes"; false; }
  local v
  for v in 0 65 abc; do
    run marked config set check_jobs "$v"
    [ "$status" -ne 0 ] || { echo "accepted: '$v'"; false; }
  done
  [[ "$(VBW_PROOF_UNIT=1 jobs_line)" == "check_jobs: 3 (set"* ]] || { VBW_PROOF_UNIT=1 jobs_line; false; }
}

@test "R257: without the mark nothing changes: the machine default of three quarters of the cores, or the set value" {
  [[ "$(jobs_line)" == "check_jobs: 7 (machine default"* ]] || { jobs_line; false; }
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(peak)" -ge 2 ] || { echo "peak $(peak): not parallel without the mark"; false; }
  "$VBW" config set check_jobs 2 > /dev/null
  [[ "$(jobs_line)" == "check_jobs: 2 (set"* ]] || { jobs_line; false; }
}

@test "R257: tests/helper.bash never strips the mark, so a hermetic test started inside a unit sees it" {
  ! grep -nE '^[^#]*unset[^#]*VBW_PROOF_UNIT' "$REPO_ROOT/tests/helper.bash" || { echo "tests/helper.bash unsets the mark"; false; }
  local seen
  seen=$(cd "$REPO_ROOT" && VBW_PROOF_UNIT=1 BATS_TEST_DIRNAME="$REPO_ROOT/tests" bash -c '. tests/helper.bash; printf "%s" "${VBW_PROOF_UNIT-gone}"')
  [ "$seen" = 1 ] || { echo "after loading the helper the mark reads: $seen"; false; }
}
