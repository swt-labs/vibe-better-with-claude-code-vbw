#!/usr/bin/env bats
# R164 (CLAUDE.md testing, docs/proof.md): bash tools/test.sh
# --release reuses the last proof (recorded in .vbw/record.json) when it passed
# on code that differs from the working tree only in the version files (those
# tools/bump-version.sh writes, listed by its --files) and plugin/CHANGELOG.md
# (T115): it then runs only the timed speed checks
# and the benchmarks, and prints which proof it reused. When any other file
# differs (uncommitted changes included), when there is no passing proof, or
# when the last proof failed, it runs everything and prints why. Which proofs
# count is tests/release-reuse-partial.bats (R170). Failing timed checks or
# benchmarks still fail the run, and the CI shards behave as before. L1: the
# fixture of tests/release-reuse-helper.bash.

load helper
load release-reuse-helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

@test "R164: with only the version files and the changelog changed since a passing proof, the release run reuses it" {
  fake_repo
  bump
  fake_run --release
  reused
}

@test "R164: the same holds when the version change is committed" {
  fake_repo
  bump
  (cd "$FAKE" && git add -A && git commit -q -m "chore(release): 1.0.1")
  fake_run --release
  reused
}

@test "R164: any other changed file, committed or not, runs everything and says why" {
  fake_repo
  bump
  printf '# Fake, changed\n' > "$FAKE/README.md"
  fake_run --release
  [ "$CODE" -eq 0 ] || { echo "$OUT"; false; }
  everything
  [[ "$OUT" == *"README.md"* ]] || { echo "the reason does not name README.md: $OUT"; false; }
  (cd "$FAKE" && git add -A && git commit -q -m "docs: readme")
  fake_run --release
  everything
  [[ "$OUT" == *"README.md"* ]] || { echo "the reason does not name README.md: $OUT"; false; }
}

@test "R164: a new untracked file runs everything and says why" {
  fake_repo
  printf 'new\n' > "$FAKE/src/new.txt"
  fake_run --release
  everything
  [[ "$OUT" == *"src/new.txt"* ]] || { echo "the reason does not name src/new.txt: $OUT"; false; }
}

@test "R164: with no proof recorded, the release run runs everything and says why" {
  fake_repo
  jq 'del(.evidence)' "$FAKE/.vbw/record.json" > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" "$FAKE/.vbw/record.json"
  bump
  fake_run --release
  [ "$CODE" -eq 0 ] || { echo "$OUT"; false; }
  everything
  [[ "$OUT" == *"proof"* ]] || { echo "no reason given: $OUT"; false; }
}

@test "R164: when the last proof failed, the release run runs everything and says why" {
  fake_repo
  prove_with '{full: true, passed: false, test_run: {status: "fail", exit: 1, seconds: 900, tail: "not ok"}, commands: {test: {status: "fail", exit: 1, seconds: 900, tail: "not ok"}}}'
  bump
  fake_run --release
  everything
  [[ "$OUT" == *"fail"* ]] || { echo "the reason does not say the proof failed: $OUT"; false; }
}

@test "R164: when the proof is reused, a failing benchmark or timed check still fails the run" {
  fake_repo
  bump
  FAIL=bench-hooks fake_run --release
  [ "$CODE" -ne 0 ] || { cat "$LOG"; false; }
  FAIL=bench-panel fake_run --release
  [ "$CODE" -ne 0 ] || { cat "$LOG"; false; }
  FAIL=timed fake_run --release
  [ "$CODE" -ne 0 ] || { cat "$LOG"; false; }
}

@test "R164: the CI shards run their whole share whatever proof is recorded" {
  fake_repo
  bump
  fake_run --shard 1/1
  [ "$CODE" -eq 0 ] || { echo "$OUT"; false; }
  everything
}

# bump_copy: a scratch copy of the bump tool and the files it writes, in $BUMP.
bump_copy() {
  BUMP="$TEST_ROOT/bump copy"
  mkdir -p "$BUMP/tools" "$BUMP/plugin/.claude-plugin" "$BUMP/.claude-plugin"
  cp "$REPO_ROOT/tools/bump-version.sh" "$BUMP/tools/"
  cp "$REPO_ROOT/VERSION" "$BUMP/VERSION"
  cp "$REPO_ROOT/plugin/VERSION" "$BUMP/plugin/VERSION"
  cp "$REPO_ROOT/plugin/.claude-plugin/plugin.json" "$BUMP/plugin/.claude-plugin/"
  cp "$REPO_ROOT/.claude-plugin/marketplace.json" "$BUMP/.claude-plugin/"
  cp "$REPO_ROOT/marketplace.json" "$BUMP/"
}

@test "R164: bump-version.sh --help prints its usage and changes nothing; an unknown flag is refused with the usage and changes nothing" {
  bump_copy
  local before arg
  before=$(cat "$BUMP/VERSION" "$BUMP/plugin/VERSION" "$BUMP/plugin/.claude-plugin/plugin.json" "$BUMP/.claude-plugin/marketplace.json" "$BUMP/marketplace.json")
  for arg in --help -h; do
    run bash "$BUMP/tools/bump-version.sh" "$arg"
    [ "$status" -eq 0 ] || { echo "$arg: exit $status: $output"; false; }
    [[ "$output" == *"usage: tools/bump-version.sh"* && "$output" == *"--offline"* && "$output" == *"--set X.Y.Z"* ]] || { echo "$arg: $output"; false; }
  done
  for arg in --bogus -x frobnicate; do
    run bash "$BUMP/tools/bump-version.sh" "$arg"
    [ "$status" -eq 2 ] || { echo "$arg: exit $status: $output"; false; }
    [[ "$output" == *"usage: tools/bump-version.sh"* ]] || { echo "$arg: $output"; false; }
  done
  [ "$before" = "$(cat "$BUMP/VERSION" "$BUMP/plugin/VERSION" "$BUMP/plugin/.claude-plugin/plugin.json" "$BUMP/.claude-plugin/marketplace.json" "$BUMP/marketplace.json")" ] || {
    echo "a version file changed"
    false
  }
}

# R303 (T283): when the proof is reused, a failed benchmark still leaves the timed tests to run;
# the run then fails, its last lines naming the failed benchmark.
@test "R303: a release run that reuses the proof runs the timed tests after a failed hook bench, then fails naming it" {
  fake_repo
  bump
  FAIL=bench-hooks fake_run --release
  [ "$CODE" -ne 0 ] || { echo "$OUT"; false; }
  grep -qx 'bench-panel' "$LOG" && bats_calls | grep -q 'tests/timed-speed.bats' || { echo "the run stopped at the benchmark:"; cat "$LOG"; false; }
  [[ "$(tail -n 3 "$TEST_ROOT/out")" == *"hook bench"* ]] || { echo "the last lines do not name the hook bench: $OUT"; false; }
}
