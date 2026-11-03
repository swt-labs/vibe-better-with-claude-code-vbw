#!/usr/bin/env bats
# R150 (decision D232; docs/record.md): every record this VBW writes is format
# 4: schema 4, its keys beginning schema, lease, protected, checks, whatever the
# number of checks, protected being every file a check protects, each once,
# sorted (an empty list without checks). Each write keeps the list equal to the
# checks; a record an older VBW wrote (schema 1, 2 or 3, no list) is read by
# every command and becomes format 4 on its next write, with no migration
# command; a list that is missing, differs or sits on an older schema is
# corrupt, and the message names it. No 50-check threshold remains. L1.

load helper
load protected-helper
load fixture-helper

built_project() {
  vbw_setup
  protected_base
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# corrupt_everywhere: every command tried calls the record corrupt (exit 3)
# and names the protected field.
corrupt_everywhere() {
  local cmd
  for cmd in "status" "next --json" "show roadmap" "decide a-decision"; do
    # shellcheck disable=SC2086 # the command words split on purpose
    vbw_run $cmd
    [ "$status" -eq 3 ] || { echo "vbw $cmd: expected a corrupt record, got exit $status: $output"; return 1; }
    [[ "$output" == *corrupt*protected* ]] || { echo "vbw $cmd does not name the protected field: $output"; return 1; }
  done
}

@test "R150: vbw init and every later write leave a format-4 record, with an empty list when there are no checks" {
  format4
  jq -e '.protected == [] and .checks == []' .vbw/record.json
  "$VBW" decide "Start small" > /dev/null
  format4
  jq -e '.protected == [] and .decisions[-1].text == "Start small"' .vbw/record.json
  "$VBW" todo add "Gift cards" > /dev/null
  format4
  jq -e '.protected == []' .vbw/record.json
}

@test "R150: with 1, 50, 51 and 2,000 checks the record is format 4 and protected holds every check file once, sorted" {
  local n
  for n in 1 50 51 2000; do
    protected_apply "$n"
    jq -e --argjson n "$n" '(.checks | length) == $n' .vbw/record.json
    format4 || { echo "with $n checks"; false; }
    [ "$(jq -c '.protected' .vbw/record.json)" = "$(protected_union)" ]
  done
  jq -e '.protected | length == 2000 and . == unique and index("tests/shared.sh") != null and index("tests/c2000.sh") == null' .vbw/record.json
}

@test "R150: a check with no files adds nothing and a file several checks share appears once" {
  protected_apply 1
  format4
  jq -e '.protected == []' .vbw/record.json
  protected_apply 3
  format4
  jq -e '.protected == ["tests/c1.sh", "tests/c2.sh", "tests/shared.sh"]' .vbw/record.json
}

@test "R150: a contract change that adds, removes or edits a check updates the list in the same write" {
  protected_apply 4
  jq -e '.protected == ["tests/c1.sh", "tests/c2.sh", "tests/c3.sh", "tests/shared.sh"]' .vbw/record.json
  # Edit: C3 now protects another file; tests/c3.sh is named by no check and leaves.
  protected_doc 4 | jq -c '{checks: [.checks[] | select(.id == "C3") | .files = ["tests/other.sh"]]}' | "$VBW" apply --patch > /dev/null
  format4
  jq -e '.protected == ["tests/c1.sh", "tests/c2.sh", "tests/other.sh", "tests/shared.sh"]' .vbw/record.json
  # Add: a new check names a new file, which joins.
  jq -nc '{checks: [{id: "C9", req: "R1", run: ["sh", "tests/new.sh"], files: ["tests/new.sh"]}]}' | "$VBW" apply --patch > /dev/null
  format4
  jq -e '.protected | index("tests/new.sh") != null' .vbw/record.json
  # Remove: a plan again without C3 (and without C9); the files no check names
  # any more leave, the shared one stays.
  protected_apply 4 '.checks |= map(select(.id != "C3"))'
  format4
  jq -e '.protected == ["tests/c1.sh", "tests/c2.sh", "tests/shared.sh"]' .vbw/record.json
}

@test "R150: a record an older VBW wrote (schema 1, 2 or 3, no list) is read by every command and becomes format 4 on its next write, all else kept" {
  local older cmd before
  for older in 1 2 3; do
    rm -rf .vbw .git src tests
    protected_base
    case "$older" in
      1) protected_apply 3 ;;
      2) protected_apply 3 '.checks[0].alone = true' ;;
      3) protected_apply 3 && "$VBW" todo add --sort later --size small "Gift cards" > /dev/null ;;
    esac
    as_older
    jq -e --argjson s "$older" '.schema == $s and (has("protected") | not)' .vbw/record.json
    before=$(cksum < .vbw/record.json)
    for cmd in "status" "next --json" "show roadmap" "show contract" "show requirements" "todo list" "doctor"; do
      # shellcheck disable=SC2086 # the command words split on purpose
      vbw_run $cmd
      [[ "$output" != *corrupt* ]] || { echo "schema $older, vbw $cmd: $output"; false; }
      [ "$cmd" = doctor ] || [ "$status" -eq 0 ] || { echo "schema $older, vbw $cmd: $output"; false; }
    done
    [ "$(cksum < .vbw/record.json)" = "$before" ]
    cp .vbw/record.json "$TEST_ROOT/older.json"
    vbw_run decide "Keep every check"
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    format4 || { echo "from schema $older"; false; }
    [ "$(jq -cS 'del(.schema, .protected, .decisions)' .vbw/record.json)" = "$(jq -cS 'del(.schema, .protected, .decisions)' "$TEST_ROOT/older.json")" ]
    jq -e --slurpfile o "$TEST_ROOT/older.json" '.decisions == $o[0].decisions + [.decisions[-1]] and .decisions[-1].text == "Keep every check"' .vbw/record.json
  done
}

@test "R150: there is no migration command" {
  vbw_run migrate
  [ "$status" -ne 0 ]
  vbw_run --help
  [[ "$output" != *migrat* ]] || { echo "$output"; false; }
}

@test "R150: a schema-4 record without the list is corrupt for every command, which names the protected field" {
  protected_apply 3
  record_edit 'del(.protected)'
  jq -e '.schema == 4' .vbw/record.json
  corrupt_everywhere
}

@test "R150: a list that differs from the checks' files is corrupt: one missing, one extra, out of order, repeated or not a list" {
  protected_apply 3
  cp .vbw/record.json "$TEST_ROOT/good.json"
  vbw_run status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local f
  for f in '.protected |= .[1:]' '.protected += ["tests/zzz.sh"]' '.protected |= reverse' '.protected += [.protected[0]]' '.protected = "tests/c1.sh"' '.checks[0].files += ["tests/late.sh"]'; do
    cp "$TEST_ROOT/good.json" .vbw/record.json
    record_edit "$f"
    corrupt_everywhere || { echo "accepted: $f"; false; }
  done
  cp "$TEST_ROOT/good.json" .vbw/record.json
  record_edit '.checks = [] | .requirements |= map(.proof = "human" | del(.rules))'
  corrupt_everywhere
}

@test "R150: a record below schema 4 that carries a protected list is corrupt for every command" {
  local s
  protected_apply 3
  cp .vbw/record.json "$TEST_ROOT/good.json"
  for s in 1 2 3; do
    cp "$TEST_ROOT/good.json" .vbw/record.json
    record_edit ".schema = $s"
    [ "$s" != 2 ] || record_edit '.checks[0].alone = true'
    [ "$s" != 3 ] || record_edit '.todos = [{id: "T1", text: "Gift cards", status: "open", sort: "later", size: "small"}]'
    corrupt_everywhere || { echo "accepted schema $s with a list"; false; }
  done
}

@test "R150: the writer and the validator hold no 50-check threshold" {
  local f
  for f in "$PLUGIN_ROOT/lib/record.sh" "$PLUGIN_ROOT/lib/record.jq"; do
    ! grep -nE '>[[:space:]]*50([^0-9]|$)|\$big|50 checks' "$f" || { echo "a 50-check threshold remains in $f"; false; }
  done
}
