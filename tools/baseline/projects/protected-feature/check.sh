#!/usr/bin/env bash
# Passes when the four new requirements hold AND the earlier ones still do
# (the fixture's original tests, re-run from git, plus their behaviour here).
set -euo pipefail
export INV_FILE="$PWD/.check-inventory.txt"
trap 'rm -f "$INV_FILE" "$PWD/.check-test.sh"' EXIT
rm -f "$INV_FILE"
inv() { ./inv.sh "$@"; }

# Earlier requirements: the original test.sh, as seeded.
git show "$(git rev-list --max-parents=0 HEAD)":test.sh > .check-test.sh
bash .check-test.sh | grep -qx 'TESTS PASS'
rm -f "$INV_FILE"
# The project's own tests pass too.
./test.sh > /dev/null
rm -f "$INV_FILE"

[ "$(inv total)" = "0" ]
inv add pears 4; inv add apples 10; inv add figs 1; inv add apples 3
[ "$(inv list)" = "$(printf 'apples 13\nfigs 1\npears 4')" ]   # merged, sorted
[ "$(inv total)" = "18" ]
[ "$(inv low 5)" = "$(printf 'figs 1\npears 4')" ]
[ -z "$(inv low 1)" ]
inv remove figs
[ "$(inv list)" = "$(printf 'apples 13\npears 4')" ]
if inv remove kiwis 2> /dev/null; then exit 1; fi
[ -n "$(inv remove kiwis 2>&1 > /dev/null || true)" ]
if inv add plums x 2> /dev/null; then exit 1; fi
