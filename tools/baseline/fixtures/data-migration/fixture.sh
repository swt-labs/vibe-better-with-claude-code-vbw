#!/usr/bin/env bash
# Seeds a small data store to migrate: data/people.csv (a header and 8 rows,
# one blank line, mixed-case emails, ;-separated tags, an empty email and empty
# tags). The request moves it to data/people.json without losing a row.
set -euo pipefail
git init -q
git config user.email eval@example.com
git config user.name "Eval"
mkdir -p data
cat > data/people.csv <<'CSV'
id,name,email,tags
1,Ana Silva,Ana@Example.com,admin;dev
2,Bo Chen,bo@example.com,dev
3,Cy Okafor,,ops

4,Di Rossi,DI.ROSSI@EXAMPLE.COM,
5,Ed Park,ed@example.com,dev;ops;oncall
6,Fay Ngo,fay@example.com,sales
7,Gus Lima,gus@Example.COM,
8,Hal Berg,hal@example.com,admin
CSV
cat > README.md <<'MD'
# People store

`data/people.csv` holds the team: `id,name,email,tags` (tags separated by `;`).
MD
git add -A && git commit -q -m "chore: seed people store"
