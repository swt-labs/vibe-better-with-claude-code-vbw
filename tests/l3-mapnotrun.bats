#!/usr/bin/env bats
# R228 (#733, D534): the real-user scenario `mapnotrun` in tools/l3-suite.sh (L3, the
# real Claude Code TUI): a project with two test suites, one the map ran green and one
# the map did not run and which is red today. The router chooses the spec's ## Commands
# from the map's Tests section: the green command (or the narrower one-test-file
# command) goes in, the red suite does not go in silently, and a dated decision names
# it. Judged in .vbw/spec.md, the record and the transcripts' tool calls, never on
# screen. As in tests/l3-mapsnapshot.bats these tests do not run Claude Code (L1):
# they hold the scenario's structure, and its committed result once a run wrote one,
# to facts from files.

load helper

SUITE="$REPO_ROOT/tools/l3-suite.sh"
RESULTS="$REPO_ROOT/tools/l3-results"

setup() { vbw_setup; }
teardown() { vbw_teardown; }

body() { sed -n "/^scenario_$1()/,/^}/p" "$SUITE"; }

@test "R228: the mapnotrun scenario exists, is in the default list and is named in the suite's header" {
  grep -q '^scenario_mapnotrun()' "$SUITE"
  grep -E '^ALL=' "$SUITE" | grep -qw mapnotrun
  sed -n '1,20p' "$SUITE" | grep -qw mapnotrun
}

@test "R228: it seeds two suites, one green and one red that the README marks as expensive, and judges .vbw/spec.md, the record and the transcripts" {
  [ -n "$(body mapnotrun)" ]
  body mapnotrun | grep -q 'result_write mapnotrun '
  body mapnotrun | grep -qi 'fixture='
  local seed
  seed=$(sed -n '/^mapnotrun_seed()/,/^}/p' "$SUITE")
  [ -n "$seed" ] || { echo "no mapnotrun_seed function"; false; }
  printf '%s\n' "$seed" | grep -qF 'not ok'
  printf '%s\n' "$seed" | grep -qF 'README.md'
  [ "$(printf '%s\n' "$seed" | grep -cE 'cat > [a-z0-9._-]*\.sh <<|> [a-z0-9._-]*\.sh( |$)|chmod \+x [a-z0-9._-]*\.sh')" -ge 2 ]
  body mapnotrun | grep -qF '.vbw/spec.md'
  body mapnotrun | grep -qF '## Commands'
  body mapnotrun | grep -qF '.vbw/map.md'
  body mapnotrun | grep -qF 'Not run'
  body mapnotrun | grep -qF 'decisions'
  body mapnotrun | grep -qF 'transcript_tool_called'
  if body mapnotrun | grep -qE 'screen \|.*grep'; then false; fi
}

@test "R228: the result states each fact the scenario judged" {
  local k
  for k in map_marks_not_run commands_lines green_in_commands red_in_commands narrower_in_commands red_decision red_suite_ran; do
    body mapnotrun | grep -qF "$k" || { echo "fact $k is not judged"; false; }
  done
}

@test "R228: a committed result of the mapnotrun scenario, when there is one, is labelled honestly" {
  local f="$RESULTS/mapnotrun.json"
  [ -f "$f" ] || skip "no mapnotrun result committed yet: a run writes it"
  jq -e '.scenario == "mapnotrun" and .passed == true and .evidence_level == "L3"
    and (.fixture | type == "string" and length > 0) and (.cost_usd | type == "number" and . > 0)
    and (.facts | type == "object") and (.not_tested | type == "array" and length > 0)
    and .facts.green_in_commands == true and .facts.red_in_commands == false
    and (.facts.red_decision | type == "string" and length > 0)' "$f"
}

@test "R228: the red suite's seed prints not ok and exits 1, the green one prints ok and exits 0" {
  local seed
  seed=$(sed -n '/^mapnotrun_seed()/,/^}/p' "$SUITE")
  printf '%s\n' "$seed" | sed -n "/cat > e2e.sh/,/^SH\$/p" | grep -qF 'echo "not ok'
  printf '%s\n' "$seed" | sed -n "/cat > e2e.sh/,/^SH\$/p" | grep -qF 'exit 1'
  if printf '%s\n' "$seed" | sed -n "/cat > e2e.sh/,/^SH\$/p" | grep -qF 'echo "ok'; then false; fi
  printf '%s\n' "$seed" | sed -n "/cat > test.sh/,/^SH\$/p" | grep -qF 'echo "ok 1'
}

@test "R228: the scenario judges the red suite in ## Commands from the spec's lines and passes only without it" {
  body mapnotrun | grep -qF "grep 'e2e' > /dev/null && red=true"
  body mapnotrun | grep -qF 'expect "## Commands does not hold the red suite ($red)" [ "$red" = false ]'
  body mapnotrun | grep -qF 'expect "## Commands holds the green command ($green)" [ "$green" = true ]'
}

# R237 (T203): the suite reads a spec section without its HTML comments. One helper,
# spec_section_lines SPEC SECTION, prints the section's '- ' lines after dropping every
# <!-- ... --> block, single-line or multi-line; commands_lines calls it, and no scenario
# pipes the raw section into grep '^- ' any more, so a command written only inside the
# template's comment (plugin/lib/cmd-init.sh: '- test: npm test') is never judged present.

helper_src() { sed -n '/^spec_section_lines()/,/^}/p' "$SUITE"; }
# section_lines SPEC SECTION: the helper, taken from the suite's text, run on SPEC.
section_lines() {
  local src
  src=$(helper_src)
  [ -n "$src" ] || { echo "no spec_section_lines in the suite"; return 1; }
  bash -c "$src"$'\n''spec_section_lines "$1" "$2"' _ "$1" "$2"
}

@test "R237: on the template's spec (vbw init) the helper prints no command; a command written after the comment is the only line printed" {
  vbw_git_project
  "$VBW" init > /dev/null
  grep -q '^- test: npm test' .vbw/spec.md || { echo "the template no longer holds the commented commands"; false; }
  run section_lines .vbw/spec.md Commands
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "status $status, output: $output"; false; }
  printf -- '- test: sh test.sh\n' >> .vbw/spec.md
  run section_lines .vbw/spec.md Commands
  [ "$status" -eq 0 ] && [ "$output" = "- test: sh test.sh" ] || { echo "status $status, output: $output"; false; }
}

@test "R237: a comment that opens and closes on one line between two real lines drops only itself; a multi-line block drops its lines; another section's lines never print" {
  printf '# x\n\n## Requirements\n\n- R1 [auto] One\n\n## Commands\n\n- test: sh a.sh\n<!-- - lint: sh x.sh -->\n- build: sh b.sh\n<!--\n- old: sh y.sh\n- older: sh z.sh\n-->\n- e2e: sh c.sh\n\n## Other\n\n- not: a command\n' > "$TEST_ROOT/spec.md"
  run section_lines "$TEST_ROOT/spec.md" Commands
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "${lines[0]}" = "- test: sh a.sh" ] && [ "${lines[1]}" = "- build: sh b.sh" ] && [ "${lines[2]}" = "- e2e: sh c.sh" ] && [ "${#lines[@]}" -eq 3 ] || { echo "$output"; false; }
}

@test "R237: commands_lines calls the helper, and no scenario pipes a raw spec section into grep '^- '" {
  body mapnotrun | grep -q 'spec_section_lines' || { echo "commands_lines does not call spec_section_lines"; false; }
  ! body mapnotrun | grep -qF "sed -n '/^## Commands/,/^## /p' \"\$spec\" 2> /dev/null | grep -E '^- '" || { echo "the raw sed | grep form is still there"; false; }
  ! grep -nE "sed -n '/\^## [A-Za-z ]+/,/\^## /p'[^|]*\| *grep -E? *'\^- '" "$SUITE" || { echo "a scenario still reads a raw section"; false; }
}
