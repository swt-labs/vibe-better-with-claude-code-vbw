#!/usr/bin/env bats
# R143 (L1): every entry of CI's Tests job asks tools/ci-scope.sh what the push
# or pull request can affect, prints the answer in the run log, and then runs
# the full suite, just the changed test files, or nothing. The job itself always
# runs (no job-level condition), so a job that runs no tests still reports
# success, not skipped. The workflow file is read as text: no YAML parser is a
# VBW dependency. The real proof is a CI run on GitHub after the owner pushes
# (L4); this file proves only what the file says.

load helper

CI="$REPO_ROOT/.github/workflows/ci.yml"

# job NAME: the lines of one job of ci.yml, from "  NAME:" to the next job.
job() {
  awk -v j="  $1:" '
    $0 == j { on = 1; print; next }
    on && /^  [A-Za-z_-]+:/ { exit }
    on { print }
  ' "$CI"
}

# step PATTERN: the lines of the first Tests step whose text matches PATTERN (ERE).
step() {
  job test | P="$1" awk '
    /^      - / { if (!done && s != "" && s ~ ENVIRON["P"]) { printf "%s", s; done = 1 } s = ""; on = 1 }
    on { s = s $0 "\n" }
    END { if (!done && s ~ ENVIRON["P"]) printf "%s", s }
  '
}

# line_of PATTERN: the line number in the Tests job of the first line matching PATTERN.
line_of() {
  job test | grep -nE -e "$1" | head -n 1 | cut -d: -f1
}

@test "R143: the Tests job checks out the whole history, so the previous tip can be compared" {
  step 'actions/checkout@' | grep -qE 'fetch-depth: *0$' || {
    step 'actions/checkout@'
    false
  }
}

@test "R143: a scope step runs tools/ci-scope.sh with the push's old and new tips, or the pull request's base and head" {
  local s
  s=$(step 'tools/ci-scope\.sh')
  [ -n "$s" ] || {
    echo "no step runs tools/ci-scope.sh"
    false
  }
  printf '%s' "$s" | grep -qE '^        id: scope$'
  printf '%s' "$s" | grep -q 'github.event.before'
  printf '%s' "$s" | grep -q 'github.event.pull_request.base.sha'
  printf '%s' "$s" | grep -q 'github.event.pull_request.head.sha'
  printf '%s' "$s" | grep -q 'GITHUB_OUTPUT'
}

@test "R143: the choice and its reason are printed in the run log" {
  # The scope step's answer goes to the log and to the step outputs at once.
  step 'tools/ci-scope\.sh' | grep -qE 'tee -a "?\$GITHUB_OUTPUT"?' || {
    step 'tools/ci-scope\.sh'
    false
  }
}

@test "R143: the scope is decided after the tools are installed and before any test runs" {
  local install scope full
  install=$(line_of '- name: Install test tools')
  scope=$(line_of 'tools/ci-scope\.sh')
  full=$(line_of 'bash tools/test\.sh')
  [ -n "$install" ] && [ -n "$scope" ] && [ -n "$full" ]
  [ "$install" -lt "$scope" ] && [ "$scope" -lt "$full" ] || {
    echo "install $install, scope $scope, suite $full"
    false
  }
}

@test "R143: the full suite runs unless the scope says some or none, so a missing answer still runs everything" {
  local s
  s=$(step 'bash tools/test\.sh')
  printf '%s' "$s" | grep -qE "^        if: .*steps\\.scope\\.outputs\\.scope != 'some'" &&
    printf '%s' "$s" | grep -qE "^        if: .*steps\\.scope\\.outputs\\.scope != 'none'" || {
    printf '%s' "$s"
    false
  }
}

@test "R143: the scope step fails the job if tools/ci-scope.sh fails, even through the pipe to the log" {
  step 'tools/ci-scope\.sh' | grep -qE '^        shell: bash$|set -o pipefail' || {
    step 'tools/ci-scope\.sh'
    false
  }
}

@test "R143: the changed test files run with bats under the target bash when the scope is some, the list passed through env" {
  local s
  s=$(step "steps\\.scope\\.outputs\\.scope == 'some'")
  [ -n "$s" ] || {
    echo "no step runs for scope some"
    false
  }
  printf '%s' "$s" | grep -qE '^ +[A-Z_]+: *\$\{\{ *steps\.scope\.outputs\.files *\}\}' || {
    echo "the file list does not reach the step through env"
    false
  }
  printf '%s' "$s" | grep -qF 'export PATH="${{ matrix.bash_path }}:$PATH"'
  printf '%s' "$s" | grep -qE '(^| )bats '
  printf '%s' "$s" | grep -q 'working-directory: src dir'
  # The list is never pasted into the script text, where a file name would run as code.
  ! printf '%s' "$s" | sed -n '/run: |/,$p' | grep -q 'steps.scope.outputs' || {
    echo "the run script expands a step output inline"
    false
  }
}

@test "R143: the changed test files run on macOS and on both Linux entries: no step is limited by platform" {
  ! job test | grep -qE '^        if: .*(matrix\.(os|name|bash_path)|runner\.os)' || {
    job test | grep -E '^        if:'
    false
  }
}

@test "R143: the Tests job always runs and reports success when no tests are needed" {
  ! job test | grep -qE '^    if:' || {
    echo "a job-level condition would report the job as skipped"
    false
  }
  ! grep -q 'continue-on-error' "$CI" || false
  # No step fails on scope none: every test-running step is conditioned on its scope.
  local s
  s=$(step 'bash tools/test\.sh')
  printf '%s' "$s" | grep -qE '^        if: '
}
