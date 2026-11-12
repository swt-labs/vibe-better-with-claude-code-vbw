#!/usr/bin/env bash
# Run every check: shellcheck on repo tooling, then the bats suite. Runs under
# whatever `bash` is first on PATH, so CI runs it once with macOS /bin/bash 3.2
# and once with bash 5. Fails on the first failing stage (no pipes), except the speed benchmarks: a failed
# bench never stops the lint or the test files; the run fails at the end naming it.
# No option: the lint and every test file except the timed ones (tests/timed-*.bats),
# the run `vbw prove` uses. --release adds both benchmarks and the timed files, run
# alone after the rest: the speed checks run once per release, never in a proof.
# When the last proof was full and passed on code that differs from the working
# tree only in the version files and the changelog, --release runs just those.
# --shard K/N runs share K of N of the release run, so CI can split it.
# --lint runs only the shellcheck stage over tools/ (VBW's own `lint` project
# command, so a proof re-runs it only when tools/ changed).
set -euo pipefail

usage='usage: tools/test.sh [--quick [--list]] | --lint | --release | --shard K/N [--list]'
quick=0
lint=0
release=0
list=0
shard=0
nshards=0

bad_usage() { echo "$usage" >&2; exit 2; }

if [ "${1-}" = --shard ]; then
  # Exactly `--shard K/N` or `--shard K/N --list`; K and N whole numbers, 1 <= K <= N.
  case "$#:${3-}" in 2:|3:--list) ;; *) bad_usage ;; esac
  spec="$2"
  case "$spec" in */*/*|/*|*/) bad_usage ;; */*) ;; *) bad_usage ;; esac
  shard="${spec%/*}"
  nshards="${spec#*/}"
  case "$shard$nshards" in *[!0-9]*) bad_usage ;; esac
  shard=$((10#$shard))
  nshards=$((10#$nshards))
  { [ "$shard" -ge 1 ] && [ "$shard" -le "$nshards" ]; } || bad_usage
  [ "$#" -eq 3 ] && list=1
else
  case "$#:${1-}:${2-}" in
    0::) ;;
    1:--quick:) quick=1 ;;
    1:--lint:) lint=1 ;;
    1:--release:) release=1 ;;
    2:--quick:--list) quick=1 list=1 ;;
    *) bad_usage ;;
  esac
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# The files that measure time (tests/timed-*.bats) run alone after the rest, so the
# parallel batch cannot slow them past their limits (2026-10-07: a 24-check proof took
# 16 s against 15 s inside the batch, 11 s alone). Found at run time; one list for
# default, release, quick and shard runs.
timed=""
for f in tests/timed-*.bats; do
  [ -e "$f" ] && timed="${timed:+$timed }$f"
done

# The quick mode: every test file no approved check runs or protects (those
# run in proof), minus the timing benchmarks, plus the engineering rules always.
quick_files() {
  local covered f
  covered="$(jq -r '[.checks[] | (.run[], (.files[]?))] | unique[] | select(test("^tests/[^/]+\\.bats$"))' .vbw/record.json)"
  for f in tests/*.bats; do
    case "$f" in
      tests/standards.bats|tests/standards-selftest.bats) echo "$f"; continue ;;
    esac
    case " $timed " in *" $f "*) continue ;; esac
    # A here-string, not a pipe: under pipefail an early grep -q exit makes printf fail (SIGPIPE).
    grep -qxF "$f" <<< "$covered" || echo "$f"
  done
}

# shard_files K N: the test files of share K of N, one per line. Files go from
# most tests to fewest (ties by name), each to the share with the fewest tests so far
# (ties to the lowest number). Computed from tests/*.bats at run time.
shard_files() {
  local f
  for f in tests/*.bats; do
    printf '%s %s\n' "$(grep -c '^@test' "$f" || true)" "$f"
  done | LC_ALL=C sort -k1,1nr -k2,2 | awk -v k="$1" -v n="$2" '
    BEGIN { for (i = 1; i <= n; i++) load[i] = 0 }
    {
      best = 1
      for (i = 2; i <= n; i++) if (load[i] < load[best]) best = i
      load[best] += $1
      if (best == k) print $2
    }'
}

# jobs_count: half the cores, so the machine stays usable; 1 without GNU parallel.
jobs_count() {
  local j=1
  if command -v parallel >/dev/null 2>&1; then
    j=$(( $(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4) / 2 )); [ "$j" -ge 1 ] || j=1
  fi
  echo "$j"
}

# The speed benchmarks never stop a run: a failed one is remembered and the lint and every
# test file still run; `finish` then prints one line per failed bench as the last lines and
# exits non-zero (also when a test file failed too).
failed_benches=""
test_failed=0

# run_benches: the hook bench, then the panel bench when node exists (the panel is JS).
run_benches() {
  if ! bash tools/bench-hooks.sh; then failed_benches="${failed_benches}failed: hook bench"$'\n'; fi
  if command -v node >/dev/null 2>&1; then
    if ! bash tools/bench-panel.sh; then failed_benches="${failed_benches}failed: panel bench"$'\n'; fi
  fi
}

# run_bats ARGS...: run bats, remember a failure without stopping the run.
run_bats() {
  bats --print-output-on-failure "$@" || test_failed=1
}

# finish: name each failed bench, then exit 1 when a bench or a test file failed.
finish() {
  [ -z "$failed_benches" ] || printf '%s' "$failed_benches"
  if [ -n "$failed_benches" ] || [ "$test_failed" -ne 0 ]; then exit 1; fi
  exit 0
}

if [ "$shard" -ge 1 ]; then
  share=()
  while IFS= read -r f; do share+=("$f"); done < <(shard_files "$shard" "$nshards")
  batch=()
  timed_run=()
  for f in ${share[@]+"${share[@]}"}; do
    case " $timed " in *" $f "*) ;; *) batch+=("$f") ;; esac
  done
  for f in $timed; do
    for g in ${share[@]+"${share[@]}"}; do
      [ "$g" = "$f" ] && timed_run+=("$f")
    done
  done
  if [ "$list" = 1 ]; then
    if [ "$shard" -eq 1 ]; then
      echo "shellcheck tools/*.sh"
      echo "bash tools/bench-hooks.sh"
      echo "bash tools/bench-panel.sh"
    fi
    for f in ${batch[@]+"${batch[@]}"} ${timed_run[@]+"${timed_run[@]}"}; do echo "$f"; done
    exit 0
  fi
  echo "bash: $(bash -c 'echo "$BASH_VERSION"')"
  if [ "$shard" -eq 1 ]; then
    tools_sh=()
    while IFS= read -r -d '' f; do tools_sh+=("$f"); done < <(find tools -type f -name '*.sh' -print0)
    if command -v shellcheck >/dev/null 2>&1; then
      shellcheck -S warning -x "${tools_sh[@]}"
    else
      echo "shellcheck not installed; skipping tool lint" >&2
    fi
    run_benches
  fi
  if [ "${#batch[@]}" -gt 0 ]; then
    run_bats --jobs "$(jobs_count)" "${batch[@]}"
  fi
  if [ "${#timed_run[@]}" -gt 0 ]; then
    run_bats "${timed_run[@]}"
  fi
  finish
fi

if [ "$list" = 1 ]; then
  echo "shellcheck tools/*.sh"
  quick_files
  exit 0
fi

echo "bash: $(bash -c 'echo "$BASH_VERSION"')"

# release_reuse: succeed when the last proof in .vbw/record.json passed, left no
# command skipped and no quick command standing in for the test command (a
# reused result counts: the read lists still vouch for it, R170), and the
# project's files differ from the code it proved only in the version files
# (those tools/bump-version.sh --files names) and plugin/CHANGELOG.md; print the
# proof's time. Otherwise fail, printing why (naming
# the differing files) on stdout.
release_reuse() {
  local ev at head idx now diff other f allowed
  [ -f .vbw/record.json ] && ev=$(jq -c '.evidence // empty | select(type == "object")' .vbw/record.json 2>/dev/null) && [ -n "$ev" ] \
    || { echo "no proof recorded"; return 1; }
  at=$(jq -r '.at // "unknown time"' <<< "$ev")
  jq -e '.passed == true' >/dev/null <<< "$ev" || { echo "the last proof (of $at) failed"; return 1; }
  jq -e '[(.commands // {})[] | select(.status == "skipped")] | length == 0' >/dev/null <<< "$ev" \
    || { echo "the last proof (of $at) skipped a command that was not approved"; return 1; }
  jq -e '(.commands // {}) | (has("test") or (has("quick") | not))' >/dev/null <<< "$ev" \
    || { echo "in the last proof (of $at) the quick command stood in for the test command"; return 1; }
  head=$(jq -r '.head // empty' <<< "$ev")
  [ -n "$head" ] || { echo "the last proof (of $at) names no proved code"; return 1; }
  git rev-parse -q --verify HEAD >/dev/null 2>&1 || { echo "not a git repository with a commit; no proof to compare"; return 1; }
  idx=$(mktemp "$ROOT/.vbw/runtime/index.XXXXXX" 2>/dev/null) || idx=$(mktemp "$(git rev-parse --absolute-git-dir)/vbw-release-index.XXXXXX") \
    || { echo "cannot fingerprint the project files"; return 1; }
  now=$(
    real=$(git rev-parse --path-format=absolute --git-path index)
    if [ -f "$real" ]; then cp "$real" "$idx"; else rm -f "$idx"; fi
    export GIT_INDEX_FILE="$idx"
    git add -A -- . ':(exclude).vbw' ':(exclude).vbw-planning' >/dev/null 2>&1 &&
      git rm -r -q --cached --ignore-unmatch -- .vbw .vbw-planning >/dev/null 2>&1 &&
      git write-tree
  ) || now=
  rm -f "$idx"
  [ -n "$now" ] || { echo "cannot fingerprint the project files"; return 1; }
  diff=$(git diff-tree -z -r --name-only "$head" "$now" 2>/dev/null | tr '\0' '\n') \
    || { echo "the proved code of $at is not in this repository"; return 1; }
  allowed=$(bash tools/bump-version.sh --files) || { echo "cannot list the version files"; return 1; }
  allowed=$'\n'"$allowed"$'\nplugin/CHANGELOG.md\n'
  other=
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$allowed" in
      *$'\n'"$f"$'\n'*) ;;
      *) other="${other:+$other, }$f" ;;
    esac
  done <<< "$diff"
  [ -z "$other" ] || { echo "files changed since the last proof (of $at): $other"; return 1; }
  echo "$at"
}

if [ "$release" = 1 ]; then
  if why=$(release_reuse); then
    echo "release: reusing the passing proof of $why (only the version files and the changelog changed since); running the benchmarks and the timed tests only"
    run_benches
    if [ -n "$timed" ]; then
      # shellcheck disable=SC2086 # the list is fixed paths without spaces
      run_bats $timed
    fi
    finish
  fi
fi

tools_sh=()
while IFS= read -r -d '' f; do tools_sh+=("$f"); done < <(find tools -type f -name '*.sh' -print0)
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning -x "${tools_sh[@]}"
else
  echo "shellcheck not installed; skipping tool lint" >&2
fi

if [ "$lint" = 1 ]; then exit 0; fi

if [ "$quick" = 1 ]; then
  quick_list=()
  while IFS= read -r f; do quick_list+=("$f"); done < <(quick_files)
  bats --print-output-on-failure --jobs "$(jobs_count)" "${quick_list[@]}"
  exit 0
fi

if [ "$release" = 1 ]; then echo "release: running everything: $why"; fi

rest=()
for f in tests/*.bats; do
  case " $timed " in *" $f "*) ;; *) rest+=("$f") ;; esac
done

if [ "$release" = 1 ]; then
  # The hook cost budget (CPU time, so other load does not skew it) is measured first.
  # The panel cost budget follows, when node exists (the panel is JS).
  run_benches
fi

run_bats --jobs "$(jobs_count)" "${rest[@]}"
if [ "$release" = 1 ] && [ -n "$timed" ]; then
  # shellcheck disable=SC2086 # the list is fixed paths without spaces
  run_bats $timed
fi
finish
