#!/usr/bin/env bash
# Known-correct solution, applied in the workspace.
set -euo pipefail
cat > migrate.sh <<'SH'
#!/usr/bin/env bash
# Migrates data/people.csv to data/people.json; safe to run again.
set -euo pipefail
jq -R -s '
  split("\n") | .[1:] | map(select(length > 0)) | map(split(","))
  | map({id: (.[0] | tonumber), name: .[1],
         email: (if .[2] == "" then null else (.[2] | ascii_downcase) end),
         tags: (.[3] // "" | split(";") | map(select(. != "")))})
  | sort_by(.id)' data/people.csv > data/people.json.new
mv data/people.json.new data/people.json
SH
chmod +x migrate.sh
cat >> README.md <<'MD'

`data/people.json` is the migrated store (`./migrate.sh` writes it from the CSV).
MD
