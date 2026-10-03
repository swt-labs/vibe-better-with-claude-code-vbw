#!/usr/bin/env bash
# Passes when migrate.sh, run again on the original CSV, writes exactly the
# expected people.json (no row lost, emails lowercased, null and [] where empty)
# and leaves the CSV unchanged.
set -euo pipefail
[ -x migrate.sh ] || { echo "no executable migrate.sh" >&2; exit 1; }
csv=$(git show "$(git rev-list --max-parents=0 HEAD)":data/people.csv)
[ "$(cat data/people.csv)" = "$csv" ]
./migrate.sh > /dev/null
./migrate.sh > /dev/null
[ "$(cat data/people.csv)" = "$csv" ]
expected='[
 {"id":1,"name":"Ana Silva","email":"ana@example.com","tags":["admin","dev"]},
 {"id":2,"name":"Bo Chen","email":"bo@example.com","tags":["dev"]},
 {"id":3,"name":"Cy Okafor","email":null,"tags":["ops"]},
 {"id":4,"name":"Di Rossi","email":"di.rossi@example.com","tags":[]},
 {"id":5,"name":"Ed Park","email":"ed@example.com","tags":["dev","ops","oncall"]},
 {"id":6,"name":"Fay Ngo","email":"fay@example.com","tags":["sales"]},
 {"id":7,"name":"Gus Lima","email":"gus@example.com","tags":[]},
 {"id":8,"name":"Hal Berg","email":"hal@example.com","tags":["admin"]}]'
jq -e --argjson want "$expected" '. == $want' data/people.json > /dev/null
