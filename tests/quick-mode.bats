#!/usr/bin/env bats
# R111 (D179): VBW's own project has a quick test mode, bash tools/test.sh
# --quick, that runs shellcheck, the engineering rules (tests/standards*.bats, always,
# a check running some of their cases or not) and the core test files, but not the
# files approved checks already run and not the timing benchmarks;
# its spec names that mode as the project's quick command. --quick --list prints
# what the mode would run, one stage or test file per line, and runs nothing. L1.

load helper

# The script runs the whole suite when it does not know its arguments: never call it before it has a quick mode.
setup() {
  grep -q -- '--quick' "$REPO_ROOT/tools/test.sh" || { echo "tools/test.sh has no --quick mode yet"; return 1; }
}

# covered: the test files an approved check of this project runs or protects.
covered() {
  jq -r '[.checks[] | (.run[], (.files[]?))] | unique[] | select(test("^tests/[^/]+\\.bats$"))' "$REPO_ROOT/.vbw/record.json" | sort -u
}

@test "R111: tools/test.sh --quick --list names shellcheck and the engineering rules" {
  cd "$REPO_ROOT"
  run bash tools/test.sh --quick --list < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qi 'shellcheck'
  printf '%s\n' "$output" | grep -qx 'tests/standards.bats'
  printf '%s\n' "$output" | grep -qx 'tests/standards-selftest.bats'
}

@test "R111: the quick mode runs every test file no approved check runs, none that a check runs, and the engineering rules always" {
  cd "$REPO_ROOT"
  run bash tools/test.sh --quick --list < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local f
  while IFS= read -r f; do
    # The engineering rules are a stage of the quick mode (tools/test.sh quick_files), whether or not an approved check runs some of their cases (C570 filters R248 out of tests/standards.bats).
    case "$f" in tests/standards.bats|tests/standards-selftest.bats) continue ;; esac
    ! printf '%s\n' "$output" | grep -qx "$f" || { echo "$f is run by an approved check but is in the quick mode"; false; }
  done < <(covered)
  while IFS= read -r f; do
    case "$f" in tests/timed-*) continue ;; esac
    covered | grep -qx "$f" && continue
    printf '%s\n' "$output" | grep -qx "$f" || { echo "$f is not in the quick mode"; false; }
  done < <(ls tests/*.bats)
}

@test "R111: the quick mode leaves out the timing benchmarks" {
  cd "$REPO_ROOT"
  run bash tools/test.sh --quick --list < /dev/null
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -q '^tests/timed-' || { echo "a timed file is in the quick mode: $output"; false; }
  [[ "$output" != *bench-hooks.sh* && "$output" != *bench-panel.sh* ]] || { echo "$output"; false; }
}

@test "R111: tools/test.sh refuses other arguments with its usage line and runs nothing" {
  cd "$REPO_ROOT"
  local arg
  for arg in --list --bogus "--quick --bogus"; do
    # shellcheck disable=SC2086 # "--quick --bogus" is two arguments on purpose
    run bash tools/test.sh $arg < /dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage: tools/test.sh [--quick [--list]]"* ]] || { echo "$arg: $output"; false; }
  done
}

@test "R111: VBW's spec names the quick mode as its quick command, and the record carries it" {
  grep -qxF -- '- quick: bash tools/test.sh --quick' "$REPO_ROOT/.vbw/spec.md"
  jq -e '.commands.quick == ["bash","tools/test.sh","--quick"] and .commands.test == ["bash","tools/test.sh"]' "$REPO_ROOT/.vbw/record.json"
}
