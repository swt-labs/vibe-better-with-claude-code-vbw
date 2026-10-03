#!/usr/bin/env bash
# Seeds an existing codebase with requirements already met and tested: an
# inventory CLI (inv.sh) with add and list (list sorted by name), and test.sh
# for both. The request adds four features; the earlier tests must keep passing.
set -euo pipefail
git init -q
git config user.email eval@example.com
git config user.name "Eval"
cat > inv.sh <<'SH'
#!/usr/bin/env bash
# inv.sh add NAME QTY | list. Items live in $INV_FILE (default ./inventory.txt),
# one "NAME QTY" per line; list prints them sorted by name.
set -euo pipefail
f="${INV_FILE:-./inventory.txt}"
case "${1:-}" in
  add)
    [ $# -eq 3 ] && [[ "$3" =~ ^[0-9]+$ ]] || { echo "usage: inv.sh add NAME QTY" >&2; exit 2; }
    echo "$2 $3" >> "$f" ;;
  list) [ -f "$f" ] && sort "$f" || true ;;
  *) echo "usage: inv.sh add NAME QTY | list" >&2; exit 2 ;;
esac
SH
cat > test.sh <<'SH'
#!/usr/bin/env bash
# Tests for the earlier requirements of inv.sh. Prints TESTS PASS or TESTS FAIL.
INV_FILE="$(mktemp)"; export INV_FILE; rm -f "$INV_FILE"
fail() { echo "TESTS FAIL: $1"; rm -f "$INV_FILE"; exit 1; }
./inv.sh add pears 4; ./inv.sh add apples 10
[ "$(./inv.sh list)" = "$(printf 'apples 10\npears 4')" ] || fail "list is sorted by name"
./inv.sh add plums x 2> /dev/null && fail "a non-numeric quantity is refused"
rm -f "$INV_FILE"
echo "TESTS PASS"
SH
chmod +x inv.sh test.sh
git add -A && git commit -q -m "chore: seed inventory fixture"
