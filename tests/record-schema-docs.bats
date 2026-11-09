#!/usr/bin/env bats
# R247 (docs/record.md): the record's schema rule is stated once, in the Versioning
# section, as the table plugin/lib/record-schema.jq holds (feature -> schema, the
# highest present wins, 4 is the floor, a record below its content loads and is
# raised on its next write, a record above its content is corrupt, VBW_SCHEMA_MAX,
# no migration command); the Shape section's rows point to it instead of restating
# numbers. L1: the docs file alone.

load helper

@test "R247 docs: docs/record.md states the rule once, in Versioning: the table's eleven rows, the floor, highest wins, below loads and is raised, above is corrupt, VBW_SCHEMA_MAX 15, no migration command; the key-order note and the schema, decisions and settings rows point to the table" {
  local doc="$REPO_ROOT/docs/record.md" section row
  section=$(awk '/^## Versioning/ { on = 1 } /^## Consent/ { on = 0 } on' "$doc")
  [ -n "$section" ] || { echo "no Versioning section before Consent"; false; }
  printf '%s\n' "$section" | grep -qE '^\|[^|]*`settings\.efforts`[^|]*\| *5 *\|' || { echo "no table row settings.efforts -> 5"; false; }
  printf '%s\n' "$section" | grep -qE '^\|[^|]*decision[^|]*plans[^|]*\| *6 *\|' || { echo "no table row for a decision's plans -> 6"; false; }
  printf '%s\n' "$section" | grep -qE '^\|[^|]*`settings\.mcp`[^|]*\| *7 *\|' || { echo "no table row settings.mcp -> 7"; false; }
  printf '%s\n' "$section" | grep -qE '^\|[^|]*tree[^|]*contract[^|]*\| *8 *\|' || { echo "no table row for a break with tree or contract -> 8"; false; }
  printf '%s\n' "$section" | grep -qE '^\|[^|]*amendment[^|]*await[^|]*queued[^|]*\| *9 *\|' || { echo "no table row for an amendment, an awaited check or a queued requirement -> 9"; false; }
  printf '%s\n' "$section" | grep -qE '^\|[^|]*test file forms[^|]*`test_files`[^|]*\| *10 *\|' || { echo "no table row for a list of test file forms -> 10"; false; }
  printf '%s\n' "$section" | grep -qE '^\|[^|]*`evidence\.own\.copy_slots`[^|]*\| *11 *\|' || { echo "no table row for a proof's copy_slots -> 11"; false; }
  printf '%s\n' "$section" | grep -qE '^\|[^|]*place[^|]*reworded[^|]*\| *12 *\|' || { echo "no table row for a break by place or a reworded requirement -> 12"; false; }
  [ "$(printf '%s\n' "$section" | grep -cE '^\|[^|]*\| *([5-9]|1[0-5]) *\|')" -eq 11 ] || { echo "the table has more or fewer than eleven rows"; false; }
  printf '%s\n' "$section" | grep -qiE 'floor' || { echo "the floor (4) is not named"; false; }
  printf '%s\n' "$section" | grep -qiE 'highest' || { echo "highest feature wins is not stated"; false; }
  printf '%s\n' "$section" | grep -qiE 'below[^.]*(load|read)[^.]*rais' || { echo "a record below its content loading and being raised is not stated"; false; }
  printf '%s\n' "$section" | grep -qiE 'above[^.]*corrupt' || { echo "a record above its content being corrupt is not stated"; false; }
  printf '%s\n' "$section" | grep -q '`VBW_SCHEMA_MAX`, currently 15' || { echo "VBW_SCHEMA_MAX, currently 15 is not stated"; false; }
  printf '%s\n' "$section" | grep -qi 'no migration command' || { echo "the docs no longer say there is no migration command"; false; }
  # The field rows point to the table instead of restating numbers.
  row=$(grep -E '^\| `schema` \|' "$doc")
  [[ "$row" == *"Versioning"* ]] || { echo "the schema row does not point to Versioning: $row"; false; }
  ! printf '%s\n' "$row" | grep -qE 'schema[- ]([5-9]|1[0-4])|`([5-9]|1[0-4])`' || { echo "the schema row restates numbers: $row"; false; }
  row=$(grep -E '^\| `decisions\[\]` \|' "$doc")
  ! printf '%s\n' "$row" | grep -qE 'schema[- ]6' || { echo "the decisions row restates schema 6: $row"; false; }
  row=$(grep -E '^\| `settings` \|' "$doc")
  ! printf '%s\n' "$row" | grep -qE 'schema[- ][57]' || { echo "the settings row restates schema 5 or 7: $row"; false; }
  ! awk 'BEGIN { RS = "" } { gsub(/\n/, " "); print }' "$doc" | grep -E 'Key order' | grep -qE '([5-9]|1[0-4]) while|schema ([5-9]|1[0-4])' || { echo "the key-order note restates numbers"; false; }
}

# R258 (T234): docs/record.md says a recorded break names its rule by place, {req, k},
# that a record written with the older {req, text} shape is converted once, at the first
# write that raises the schema, and that a full vbw apply which inserts or removes live
# rules in the middle of a requirement moves the places under the breaks that follow;
# the table's row 12 names the break by place and the reworded requirement. docs/proof.md's
# mutation-check section says a break is matched to its rule by its place, so rewording a
# rule keeps its breaks.

@test "R258 docs: docs/record.md's plans row and Versioning describe the break by place, its one-time conversion and the moving places of a full apply; docs/proof.md says a break follows its rule's place" {
  local doc="$REPO_ROOT/docs/record.md" proof="$REPO_ROOT/docs/proof.md" row section mut
  row=$(grep -E '^\| `plans\[\]` \|' "$doc")
  [ -n "$row" ] || { echo "no plans[] row"; false; }
  printf '%s\n' "$row" | grep -qF 'rule: {req, k}' || { echo "the plans row does not give the break's rule as {req, k}"; false; }
  printf '%s\n' "$row" | grep -qiE 'place' || { echo "the plans row does not say k is the rule's place"; false; }
  printf '%s\n' "$row" | grep -qiE 'full[^|.]*apply[^|.]*(move|place)|(move|place)[^|.]*full[^|.]*apply' || { echo "the plans row does not say a full vbw apply that inserts or removes live rules moves the places under later breaks"; false; }
  section=$(awk '/^## Versioning/ { on = 1 } /^## Consent/ { on = 0 } on' "$doc")
  printf '%s\n' "$section" | grep -qE '^\|[^|]*place[^|]*reworded[^|]*\| *12 *\|' || { echo "no table row for a break by place or a reworded requirement -> 12"; false; }
  printf '%s\n' "$section" | grep -qiE 'convert' || { echo "Versioning does not say the older {req, text} breaks are converted"; false; }
  printf '%s\n' "$section" | grep -qiE 'first write' || { echo "Versioning does not say the conversion happens at the first write"; false; }
  mut=$(awk '/^### The mutation check/{p=1; print; next} /^##(#)? /{p=0} p' "$proof")
  [ -n "$mut" ] || { echo "no section 'The mutation check' in docs/proof.md"; false; }
  printf '%s\n' "$mut" | grep -qiE 'by (its|the rule.s) place|place in the requirement|Rn\.k' || { echo "docs/proof.md does not say a break is matched to its rule by place"; false; }
  printf '%s\n' "$mut" | grep -qiE 'reword' || { echo "docs/proof.md does not say rewording a rule keeps its breaks"; false; }
}

# R265 and R264: each new key in a recorded break gets one row of its own (D614).
@test "R265 docs: docs/record.md's Versioning table has a row 13 for a break's digests, and the plans row describes the digests" {
  local doc="$REPO_ROOT/docs/record.md" section
  section=$(awk '/^## Versioning/ {p=1} p' "$doc")
  printf '%s\n' "$section" | grep -qE '^\|[^|]*digest[^|]*\| *13 *\|' || { echo "no table row for a break with digests -> 13"; false; }
  grep -E '^\| *`plans\[\]`' "$doc" | grep -qi 'digest' || { echo "the plans row does not describe the digests"; false; }
}

@test "R264 docs: docs/record.md's Versioning table has a row 14 for a none entry marked git" {
  local doc="$REPO_ROOT/docs/record.md" section
  section=$(awk '/^## Versioning/ {p=1} p' "$doc")
  printf '%s\n' "$section" | grep -qE '^\|[^|]*git[^|]*\| *14 *\|' || { echo "no table row for a git-marked none entry -> 14"; false; }
}

# R286 (D685): docs/record.md gives a break's digests as a list of {file, sha256}, says why
# (a secret scanner's keyword rule never meets a path and a digest on one line), has the
# table's row 15 and says an older VBW must be updated to read it; R287: docs/next.md
# describes the step a failed record commit stops at, with the three ways on and never
# skipping the project's hooks.
@test "R286 docs: docs/record.md's plans row gives the digests as a list of {file, sha256} kept off the path's line for secret scanners, the Versioning table has row 15, and an older VBW must update" {
  local doc="$REPO_ROOT/docs/record.md" section
  section=$(awk '/^## Versioning/ { on = 1 } /^## Consent/ { on = 0 } on' "$doc")
  printf '%s\n' "$section" | grep -qE '^\|[^|]*digest[^|]*list[^|]*red-first[^|]*\| *15 *\|' || { echo "no table row for a list of digests or red-first runs -> 15"; false; }
  printf '%s\n' "$section" | grep -qiE 'older VBW[^.]*(update|newer)|(update|newer)[^.]*older VBW' || { echo "Versioning does not say an older VBW must be updated"; false; }
  grep -E '^\| *`plans\[\]`' "$doc" | grep -qF '{file, sha256}' || { echo "the plans row does not give the digests as {file, sha256}"; false; }
  grep -qiE 'secret scanner' "$doc" || { echo "docs/record.md does not say why the digests are kept off the path's line"; false; }
}

@test "R287 docs: docs/next.md describes the step a failed record commit stops at, the hook's message, the three ways on, and that VBW never skips the project's hooks" {
  local doc="$REPO_ROOT/docs/next.md"
  grep -qE '`commit`' "$doc" || { echo "docs/next.md names no commit step"; false; }
  grep -qiE 'pre-commit hook' "$doc" || { echo "docs/next.md does not name the project's pre-commit hook"; false; }
  grep -qiE 'allow it in the checker' "$doc" || { echo "docs/next.md does not give the checker's settings way"; false; }
  grep -qiE 'commit the VBW files yourself' "$doc" || { echo "docs/next.md does not give the commit-yourself way"; false; }
  grep -qF -- '--no-verify' "$doc" || { echo "docs/next.md does not say VBW never passes --no-verify"; false; }
}
