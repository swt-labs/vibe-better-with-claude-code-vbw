#!/usr/bin/env bats
# R247 (docs/record.md): the record's schema rule is stated once, in the Versioning
# section, as the table plugin/lib/record-schema.jq holds (feature -> schema, the
# highest present wins, 4 is the floor, a record below its content loads and is
# raised on its next write, a record above its content is corrupt, VBW_SCHEMA_MAX,
# no migration command); the Shape section's rows point to it instead of restating
# numbers. L1: the docs file alone.

load helper

@test "R247 docs: docs/record.md states the rule once, in Versioning: the table's five rows, the floor, highest wins, below loads and is raised, above is corrupt, VBW_SCHEMA_MAX 9, no migration command; the key-order note and the schema, decisions and settings rows point to the table" {
  local doc="$REPO_ROOT/docs/record.md" section row
  section=$(awk '/^## Versioning/ { on = 1 } /^## Consent/ { on = 0 } on' "$doc")
  [ -n "$section" ] || { echo "no Versioning section before Consent"; false; }
  printf '%s\n' "$section" | grep -qE '^\|[^|]*`settings\.efforts`[^|]*\| *5 *\|' || { echo "no table row settings.efforts -> 5"; false; }
  printf '%s\n' "$section" | grep -qE '^\|[^|]*decision[^|]*plans[^|]*\| *6 *\|' || { echo "no table row for a decision's plans -> 6"; false; }
  printf '%s\n' "$section" | grep -qE '^\|[^|]*`settings\.mcp`[^|]*\| *7 *\|' || { echo "no table row settings.mcp -> 7"; false; }
  printf '%s\n' "$section" | grep -qE '^\|[^|]*tree[^|]*contract[^|]*\| *8 *\|' || { echo "no table row for a break with tree or contract -> 8"; false; }
  printf '%s\n' "$section" | grep -qE '^\|[^|]*amendment[^|]*await[^|]*queued[^|]*\| *9 *\|' || { echo "no table row for an amendment, an awaited check or a queued requirement -> 9"; false; }
  [ "$(printf '%s\n' "$section" | grep -cE '^\|[^|]*\| *[5-9] *\|')" -eq 5 ] || { echo "the table has more or fewer than five rows"; false; }
  printf '%s\n' "$section" | grep -qiE 'floor' || { echo "the floor (4) is not named"; false; }
  printf '%s\n' "$section" | grep -qiE 'highest' || { echo "highest feature wins is not stated"; false; }
  printf '%s\n' "$section" | grep -qiE 'below[^.]*(load|read)[^.]*rais' || { echo "a record below its content loading and being raised is not stated"; false; }
  printf '%s\n' "$section" | grep -qiE 'above[^.]*corrupt' || { echo "a record above its content being corrupt is not stated"; false; }
  printf '%s\n' "$section" | grep -q '`VBW_SCHEMA_MAX`, currently 9' || { echo "VBW_SCHEMA_MAX, currently 9 is not stated"; false; }
  printf '%s\n' "$section" | grep -qi 'no migration command' || { echo "the docs no longer say there is no migration command"; false; }
  # The field rows point to the table instead of restating numbers.
  row=$(grep -E '^\| `schema` \|' "$doc")
  [[ "$row" == *"Versioning"* ]] || { echo "the schema row does not point to Versioning: $row"; false; }
  ! printf '%s\n' "$row" | grep -qE 'schema[- ][5-9]|`[5-9]`' || { echo "the schema row restates numbers: $row"; false; }
  row=$(grep -E '^\| `decisions\[\]` \|' "$doc")
  ! printf '%s\n' "$row" | grep -qE 'schema[- ]6' || { echo "the decisions row restates schema 6: $row"; false; }
  row=$(grep -E '^\| `settings` \|' "$doc")
  ! printf '%s\n' "$row" | grep -qE 'schema[- ][57]' || { echo "the settings row restates schema 5 or 7: $row"; false; }
  ! awk 'BEGIN { RS = "" } { gsub(/\n/, " "); print }' "$doc" | grep -E 'Key order' | grep -qE '[5-9] while|schema [5-9]' || { echo "the key-order note restates numbers"; false; }
}
