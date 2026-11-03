#!/usr/bin/env bash
# check-record-shape.sh PLUGIN_ROOT PINNED_SCHEMA PINNED_DIGEST: a new key or allowed
# value of the record comes with a schema bump (R248, docs/record.md Versioning).
# It digests the record's accepted shape, one line per item: every literal array of
# string literals in lib/record.jq (key lists and enums; comment lines dropped and
# line breaks inside a list ignored, the names of a list sorted), every row of the
# schema table in lib/record-schema.jq, and every array of lib/interview.json (read
# through jq). The SHA-256 of that text is compared with PINNED_DIGEST, and the
# table's top, VBW_SCHEMA_MAX (lib/record.sh) and PINNED_SCHEMA are compared with
# each other. Exit 0 when all agree, 1 with a refusal naming the places to touch,
# 2 on a wrong argument count. tests/standards.bats pins the values.
set -euo pipefail
[ $# -eq 3 ] || { printf 'usage: check-record-shape.sh PLUGIN_ROOT PINNED_SCHEMA PINNED_DIGEST\n' >&2; exit 2; }
root=$1 pinned_schema=$2 pinned_digest=$3
lib="$root/lib"
for f in record.jq record-schema.jq record.sh interview.json; do
  [ -f "$lib/$f" ] || { printf 'check-record-shape.sh: no %s\n' "$lib/$f" >&2; exit 2; }
done

sep=$(printf '\001')
list_re='\[[[:space:]]*"[^"]*"([[:space:]]*,[[:space:]]*"[^"]*")*[[:space:]]*\]'

sorted() { LC_ALL=C sort; }

lists=$(grep -vE '^[[:space:]]*#' "$lib/record.jq" | tr '\n' ' ' | { grep -oE "$list_re" || true; } |
  while IFS= read -r l; do
    names=$(printf '%s\n' "$l" | sed -e 's/^\[[[:space:]]*"//' -e 's/"[[:space:]]*\]$//' -e "s/\"[[:space:]]*,[[:space:]]*\"/$sep/g" |
      tr "$sep" '\n' | sorted | paste -sd, -)
    printf 'record.jq: %s\n' "$names"
  done | sorted)
rows=$(jq -r -n -L "$lib" 'include "record-schema"; schema_features[] | "\(.schema) \(.feature)"' |
  while IFS= read -r r; do printf 'record-schema.jq: %s\n' "$r"; done | sorted)
iv=$(jq -r 'to_entries[] | "\(.key)=\(.value | sort | join(","))"' "$lib/interview.json" |
  while IFS= read -r r; do printf '%s.json: %s\n' interview "$r"; done | sorted)
shape=$(printf '%s\n%s\n%s\n' "$lists" "$rows" "$iv")

if command -v shasum > /dev/null 2>&1; then
  digest=$(printf '%s\n' "$shape" | shasum -a 256 | cut -d' ' -f1)
else
  digest=$(printf '%s\n' "$shape" | sha256sum | cut -d' ' -f1)
fi

top=$(jq -r -n -L "$lib" 'include "record-schema"; schema_top')
max=$(sed -n 's/^VBW_SCHEMA_MAX=//p' "$lib/record.sh")
bad=0
if [ "$digest" != "$pinned_digest" ]; then
  printf 'The accepted shape of the record changed: a key or value was added or removed.\n'
  printf 'computed digest: %s\n' "$digest"
  bad=1
fi
if [ "$top" != "$max" ] || [ "$max" != "$pinned_schema" ]; then
  printf 'schema numbers differ: table %s, VBW_SCHEMA_MAX %s, pinned %s\n' "$top" "$max" "$pinned_schema"
  bad=1
fi
if [ "$bad" -ne 0 ]; then
  printf 'Next: a new key or value needs a schema bump. Add the row to the schema table in plugin/lib/record-schema.jq, set VBW_SCHEMA_MAX in plugin/lib/record.sh, describe it in docs/record.md, then move the pin (R248_SCHEMA and R248_DIGEST) in tests/standards.bats.\n'
  exit 1
fi
