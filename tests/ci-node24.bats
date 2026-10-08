#!/usr/bin/env bats
# R126 (L1): GitHub's CI runs its ready-made steps (actions) on their Node 24
# majors, and the Linux tests also run on the Ubuntu 26.04 image, before
# ubuntu-latest moves on 2026-10-19. The workflow files are read as text: no
# YAML parser is a VBW dependency. The real proof is the first CI run on GitHub
# after the owner pushes (L4); this file proves only what the files say.

load helper

WF="$REPO_ROOT/.github/workflows"
CI="$WF/ci.yml"

# uses_lines: every "uses: owner/name@ref" of the four workflow files, as "file: owner/name@ref".
uses_lines() {
  local f
  for f in "$WF/ci.yml" "$WF/discord-release.yml" "$WF/linked-issue.yml" "$WF/qa-review.yml"; do
    [ -f "$f" ] || { echo "missing workflow file: $f" >&2; return 1; }
    sed -n 's/^[[:space:]-]*uses:[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$f" | sed "s|^|$(basename "$f"): |"
  done
}

# test_entries: the matrix entries of the Tests job, one line each: "name|os|bash_path".
test_entries() {
  awk '
    /^  test:/ { injob = 1; next }
    /^  [a-z]/ { injob = 0 }
    injob && /^ *- name:/ { if (n) print n "|" o "|" b; n = $0; sub(/^ *- name: */, "", n); o = ""; b = ""; next }
    injob && n && /^ *os:/ { o = $0; sub(/^ *os: */, "", o) }
    injob && n && /^ *bash_path:/ { b = $0; sub(/^ *bash_path: */, "", b) }
    injob && /^    steps:/ { if (n) print n "|" o "|" b; n = ""; injob = 0 }
  ' "$CI"
}

# install_step: the run block of the "Install test tools" step.
install_step() {
  awk '
    /- name: Install test tools/ { on = 1; next }
    on && /^      - / { exit }
    on { print }
  ' "$CI"
}

@test "R126: every actions/checkout and actions/setup-node step is on a Node 24 major (v5 or later)" {
  local lines bad
  lines=$(uses_lines)
  printf '%s\n' "$lines" | grep -q 'actions/checkout@' || { echo "no actions/checkout step found"; false; }
  printf '%s\n' "$lines" | grep -q 'actions/setup-node@' || { echo "no actions/setup-node step found"; false; }
  bad=$(printf '%s\n' "$lines" | awk -F'@' '
    /actions\/(checkout|setup-node)@/ {
      ref = $2
      if (ref !~ /^v[0-9]+/) { print; next }
      major = ref; sub(/^v/, "", major); sub(/[^0-9].*$/, "", major)
      if (major + 0 < 5) print
    }')
  [ -z "$bad" ] || { echo "pre-Node-24 majors: $bad"; false; }
}

@test "R126: no step in the four workflow files is left on a major that runs on Node 20" {
  local lines
  lines=$(uses_lines)
  ! printf '%s\n' "$lines" | grep -E '@v[1-4]([^0-9]|$)' || { echo "a step is on v4 or older"; false; }
}

@test "R126: the Tests job has three entries: macOS /bin/bash 3.2, Linux bash 5 on ubuntu-latest and on ubuntu-26.04" {
  local entries
  entries=$(test_entries)
  [ "$(printf '%s\n' "$entries" | grep -c .)" -eq 3 ] || { echo "entries: $entries"; false; }
  printf '%s\n' "$entries" | grep -qE '\|macos-latest\|/bin$' || { echo "entries: $entries"; false; }
  printf '%s\n' "$entries" | grep -qE '\|ubuntu-latest\|/usr/bin$' || { echo "entries: $entries"; false; }
  printf '%s\n' "$entries" | grep -qE '\|ubuntu-26\.04\|/usr/bin$' || { echo "the ubuntu-26.04 Tests entry is missing: $entries"; false; }
}

@test "R126: the ubuntu-26.04 entry runs the same steps as the other Linux one (one step list for the whole matrix)" {
  # The entries share the job's steps: checkout into a folder whose name has a
  # space, the tool install, the same budgets and bash tools/test.sh.
  [ "$(grep -c '^    steps:' "$CI")" -ge 1 ]
  grep -q 'path: src dir' "$CI"
  grep -q 'working-directory: src dir' "$CI"
  grep -q 'VBW_HOOK_BUDGET_MS: "25"' "$CI"
  grep -q 'VBW_PANEL_BUDGET_MS: "3"' "$CI"
  grep -q 'bash tools/test.sh' "$CI"
  ! grep -qE "matrix\.os *(==|!=) *'?ubuntu-(latest|26)" "$CI" || { echo "a step is limited to one Linux image"; false; }
}

@test "R126: the tool install works on both Linux images by the same package names and fails the job when a package is missing" {
  local step
  step=$(install_step)
  [ -n "$step" ] || { echo "no Install test tools step"; false; }
  printf '%s\n' "$step" | grep -q 'shell: bash'
  printf '%s\n' "$step" | grep -qE 'apt-get install -y( -qq)? bats shellcheck jq parallel'
  printf '%s\n' "$step" | grep -q 'brew install bats-core shellcheck jq parallel'
  ! printf '%s\n' "$step" | grep -qE '\|\| *(true|:)|--ignore-missing|--fix-missing|set \+e|continue-on-error' || { echo "a missing package would be skipped silently"; false; }
  ! grep -q 'continue-on-error' "$CI" || { echo "continue-on-error hides a failing entry"; false; }
}

@test "R126: fail-fast stays off, so a failure on one image never cancels the other entries" {
  grep -qE '^      fail-fast: false$' "$CI"
}
