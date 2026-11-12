#!/usr/bin/env bats
# R152 (docs/proof.md, CLAUDE.md testing): the timed speed checks run once per
# release, not in every vbw prove. bash tools/test.sh with no option (the test
# command vbw prove runs) runs neither benchmark and no timed test file; the
# release way, bash tools/test.sh --release, runs the lint, both benchmarks
# (tools/bench-hooks.sh, tools/bench-panel.sh), the suite in one parallel batch
# and then the timed test files (tests/timed-*.bats) alone; --quick and the CI
# shards keep working, the shards together making one release run. CI runs the
# release way. No test file of the default run measures a duration. L1: a copy
# of tools/test.sh runs in a scratch repository whose bats, shellcheck,
# parallel, node, getconf and benchmarks are stand-ins that log their calls;
# the repository's own files are read as text.

load helper

CI="$REPO_ROOT/.github/workflows/ci.yml"

setup() { vbw_setup; }
teardown() { vbw_teardown; }

# fake_repo: a scratch repository holding a copy of tools/test.sh, stand-in
# benchmarks, ordinary test files a, b, c and z, two timed ones and an empty
# record, with stand-in tools first on PATH that log every call to $LOG. A
# benchmark fails when FAIL names it; bats fails its batch (--jobs) or its
# timed call when FAIL is batch or timed.
fake_repo() {
  FAKE="$TEST_ROOT/fake repo"
  LOG="$TEST_ROOT/calls.log"
  STUBS="$TEST_ROOT/stubs"
  export FAKE LOG STUBS
  mkdir -p "$FAKE/tools" "$FAKE/tests" "$FAKE/.vbw" "$STUBS"
  cp "$REPO_ROOT/tools/test.sh" "$FAKE/tools/test.sh"
  local b f t
  for b in bench-hooks bench-panel; do
    printf '#!/usr/bin/env bash\necho %s >> "$LOG"\n[ "${FAIL:-}" != %s ]\n' "$b" "$b" > "$FAKE/tools/$b.sh"
  done
  for f in a b c z timed-speed timed-cost; do
    printf '#!/usr/bin/env bats\n@test "%s" { true; }\n' "$f" > "$FAKE/tests/$f.bats"
  done
  printf '{"schema": 4, "protected": [], "checks": []}\n' > "$FAKE/.vbw/record.json"
  for t in shellcheck parallel node; do
    printf '#!/usr/bin/env bash\n{ printf %%s %s; printf " %%s" "$@"; echo; } >> "$LOG"\n' "$t" > "$STUBS/$t"
  done
  cat > "$STUBS/bats" << 'SH'
#!/usr/bin/env bash
{ printf %s bats; printf " %s" "$@"; echo; } >> "$LOG"
case " $* " in
  *" --jobs "*) [ "${FAIL:-}" != batch ] ;;
  *) [ "${FAIL:-}" != timed ] ;;
esac
SH
  printf '#!/usr/bin/env bash\necho 8\n' > "$STUBS/getconf"
  chmod +x "$STUBS"/*
  : > "$LOG"
}

# fake_run ARGS...: run the copied script in the scratch repository; sets CODE.
fake_run() {
  : > "$LOG"
  CODE=0
  (cd "$FAKE" && PATH="$STUBS:$PATH" bash tools/test.sh "$@" < /dev/null) > "$TEST_ROOT/out" 2>&1 || CODE=$?
}

# bats_calls: the logged bats calls, one per line.
bats_calls() { grep '^bats ' "$LOG" || true; }

# files_of LINE: the test files a logged call names, sorted, one per line.
files_of() { printf '%s\n' "$1" | tr ' ' '\n' | grep -E '^tests/' | LC_ALL=C sort; }

PLAIN='tests/a.bats
tests/b.bats
tests/c.bats
tests/z.bats'
TIMED='tests/timed-cost.bats
tests/timed-speed.bats'

@test "R152: bash tools/test.sh with no option runs the lint and every test file except the timed ones, and neither benchmark" {
  fake_repo
  fake_run
  [ "$CODE" -eq 0 ] || {
    cat "$TEST_ROOT/out"
    false
  }
  ! grep -qE '^bench-(hooks|panel)$' "$LOG" || {
    echo "a benchmark ran:"
    cat "$LOG"
    false
  }
  grep -q '^shellcheck ' "$LOG" || {
    echo "no lint:"
    cat "$LOG"
    false
  }
  [ "$(bats_calls | grep -c .)" -eq 1 ] || {
    cat "$LOG"
    false
  }
  [ "$(files_of "$(bats_calls)")" = "$PLAIN" ] || {
    echo "the default run ran other files than the untimed ones:"
    cat "$LOG"
    false
  }
  bats_calls | grep -qe '--jobs 4' || {
    cat "$LOG"
    false
  }
}

@test "R152: bash tools/test.sh --release runs the lint, both benchmarks, the suite in one parallel batch, then the timed files alone" {
  fake_repo
  fake_run --release
  [ "$CODE" -eq 0 ] || {
    cat "$TEST_ROOT/out"
    false
  }
  grep -q '^shellcheck ' "$LOG" && grep -qx 'bench-hooks' "$LOG" && grep -qx 'bench-panel' "$LOG" || {
    echo "the lint or a benchmark did not run:"
    cat "$LOG"
    false
  }
  local calls batch timed
  calls=$(bats_calls)
  [ "$(printf '%s\n' "$calls" | grep -c .)" -eq 2 ] || {
    cat "$LOG"
    false
  }
  batch=$(printf '%s\n' "$calls" | sed -n 1p)
  timed=$(printf '%s\n' "$calls" | sed -n 2p)
  [[ "$batch" == *"--jobs 4"* ]] && [ "$(files_of "$batch")" = "$PLAIN" ] || {
    echo "the parallel batch is not the untimed files: $batch"
    false
  }
  [[ "$timed" != *"--jobs"* ]] && [ "$(files_of "$timed")" = "$TIMED" ] || {
    echo "the last call is not the timed files alone: $timed"
    false
  }
}

@test "R152: the release run fails when a benchmark, the batch or a timed file fails" {
  fake_repo
  fake_run --release
  [ "$CODE" -eq 0 ] || {
    cat "$TEST_ROOT/out"
    false
  }
  local what
  for what in bench-hooks bench-panel batch timed; do
    FAIL=$what fake_run --release
    [ "$CODE" -ne 0 ] || {
      echo "--release passed with a failing $what"
      cat "$LOG"
      false
    }
  done
}

@test "R152: --quick still runs without the benchmarks and without any timed file" {
  fake_repo
  fake_run --quick
  [ "$CODE" -eq 0 ] || {
    cat "$TEST_ROOT/out"
    false
  }
  ! grep -qE '^bench-(hooks|panel)$|tests/timed-' "$LOG" || {
    cat "$LOG"
    false
  }
  [ "$(files_of "$(bats_calls)")" = "$PLAIN" ] || {
    cat "$LOG"
    false
  }
  cd "$REPO_ROOT"
  run bash tools/test.sh --quick --list < /dev/null
  [ "$status" -eq 0 ] || {
    echo "$output"
    false
  }
  ! printf '%s\n' "$output" | grep -qE 'tests/timed-|bench-(hooks|panel)\.sh' || {
    echo "$output"
    false
  }
}

@test "R152: the CI shards together make one release run: shard 1 runs both benchmarks, each shard runs its timed files alone after its batch" {
  fake_repo
  local k calls last all_timed="" all=""
  for k in 1 2; do
    fake_run --shard "$k/2"
    [ "$CODE" -eq 0 ] || {
      cat "$TEST_ROOT/out"
      false
    }
    if [ "$k" -eq 1 ]; then
      grep -qx 'bench-hooks' "$LOG" && grep -qx 'bench-panel' "$LOG" || {
        cat "$LOG"
        false
      }
    else
      ! grep -qE '^bench-(hooks|panel)$' "$LOG" || {
        cat "$LOG"
        false
      }
    fi
    calls=$(bats_calls)
    last=$(printf '%s\n' "$calls" | tail -n 1)
    if printf '%s\n' "$calls" | grep -q 'tests/timed-'; then
      [[ "$last" != *"--jobs"* ]] && ! files_of "$last" | grep -qv 'tests/timed-' || {
        echo "shard $k does not run its timed files alone, last:"
        cat "$LOG"
        false
      }
      ! printf '%s\n' "$calls" | grep -e '--jobs' | grep -q 'tests/timed-' || {
        echo "shard $k runs a timed file in its parallel batch"
        cat "$LOG"
        false
      }
      all_timed="$all_timed$(files_of "$last")"$'\n'
    fi
    all="$all$(files_of "$(printf '%s\n' "$calls" | tr '\n' ' ')")"$'\n'
  done
  [ "$(printf '%s' "$all_timed" | grep . | LC_ALL=C sort)" = "$TIMED" ] || {
    echo "the shards ran these timed files: $all_timed"
    false
  }
  [ "$(printf '%s' "$all" | grep . | LC_ALL=C sort)" = "$(printf '%s\n%s\n' "$PLAIN" "$TIMED" | LC_ALL=C sort)" ] || {
    echo "the shards together ran: $all"
    false
  }
}

@test "R152: tools/test.sh refuses --release with other arguments, naming the release way in its usage line, and runs nothing" {
  fake_repo
  local arg
  for arg in "--release --bogus" "--bogus --release" "--quick --release" "--release --quick"; do
    # shellcheck disable=SC2086 # each arg string is several arguments on purpose
    fake_run $arg
    [ "$CODE" -eq 2 ] || {
      echo "$arg: exit $CODE"
      false
    }
    grep -q 'usage: tools/test.sh.*--release' "$TEST_ROOT/out" || {
      echo "$arg: $(cat "$TEST_ROOT/out")"
      false
    }
    [ ! -s "$LOG" ] || {
      echo "$arg ran: $(cat "$LOG")"
      false
    }
  done
}

@test "R152: CI runs the release way: every job runs its shard of the release run" {
  grep -qF 'bash tools/test.sh --shard "$SHARD/$SHARDS"' "$CI"
  ! grep -nE 'bash tools/test\.sh *($|;|&|\|| fi)' "$CI" || {
    echo "ci.yml still runs tools/test.sh without the release way"
    false
  }
}

# has_clock FILE: whether a line of FILE that is not a comment reads a clock: bash's
# SECONDS, the wall clock in seconds or finer (date +%s, %N, gdate), or a high-resolution
# timer (Time::HiRes, EPOCHREALTIME, Python's time.time and perf_counter,
# Node's hrtime, Date.now and performance.now). Moving the shell's clock forward
# (SECONDS=$((SECONDS + N)), a test's injected clock in place of a sleep) reads none.
has_clock() {
  [ "$(grep -vE '^[[:space:]]*#' "$1" | sed -E 's/SECONDS=\$\(\(SECONDS \+ [0-9]+\)\)//g' | grep -cE '(^|[^A-Za-z_])(SECONDS|EPOCHREALTIME)|date .*%[sN]|gdate|Time::HiRes|time\.time|perf_counter|hrtime|Date\.now|performance\.now')" -gt 0 ]
}

@test "R152: the clock rule sees every kind of timer a test file could read, and passes comments and plain words" {
  printf 'x=$SECONDS\n' > "$TEST_ROOT/a"
  printf 't=$(date +%%s)\n' > "$TEST_ROOT/b"
  printf 'n=$(date +%%s%%N)\n' > "$TEST_ROOT/c"
  printf 'n=$(gdate +%%N)\n' > "$TEST_ROOT/d"
  printf "now() { perl -MTime::HiRes=time -e 'print time'; }\n" > "$TEST_ROOT/e"
  printf 't=$EPOCHREALTIME\n' > "$TEST_ROOT/f"
  printf 'SECONDS=$((SECONDS + 1)); t=$SECONDS\n' > "$TEST_ROOT/g"
  printf "t=\$(python3 -c 'import time; print(time.perf_counter())')\n" > "$TEST_ROOT/h"
  local f
  for f in a b c d e f g h; do
    has_clock "$TEST_ROOT/$f" || {
      echo "not seen: $(cat "$TEST_ROOT/$f")"
      false
    }
  done
  printf '# a comment about SECONDS and Time::HiRes\nsecs=2\nsleep "$secs"\nnow=$(date +%%Y)\nstamp=$(jq -n "now | todate")\nsleep() { SECONDS=$((SECONDS + 1)); }\n' > "$TEST_ROOT/ok"
  ! has_clock "$TEST_ROOT/ok" || {
    echo "a comment or a plain word was taken for a clock"
    false
  }
}

@test "R152: no test file of the default run measures a duration; the timed tests live in tests/timed-*.bats" {
  cd "$REPO_ROOT"
  local f bad=""
  for f in tests/*.bats; do
    case "$f" in tests/timed-* | tests/release-run.bats) continue ;; esac
    # Two files read a high-resolution clock only to put the starts and ends of checks in
    # order (no limit is judged on a duration): the overlap of checks that must not overlap.
    case "$f" in tests/check-alone-runner.bats | tests/fix-many.bats) ;; *)
      if has_clock "$f"; then bad="$bad $f(clock)"; fi ;;
    esac
    # A speed benchmark judged at its real limit: every run of one sets the
    # limit on the same line. tests/bench-limits.bats checks the limit logic
    # itself, with 100 ms of extra work against 20 ms.
    [ "$f" != tests/bench-limits.bats ] || continue
    grep -qE 'tools/bench-(hooks|panel)\.sh' "$f" || continue
    if grep -E 'bash +"?\$(BENCH|\{?REPO_ROOT\}?/tools/bench-|BATS_TEST_DIRNAME/\.\./tools/bench-)' "$f" \
      | grep -qv '_BUDGET_MS='; then bad="$bad $f(benchmark)"; fi
  done
  [ -z "$bad" ] || {
    echo "default-run test files that measure a duration:$bad"
    false
  }
  ls tests/timed-*.bats > /dev/null 2>&1 || {
    echo "no tests/timed-*.bats"
    false
  }
  grep -l '24 checks' tests/timed-*.bats > /dev/null || {
    echo "the 24-check proof time is not a timed test"
    false
  }
  grep -l '50,000 files' tests/timed-*.bats > /dev/null || {
    echo "the 50,000-file scan time is not a timed test"
    false
  }
}

# R303 (T283): a failed hook or panel benchmark never stops the rest of a run: the lint and
# every test file still run, then the run fails, its last lines naming each failed benchmark
# ('hook bench' for tools/bench-hooks.sh, 'panel bench' for tools/bench-panel.sh).

# ran_all: the lint and both benchmarks ran, and bats ran the untimed files in one batch and the timed files alone.
ran_all() {
  grep -q '^shellcheck ' "$LOG" && grep -qx 'bench-hooks' "$LOG" && grep -qx 'bench-panel' "$LOG" || {
    echo "the lint or a benchmark did not run:"
    cat "$LOG"
    return 1
  }
  local calls
  calls=$(bats_calls)
  printf '%s\n' "$calls" | grep -e '--jobs' | grep -q 'tests/a.bats' || {
    echo "the parallel batch did not run:"
    cat "$LOG"
    return 1
  }
  [ "$(files_of "$(printf '%s\n' "$calls" | tail -n 1)")" = "$TIMED" ] || {
    echo "the timed files did not run alone, last:"
    cat "$LOG"
    return 1
  }
}

# names_failed WORDS...: the run failed and its last 3 lines name each failed benchmark.
names_failed() {
  local tail w
  [ "$CODE" -ne 0 ] || {
    echo "the run passed with a failed benchmark"
    cat "$TEST_ROOT/out"
    return 1
  }
  tail=$(tail -n 3 "$TEST_ROOT/out")
  for w in "$@"; do
    [[ "$tail" == *"$w"* ]] || {
      echo "the last lines do not name the $w:"
      cat "$TEST_ROOT/out"
      return 1
    }
  done
}

@test "R303: in CI shard 1 a failed hook bench stops nothing: the panel bench, the lint and every test file run, then the shard fails naming the hook bench" {
  fake_repo
  FAIL=bench-hooks fake_run --shard 1/1
  ran_all
  names_failed 'hook bench'
  ! tail -n 3 "$TEST_ROOT/out" | grep -q 'panel bench' || {
    echo "the panel bench passed but is named as failed:"
    cat "$TEST_ROOT/out"
    false
  }
}

@test "R303: in CI shard 1 a failed panel bench stops nothing either, and the shard fails naming it" {
  fake_repo
  FAIL=bench-panel fake_run --shard 1/1
  ran_all
  names_failed 'panel bench'
}

@test "R303: the non-shard release run runs every test file after a failed benchmark, then fails naming it" {
  fake_repo
  FAIL=bench-hooks fake_run --release
  ran_all
  names_failed 'hook bench'
}

@test "R303: a failed benchmark and a failed batch: the run fails and still names the benchmark" {
  fake_repo
  printf '#!/usr/bin/env bash\n{ printf %%s bats; printf " %%s" "$@"; echo; } >> "$LOG"\nexit 1\n' > "$STUBS/bats"
  chmod +x "$STUBS/bats"
  FAIL=bench-hooks fake_run --shard 1/1
  grep -qx 'bench-panel' "$LOG" && bats_calls | grep -q 'tests/a.bats' || {
    echo "the run stopped at the benchmark:"
    cat "$LOG"
    false
  }
  names_failed 'hook bench'
}

@test "R303: with every benchmark passing the shard and the release run exit 0 and name no failed benchmark; with only a test file failing, the run fails and names none" {
  fake_repo
  local how
  for how in '--shard 1/1' '--release'; do
    # shellcheck disable=SC2086 # two words on purpose
    fake_run $how
    [ "$CODE" -eq 0 ] || {
      echo "$how failed with nothing failing:"
      cat "$TEST_ROOT/out"
      false
    }
    ! grep -qE 'hook bench|panel bench' "$TEST_ROOT/out" || {
      echo "$how names a failed benchmark with none failing:"
      cat "$TEST_ROOT/out"
      false
    }
    # shellcheck disable=SC2086 # two words on purpose
    FAIL=batch fake_run $how
    [ "$CODE" -ne 0 ] && ! grep -qE 'hook bench|panel bench' "$TEST_ROOT/out" || {
      echo "$how with a failing test file:"
      cat "$TEST_ROOT/out"
      false
    }
  done
}
