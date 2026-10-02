#!/usr/bin/env bash
# Seeds a tiny repo with one bug: add() subtracts. test.sh prints TESTS PASS or
# TESTS FAIL. A plain git repo: no project files of any VBW version.
set -euo pipefail
git init -q
git config user.email eval@example.com
git config user.name "Eval"
cat > calc.sh <<'SH'
#!/usr/bin/env bash
add() { echo $(( $1 - $2 )); }
SH
cat > test.sh <<'SH'
#!/usr/bin/env bash
. ./calc.sh
if [ "$(add 2 3)" = "5" ] && [ "$(add -1 1)" = "0" ]; then echo "TESTS PASS"; else echo "TESTS FAIL"; exit 1; fi
SH
chmod +x calc.sh test.sh
git add -A && git commit -q -m "chore: seed calc fixture"
