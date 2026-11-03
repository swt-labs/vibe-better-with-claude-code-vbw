#!/usr/bin/env bats
# R150 (decision D232): docs/record.md names the protected field and schema 4
# (VBW_SCHEMA_MAX); docs/guards.md quotes the refusal while an older record is
# not yet saved. Neither mentions a 50-check threshold, schemas 1 to 3 being
# written, or guards reading the checks. L1.

load helper

# paragraphs FILE: each paragraph (or table row block) of FILE on one line.
paragraphs() { awk 'BEGIN { RS = "" } { gsub(/\n/, " "); print }' "$1"; }

@test "R150: docs/record.md names the protected field and the reader's highest schema as in record.sh" {
  local doc="$REPO_ROOT/docs/record.md" max
  grep -q '`protected`' "$doc"
  max=$(sed -n 's/^VBW_SCHEMA_MAX=//p' "$PLUGIN_ROOT/lib/record.sh")
  grep -q "\`VBW_SCHEMA_MAX\`, currently $max" "$doc"
  # Which schema a chosen effort makes is the schema table's row (R247, tests/record-schema.bats).
}

@test "R150: docs/record.md and docs/guards.md no longer mention a 50-check threshold" {
  local doc
  for doc in "$REPO_ROOT/docs/record.md" "$REPO_ROOT/docs/guards.md"; do
    ! grep -niE '50 checks|more than 50|fewer than 50' "$doc" || { echo "$doc still names the threshold"; false; }
  done
}

@test "R150: docs/record.md no longer says this VBW writes schema 1, 2 or 3" {
  ! paragraphs "$REPO_ROOT/docs/record.md" | grep -iE 'kernel writes|vbw writes|is written|keeps? schema|stays? (at )?schema' \
    | grep -iE 'schemas? [123]([^0-9]|$)' | grep -viE 'older vbw|before (format|schema) 4|earlier' \
    || { echo "docs/record.md still says schemas 1 to 3 are written"; false; }
}

@test "R150: docs/guards.md no longer says the guards read the checks on older records" {
  local doc="$REPO_ROOT/docs/guards.md"
  ! paragraphs "$doc" | grep -iE 'schemas? 1 to 3|schema 1, 2 or 3' | grep -iE '(read|walk)(s|ing)? (the|its|their|every) (check|`checks`)' \
    || { echo "docs/guards.md still says the guards read the checks on older records"; false; }
}

@test "R150: docs/guards.md quotes the refusal on a record without the list: not saved by this VBW yet" {
  grep -qF 'saved by this VBW' "$REPO_ROOT/docs/guards.md"
}
