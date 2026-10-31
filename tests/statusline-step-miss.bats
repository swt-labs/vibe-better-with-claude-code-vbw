#!/usr/bin/env bats
# R235 (T205, plan P189.2, L1): the one miss of the R190 bench case 'status line
# (step running)' (PR #740, Linux bash 5 shard 3: "first line: " empty, no text
# in statusline.err) came from the status line's EXIT STATUS, not from its
# text. The bench reads the first line through `status line | head -n 1` under
# `set -o pipefail`; head leaves as soon as it has line 1, and bash 5.2 on
# Linux writes the answer in more than one piece, so a piece written after
# head's exit killed the script with SIGPIPE (141), the pipeline failed and the
# bench took "" for the line. Evidence (counts):
#   probe (a four-line answer written by `printf '%s\n' "$out"` into
#   `| head -n 1`, pipefail on, 2500 to 1500 runs): ubuntu:24.04 (bash 5.2.21)
#   2 to 5 failures per run; Mac bash 5.3 and /bin/bash 3.2 0; the bench case
#   itself, 20 runs: ubuntu:24.04 1 miss with an empty first line, ubuntu:26.04
#   0, this Mac 0.
#   The fix (trap '' PIPE and a quiet write at the end of vbw-statusline.sh)
#   gave 0 failures in 2500 on ubuntu:24.04.
# Ruled out, each with a crafted note and a set clock (below): a jq failure in
# the render (the error file was empty in the miss; the render is the same on
# jq 1.7 and 1.8.1), mins() with a start in the same minute, a glance written in
# the record's second, and "tomorrow" across midnight in any zone.
# Without the fix the first test fails: the status of the script is 141.

load helper
load step-helper
load fixture-helper

step_line_project() {
  vbw_setup
  step_project
  SL="$PLUGIN_ROOT/scripts/vbw-statusline.sh"
}

setup_file() { fixture_build step-miss step_line_project; }
setup() {
  fixture_copy step-miss
  "$VBW" run start build P1.1 P1.2 > /dev/null
  jq -nc --arg d "$PROJECT" '{session_id: "s1", workspace: {project_dir: $d, current_dir: $d}, model: {display_name: "Opus"}}' > "$TEST_ROOT/in.json"
}
teardown_file() { fixture_teardown; }
teardown() { vbw_teardown; }

# note START END: the open run's build note, started START seconds from now and
# ending END seconds from now (as the bench's step.json does).
note() {
  jq -n --slurpfile r .vbw/record.json --argjson a "$1" --argjson b "$2" 'def s($n): (now | floor) + $n | todateiso8601;
    {kind: "build", run: $r[0].lease.run, session: "s1", pid: null, started_at: s($a), ids: ["P1.1", "P1.2"], doing: "building P1.1, P1.2",
     parts: {done: 1, total: 2}, proof: null, first_end: s($b), end: s($b), late: false}' > "$NOTE"
}

# The bench's own test of the first line (tools/bench-hooks.sh).
shown() {
  case "$1" in
    *"1 of 2 · "*" min, until around "[0-9][0-9]:[0-9][0-9]* | *"1 of 2 · "*" min, until around tomorrow "[0-9][0-9]:[0-9][0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

@test "R235: a reader that leaves early does not fail the status line (SIGPIPE ignored, status 0)" {
  note -300 720
  # Deterministic form of the miss: the reader is gone before the answer is written.
  set -o pipefail
  NO_COLOR=1 bash "$SL" < "$TEST_ROOT/in.json" | true
  [ "${PIPESTATUS[0]}" -eq 0 ]
  # The bench's form: the first line only.
  for _ in 1 2 3 4 5; do
    first=$(NO_COLOR=1 bash "$SL" < "$TEST_ROOT/in.json" | head -n 1)
    shown "$first" || { echo "$first"; false; }
  done
}

@test "R235: the step shows at local times around midnight, in any zone (the day word is tomorrow or none)" {
  note -300 720
  # The same clock the note's times come from (jq's now), read once to place the zones.
  now=$(jq -n 'now | floor')
  # Local clocks 23:40 to 00:10, as POSIX zones (east of UTC is "-"): the step ends 12 minutes ahead.
  for want in 1420 1430 1438 1439 0 5 10; do
    off=$(((want - (now / 60 % 1440) + 2880) % 1440))
    [ "$off" -le 720 ] || off=$((off - 1440))
    if [ "$off" -ge 0 ]; then sign=-; a=$off; else sign=+; a=$((-off)); fi
    tz=$(printf 'XXX%s%d:%02d' "$sign" $((a / 60)) $((a % 60)))
    first=$(TZ="$tz" NO_COLOR=1 bash "$SL" < "$TEST_ROOT/in.json" | head -n 1)
    shown "$first" || { echo "TZ=$tz: $first"; false; }
  done
}

@test "R235: a start inside the same minute leaves the minutes out and still shows the end" {
  note -10 720
  run bash -c "NO_COLOR=1 bash '$SL' < '$TEST_ROOT/in.json' | head -n 1"
  [[ "${lines[0]}" == *"1 of 2 · until around "* ]] || { echo "${lines[0]}"; false; }
}

@test "R235: a glance written in the record's second does not hide the step" {
  note -300 720
  [ -f .vbw/runtime/glance.json ] || cp .vbw/record.json .vbw/runtime/glance.json
  touch -r .vbw/record.json .vbw/runtime/glance.json
  first=$(NO_COLOR=1 bash "$SL" < "$TEST_ROOT/in.json" | head -n 1)
  shown "$first" || { echo "$first"; false; }
  [ ! -s .vbw/runtime/statusline.err ] || { cat .vbw/runtime/statusline.err; false; }
}
