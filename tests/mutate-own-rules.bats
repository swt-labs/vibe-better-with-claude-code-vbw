#!/usr/bin/env bats
# R193 (T159, T165; docs/proof.md, docs/workflows.md): a task break
# (vbw mutate PLAN taskK) without --check runs the checks of the rules the plan
# owes: every rule whose plan field names PLAN, plus every rule of a requirement
# PLAN completes (no other open plan serves it). A check shared by several of
# those rules runs once; no check of another requirement runs. The run on the
# unbroken code judges only those checks, so a check of the plan's requirement
# that is red but belongs to a rule the plan does not owe no longer refuses the
# break (the T159 case: an early plan of a requirement later plans complete). An
# owed check that is red on the unbroken code refuses, writes nothing, names the
# check and says what to do: make it pass and commit, --check ID, or --none
# REASON naming the plan that completes the requirement. A plan that owes no
# rule runs the checks of its requirements as before, and its refusal adds that
# the plan owns no rule and that the Lead names a plan on each rule. --check and
# rule breaks are unchanged; the recorded checks map and the output list exactly
# the checks that ran. Checks log their runs to $RANLOG. L1: the kernel on a
# fixture project.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  # P1.2 is not built yet: C1 stays red until it is, and it sorts first.
  printf 'echo nothing yet\n' > src/more.sh
  printf 'a note\n' > src/note.txt
  printf 'echo receipt\n' > src/receipt.sh
  # C1 wants more.sh built; C2 reads the first line paid prints; C3 counts its lines; C4 is R2's.
  printf 'echo C1 >> "$RANLOG"\n[ "$(sh src/more.sh)" = more ]\n' > tests/more.sh
  printf 'echo C2 >> "$RANLOG"\n[ "$(sh src/pay.sh | head -n 1)" = paid ]\n' > tests/pay.sh
  printf 'echo C3 >> "$RANLOG"\n[ "$(sh src/pay.sh | wc -l | tr -d " ")" = 1 ]\n' > tests/pay-once.sh
  printf 'echo C4 >> "$RANLOG"\n[ "$(sh src/receipt.sh)" = receipt ]\n' > tests/receipt.sh
  # R1 has three plans: P1.1 owns one rule on C2 and two on C3, P1.2 owns the
  # rule on C1, P1.3 owns no rule. P1.4 serves R2 alone.
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1", "R2"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay", "print once"]},
            {id: "P1.2", phase: "P1", title: "More", reqs: ["R1"], files: ["src/more.sh"], after: [], role: "dev", tasks: ["more"]},
            {id: "P1.3", phase: "P1", title: "Note", reqs: ["R1"], files: ["src/note.txt"], after: [], role: "dev", tasks: ["note"]},
            {id: "P1.4", phase: "P1", title: "Receipt", reqs: ["R2"], files: ["src/receipt.sh"], after: [], role: "dev", tasks: ["receipt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/more.sh"], files: ["tests/more.sh"]},
             {id: "C2", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C3", req: "R1", run: ["sh", "tests/pay-once.sh"], files: ["tests/pay-once.sh"]},
             {id: "C4", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]}],
    rules: [{req: "R1", text: "more prints more", check: "C1", plan: "P1.2"},
            {req: "R1", text: "paying prints paid", check: "C2", plan: "P1.1"},
            {req: "R1", text: "paying prints one line", check: "C3", plan: "P1.1"},
            {req: "R1", text: "paying prints nothing else", check: "C3", plan: "P1.1"},
            {req: "R2", text: "a receipt is printed", check: "C4", plan: "P1.4"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

record_sum() { cksum < .vbw/record.json; }
breaks() { jq -c --arg p "$1" '[.plans[] | select(.id == $p) | .mutations // [] | .[]]' .vbw/record.json; }
# ran ID: how many times check ID ran.
ran() { grep -cx "$1" "$RANLOG" || true; }
# kept_break FILE: the working file still differs from its last commit (R265: the kernel never puts it back).
kept_break() { [ -n "$(git status --porcelain -- "$1")" ] || { echo "$1 was put back to its last commit by the kernel"; return 1; }; }
# refused SUM: the last run failed and the record is byte-identical to SUM.
refused() {
  [ "$status" -ne 0 ] || { echo "not refused: $output"; return 1; }
  [ "$(record_sum)" = "$1" ] || { echo "the record changed: $output"; return 1; }
}
edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
}
# build_more: P1.2's code is built and committed, so C1 passes.
build_more() {
  printf 'echo more\n' > src/more.sh
  git add src/more.sh && git commit -q -m "feat(more): more" -- src/more.sh
}

@test "R193: the T159 case: a task break runs only the checks of the rules the plan owes and records red, though another rule's check of the requirement is still red" {
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 task1 "prints unpaid" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"task1 red"* ]] || { echo "$output"; false; }
  breaks P1.1 | jq -e 'length == 1 and .[0].task == 1 and .[0].checks == {C2: "red"} and .[0].result == "red"' || { breaks P1.1; false; }
  # C1 belongs to P1.2's rule and never ran; C4 is another requirement's.
  [ "$(ran C1)" -eq 0 ] || { echo "C1 ran: $(cat "$RANLOG")"; false; }
  [ "$(ran C4)" -eq 0 ] || { echo "C4 ran: $(cat "$RANLOG")"; false; }
  kept_break src/pay.sh
}

@test "R193: a check shared by several owed rules runs once; the record and the output list exactly the checks that ran" {
  # Two lines: C2 (first line) stays green, C3 (one line) goes red.
  printf 'echo paid\necho paid\n' > src/pay.sh
  run "$VBW" mutate P1.1 task2 "prints paid twice" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  breaks P1.1 | jq -e '.[0].task == 2 and .[0].checks == {C2: "green", C3: "red"} and .[0].result == "red"' || { breaks P1.1; false; }
  [[ "$output" == *"C2 green"* && "$output" == *"C3 red"* && "$output" != *C1* && "$output" != *C4* ]] || { echo "$output"; false; }
  # Each ran once on the unbroken code and once on the break: the shared C3 not twice over.
  [ "$(ran C2)" -eq 2 ] || { echo "C2 ran $(ran C2) times"; false; }
  [ "$(ran C3)" -eq 2 ] || { echo "C3 ran $(ran C3) times"; false; }
  [ "$(ran C1)" -eq 0 ] && [ "$(ran C4)" -eq 0 ] || { echo "$(cat "$RANLOG")"; false; }
  kept_break src/pay.sh
}

@test "R193: the plan that completes a requirement owes every rule of it, those naming other plans included; while another plan is open it owes only its own" {
  build_more
  # A break no check notices runs every owed check: with P1.1 open, P1.2 owes only its own rule.
  printf 'echo more # noted\n' > src/more.sh
  run "$VBW" mutate P1.2 task1 "adds a comment" src/more.sh < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *survivor* ]] || { echo "$output"; false; }
  breaks P1.2 | jq -e '.[0].checks == {C1: "green"} and .[0].result == "survivor"' || { breaks P1.2; false; }
  kept_break src/more.sh
  # With P1.1 and P1.3 done, P1.2 completes R1 and owes every rule of it.
  edit_record '(.plans[] | select(.id == "P1.1" or .id == "P1.3")).status = "done"'
  : > "$RANLOG"
  printf 'echo more # noted twice\n' > src/more.sh
  run "$VBW" mutate P1.2 task1 "adds another comment" src/more.sh < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *survivor* ]] || { echo "$output"; false; }
  breaks P1.2 | jq -e '.[1].checks == {C1: "green", C2: "green", C3: "green"} and .[1].result == "survivor"' || { breaks P1.2; false; }
  [ "$(ran C4)" -eq 0 ] || { echo "C4 ran: $(cat "$RANLOG")"; false; }
}

@test "R193: an owed check red on the unbroken code refuses, writes nothing, names the check and the three ways out" {
  local sum
  sum=$(record_sum)
  printf 'echo less\n' > src/more.sh
  run "$VBW" mutate P1.2 task1 "prints less" src/more.sh < /dev/null
  refused "$sum"
  [[ "$output" == *C1* ]] || { echo "$output"; false; }
  [[ "$output" == *"make it pass and commit"* ]] || { echo "no 'make it pass and commit': $output"; false; }
  [[ "$output" == *"--check"* ]] || { echo "no --check: $output"; false; }
  [[ "$output" == *"--none"* ]] || { echo "no --none: $output"; false; }
  [ "$(ran C4)" -eq 0 ]
  kept_break src/more.sh
}

@test "R193: a plan owning no rule runs the checks of its requirements as before, and its refusal says so and names the Lead's remedy" {
  local sum
  sum=$(record_sum)
  printf 'another note\n' > src/note.txt
  run "$VBW" mutate P1.3 task1 "changes the note" src/note.txt < /dev/null
  refused "$sum"
  [[ "$output" == *C1* ]] || { echo "$output"; false; }
  [[ "$output" == *"owns no rule"* ]] || { echo "no 'owns no rule': $output"; false; }
  [[ "$output" == *"names a plan"* ]] || { echo "no 'names a plan': $output"; false; }
  kept_break src/note.txt
  # Once every check of its requirements passes, the break runs them all, as before.
  build_more
  : > "$RANLOG"
  printf 'another note\n' > src/note.txt
  run "$VBW" mutate P1.3 task1 "changes the note" src/note.txt < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *survivor* ]] || { echo "$output"; false; }
  breaks P1.3 | jq -e '.[0].checks == {C1: "green", C2: "green", C3: "green"} and .[0].result == "survivor"' || { breaks P1.3; false; }
  [ "$(ran C4)" -eq 0 ]
  kept_break src/note.txt
}

@test "R193: --check still narrows the run and refuses another requirement's check; a rule break runs its own check as before" {
  printf 'echo paid\necho paid\n' > src/pay.sh
  run "$VBW" mutate P1.1 task2 --check C3 "prints paid twice" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  breaks P1.1 | jq -e '.[0].checks == {C3: "red"}' || { breaks P1.1; false; }
  [[ "$output" == *"C3 red"* && "$output" != *C2* ]] || { echo "$output"; false; }
  [ "$(ran C2)" -eq 0 ]
  local sum
  sum=$(record_sum)
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 task1 --check C4 "prints unpaid" src/pay.sh < /dev/null
  refused "$sum"
  # --check C1 names a check of the plan's requirement that is red: refused as a red check is.
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 task1 --check C1 "prints unpaid" src/pay.sh < /dev/null
  refused "$sum"
  [[ "$output" == *C1* ]] || { echo "$output"; false; }
  # A rule break runs that rule's own check, nothing else.
  : > "$RANLOG"
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 R1.2 "prints unpaid" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  breaks P1.1 | jq -e '.[-1].rule == {req: "R1", k: 2} and .[-1].checks == {C2: "red"}' || { breaks P1.1; false; }
  [ "$(ran C2)" -eq 2 ] && [ "$(ran C3)" -eq 0 ] || { echo "$(cat "$RANLOG")"; false; }
  run "$VBW" mutate P1.1 R2.1 "prints unpaid" src/pay.sh < /dev/null
  [ "$status" -ne 0 ]
  kept_break src/pay.sh
}

@test "R193: the Dev's instructions say a task break runs the checks of the plan's own rules" {
  grep -i 'task' "$PLUGIN_ROOT/agents/dev.md" | grep -qi 'own rules' || { echo "dev.md has no line saying a task break runs the plan's own rules' checks"; false; }
}

@test "R193: the kernel code is bash 3.2 code that passes JSON only through jq" {
  local f="$PLUGIN_ROOT/lib/cmd-mutate.sh"
  /bin/bash -n "$f"
  ! grep -nE '^[^#]*(\b(mapfile|readarray|eval)\b|(declare|local|typeset) -[a-zA-Z]*A|\$\{[A-Za-z_][A-Za-z_0-9]*(,,|\^\^|,|\^)\})' "$f" || false
  ! grep -nE '^[^#]*\b(grep|sed|awk|cut)\b[^|;]*(record\.json|\.json\b)' "$f" || false
}
