#!/usr/bin/env bats
# R207 (docs/workflows.md): vbw mutate PLAN Rn.k WHAT FILE..., vbw mutate PLAN
# taskK ... WHAT FILE... and vbw mutate PLAN --run end with where their time went,
# in the proof's form, measured by prooftime.sh's clock and nothing estimated:
#   VBW's own work: X of Y min
#     steps of W s: copies A, unbroken B, break R3.1 C, waits D, saving E
# copies: making, breaking, restoring and removing the clean copies; unbroken:
# the checks on the unbroken code; one entry per break named by its target
# ("break R3.1", "break task2"; in --run a wave of breaks run side by side is one
# entry naming its targets, "breaks R3.1 R3.2"); waits: the seconds spent waiting
# for a computer-wide slot (the figure the slots count); saving: recording the
# result. Seconds carry one decimal and the steps sum to W within rounding; X is
# the own work (copies, saving and the read tracking inside the runs). The two
# lines come after the result lines (red, survivor, "caught by the pending one")
# and before the slots line, for every outcome; the verdict, the recorded entry,
# the strengthened and pending markings and the exit code are what they were
# without them. A refusal prints no breakdown; --queue and --none print none.
# L1: the kernel on a fixture project; the wait case holds the only slot from
# another project (tests/machine-helper.bash).

load helper
load machine-helper
load fixture-helper

# shop_here: the shop in the current project folder: two requirements, two plans,
# C1 checks what pay.sh prints, C3 that it prints one line, C2 cannot fail on what
# receipt.sh prints. Approved and committed.
shop_here() {
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n- R2 [auto] A customer gets a receipt\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  printf 'echo receipt\n' > src/receipt.sh
  printf '[ "$(sh src/pay.sh)" = paid ]\n' > tests/pay.sh
  printf '[ "$(sh src/pay.sh | wc -l | tr -d " ")" = 1 ]\n' > tests/pay-once.sh
  printf 'sh src/receipt.sh > /dev/null\n' > tests/receipt.sh
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1", "R2"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay", "print once"]},
            {id: "P1.2", phase: "P1", title: "Receipt", reqs: ["R2"], files: ["src/receipt.sh"], after: [], role: "dev", tasks: ["receipt"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]},
             {id: "C2", req: "R2", run: ["sh", "tests/receipt.sh"], files: ["tests/receipt.sh"]},
             {id: "C3", req: "R1", run: ["sh", "tests/pay-once.sh"], files: ["tests/pay-once.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"},
            {req: "R1", text: "paying prints one line", check: "C3"},
            {req: "R2", text: "a receipt is printed", check: "C2"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
}

built_project() {
  vbw_setup
  shop_here
}

# pair: on 2 cores (limit 1), the shop and, beside it, project B whose one unit
# works 5 s, to hold the only slot. For fixture_build.
pair() {
  machine_setup
  cores 2
  shop_here
  machine_project "$OTHER" B 1 5
}

setup_file() {
  fixture_build built built_project
  fixture_build pair pair
}
setup() { fixture_copy built; }
teardown() { machine_teardown; }
teardown_file() { fixture_teardown; }

OWN_RE="^VBW's own work: [0-9]+\.[0-9] of [0-9]+\.[0-9] min$"
STEPS_RE='^  steps of [0-9]+\.[0-9] s: copies [0-9]+\.[0-9], unbroken [0-9]+\.[0-9], (breaks? [^,]+ [0-9]+\.[0-9], )+waits [0-9]+\.[0-9], saving [0-9]+\.[0-9]$'

# split: OWN (the own-work line), STEPS (the line after it), BEFORE (every line
# before OWN) and AFTER (every line after STEPS), from $output. Fails when the
# own-work line is missing or appears twice.
split() {
  local n
  [ "$(printf '%s\n' "$output" | grep -cE "$OWN_RE")" -eq 1 ] || { echo "own-work line count is not 1:"; echo "$output"; return 1; }
  n=$(printf '%s\n' "$output" | grep -nE "$OWN_RE" | cut -d: -f1)
  OWN=$(printf '%s\n' "$output" | sed -n "${n}p")
  STEPS=$(printf '%s\n' "$output" | sed -n "$((n + 1))p")
  BEFORE=$(printf '%s\n' "$output" | sed -n "1,$((n - 1))p")
  AFTER=$(printf '%s\n' "$output" | sed -n "$((n + 2)),\$p")
  [[ "$STEPS" =~ $STEPS_RE ]] || { echo "no steps line after the own-work line: $STEPS"; echo "$output"; return 1; }
}

# none: the output carries no breakdown.
none() {
  if printf '%s\n' "$output" | grep -qE "$OWN_RE|^  steps of "; then echo "a breakdown was printed:"; echo "$output"; return 1; fi
}

# step NAME: the seconds of step NAME in $STEPS (empty when absent).
step() { printf '%s\n' "$STEPS" | sed 's/^  steps of [0-9.]* s: //' | tr ',' '\n' | sed 's/^ //' | awk -v n="$1" '{v=$NF; $NF=""; sub(/ $/, ""); if ($0 == n) print v}'; }
# names: the step names of $STEPS, in order, one per line.
names() { printf '%s\n' "$STEPS" | sed 's/^  steps of [0-9.]* s: //' | tr ',' '\n' | sed 's/^ //' | awk '{$NF=""; sub(/ $/, ""); print}'; }
# total: W of $STEPS.
total() { printf '%s\n' "$STEPS" | sed 's/^  steps of \([0-9.]*\) s:.*/\1/'; }
# sum_ok: the steps sum to W within rounding (a tenth per figure).
sum_ok() {
  local w s k
  w=$(total)
  s=$(printf '%s\n' "$STEPS" | sed 's/^  steps of [0-9.]* s: //' | tr ',' '\n' | awk '{s += $NF} END {printf "%.1f", s}')
  k=$(names | wc -l | tr -d ' ')
  awk -v w="$w" -v s="$s" -v k="$k" 'BEGIN {d = w - s; if (d < 0) d = -d; exit !(d <= 0.1 * k + 0.05)}' \
    || { echo "steps sum $s, wall $w: $STEPS"; return 1; }
}

last_break() { jq -c --arg p "$1" '[.plans[] | select(.id == $p) | .mutations // [] | .[]] | last' .vbw/record.json; }

@test "R207: a red rule break ends with the own-work line and the split: copies, unbroken, break Rn.k, waits, saving, summing to the wall" {
  printf 'echo unpaid\n' > src/pay.sh
  vbw_run mutate P1.1 R1.1 "prints unpaid instead of paid" src/pay.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  [ "$BEFORE" = "R1.1 red: prints unpaid instead of paid
C1 red" ] || { echo "$output"; false; }
  [ -z "$AFTER" ] || { echo "lines after the split: $AFTER"; false; }
  [ "$(names | tr '\n' '|')" = "copies|unbroken|break R1.1|waits|saving|" ] || { names; false; }
  sum_ok
  last_break P1.1 | jq -e '(keys | sort) == ["at","checks","files","head","result","rule","tree","what"] and .result == "red" and .checks == {C1: "red"}' || { last_break P1.1; false; }
  [ "$(cat src/pay.sh)" = "$(git show HEAD:src/pay.sh)" ]
}

@test "R207: a survivor keeps its exit 1 and its line; the breakdown follows it" {
  printf 'echo nothing\n' > src/receipt.sh
  vbw_run mutate P1.2 R2.1 "prints nothing" src/receipt.sh
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  split
  [ "$BEFORE" = "survivor: R2.1 (a receipt is printed): C2 still pass" ] || { echo "$output"; false; }
  [ -z "$AFTER" ] || { echo "$output"; false; }
  [ "$(names | tr '\n' '|')" = "copies|unbroken|break R2.1|waits|saving|" ] || { names; false; }
  last_break P1.2 | jq -e '.result == "survivor" and (keys | sort) == ["at","checks","files","head","result","rule","tree","what"]' || { last_break P1.2; false; }
}

@test "R207: a task break names its entry by the task" {
  printf 'echo unpaid\n' > src/pay.sh
  vbw_run mutate P1.1 task1 "prints unpaid" src/pay.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  [ "$(printf '%s\n' "$BEFORE" | head -n 1)" = "task1 red: prints unpaid" ] || { echo "$output"; false; }
  [ "$(names | tr '\n' '|')" = "copies|unbroken|break task1|waits|saving|" ] || { names; false; }
  sum_ok
  last_break P1.1 | jq -e '.task == 1 and .result == "red"' || { last_break P1.1; false; }
}

@test "R207: a break caught by a check file waiting for approval keeps its lines, the pending marking and exit 0; the breakdown comes after them" {
  printf 'echo nothing\n' > src/receipt.sh
  run "$VBW" mutate P1.2 R2.1 "prints nothing" src/receipt.sh < /dev/null
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  printf '[ "$(sh src/receipt.sh)" = receipt ]\n' > tests/receipt.sh
  git commit -q -am "test(receipt): check what is printed"
  printf 'echo nothing\n' > src/receipt.sh
  vbw_run mutate P1.2 R2.1 "prints nothing" src/receipt.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  [ "$BEFORE" = "vbw: waiting for approval (new or changed since approved): tests/receipt.sh
R2.1 survives the approved check; caught by the pending one: tests/receipt.sh
C2 red
the pending file still needs the one approval before the proof" ] || { echo "$output"; false; }
  [ -z "$AFTER" ] || { echo "$output"; false; }
  last_break P1.2 | jq -e '.result == "red" and .pending == ["tests/receipt.sh"]' || { last_break P1.2; false; }
}

@test "R207, R232: the figures are measured by the proof's clock: a check that moves the injected clock one second on broken code puts exactly that second into the break's entry" {
  # The clock is a file (VBW_PROOFTIME_CLOCK): the check on broken code writes a reading
  # 1.000 s later into it, so nothing here waits a real second (T195: real time made the
  # unbroken and the break figures both 1.1 s on Linux runners).
  local clock="$TEST_ROOT/clock"
  printf '1000.000\n' > "$clock"
  printf 'out=$(sh src/pay.sh)\n[ "$out" = paid ] || printf "1001.000\\n" > "%s"\n[ "$out" = paid ]\n' "$clock" > tests/pay.sh
  git commit -q -am "test(pay): moves the clock when red"
  "$VBW" approve > /dev/null
  printf 'echo unpaid\n' > src/pay.sh
  run env VBW_PROOFTIME_CLOCK="$clock" "$VBW" mutate P1.1 R1.1 "prints unpaid" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  [ "$(step 'break R1.1')" = "1.0" ] || { echo "$STEPS"; false; }
  [ "$(step unbroken)" = "0.0" ] || { echo "$STEPS"; false; }
  [ "$(total)" = "1.0" ] || { echo "$STEPS"; false; }
  sum_ok
  [ "$(cat "$clock")" = "1001.000" ]
}

@test "R207: a refusal ends with its message as today and prints no breakdown: red on the unbroken code, a dirty check file, a stale queued break" {
  printf 'echo unpaid\n' > src/pay.sh
  git commit -q -am "feat(pay): broken on purpose"
  printf 'echo nothing\n' > src/pay.sh
  vbw_run mutate P1.1 R1.1 "prints nothing" src/pay.sh
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"checks do not pass on the unbroken code"* ]] || { echo "$output"; false; }
  none
  git checkout -q HEAD~1 -- src/pay.sh && git commit -q -am "fix(pay): paid again"
  printf 'echo paid # touched\n' > src/pay.sh
  printf '# dirty\n' >> tests/pay.sh
  vbw_run mutate P1.1 R1.1 "a comment" src/pay.sh
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"check files differ from the last commit"* ]] || { echo "$output"; false; }
  none
  git checkout -q -- tests/pay.sh src/pay.sh
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.1 --queue "prints unpaid" src/pay.sh > /dev/null
  printf 'later\n' > src/later.txt
  git add src/later.txt && git commit -q -m "chore: another commit"
  vbw_run mutate P1.1 --run
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"was queued at another commit"* ]] || { echo "$output"; false; }
  none
}

@test "R207: --queue and --none run no break and print no breakdown" {
  printf 'echo unpaid\n' > src/pay.sh
  vbw_run mutate P1.1 R1.1 --queue "prints unpaid" src/pay.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  none
  vbw_run mutate P1.1 task2 --none "documentation only"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  none
  vbw_run mutate P1.2 R2.1 --none "the check judges the record alone"
  none
}

@test "R207: --run one at a time ends with one entry per break in queue order, after the last result" {
  "$VBW" config set check_jobs 1 > /dev/null
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.1 --queue "prints unpaid" src/pay.sh > /dev/null
  printf 'echo paid\necho paid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.2 --queue "prints twice" src/pay.sh > /dev/null
  vbw_run mutate P1.1 --run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  [ "$(printf '%s\n' "$BEFORE" | tail -n 2)" = "R1.2 red: prints twice
C3 red" ] || { echo "$output"; false; }
  [ -z "$AFTER" ] || { echo "$output"; false; }
  [ "$(names | tr '\n' '|')" = "copies|unbroken|break R1.1|break R1.2|waits|saving|" ] || { names; false; }
  sum_ok
  jq -e '[.plans[] | select(.id == "P1.1") | .mutations[] | .result] == ["red", "red"]' .vbw/record.json
}

@test "R207: --run with breaks side by side names the wave's targets in one entry" {
  "$VBW" config set check_jobs 2 > /dev/null
  printf 'echo unpaid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.1 --queue "prints unpaid" src/pay.sh > /dev/null
  printf 'echo paid\necho paid\n' > src/pay.sh
  "$VBW" mutate P1.1 R1.2 --queue "prints twice" src/pay.sh > /dev/null
  vbw_run mutate P1.1 --run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  [ "$(names | tr '\n' '|')" = "copies|unbroken|breaks R1.1 R1.2|waits|saving|" ] || { names; false; }
  sum_ok
}

@test "R207: waits is the time the run waited for a computer-wide slot, and the slots line still comes last" {
  fixture_copy pair
  bg "$OTHER" "$TEST_ROOT/b.out" check C1
  wait_starts 1 B-
  printf 'echo unpaid\n' > src/pay.sh
  vbw_run mutate P1.1 R1.1 "prints unpaid" src/pay.sh
  wait "$BG_PID" || true
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  awk -v w="$(step waits)" 'BEGIN {exit !(w >= 1.0)}' || { echo "$STEPS"; false; }
  sum_ok
  [[ "$AFTER" =~ ^waited\ [0-9]+\ s\ for\ other\ VBW\ runs\ on\ this\ computer ]] || { echo "after the split: $AFTER"; echo "$output"; false; }
  [ "$(printf '%s\n' "$AFTER" | wc -l | tr -d ' ')" -eq 1 ] || { echo "$AFTER"; false; }
}

@test "R207: without a wait the entry reads 0.0 and no slots line follows" {
  printf 'echo unpaid\n' > src/pay.sh
  vbw_run mutate P1.1 R1.1 "prints unpaid" src/pay.sh
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  split
  [ "$(step waits)" = "0.0" ] || { echo "$STEPS"; false; }
  [ -z "$AFTER" ]
}

@test "R207: the own-work figure is copies plus tracking plus saving, in minutes with one decimal, of the wall" {
  # mutate_time_say on a timer of known steps: 100 s of copies, 5 unbroken, 20 broken, 10 of tracking, 20 saving, 160 s wall.
  # The clock stands still: mutate_time_say reads it again, and on a busy machine a real clock
  # moved on between the readings (2026-10-29: "steps of 160.1 s").
  run env VBW_LIB="$REPO_ROOT/plugin/lib" VBW_RUNTIME="$PWD/.vbw/runtime" bash -c '
    . "$VBW_LIB/core.sh"; . "$VBW_LIB/prooftime.sh"; . "$VBW_LIB/cmd-mutate.sh"
    prooftime_clock() { printf "%s\n" 1000.000; }
    prooftime_begin
    n=$(prooftime_clock)
    PROOFTIME_T0=$(awk -v n="$n" "BEGIN {printf \"%.3f\", n - 160}")
    PROOFTIME_AT=$n
    prooftime_add copies 100; prooftime_add unbroken 5; prooftime_add "break R1.1" 20; prooftime_add tracking 10; prooftime_add saving 20
    mutate_time_say' 2> /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | head -n 1)" = "VBW's own work: 2.2 of 2.7 min" ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | sed -n 2p)" = "  steps of 160.0 s: copies 100.0, unbroken 5.0, break R1.1 20.0, waits 0.0, saving 20.0" ] || { echo "$output"; false; }
}

# R232 (T195): the clock the proof's timer reads can be injected: when VBW_PROOFTIME_CLOCK
# names a readable file, prooftime_detect sets the clock kind to file and prooftime_clock
# prints that file's first line (seconds with milliseconds) instead of the machine clock;
# unset or unreadable, nothing changes. The variable is an environment variable, so it
# reaches a unit's subshell and the vbw process a test starts. This file then measures no
# real duration: nothing in it pauses the shell (the R152 rule in tests/release-run.bats
# sees clocks, not pauses), and docs/proof.md names the variable as a test hook.

@test "R232: prooftime_clock reads the file VBW_PROOFTIME_CLOCK names, and the machine clock when it is unset or unreadable" {
  local clock="$TEST_ROOT/clock"
  printf '1234.567\nignored second line\n' > "$clock"
  run env VBW_PROOFTIME_CLOCK="$clock" VBW_LIB="$REPO_ROOT/plugin/lib" bash -c '. "$VBW_LIB/core.sh"; . "$VBW_LIB/prooftime.sh"; prooftime_detect; printf "%s %s\n" "$PROOFTIME_NS" "$(prooftime_clock)"; printf "1300.000\n" > "$VBW_PROOFTIME_CLOCK"; prooftime_clock'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | sed -n 1p)" = "file 1234.567" ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | sed -n 2p)" = "1300.000" ] || { echo "$output"; false; }
  run env -u VBW_PROOFTIME_CLOCK VBW_LIB="$REPO_ROOT/plugin/lib" bash -c '. "$VBW_LIB/core.sh"; . "$VBW_LIB/prooftime.sh"; prooftime_detect; printf "%s %s\n" "$PROOFTIME_NS" "$(prooftime_clock)"'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" =~ ^(nanos|perl|none)\ [0-9]+\.[0-9]{3}$ ]] || { echo "$output"; false; }
  run env VBW_PROOFTIME_CLOCK="$TEST_ROOT/no-such-file" VBW_LIB="$REPO_ROOT/plugin/lib" bash -c '. "$VBW_LIB/core.sh"; . "$VBW_LIB/prooftime.sh"; prooftime_detect; printf "%s %s\n" "$PROOFTIME_NS" "$(prooftime_clock)"'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" =~ ^(nanos|perl|none)\ [0-9]+\.[0-9]{3}$ ]] || { echo "$output"; false; }
}

@test "R232: this file waits no real time: nothing in it pauses the shell" {
  [ "$(grep -c 'slee[p]' "$BATS_TEST_FILENAME")" -eq 0 ] || { grep -n 'slee[p]' "$BATS_TEST_FILENAME"; false; }
}

@test "R232: docs/proof.md names VBW_PROOFTIME_CLOCK as a test hook for the proof's clock" {
  grep -qF 'VBW_PROOFTIME_CLOCK' "$REPO_ROOT/docs/proof.md"
  grep -F 'VBW_PROOFTIME_CLOCK' "$REPO_ROOT/docs/proof.md" | grep -qi 'test'
}
