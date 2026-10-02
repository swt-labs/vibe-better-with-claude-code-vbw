#!/usr/bin/env bash
# Seeds a small existing codebase: a todo CLI (todo.sh) with add and list, and
# its test. The feature to add is "done N". A plain git repo.
set -euo pipefail
git init -q
git config user.email eval@example.com
git config user.name "Eval"
cat > todo.sh <<'SH'
#!/usr/bin/env bash
# todo.sh add TEXT | list. Items live in $TODO_FILE (default ./todos.txt), one per line.
set -euo pipefail
f="${TODO_FILE:-./todos.txt}"
case "${1:-}" in
  add) shift; echo "[ ] $*" >> "$f" ;;
  list) [ -f "$f" ] && nl -w1 -s'. ' "$f" || true ;;
  *) echo "usage: todo.sh add TEXT | list" >&2; exit 2 ;;
esac
SH
cat > test.sh <<'SH'
#!/usr/bin/env bash
# Tests for todo.sh. Prints TESTS PASS or TESTS FAIL.
TODO_FILE="$(mktemp)"; export TODO_FILE; rm -f "$TODO_FILE"
./todo.sh add "buy milk"; ./todo.sh add "walk dog"
got="$(./todo.sh list)"; rm -f "$TODO_FILE"
[ "$got" = "$(printf '1. [ ] buy milk\n2. [ ] walk dog')" ] && echo "TESTS PASS" || { echo "TESTS FAIL"; exit 1; }
SH
chmod +x todo.sh test.sh
git add -A && git commit -q -m "chore: seed todo fixture"
