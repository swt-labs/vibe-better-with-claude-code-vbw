#!/usr/bin/env bats
# R143 (L1): tools/ci-scope.sh BASE HEAD sorts what a push or pull request
# changed into what CI must run. It reads the git repository of the current
# folder and prints three lines for GitHub's step outputs:
#   scope=full|some|none
#   files=<the test files to run, space-separated, only for some>
#   reason=<why, in words>
# The changed files are those that differ between BASE and HEAD (every commit
# of the push); a renamed file counts under its new path, and its old path is
# sorted too. Safe paths: tests/*.bats files (run them, unless deleted), the VBW
# record (.vbw/record.json, .vbw/spec.md) and the saved test results folders
# that the record's project.results names at both BASE and HEAD (D195; CI
# guesses no folder). Any other path, an unknown one included, means the full
# suite, as does an unknown BASE (empty, all zeros, not in the repository, or
# not an ancestor of HEAD: a new branch, a rewritten history, a shallow clone).

load helper

SCRIPT="$REPO_ROOT/tools/ci-scope.sh"

setup() {
  vbw_setup
  [ -f "$SCRIPT" ] || {
    echo "tools/ci-scope.sh does not exist yet"
    return 1
  }
  git init -q
  mkdir -p plugin/lib docs tools/l3-results tools/baseline/results tests/fixtures tests/helpers .vbw .github/workflows
  printf 'x\n' > plugin/lib/core.sh
  printf 'x\n' > docs/guide.md
  printf 'x\n' > README.md
  printf 'x\n' > tools/test.sh
  printf 'x\n' > tools/l3-results/run1.json
  printf 'x\n' > tools/baseline/results/run1.json
  printf 'x\n' > tests/a.bats
  printf 'x\n' > tests/b.bats
  printf 'x\n' > tests/helper.bash
  printf 'x\n' > tests/fixtures/rec.json
  printf 'x\n' > tests/helpers/run.js
  printf 'x\n' > .github/workflows/ci.yml
  printf '# spec\n' > .vbw/spec.md
  printf '{"project": {"name": "t", "results": ["tools/l3-results/", "tools/baseline/results/"]}}\n' > .vbw/record.json
  git add -A
  git commit -q -m "chore(test): seed"
  BASE=$(git rev-parse HEAD)
  export BASE
}

teardown() { vbw_teardown; }

# change PATH...: append a line to each PATH (creating it) and commit.
change() {
  local p
  for p in "$@"; do
    mkdir -p "$(dirname "$p")"
    printf 'more\n' >> "$p"
  done
  git add -A
  git commit -q -m "chore(test): change"
}

# decide [BASE [HEAD]]: run the script; sets status, output (stdout), SCOPE, FILES, REASON.
decide() {
  local base=${1-$BASE} head=${2-$(git rev-parse HEAD)}
  run bash "$SCRIPT" "$base" "$head" < /dev/null
  SCOPE=$(printf '%s\n' "$output" | sed -n 's/^scope=//p')
  FILES=$(printf '%s\n' "$output" | sed -n 's/^files=//p')
  REASON=$(printf '%s\n' "$output" | sed -n 's/^reason=//p')
}

# expect SCOPE [FILES]: the decision is SCOPE (and the files FILES), with a reason.
expect() {
  [ "$status" -eq 0 ] || {
    echo "exit $status: $output"
    return 1
  }
  [ "$SCOPE" = "$1" ] || {
    echo "expected $1: $output"
    return 1
  }
  [ "$FILES" = "${2-}" ] || {
    echo "expected files '${2-}': $output"
    return 1
  }
  [ -n "$REASON" ] || {
    echo "no reason: $output"
    return 1
  }
}

@test "R143: a changed plugin file means the full suite" {
  change plugin/lib/core.sh
  decide
  expect full
}

@test "R143: a changed docs file or root document means the full suite" {
  change docs/guide.md
  decide
  expect full
  BASE=$(git rev-parse HEAD)
  change README.md
  decide
  expect full
}

@test "R143: a changed tools file means the full suite" {
  change tools/test.sh
  decide
  expect full
}

@test "R143: a change to the CI setup itself means the full suite" {
  change .github/workflows/ci.yml
  decide
  expect full
}

@test "R143: a push of only saved test results runs no tests" {
  change tools/l3-results/run2.json tools/baseline/results/run1.json
  decide
  expect none
}

@test "R143: a push of only the VBW record and spec runs no tests" {
  change .vbw/record.json .vbw/spec.md
  decide
  expect none
}

@test "R143: a push of only test files runs just those files" {
  change tests/b.bats tests/c.bats
  decide
  expect some "tests/b.bats tests/c.bats"
}

@test "R143: the record plus a test file runs just that test file" {
  change .vbw/record.json tests/a.bats tools/l3-results/run3.json
  decide
  expect some "tests/a.bats"
}

@test "R143: a changed test helper, helpers file or fixture means the full suite" {
  local p
  for p in tests/helper.bash tests/helpers/run.js tests/fixtures/rec.json; do
    BASE=$(git rev-parse HEAD)
    change "$p" tests/a.bats
    decide
    expect full || {
      echo "after changing $p"
      false
    }
  done
}

@test "R143: an unknown path means the full suite" {
  local p
  for p in notes.txt .vbw/map.md tests/sub/x.bats "tests/with space.bats" tools/l3-results.json; do
    BASE=$(git rev-parse HEAD)
    change "$p"
    decide
    expect full || {
      echo "after changing $p"
      false
    }
  done
}

@test "R143: a test file deleted by the push is not run" {
  git rm -q tests/b.bats
  git commit -q -m "chore(test): drop b"
  printf 'more\n' >> tests/a.bats
  git commit -q -am "chore(test): change a"
  decide
  expect some "tests/a.bats"
}

@test "R143: a push that only deletes a test file runs no tests" {
  git rm -q tests/b.bats
  git commit -q -m "chore(test): drop b"
  decide
  expect none
}

@test "R143: a renamed test file runs under its new path; a file moved out of plugin/ still means the full suite" {
  git mv tests/b.bats tests/renamed.bats
  git commit -q -m "chore(test): rename"
  decide
  expect some "tests/renamed.bats"
  BASE=$(git rev-parse HEAD)
  git mv plugin/lib/core.sh tests/moved.bats
  git commit -q -m "chore(test): move"
  decide
  expect full
}

@test "R143: every commit of the push counts, not only the last one" {
  change plugin/lib/core.sh
  change tests/a.bats
  decide
  expect full
}

@test "R143: an unknown previous tip means the full suite: empty, all zeros, missing, or rewritten history" {
  change tests/a.bats
  local head
  head=$(git rev-parse HEAD)
  decide "" "$head"
  expect full
  decide 0000000000000000000000000000000000000000 "$head"
  expect full
  decide 1234567890abcdef1234567890abcdef12345678 "$head"
  expect full
  # A force push: the old tip is not an ancestor of the new one.
  git checkout -q -b other "$BASE"
  change tests/b.bats
  local old
  old=$(git rev-parse HEAD)
  decide "$old" "$head"
  expect full
}

@test "R143: results folders count only when the record names them before and after the push" {
  # A push that names a new results folder cannot use it to skip its own files.
  printf '{"project": {"name": "t", "results": ["tools/l3-results/", "tools/baseline/results/", "plugin/"]}}\n' > .vbw/record.json
  change plugin/lib/core.sh
  decide
  expect full
  # A project that names no results folders gets no saving: CI guesses none.
  BASE=$(git rev-parse HEAD)
  printf '{"project": {"name": "t"}}\n' > .vbw/record.json
  git commit -q -am "chore(test): no results"
  BASE=$(git rev-parse HEAD)
  change tools/l3-results/run1.json
  decide
  expect full
}

@test "R143: the wrong number of arguments exits 2 with a usage line" {
  run bash "$SCRIPT" < /dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *usage* ]]
  run bash "$SCRIPT" a b c < /dev/null
  [ "$status" -eq 2 ]
}

@test "R143: this repository's record names its saved results folders, tools/l3-results/ and tools/baseline/results/" {
  jq -e '(.project.results // []) as $r | ($r | index("tools/l3-results/")) and ($r | index("tools/baseline/results/"))' "$REPO_ROOT/.vbw/record.json" > /dev/null || {
    echo "the spec's Test results section does not name both folders"
    false
  }
}
