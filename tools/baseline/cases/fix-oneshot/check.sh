#!/usr/bin/env bash
# Deterministic post-run check (direct.sh): the tests pass and add() adds.
set -euo pipefail
./test.sh | grep -qx 'TESTS PASS'
grep -Eq '\$\(\(\s*\$1\s*\+\s*\$2\s*\)\)' calc.sh
