#!/usr/bin/env bats
# R268 (T-big-milestone): vbw next --json on the big-milestone fixture (the field
# report's shape: 79 phases, 258 plans, 568 after-links, 47 interleaved phases,
# P1 to P40 built; tests/big-milestone-helper.bash) answers within 5 s (5000 ms)
# of CPU on a nominal machine. The figure is user plus system CPU of the command
# (bash TIMEFORMAT), the median of three runs after one warm-up run. The budget is
# scaled as tools/bench-hooks.sh scales its own and as tests/timed-big-record.bats
# scales its own: the bench's reference workload is measured first (its two files
# written by the bench, VBW_BENCH_REFERENCE_FILES), NOMINAL_MS is read from the
# bench so it is defined once, VBW_BENCH_REFERENCE_MS stands in for the measure,
# a figure over the budget but within budget x ratio passes marked slow, and a
# machine whose jq startup alone is above the hook limit is reported busy and
# judged not at all. The measured CPU is printed.
# Measured once on the author's machine (reference ratio 0.66): 3760 ms CPU, budget 5000 ms.
# A timed file: the release run only (tools/test.sh --release), never vbw prove.

load helper
load big-milestone-helper
load fixture-helper

setup_file() {
  fixture_build big big_milestone_fixture
  reference
}
setup() { fixture_copy big; }
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
  [ "$kind" != busy ] || skip "the machine was busy: jq startup $ratio ms by the clock, above the 20 ms hook limit"
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

@test "R268: vbw next --json on the big milestone takes at most 5 s of CPU" {
  local a b c
  cd "$PROJECT" || return 1
  "$VBW" next --json > /dev/null 2>&1 < /dev/null || true
  a=$(cpu "$VBW" next --json); b=$(cpu "$VBW" next --json); c=$(cpu "$VBW" next --json)
  judge "vbw next --json" "$(median "$a" "$b" "$c")" 5000
}
