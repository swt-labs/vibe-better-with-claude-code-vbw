#!/usr/bin/env bats
# R279 (measured at 2.1.28: 450 of 743 units ran again after a bump, D686): a version bump
# reruns only the proof units whose outcome can depend on the version. The kernel reads
# its own version for the writer file (R272) on every record write; when the proof names a
# file for it (VBW_KERNEL_READS, set for each unit), the kernel logs that read there and
# leaves plugin.json's access time as it was, so the proof keeps it apart from the unit's
# own reads (kernel_reads beside reads). vbw prove after a change of only the version
# reuses a unit whose only contact with plugin.json is that read, reruns a unit that
# prints or compares the version, and says why for each unit that ran again; any other
# change to plugin.json reruns both, as before. L1: a project holding a copy of the
# plugin under test, whose test files run that copy's kernel.

load helper
load fixture-helper

PJ='plugin/.claude-plugin/plugin.json'

versioned() {
  vbw_setup
  vbw_git_project
  cp -R "$PLUGIN_ROOT" plugin
  mkdir -p tests
  # Prints and compares the version: its outcome depends on it.
  printf '[ "$(plugin/bin/vbw version)" = "$(jq -r .version %s)" ]\n' "$PJ" > tests/t_compare.sh
  # Writes a record with the copy's kernel in a project of its own: the kernel reads the version, the test does not.
  printf 'd=$(mktemp -d "$TEST_ROOT/unit.XXXXXX") || exit 1\nk="$PWD/plugin/bin/vbw"\ncd "$d" && git init -q && "$k" init > /dev/null && [ -f .vbw/record.json ]\n' > tests/t_record.sh
  git add -A && git commit -q -m "chore(test): versioned project"
  "$VBW" init > /dev/null
  printf '# Plugin\n\n## Requirements\n\n- R1 [auto] The plugin works\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  printf 'exit 0\n' > tests/c1.sh
  jq -nc '{phases: [{id: "P1", title: "Plugin", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Plugin", reqs: ["R1"], files: ["plugin/"], after: [], role: "dev", tasks: ["t"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/c1.sh"], files: ["tests/c1.sh"]}],
    rules: [{req: "R1", text: "it works", check: "C1"}]}' | "$VBW" apply > /dev/null
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  [ -z "$(git status --porcelain)" ] || { git add -A && git commit -q -m "chore(vbw): approve"; }
  "$VBW" prove > /dev/null
}
setup_file() { fixture_build versioned versioned; }
setup() { fixture_copy versioned; }
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# change FILTER: plugin.json changed by FILTER (plugin/VERSION follows the version), committed.
change() {
  jq "$1" "$PJ" > "$TEST_ROOT/p.json" && cp "$TEST_ROOT/p.json" "$PJ"
  jq -r .version "$PJ" > plugin/VERSION
  git commit -q -am "chore(test): change plugin.json"
}
tf() { jq -c --arg f "$1" '.evidence.test_files[$f] | {status, reused: (.reused // false), why: (.why // null)}' .vbw/record.json; }

@test "R279 kernel: with VBW_KERNEL_READS set, a record write logs the kernel's read of plugin.json there and leaves its access time; vbw version is the caller's own read and logs nothing" {
  local d log at0 at1
  d=$(mktemp -d "$TEST_ROOT/k.XXXXXX")
  log="$TEST_ROOT/kernel-reads"
  touch -a -t 200001010000 "$PJ"
  at0=$(ls -lu "$PJ" | awk '{print $6, $7, $8}')
  (cd "$d" && git init -q && VBW_KERNEL_READS="$log" "$PROJECT/plugin/bin/vbw" init > /dev/null)
  at1=$(ls -lu "$PJ" | awk '{print $6, $7, $8}')
  [ "$at0" = "$at1" ] || { echo "the record write moved plugin.json's access time: $at0 -> $at1"; false; }
  grep -qxF "$PROJECT/$PJ" "$log" || { echo "the kernel's read is not logged: $(cat "$log" 2> /dev/null)"; false; }
  : > "$log"
  VBW_KERNEL_READS="$log" plugin/bin/vbw version > /dev/null
  [ ! -s "$log" ] || { echo "vbw version logged a kernel read: $(cat "$log")"; false; }
  [ "$(ls -lu "$PJ" | awk '{print $6, $7, $8}')" != "$at0" ] || { echo "vbw version did not read plugin.json"; false; }
}

@test "R279 prove: after a change of only the version, the unit that compares the version runs again and says why; the unit that only writes a record is reused" {
  change '.version = "9.9.9"'
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  tf tests/t_compare.sh | jq -e --arg w "reads the version: $PJ" '.reused == false and .why == $w' || { tf tests/t_compare.sh; false; }
  tf tests/t_record.sh | jq -e '.reused == true' || { tf tests/t_record.sh; false; }
  printf '%s\n' "$output" | grep -F 'tests/t_compare.sh' | grep -qF "reads the version: $PJ" || { echo "the run does not say why t_compare.sh ran again:"; echo "$output"; false; }
  ! printf '%s\n' "$output" | grep -F 'tests/t_record.sh' | grep -qiE 'ran again|reads the version|changed' || { echo "$output"; false; }
}

@test "R279 prove: any other change to plugin.json reruns both units, the reason as before" {
  change '.description = "another description"'
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  tf tests/t_compare.sh | jq -e '.reused == false' || { tf tests/t_compare.sh; false; }
  tf tests/t_record.sh | jq -e --arg w "$PJ changed" '.reused == false and .why == $w' || { tf tests/t_record.sh; false; }
}

@test "R279 docs: docs/proof.md says a change of only the version reruns only the units that read the version themselves, and names the kernel's own reads" {
  grep -qiE 'reads the version' "$REPO_ROOT/docs/proof.md" || { echo "docs/proof.md does not give the reason 'reads the version'"; false; }
  grep -qF 'VBW_KERNEL_READS' "$REPO_ROOT/docs/proof.md" || { echo "docs/proof.md does not name the kernel's own reads"; false; }
}
