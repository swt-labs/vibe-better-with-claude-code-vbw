#!/usr/bin/env bats
# R305 (T288): vbw fix done reruns the units a change can reach and no others. A unit is
# reached when its recorded read list names a changed file (the one reuse rule of vbw
# prove). T288's round reran 210 units because the fix changed a kernel library and a doc
# that about 220 units had read; the rule was right, and the run said nothing about it.
# Now the opening line counts the units before the first one starts. Scripts log their runs
# to $RANLOG and copy what fix done had printed ($PEEK) into $PEEK.seen when they start. L1.

load helper
load fixture-helper

setup_file() { fixture_build reach reach_project; }
setup() { fixture_copy reach; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# reach_project: a passing proof, then a failing one that opens a fix for the test command.
reach_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'a\n' > src/a.txt
  printf 'b\n' > src/b.txt
  printf 'c\n' > src/c.txt
  printf 'echo t_a >> "$RANLOG"\n[ -z "${PEEK:-}" ] || cat "$PEEK" >> "$PEEK.seen"\n[ ! -e "$TEST_ROOT/fail_a" ] || { echo "t_a broken"; exit 1; }\ngrep -q . src/a.txt\n' > tests/t_a.sh
  printf 'echo t_b >> "$RANLOG"\n[ -z "${PEEK:-}" ] || cat "$PEEK" >> "$PEEK.seen"\ngrep -q . src/b.txt\n' > tests/t_b.sh
  printf 'echo t_c >> "$RANLOG"\n[ -z "${PEEK:-}" ] || cat "$PEEK" >> "$PEEK.seen"\ngrep -q . src/c.txt\n' > tests/t_c.sh
  printf 'echo all >> "$RANLOG"\n' > tests/all.sh
  export RANLOG="$TEST_ROOT/ran.log"
  : > "$RANLOG"
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf 'echo C1 >> "$RANLOG"\ngrep -q . src/a.txt\n' > tests/c1.sh
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]}] | .protected = ["tests/c1.sh"] | .schema = ([.schema, 4] | max)
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["src/"], after:[], status:"done"}]' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || { echo "the first proof failed"; return 1; }
  : > "$TEST_ROOT/fail_a"
  run "$VBW" prove < /dev/null
  [ "$status" -eq 1 ] || { echo "the second proof did not fail: $output"; return 1; }
  FIX=$(jq -r '.fixes[0].id' .vbw/record.json)
  : > "$RANLOG"
}

ran() { sort "$RANLOG" | tr '\n' ' '; }

# fix_done_peek: vbw fix done "$FIX" with its output in $PEEK; sets status and output.
fix_done_peek() {
  export PEEK="$TEST_ROOT/fixdone.out"
  : > "$PEEK.seen"
  status=0
  "$VBW" fix done "$FIX" > "$PEEK" 2>&1 < /dev/null || status=$?
  output=$(cat "$PEEK")
}

@test "R305: a fix whose change one unit read reruns that unit and the failed one; the opening line counts both before any unit starts" {
  rm -f "$TEST_ROOT/fail_a"
  printf 'more\n' >> src/c.txt && git commit -q -am "fix: c"
  fix_done_peek
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "t_a t_c " ] || { echo "ran: $(ran)"; false; }
  grep -qE '^run again: 2 of 4 units; ' "$PEEK.seen" || { echo "not said before the units ran; they saw:"; cat "$PEEK.seen"; echo "output:"; echo "$output"; false; }
  [[ "$output" == *"test files: 2 ran, 1 reused"* ]] || { echo "$output"; false; }
}

@test "R305: a change that touches no unit's read list reruns only the failed file" {
  rm -f "$TEST_ROOT/fail_a"
  printf 'notes\n' > NOTES.md && git add NOTES.md && git commit -q -m "docs: notes"
  fix_done_peek
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ran)" = "t_a " ] || { echo "ran: $(ran)"; false; }
  grep -qE '^run again: 1 of 4 units; top reasons: last result failed \(1\)$' "$PEEK.seen" || { echo "$output"; false; }
}
