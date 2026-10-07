#!/usr/bin/env bash
# Run every check: shellcheck on repo tooling, then the bats suite. Runs under
# whatever `bash` is first on PATH, so CI runs it once with macOS /bin/bash 3.2
# and once with bash 5. Fails on the first failing stage (no pipes).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "bash: $(bash -c 'echo "$BASH_VERSION"')"

tools_sh=()
while IFS= read -r -d '' f; do tools_sh+=("$f"); done < <(find tools -type f -name '*.sh' -print0)
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning -x "${tools_sh[@]}"
else
  echo "shellcheck not installed; skipping tool lint" >&2
fi

jobs=1
if command -v parallel >/dev/null 2>&1; then
  jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
fi
# The hook cost budget (CPU time, so other load does not skew it) is measured first.
bash tools/bench-hooks.sh
# The panel cost budget, when node exists (the panel is JS).
if command -v node >/dev/null 2>&1; then
  bash tools/bench-panel.sh
fi

# Files that measure time run alone after the rest, so the parallel batch
# cannot slow them past their limits (2026-10-07: a 24-check proof took 16 s
# against 15 s inside the batch, 11 s alone).
timed='tests/prove-parallel.bats tests/guard-cost.bats tests/bench-hooks.bats tests/proof-stale-links.bats'
rest=()
for f in tests/*.bats; do
  case " $timed " in *" $f "*) ;; *) rest+=("$f") ;; esac
done
bats --print-output-on-failure --jobs "$jobs" "${rest[@]}"
# shellcheck disable=SC2086 # the list is fixed paths without spaces
bats --print-output-on-failure $timed
