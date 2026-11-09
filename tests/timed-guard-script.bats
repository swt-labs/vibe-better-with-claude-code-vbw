#!/usr/bin/env bats
# R273 (T251): the Bash guard's read of a script run by name costs in step with the
# script's size. Under a build lease whose protected list holds tests/c1.sh, a shell
# script in the field report's shape (thousands of echo lines, a write of the
# protected check file last) of 80 KB and of 264 KB is run by name, and the guard's
# CPU (user plus system, bash TIMEFORMAT) is the median of three runs after one
# warm-up run. The 264 KB script is answered within 5 s (5000 ms) of CPU on a nominal
# machine, and within 1.5 times the size ratio (264/80) times the 80 KB time. The
# 5 s budget is scaled as tools/bench-hooks.sh scales its own and as
# tests/timed-big-record.bats scales its own: the bench's reference workload is
# measured first (its two files written by the bench, VBW_BENCH_REFERENCE_FILES),
# NOMINAL_MS is read from the bench so it is defined once, VBW_BENCH_REFERENCE_MS
# stands in for the measure, a figure over the budget but within budget x ratio
# passes marked slow, and a machine whose jq startup alone is above the hook limit is
# reported busy and judged not at all. Both measures and their ratio are printed.
# A timed file: the release run only (tools/test.sh --release), never vbw prove.

load helper
load protected-helper
load fixture-helper

built_project() {
  vbw_setup
  protected_base
  protected_apply 2 '.plans[0].files = ["src/", "tests/"]'
  "$VBW" approve > /dev/null
  VBW_SESSION_ID=s1 "$VBW" run start build P1.1 > /dev/null
  mkdir -p .vbw/runtime/scratch
}

setup_file() {
  fixture_build built built_project
  reference
}
setup() { fixture_copy built; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

now_ms() { perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000'; }

# cpu CMD...: the user plus system CPU milliseconds of one run of CMD (stdout and
# stderr dropped), by the shell's own time keyword.
cpu() {
  local t
  # shellcheck disable=SC2030,SC2031
  t=$(TIMEFORMAT='%3U %3S'; { time "$@" > /dev/null 2>&1 < /dev/null; } 2>&1)
  perl -e 'printf "%.0f\n", ($ARGV[0] + $ARGV[1]) * 1000' -- ${t}
}

# median A B C: the middle value of three integers.
median() { printf '%s\n%s\n%s\n' "$1" "$2" "$3" | sort -n | sed -n 2p; }

# field_script FILE KB: a shell script of about KB kilobytes in the field report's shape
# (thousands of echo lines, a cd first and more spread through it, the last one back to the project folder) whose last command (a python3 here-doc, so that every earlier here-doc is read first) writes the protected check file.
field_script() {
  # Every 20th step is a cat here-doc, every 20th (offset 10) a python3 - <<PY here-doc, every
  # 7th a $(...) assignment, the rest echo lines: the mix is the same at every size.
  awk -v n="$(( $2 * 1024 / 45 ))" 'BEGIN {
    print "cd src && true"
    for (i = 1; i <= n; i++) {
      if (i % 250 == 0) printf "cd .. && cd src\n"
      if (i % 20 == 0) printf "cat > .vbw/runtime/scratch/note%d.txt <<EOF\nstep %06d: a note the build writes\nsecond line of the note\nEOF\n", i, i
      else if (i % 20 == 10) printf "python3 - <<PY\nprint(\"step %06d: a program the build runs\")\nPY\n", i
      else if (i % 7 == 0) printf "v%d=$(date +%%s) # step %06d: a value the build reads\n", i, i
      else printf "echo \"step %06d: the build prints a line here\"\n", i
    }
    printf "cd ..\npython3 - <<PY\nopen(\"tests/c1.sh\", \"w\").write(\"x\")\nPY\n" }' > "$1"
}

# guard_once INPUT: the Bash guard's answer for the call in the file INPUT, as Claude Code runs it.
guard_once() {
  PATH="$PATH" HOOK_PROJECT_DIR="$PROJECT" vbw_hook PreToolUse Bash < "$1"
}

# guard_ms KB: the median CPU ms of the guard on a KB-kilobyte script run by name.
guard_ms() {
  local f=".vbw/runtime/scratch/field$1.sh" a b c
  field_script "$PROJECT/$f" "$1"
  jq -nc --arg c "bash $f" --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "Bash",
      agent_id: "a1", agent_type: "vbw:dev", tool_input: {command: $c}}' > "$BATS_TEST_TMPDIR/in$1.json"
  guard_once "$BATS_TEST_TMPDIR/in$1.json" > "$BATS_TEST_TMPDIR/out$1.json" 2>&1 || true
  grep -q "writes tests/c1.sh" "$BATS_TEST_TMPDIR/out$1.json" || { echo "the guard did not refuse the $1 KB script's write by name:"; cat "$BATS_TEST_TMPDIR/out$1.json" >&2; return 1; }
  a=$(cpu guard_once "$BATS_TEST_TMPDIR/in$1.json"); b=$(cpu guard_once "$BATS_TEST_TMPDIR/in$1.json"); c=$(cpu guard_once "$BATS_TEST_TMPDIR/in$1.json")
  median "$a" "$b" "$c"
}

# reference: the bench's ratio for this machine, into $BATS_FILE_TMPDIR/ratio
# (the word ratio, the ratio, the measure, the nominal) or the word busy.
reference() {
  local bench="$BATS_TEST_DIRNAME/../tools/bench-hooks.sh" dir="$BATS_FILE_TMPDIR/reference" nominal startup total measured ratio
  nominal=$(sed -n 's/^NOMINAL_MS=//p' "$bench")
  [ -n "$nominal" ] || { echo "no NOMINAL_MS in tools/bench-hooks.sh"; return 1; }
  VBW_BENCH_REFERENCE_FILES="$dir" bash "$bench" > /dev/null
  [ -f "$dir/reference.jq" ] && [ -f "$dir/reference.json" ] || { echo "the bench wrote no reference files"; return 1; }
  startup=$(wall_n 20 jq -n empty)
  if perl -e 'exit($ARGV[0] > 20 ? 0 : 1)' -- "$startup"; then
    printf 'busy %s\n' "$startup" > "$BATS_FILE_TMPDIR/ratio"
    return 0
  fi
  total=$(wall_n 20 jq -nc --rawfile glance /dev/null --arg root "$dir" --arg dir "$dir" --arg open 0 \
    -f "$dir/reference.jq" - "$dir/reference.json" "$PLUGIN_ROOT/hooks/end.json")
  measured=$(perl -e 'printf "%.1f", $ARGV[0] - $ARGV[1]' -- "$total" "$startup")
  [ -z "${VBW_BENCH_REFERENCE_MS:-}" ] || measured="$VBW_BENCH_REFERENCE_MS"
  ratio=$(perl -e 'printf "%.2f", $ARGV[0] / $ARGV[1]' -- "$measured" "$nominal")
  printf 'ratio %s %s %s\n' "$ratio" "$measured" "$nominal" > "$BATS_FILE_TMPDIR/ratio"
}

# wall_n N CMD...: the mean wall milliseconds per call over N calls, one decimal.
wall_n() {
  local n=$1 a b
  shift
  a=$(now_ms)
  for _ in $(seq 1 "$n"); do "$@" > /dev/null 2>&1 < /dev/null; done
  b=$(now_ms)
  perl -e 'printf "%.1f\n", ($ARGV[0] - $ARGV[1]) / $ARGV[2]' -- "$b" "$a" "$n"
}

# judge LABEL MS BUDGET: pass within the budget; above it, pass marked slow when
# the ratio is above 1 and MS is within budget x ratio; else fail with OVER.
judge() {
  local kind ratio measured nominal scaled
  read -r kind ratio measured nominal < "$BATS_FILE_TMPDIR/ratio"
  echo "reference: $measured ms per call; nominal $nominal ms; ratio $ratio"
  if perl -e 'exit($ARGV[0] <= $ARGV[1] ? 0 : 1)' -- "$2" "$3"; then
    echo "$1: $2 ms CPU (budget $3 ms)"
    return 0
  fi
  scaled=$(perl -e 'printf "%.1f", $ARGV[0] * $ARGV[1]' -- "$3" "$ratio")
  if perl -e 'exit($ARGV[0] > 1 && $ARGV[1] <= $ARGV[2] ? 0 : 1)' -- "$ratio" "$2" "$scaled"; then
    echo "$1: $2 ms CPU: slow (ratio $ratio, scaled budget $scaled ms)"
    return 0
  fi
  echo "$1: $2 ms CPU: OVER (budget $3 ms, scaled $scaled ms)"
  return 1
}

@test "R273 timed: the guard on a 264 KB script takes at most 5 s of CPU and at most 1.5 times the size ratio of the 80 KB time" {
  local kind small big limit
  read -r kind _ < "$BATS_FILE_TMPDIR/ratio"
  [ "$kind" != busy ] || skip "the machine was busy: jq startup by the clock above the 20 ms hook limit"
  cd "$PROJECT" || return 1
  small=$(guard_ms 80)
  big=$(guard_ms 264)
  limit=$(perl -e 'printf "%.0f", 1.5 * (264 / 80) * $ARGV[0]' -- "$small")
  echo "80 KB: $small ms CPU; 264 KB: $big ms CPU; ratio $(perl -e 'printf "%.2f", $ARGV[0] / ($ARGV[1] || 1)' -- "$big" "$small") (limit 1.5 x 264/80 = 4.95, so $limit ms)"
  judge "the guard on a 264 KB script" "$big" 5000
  perl -e 'exit($ARGV[0] <= $ARGV[1] ? 0 : 1)' -- "$big" "$limit" || { echo "the 264 KB time grows faster than the size: $big ms against $limit ms"; false; }
}

# inline_ms KB: the median CPU ms of the guard on an inline command of about KB kilobytes (the
# field script's mix as the command itself, not a file run by name).
inline_ms() {
  local f=".vbw/runtime/scratch/inline$1.sh" a b c
  field_script "$PROJECT/$f" "$1"
  jq -nc --rawfile c "$PROJECT/$f" --arg d "$PROJECT" '{hook_event_name: "PreToolUse", session_id: "s1", cwd: $d, tool_name: "Bash",
      agent_id: "a1", agent_type: "vbw:dev", tool_input: {command: $c}}' > "$BATS_TEST_TMPDIR/inl$1.json"
  guard_once "$BATS_TEST_TMPDIR/inl$1.json" > "$BATS_TEST_TMPDIR/outl$1.json" 2>&1 || true
  grep -q "tests/c1.sh" "$BATS_TEST_TMPDIR/outl$1.json" || { echo "the guard did not refuse the $1 KB inline command's write:"; cat "$BATS_TEST_TMPDIR/outl$1.json" >&2; return 1; }
  a=$(cpu guard_once "$BATS_TEST_TMPDIR/inl$1.json"); b=$(cpu guard_once "$BATS_TEST_TMPDIR/inl$1.json"); c=$(cpu guard_once "$BATS_TEST_TMPDIR/inl$1.json")
  median "$a" "$b" "$c"
}

@test "R273 timed: the guard on a 66 KB inline command takes at most 5 s of CPU and at most 1.5 times the size ratio of the 20 KB time" {
  local kind small big limit
  read -r kind _ < "$BATS_FILE_TMPDIR/ratio"
  [ "$kind" != busy ] || skip "the machine was busy: jq startup by the clock above the 20 ms hook limit"
  cd "$PROJECT" || return 1
  small=$(inline_ms 20)
  big=$(inline_ms 66)
  limit=$(perl -e 'printf "%.0f", 1.5 * (66 / 20) * $ARGV[0]' -- "$small")
  echo "20 KB: $small ms CPU; 66 KB: $big ms CPU; ratio $(perl -e 'printf "%.2f", $ARGV[0] / ($ARGV[1] || 1)' -- "$big" "$small") (limit 1.5 x 66/20 = 4.95, so $limit ms)"
  judge "the guard on a 66 KB inline command" "$big" 5000
  perl -e 'exit($ARGV[0] <= $ARGV[1] ? 0 : 1)' -- "$big" "$limit" || { echo "the 66 KB time grows faster than the size: $big ms against $limit ms"; false; }
}
