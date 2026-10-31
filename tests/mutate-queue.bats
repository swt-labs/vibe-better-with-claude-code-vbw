#!/usr/bin/env bats
# T174 (docs/workflows.md, docs/proof.md): rule breaks run side by side. vbw
# mutate PLAN Rn.k --queue WHAT FILE... sets one break aside and puts the files
# back at once, running nothing; vbw mutate PLAN --run runs every queued break of
# the plan: each rule's check once on the unbroken code (as the single form, never
# once per break), then the breaks, each in its own proof copy, as many at a time
# as check_jobs allows, and records each result as the single form would. A
# survivor makes it exit 1; a break queued at another commit is dropped and named
# (break it again), and it exits 1 too. Check files that differ from the last
# commit stop it. --queue is for a rule break only; --run with nothing queued
# says how to queue. vbw plan done names queued breaks not run yet. L1: the
# kernel on a fixture project.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'echo paid\n' > src/pay.sh
  LOG="$TEST_ROOT/runs"
  BAR="$TEST_ROOT/bar"
  MARK="$TEST_ROOT/marks"
  MARKER="$PROJECT/.vbw/runtime/mutate-queue/P1.1/run.pid"
  mkdir -p "$BAR"
  # Every run logs a line and copies the plan's run marker, when there is one (R230).
  # With $BAR/on, a run on broken code waits (up to 10 s) until a second one is under
  # way, and says whether it saw it: the breaks ran side by side. With $BAR/hold, a run
  # on broken code names itself in $BAR and waits (up to 30 s) for $BAR/go.
  cat > tests/pay.sh <<EOF
out=\$(sh src/pay.sh)
echo run >> "$LOG"
cat "$MARKER" >> "$MARK" 2> /dev/null || true
if [ "\$out" != paid ] && [ -f "$BAR/on" ]; then
  touch "$BAR/\$\$"; i=0
  while [ "\$(ls "$BAR" | grep -c '^[0-9]')" -lt 2 ] && [ \$i -lt 100 ]; do sleep 0.1; i=\$((i + 1)); done
  [ "\$(ls "$BAR" | grep -c '^[0-9]')" -lt 2 ] || touch "$BAR/met.\$\$"
fi
if [ "\$out" != paid ] && [ -f "$BAR/hold" ]; then
  touch "$BAR/\$\$"; i=0
  while [ ! -f "$BAR/go" ] && [ \$i -lt 300 ]; do sleep 0.1; i=\$((i + 1)); done
fi
[ "\$out" = paid ]
EOF
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.sh"], after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}],
    rules: [{req: "R1", text: "paying prints paid", check: "C1"},
            {req: "R1", text: "nothing but paid is printed", check: "C1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
  "$VBW" config set check_jobs 2 > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
}

teardown() {
  [ -z "${SLEEPER:-}" ] || kill "$SLEEPER" 2> /dev/null || true
  [ -z "${RUN1:-}" ] || { touch "$BAR/go"; wait "$RUN1" 2> /dev/null || true; }
  vbw_teardown
}

breaks() { jq -c '[.plans[0].mutations[]? | {t: (.rule.text // "task\(.task)"), r: .result, c: .checks}]' .vbw/record.json; }
queue() {
  local target=$1 what=$2 body=$3
  printf '%s\n' "$body" > src/pay.sh
  run "$VBW" mutate P1.1 "$target" --queue "$what" src/pay.sh < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat src/pay.sh)" = "$(git show HEAD:src/pay.sh)" ] || { echo "src/pay.sh was not put back: $(cat src/pay.sh)"; return 1; }
}

@test "T174: --queue sets the break aside and puts the file back at once; nothing runs and nothing is recorded" {
  queue R1.1 "prints unpaid" 'echo unpaid'
  [[ "$output" == *"R1.1 queued"* && "$output" == *"vbw mutate P1.1 --run"* ]] || { echo "$output"; false; }
  [ ! -f "$LOG" ] || { echo "a check ran: $(cat "$LOG")"; false; }
  [ "$(breaks)" = '[]' ] || breaks
  git diff --quiet -- src tests || { git status --short; false; }
}

@test "T174: --run runs the queued breaks side by side, the check once unbroken, and records each as red" {
  touch "$BAR/on"
  queue R1.1 "prints unpaid" 'echo unpaid'
  queue R1.2 "prints more than paid" 'echo paid; echo more'
  run "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"R1.1 red: prints unpaid"* && "$output" == *"R1.2 red: prints more than paid"* ]] || { echo "$output"; false; }
  breaks | jq -e '. == [{t: "paying prints paid", r: "red", c: {C1: "red"}}, {t: "nothing but paid is printed", r: "red", c: {C1: "red"}}]' || breaks
  # One unbroken run of C1 and one run per break; both breaks were under way together.
  [ "$(wc -l < "$LOG" | tr -d ' ')" -eq 3 ] || { cat "$LOG"; false; }
  [ "$(ls "$BAR" | grep -c '^met\.')" -eq 2 ] || { ls "$BAR"; false; }
  [ -z "$(ls -A .vbw/runtime/mutate-queue/P1.1 2> /dev/null)" ] || ls -R .vbw/runtime/mutate-queue
  git diff --quiet -- src tests || { git status --short; false; }
  run "$VBW" plan done P1.1 < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "T174: a survivor among the queued breaks is recorded and makes --run exit 1; the others are recorded red" {
  queue R1.1 "prints unpaid" 'echo unpaid'
  queue R1.2 "prints oops on stderr" 'echo paid; echo oops >&2'
  run "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"R1.1 red"* && "$output" == *"survivor: R1.2"* ]] || { echo "$output"; false; }
  breaks | jq -e 'map(.r) == ["red", "survivor"]' || breaks
}

@test "T174: a break queued at another commit is dropped and named, and --run exits 1" {
  queue R1.1 "prints unpaid" 'echo unpaid'
  printf 'echo paid\n# one more line\n' > src/pay.sh
  "$VBW" commit P1.1 "feat(pay): note" > /dev/null
  queue R1.2 "prints unpaid again" 'echo unpaid'
  run "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"R1.1"*"another commit"*"break it again"* && "$output" == *"R1.2 red"* ]] || { echo "$output"; false; }
  breaks | jq -e 'map(.t) == ["nothing but paid is printed"]' || breaks
}

@test "T174: check files that differ from the last commit stop --run, and nothing is recorded" {
  queue R1.1 "prints unpaid" 'echo unpaid'
  printf '\n# stronger\n' >> tests/pay.sh
  run "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"tests/pay.sh"* && "$output" == *"commit them first"* ]] || { echo "$output"; false; }
  [ "$(breaks)" = '[]' ] || breaks
}

@test "T174: --queue is for a rule break; --run with nothing queued says how to queue" {
  printf 'echo unpaid\n' > src/pay.sh
  run "$VBW" mutate P1.1 task1 --queue "prints unpaid" src/pay.sh < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"--queue is for a rule break"* ]] || { echo "$output"; false; }
  run "$VBW" mutate P1.1 R1.1 --queue --none "a reason" < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"--queue is for a rule break"* ]] || { echo "$output"; false; }
  git checkout -q -- src/pay.sh
  run "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"no break waits for P1.1"* && "$output" == *"--queue"* ]] || { echo "$output"; false; }
}

@test "T174: vbw plan done names queued breaks that have not run yet" {
  queue R1.1 "prints unpaid" 'echo unpaid'
  run "$VBW" plan done P1.1 < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"R1.1"* && "$output" == *"vbw mutate P1.1 --run"* ]] || { echo "$output"; false; }
}

# R217 (M45 QA, kernel F323): the queued path records each result through the one
# mutate_record, with its ten documented arguments and no list of the check's
# files: pending and strengthened come from strengthen_files, never from the files
# of the checks a break ran.
@test "R217: the queued path passes mutate_record no check files, only the ten documented arguments" {
  local f="$PLUGIN_ROOT/lib/mutate-queue.sh" call
  ! awk '/^  for e in "\$\{keep\[@\]\}"; do$/, /rm -rf "\$e"/' "$f" | grep -q cfiles || { echo "mutate-queue.sh still builds a per-break list of the check's files"; false; }
  call=$(awk '/mutate_record /, /\|\| surv=1$/' "$f" | tr -d '\\\n' | tr -s ' ')
  [ -n "$call" ] || { echo "no mutate_record call found in mutate-queue.sh"; false; }
  [[ "$call" == *'"$(printf '"'"'%s'"'"' "$m" | jq -c .files)" "$tree" || surv=1'* ]] || { echo "the call does not end with FILES_JSON TREE: $call"; false; }
}

# R230 (#738): one vbw mutate PLAN --run at a time per plan. The run takes a marker,
# .vbw/runtime/mutate-queue/PLAN/run.pid, holding its own pid before it reads any queue
# entry, and removes it when it ends, however it ends. A second --run while that pid is
# alive is refused before it reads, copies or deletes any entry and before it records
# anything: "vbw: ..." names the running one (its pid and the command) and a Next: line
# tells the Dev to wait for it. A marker whose pid is dead does not block: the next run
# takes it over. So two runs of one plan never both make copies or record an entry twice.

# wait_for CONDITION...: wait (up to 30 s) until the command CONDITION succeeds.
wait_for() {
  local i
  for ((i = 0; i < 300; i++)); do
    "$@" > /dev/null 2>&1 && return 0
    sleep 0.1
  done
  echo "timed out waiting for: $*"
  return 1
}

# queue_entries: the queued breaks' folders, sorted, one per line.
queue_entries() { ls -d .vbw/runtime/mutate-queue/P1.1/[0-9]* 2> /dev/null; }

# started: at least one break's check has named itself in $BAR.
started() { [ "$(ls "$BAR" | grep -c '^[0-9]')" -ge 1 ]; }

@test "R230: a second --run while the marker's pid is alive is refused before it touches the queue or the record, naming the running one and telling the Dev to wait" {
  queue R1.1 "prints unpaid" 'echo unpaid'
  sleep 60 > /dev/null 2>&1 3>&- &
  SLEEPER=$!
  printf '%s\n' "$SLEEPER" > "$MARKER"
  local before
  before=$(find .vbw/runtime/mutate-queue -type f -print0 | sort -z | xargs -0 cat | shasum)
  run "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | head -n 1 | grep -c "^vbw: .*pid $SLEEPER.*vbw mutate P1\.1 --run")" -eq 1 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^Next: wait for it to finish' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'never start a second' || { echo "$output"; false; }
  [ "$(queue_entries | wc -l | tr -d ' ')" -eq 1 ] || { ls -R .vbw/runtime/mutate-queue; false; }
  [ "$(find .vbw/runtime/mutate-queue -type f -print0 | sort -z | xargs -0 cat | shasum)" = "$before" ] || { ls -R .vbw/runtime/mutate-queue; false; }
  [ "$(cat "$MARKER")" = "$SLEEPER" ]
  [ ! -f "$LOG" ] || { echo "a check ran: $(cat "$LOG")"; false; }
  [ -z "$(ls -d .vbw/runtime/proof.* 2> /dev/null)" ] || { ls .vbw/runtime; false; }
  [ "$(breaks)" = '[]' ] || breaks
  kill "$SLEEPER"
  SLEEPER=
}

@test "R230: a marker whose pid is dead does not block: the run takes it over, holds its own pid while the breaks run, and leaves none after" {
  queue R1.1 "prints unpaid" 'echo unpaid'
  local dead
  ( : ) > /dev/null 2>&1 3>&- &
  dead=$!
  wait "$dead" || true
  ! kill -0 "$dead" 2> /dev/null || skip "the dead pid is alive again"
  printf '%s\n' "$dead" > "$MARKER"
  run "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"R1.1 red: prints unpaid"* ]] || { echo "$output"; false; }
  [ -s "$MARK" ] || { echo "no check saw the marker"; false; }
  [ "$(sort -u "$MARK" | wc -l | tr -d ' ')" -eq 1 ] || { cat "$MARK"; false; }
  [[ "$(head -n 1 "$MARK")" =~ ^[0-9]+$ ]] || { cat "$MARK"; false; }
  [ "$(head -n 1 "$MARK")" != "$dead" ] || { cat "$MARK"; false; }
  [ ! -e "$MARKER" ] || { echo "the marker outlived the run"; false; }
  [ ! -d .vbw/runtime/mutate-queue/P1.1 ] || { echo "the queue folder outlived the run"; ls -A .vbw/runtime/mutate-queue/P1.1; false; }
  breaks | jq -e 'map(.r) == ["red"]' || breaks
}

@test "R230: a run with no break waiting, or only a break of another commit, leaves no marker and no empty folder" {
  run "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"no break waits for P1.1"* ]] || { echo "$output"; false; }
  [ ! -d .vbw/runtime/mutate-queue/P1.1 ] || { ls -A .vbw/runtime/mutate-queue/P1.1; false; }
  queue R1.1 "prints unpaid" 'echo unpaid'
  # Other committed code (a commit that changes no file leaves the break valid).
  printf 'x\n' > other.txt
  git add other.txt && git commit -q -m "move head"
  run "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -ne 0 ] && [[ "$output" == *"queued at another commit"* ]] || { echo "$output"; false; }
  [ ! -d .vbw/runtime/mutate-queue/P1.1 ] || { ls -A .vbw/runtime/mutate-queue/P1.1; false; }
}

@test "R230: two --run of the same plan never both make copies: the second is refused while the first holds its slot, one set of copies exists, and each entry is recorded once" {
  touch "$BAR/hold"
  queue R1.1 "prints unpaid" 'echo unpaid'
  queue R1.2 "prints more than paid" 'echo paid; echo more'
  "$VBW" mutate P1.1 --run > "$TEST_ROOT/run1.out" 2>&1 < /dev/null 3>&- &
  RUN1=$!
  wait_for started || { cat "$TEST_ROOT/run1.out"; false; }
  run "$VBW" mutate P1.1 --run < /dev/null
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"pid $RUN1"* ]] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^Next: wait for it to finish' || { echo "$output"; false; }
  local n
  n=$(sed -n 's/^running 2 breaks of P1.1, \([0-9]*\) at a time$/\1/p' "$TEST_ROOT/run1.out")
  [ -n "$n" ] || { cat "$TEST_ROOT/run1.out"; false; }
  [ "$(ls -d .vbw/runtime/proof.* | wc -l | tr -d ' ')" -eq "$n" ] || { ls .vbw/runtime; false; }
  [ "$(cat "$MARKER")" = "$RUN1" ] || { cat "$MARKER"; false; }
  touch "$BAR/go"
  wait "$RUN1"
  RUN1=
  breaks | jq -e '. == [{t: "paying prints paid", r: "red", c: {C1: "red"}}, {t: "nothing but paid is printed", r: "red", c: {C1: "red"}}]' || breaks
  [ ! -e "$MARKER" ]
  [ -z "$(ls -d .vbw/runtime/proof.* 2> /dev/null)" ] || { ls .vbw/runtime; false; }
}

@test "R230: the marker lives under .vbw/runtime and mutate-queue.sh's header names it" {
  local f="$PLUGIN_ROOT/lib/mutate-queue.sh"
  sed -n '1,/^[^#]/p' "$f" | grep -qF 'run.pid' || { echo "the header comment does not name run.pid"; false; }
  grep -qF 'mutate-queue/PLAN/run.pid' "$f" || { echo "the header does not place the marker under .vbw/runtime/mutate-queue/PLAN/"; false; }
  ! grep -nE '(/tmp|\$TMPDIR|\$HOME)' "$f" || { echo "mutate-queue.sh names a place outside the project"; false; }
}

@test "R230 wording: the Dev agent starts a long --run in the background on purpose, waits for it and reads its whole result, and never starts a second one; a refusal means wait" {
  local dev="$PLUGIN_ROOT/agents/dev.md" line
  line=$(grep -F -- '--run' "$dev" | tr '\n' ' ')
  printf '%s' "$line" | grep -qE 'start[^.]{0,80}in the background' || { echo "dev.md does not say to start --run in the background on purpose"; false; }
  printf '%s' "$line" | grep -qi '10 minutes\|10-minute' || { echo "dev.md does not name the one-command limit"; false; }
  printf '%s' "$line" | grep -qi 'whole result\|whole output' || { echo "dev.md does not say to read the whole result"; false; }
  printf '%s' "$line" | grep -qF 'never start a second' || { echo "dev.md does not say never start a second --run"; false; }
  printf '%s' "$line" | grep -qiE 'refus[^.]{0,80}wait' || { echo "dev.md does not say a refusal naming a running one means wait"; false; }
}

@test "R230 wording: docs/workflows.md documents the refusal, its Next: line, the marker and the background advice" {
  local doc="$REPO_ROOT/docs/workflows.md" sec
  sec=$(sed -n '/^## The mutation check/,/^## /p' "$doc" | tr '\n' ' ' | tr -s ' ')
  printf '%s' "$sec" | grep -qF 'Next: wait for it to finish' || { echo "the Next: wording of the refusal is not documented"; false; }
  printf '%s' "$sec" | grep -qF 'run.pid' || { echo "the marker is not documented"; false; }
  printf '%s' "$sec" | grep -qiE 'refus[^.]{0,200}same plan' || { echo "the refusal of a second run of the same plan is not documented"; false; }
  printf '%s' "$sec" | grep -qiE 'dead|no longer runs|ended' || { echo "the dead-marker takeover is not documented"; false; }
  printf '%s' "$sec" | grep -qi 'background' || { echo "the background advice is not documented"; false; }
}
