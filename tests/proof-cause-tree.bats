#!/usr/bin/env bats
# R175 (docs/proof.md): the cause "nothing was committed since the last passing
# proof" fires only when the project's code is the code that proof proved: the
# record's last proof passed (evidence.passed), the project's files have the
# fingerprint it recorded (evidence.tree) and the committed code is the tree it
# ran on (evidence.head). It never reads the subject of the last commit, so a
# VBW record commit landing after code commits (T116) re-runs nothing it need
# not. vbw fix done never names it (D270). The reuse rule's sibling reason
# "proving again with nothing committed" comes from the same comparison.
# Scripts log their runs to $RANLOG. L1.

load helper
load fixture-helper

setup_file() { fixture_build shop tree_project; }
setup() { fixture_copy shop; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# tree_project: the project every test starts from, built once per file.
tree_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'a\n' > src/a.txt
  printf 'echo t_a >> "$RANLOG"\n' > tests/t_a.sh
  printf 'echo t_b >> "$RANLOG"\ngrep -q . src/a.txt\n' > tests/t_b.sh
  printf 'echo C1 >> "$RANLOG"\ngrep -q . src/a.txt\n' > tests/c1.sh
  printf 'echo all >> "$RANLOG"\n' > tests/all.sh
  printf 'echo lint >> "$RANLOG"\n' > tests/lint.sh
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n- lint: sh tests/lint.sh\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  edit_record '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["src/a.txt"], after:[], status:"done"}]'
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || { echo "the first proof failed"; return 1; }
  : > "$RANLOG"
}

# edit_record FILTER: a hand edit of the record, protected list in step, glance dropped (R155).
edit_record() {
  jq "$1 | del(.requirements[]?.rules) | if has(\"protected\") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}

ran() { sort "$RANLOG" | tr '\n' ' '; }

# causes [KIND]: the causes proofcauses_find prints for the committed code (KIND: prove or fix).
causes() {
  vbw_kernel '. "$VBW_LIB/proofcauses.sh"; VBW_COMMAND_TIMEOUT=3600; mkdir -p "$VBW_RUNTIME"; proofcauses_find "$(record_read)" 0 "$(vbw_head_tree)" "'"${1:-prove}"'"'
}

# allowed: what proofreuse_allowed prints (nothing when this proof may reuse results).
allowed() {
  vbw_kernel '. "$VBW_LIB/proofreuse.sh"; VBW_COMMAND_TIMEOUT=3600; mkdir -p "$VBW_RUNTIME"; proofreuse_allowed "$(record_read)" || true'
}

# commit_record MSG: commit VBW's own files, as the kernel does after a step.
commit_record() { git add -A .vbw && git commit -q -m "$1"; }

@test "R175: a second vbw prove right after a passing proof with nothing changed names the cause and runs everything (D173)" {
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qF 'ran everything: nothing was committed since the last passing proof' || { echo "$output"; false; }
  [ "$(ran)" = "C1 lint t_a t_b " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  # Fresh: nothing is reused, and the counts say so.
  printf '%s\n' "$output" | grep -qE '^ +checks: 1 ran, 0 reused$' || { echo "$output"; false; }
  [[ "$output" != *"reused (proof of"* ]] || { echo "$output"; false; }
}

@test "R175: T116: code commits land, then a record commit that reads like a proof commit lands last: no such cause, only the units that read the change run" {
  printf 'more\n' >> src/a.txt
  git commit -q -am "feat: a"
  git commit -q --allow-empty -m "chore(vbw): proof passed"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qF 'nothing was committed' && { echo "$output"; false; }
  [ "$(ran)" = "C1 t_b " ] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^  tests/t_a\.sh pass [0-9.]+s reused \(proof of ' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^  lint pass [0-9.]+s reused \(proof of ' || { echo "$output"; false; }
}

@test "R175: with no evidence the cause never fires, whatever the last commit's subject says" {
  # Without the evidence its copy_slots goes too: the floor is always a valid schema.
  edit_record '.evidence = null | .schema = 4'
  commit_record "chore(vbw): state"
  git commit -q --allow-empty -m "chore(vbw): proof passed"
  run causes
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R175: when the last proof did not pass the cause never fires; the reuse rule alone decides" {
  edit_record '.evidence.passed = false'
  commit_record "chore(vbw): state"
  git commit -q --allow-empty -m "chore(vbw): proof passed"
  run causes
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R175: vbw fix done never names the cause: right after a passing proof it reuses every pass (D270)" {
  edit_record '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "a"}]'
  vbw_run fix done F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qF 'nothing was committed' && { echo "$output"; false; }
  [ "$(ran)" = "" ] || { echo "ran: $(ran)"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^C1 unchanged since its pass \(' || { echo "$output"; false; }
  [[ "$output" != *"every candidate check runs"* ]] || { echo "$output"; false; }
  run causes fix
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R175: the reuse rule's reason 'proving again with nothing committed' comes from the same tree comparison, not from the commit subject" {
  run allowed
  [ "$output" = "proving again with nothing committed" ] || { echo "$output"; false; }
  # An empty commit with another subject changes no tree: still the same code the proof proved.
  git commit -q --allow-empty -m "chore: a note"
  run allowed
  [ "$output" = "proving again with nothing committed" ] || { echo "$output"; false; }
  # A code commit, then a commit with the proof's subject: the trees differ, so no reason.
  printf 'more\n' >> src/a.txt
  git commit -q -am "feat: a"
  git commit -q --allow-empty -m "chore(vbw): proof passed"
  run allowed
  [ -z "$output" ] || { echo "$output"; false; }
  run causes
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R175: no code in plugin/lib decides anything from a commit subject: the proof commit's words appear only where the commit message is written" {
  local f
  while IFS= read -r f; do
    [ "$(basename "$f")" = cmd-prove.sh ] || { echo "$f reads the proof commit's subject"; false; }
  done < <(grep -lF 'chore(vbw): proof passed' "$PLUGIN_ROOT"/lib/* || true)
  run grep -nE 'git[^|&;]*\blog\b' "$PLUGIN_ROOT/lib/proofreuse.sh" "$PLUGIN_ROOT/lib/proofcauses.sh"
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "R175: a proof recorded on an uncommitted edit, then that edit committed: the working tree still matches the proof but HEAD is not the tree it ran on, so no 'nothing was committed' cause or reason" {
  printf 'more\n' >> src/a.txt
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.passed == true and (.evidence.head != .evidence.tree)' .vbw/record.json > /dev/null || { jq .evidence .vbw/record.json; false; }
  git commit -q -am "feat: a"
  run causes
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'nothing was committed' && { echo "$output"; false; }
  run allowed
  [ -z "$output" ] || { echo "$output"; false; }
}
