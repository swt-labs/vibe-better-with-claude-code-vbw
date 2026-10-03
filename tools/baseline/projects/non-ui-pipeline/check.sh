#!/usr/bin/env bash
# Passes when logstat.sh prints the exact summary of fixed inputs (the seeded
# log and a second log), reports malformed lines on stderr, and refuses a
# missing file with exit 2.
set -euo pipefail
t=$(mktemp -d "$PWD/.check.XXXX")
trap 'rm -rf "$t"' EXIT
git show "$(git rev-list --max-parents=0 HEAD)":logs/access.log > "$t/a.log"
./logstat.sh "$t/a.log" > "$t/out" 2> "$t/err"
[ "$(cat "$t/out")" = "$(printf '%s\n' 'requests: 8' 'status 2xx: 4' 'status 3xx: 1' 'status 4xx: 2' 'status 5xx: 1' \
  'bytes: 1792' 'top: /index.html (3)' 'top: /login (3)' 'top: /about.html (1)')" ]
grep -q 'malformed: 4' "$t/err"

printf '%s\n' 't GET /b 200 1' 't GET /a 200 2' 't GET /c 503 3' 'bad' > "$t/b.log"
./logstat.sh "$t/b.log" > "$t/out" 2> "$t/err"
[ "$(cat "$t/out")" = "$(printf '%s\n' 'requests: 3' 'status 2xx: 2' 'status 3xx: 0' 'status 4xx: 0' 'status 5xx: 1' \
  'bytes: 6' 'top: /a (1)' 'top: /b (1)' 'top: /c (1)')" ]
grep -q 'malformed: 1' "$t/err"

set +e
./logstat.sh "$t/none.log" > /dev/null 2>&1; s1=$?
./logstat.sh > /dev/null 2>&1; s2=$?
set -e
[ "$s1" -eq 2 ] && [ "$s2" -eq 2 ]
