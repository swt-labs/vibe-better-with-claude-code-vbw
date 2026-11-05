#!/usr/bin/env bats
# R249 (T229): kernel latency on the R149 large twin (a record over 2 MB,
# tests/big-record-helper.bash): vbw next --json, vbw status, vbw show roadmap and
# vbw triage --json each finish within 1.5 s, vbw todo add within 2.5 s. Budgets
# are the documented meaning on a nominal machine, scaled as tools/bench-hooks.sh
# scales its own: the bench's reference workload is measured here first (its two
# files written by the bench, VBW_BENCH_REFERENCE_FILES), NOMINAL_MS is read from
# the bench so it is defined once, VBW_BENCH_REFERENCE_MS stands in for the
# measure, a case over its budget but within budget x ratio passes marked slow,
# and a machine whose jq startup alone is above the hook limit is reported busy
# and judged not at all. Wall time (the kernel waits on git and jq), the median of
# three runs after one warm-up run that leaves the record's validation digest.
# A timed file: the release run only (tools/test.sh --release), never vbw prove.

load helper
load big-record-helper
load fixture-helper

setup_file() {
  fixture_build twins twin_fixture
  reference
}
setup() { twin_copy twins; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

now_ms() { perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000'; }

# wall CMD...: the wall milliseconds of one run of CMD (stdout and stderr dropped).
wall() {
  local a b
  a=$(now_ms)
  "$@" > /dev/null 2>&1 < /dev/null
  b=$(now_ms)
  echo $((b - a))
}

# median A B C: the middle value of three integers.
median() { printf '%s\n%s\n%s\n' "$1" "$2" "$3" | sort -n | sed -n 2p; }

# reference: the bench's ratio for this machine, into $BATS_FILE_TMPDIR/ratio
# (RATIO and SLOW as the bench defines them) or the word busy. The reference
# workload is one jq call of the guard's shape over the bench's own program and
# document, as the bench measures it; here by the clock, which only ever reads
# slower than the bench's CPU figure, so a busy machine scales the budgets up.
reference() {
  local bench="$BATS_TEST_DIRNAME/../tools/bench-hooks.sh" dir="$BATS_FILE_TMPDIR/reference" nominal startup total n measured ratio
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
    echo "$1: $2 ms (budget $3 ms)"
    return 0
  fi
  scaled=$(perl -e 'printf "%.1f", $ARGV[0] * $ARGV[1]' -- "$3" "$ratio")
  if perl -e 'exit($ARGV[0] > 1 && $ARGV[1] <= $ARGV[2] ? 0 : 1)' -- "$ratio" "$2" "$scaled"; then
    echo "$1: $2 ms: slow (ratio $ratio, scaled budget $scaled ms)"
    return 0
  fi
  echo "$1: $2 ms: OVER (budget $3 ms, scaled $scaled ms)"
  return 1
}

# timed BUDGET CMD...: warm up once in the large twin, then the median of three runs, judged.
timed() {
  local budget=$1 a b c
  shift
  cd "$BIG" || return 1
  "$VBW" "$@" > /dev/null 2>&1 < /dev/null || true
  a=$(wall "$VBW" "$@"); b=$(wall "$VBW" "$@"); c=$(wall "$VBW" "$@")
  judge "vbw $*" "$(median "$a" "$b" "$c")" "$budget"
}

@test "R249: vbw next --json on the large twin finishes within 1.5 s" {
  timed 1500 next --json
}

@test "R249: vbw status on the large twin finishes within 1.5 s" {
  timed 1500 status
}

@test "R249: vbw show roadmap on the large twin finishes within 1.5 s" {
  timed 1500 show roadmap
}

@test "R249: vbw triage --json on the large twin finishes within 1.5 s" {
  timed 1500 triage --json
}

@test "R249: vbw todo add on the large twin finishes within 2.5 s" {
  timed 2500 todo add "one more idea"
}
