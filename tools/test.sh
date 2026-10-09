#!/usr/bin/env bash
# Run every check: shellcheck on repo tooling, then the bats suite. Runs under
# whatever `bash` is first on PATH, so CI runs it once with macOS /bin/bash 3.2
# and once with bash 5. Fails on the first failing stage (no pipes).
# --shard K/N runs share K of N of the suite, so CI can split the run.
set -euo pipefail

usage='usage: tools/test.sh [--quick [--list]] | --shard K/N [--list]'
quick=0
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
    2:--quick:--list) quick=1 list=1 ;;
    *) bad_usage ;;
  esac
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# The files that measure time run alone after the rest, so the parallel batch
# cannot slow them past their limits (2026-10-07: a 24-check proof took 16 s
# against 15 s inside the batch, 11 s alone). One list for full, quick and shard runs.
timed='tests/prove-parallel.bats tests/guard-cost.bats tests/bench-hooks.bats tests/proof-stale-links.bats'

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
    bash tools/bench-hooks.sh
    if command -v node >/dev/null 2>&1; then
      bash tools/bench-panel.sh
    fi
  fi
  if [ "${#batch[@]}" -gt 0 ]; then
    bats --print-output-on-failure --jobs "$(jobs_count)" "${batch[@]}"
  fi
  if [ "${#timed_run[@]}" -gt 0 ]; then
    bats --print-output-on-failure "${timed_run[@]}"
  fi
  exit 0
fi

if [ "$list" = 1 ]; then
  echo "shellcheck tools/*.sh"
  quick_files
  exit 0
fi

echo "bash: $(bash -c 'echo "$BASH_VERSION"')"

tools_sh=()
while IFS= read -r -d '' f; do tools_sh+=("$f"); done < <(find tools -type f -name '*.sh' -print0)
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning -x "${tools_sh[@]}"
else
  echo "shellcheck not installed; skipping tool lint" >&2
fi

if [ "$quick" = 1 ]; then
  quick_list=()
  while IFS= read -r f; do quick_list+=("$f"); done < <(quick_files)
  bats --print-output-on-failure --jobs "$(jobs_count)" "${quick_list[@]}"
  exit 0
fi

# The hook cost budget (CPU time, so other load does not skew it) is measured first.
bash tools/bench-hooks.sh
# The panel cost budget, when node exists (the panel is JS).
if command -v node >/dev/null 2>&1; then
  bash tools/bench-panel.sh
fi

rest=()
for f in tests/*.bats; do
  case " $timed " in *" $f "*) ;; *) rest+=("$f") ;; esac
done
bats --print-output-on-failure --jobs "$(jobs_count)" "${rest[@]}"
# shellcheck disable=SC2086 # the list is fixed paths without spaces
bats --print-output-on-failure $timed
