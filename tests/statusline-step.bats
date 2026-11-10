#!/usr/bin/env bats
# R190, phase P147 (L1): while a step runs, the status line's first line shows
# the step, what it is doing and the clock time only (D425), read from the
# kernel's note (.vbw/runtime/step.json), never worked out by the status line:
# '● working: building P1.1, P1.2 · 1 of 2 · 5 min, until around 14:20'; a background proof 'proving 12 of
# 40 checks · 1 min, until around 14:26'; later than usual 'until around 14:35, later than usual'; a
# late step without parts 'until around 14:20, 6 min late'; no basis: the step and what
# it is doing, no time. Clock times are the computer's local time, 24-hour
# HH:MM; an end on another day names the day ('until around tomorrow 00:20'). A note
# whose run is not the open run, or whose proof process is gone, shows nothing.
# The times here are local to Europe/Zurich (UTC+01:00, +02:00 in summer), so a UTC clock shows.

load helper
load step-helper
load fixture-helper

step_line_project() {
  vbw_setup
  step_project
  SL="$PLUGIN_ROOT/scripts/vbw-statusline.sh"
  export TZ=Europe/Zurich
}

setup_file() { fixture_build step-line step_line_project; }
setup() {
  fixture_copy step-line
  # R284: the clock is set, for the kernel and the status line alike.
  export VBW_NOW=2030-01-15T10:00:00Z
  sleep 30 &
  LIVE=$!
}
teardown_file() { fixture_teardown; }

teardown() {
  kill "$LIVE" 2> /dev/null || true
  wait 2> /dev/null || true
  vbw_teardown
}

render() {
  jq -nc --arg d "$PROJECT" '{session_id: "s1", workspace: {project_dir: $d, current_dir: $d}, model: {display_name: "Sonnet 5.5"}, version: "2.1.286"}' \
    | NO_COLOR=1 bash "$SL"
}

# hm FIELD: the local HH:MM of the note's FIELD (end or first_end)., after "tomorrow " or
# "yesterday " when it falls on another local day than now, as VBW words it:
# the test holds at any hour, local midnight included.
hm() {
  jq -r --arg f "$1" '(.[$f] | fromdateiso8601) as $t | ([$t, ($ENV.VBW_NOW | fromdateiso8601)] | map(strflocaltime("%Y-%m-%d"))) as [$e, $d]
    | (if $e == $d then "" elif $e > $d then "tomorrow " else "yesterday " end) + ($t | strflocaltime("%H:%M"))' "$NOTE"
}

# note FILTER: write the note: the open run's, a build of P1.1 and P1.2 started
# 5 min ago, ending in 12 min, then FILTER (times as seconds from the set clock, VBW_NOW: s(N)).
note() {
  jq -n --slurpfile r .vbw/record.json "def s(\$n): (\$ENV.VBW_NOW | fromdateiso8601) + \$n | todateiso8601;
    {kind: \"build\", run: \$r[0].lease.run, session: \"s1\", pid: null, started_at: s(-300), ids: [\"P1.1\", \"P1.2\"],
     doing: \"building P1.1, P1.2\", parts: {done: 1, total: 2}, proof: null, first_end: s(720), end: s(720), late: false} | $1" > "$NOTE"
}

@test "R190: a build shows the step, its plans, parts done and the clock time only" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  note .
  run render
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"● working: building P1.1, P1.2 · 1 of 2 · 5 min, until around $(hm end)"* ]] || { echo "${lines[0]}"; false; }
  [[ "${lines[0]}" != *"about"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190: a background proof shows 'proving N of M checks' and its clock time, and counts up" {
  jq -n --argjson pid "$LIVE" 'def s($n): ($ENV.VBW_NOW | fromdateiso8601) + $n | todateiso8601;
    {kind: "proof", run: null, session: "s1", pid: $pid, started_at: s(-60), ids: [], doing: "proving 12 of 40 checks",
     parts: {done: 12, total: 40}, proof: {done: 12, total: 40}, first_end: s(480), end: s(480), late: false}' > "$NOTE"
  run render
  [[ "${lines[0]}" == *"proving 12 of 40 checks · 1 min, until around $(hm end)"* ]] || { echo "${lines[0]}"; false; }
  jq '.parts.done = 13 | .proof.done = 13 | .doing = "proving 13 of 40 checks"' "$NOTE" > "$TEST_ROOT/n.json" && cp "$TEST_ROOT/n.json" "$NOTE"
  run render
  [[ "${lines[0]}" == *"proving 13 of 40 checks · 1 min, until around $(hm end)"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190: a proof inside a fix shows as what the fix is doing; the time stays the fix's" {
  step_edit '.plans[].status = "done" | .fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "C1 fail"}]'
  git add -A && git commit -q -m "chore(vbw): fix"
  "$VBW" run start fix F1 > /dev/null
  note '.kind = "fix" | .ids = ["F1"] | .parts = {done: 0, total: 1} | .proof = {done: 12, total: 40} | .doing = "proving 12 of 40 checks"'
  run render
  [[ "${lines[0]}" == *"● working: fix F1"* ]] || { echo "${lines[0]}"; false; }
  [[ "${lines[0]}" == *"proving 12 of 40 checks"*"until around $(hm end)"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190: a late step with parts shows its moved clock time, later than usual" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  note '.first_end = s(-120) | .end = s(900) | .late = true'
  run render
  [[ "${lines[0]}" == *"until around $(hm end), later than usual"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190 (F246): a step with parts past its end that the kernel has not moved says later than usual too" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  note '.first_end = s(-120) | .end = s(-120) | .late = false | .parts = {done: 0, total: 2}'
  run render
  [[ "${lines[0]}" == *"until around $(hm end), later than usual"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190: a late step without parts keeps its clock time and says how many minutes late" {
  "$VBW" run start plan > /dev/null
  note '.kind = "plan" | .ids = [] | .doing = "planning" | .parts = null | .first_end = s(-380) | .end = s(-380)'
  run render
  [[ "${lines[0]}" == *"until around $(hm first_end), 6 min late"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190: with no basis the step and what it is doing show, with no time" {
  step_edit '.phases[0].tier = "standard" | .plans[].status = "done"'
  git add -A && git commit -q -m "chore(vbw): built"
  "$VBW" run start qa > /dev/null
  note '.kind = "qa" | .ids = ["P1"] | .doing = "checking P1" | .parts = null | .first_end = null | .end = null'
  run render
  [[ "${lines[0]}" == *"● working: checking P1"* ]] || { echo "${lines[0]}"; false; }
  [[ "${lines[0]}" != *"until"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190: an end on another day names the day, in 24-hour local time" {
  export TZ=UTC
  "$VBW" run start build P1.1 P1.2 > /dev/null
  # 00:20 tomorrow, UTC.
  jq -n --slurpfile r .vbw/record.json '($ENV.VBW_NOW | fromdateiso8601) as $t | ($t - ($t % 86400) + 86400 + 1200) as $e
    | {kind: "build", run: $r[0].lease.run, session: "s1", pid: null, started_at: ($t - 300 | todateiso8601), ids: ["P1.1", "P1.2"],
       doing: "building P1.1, P1.2", parts: {done: 1, total: 2}, proof: null, first_end: ($e | todateiso8601), end: ($e | todateiso8601), late: false}' > "$NOTE"
  run render
  [[ "${lines[0]}" == *"until around tomorrow 00:20"* ]] || { echo "${lines[0]}"; false; }
}

@test "R190: a note whose run is not the open run, or whose proof process is gone, shows no step" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  # The open run's own note shows; the same note of another run does not.
  note .
  run render
  [[ "${lines[0]}" == *"1 of 2 · 5 min, until around"* ]] || { echo "${lines[0]}"; false; }
  note '.run = "build-20200101T000000Z"'
  run render
  [[ "${lines[0]}" != *"until"* && "${lines[0]}" != *"1 of 2"* ]] || { echo "${lines[0]}"; false; }
  "$VBW" run end > /dev/null
  note .
  run render
  [[ "${lines[0]}" != *"▶"* ]] || { echo "${lines[0]}"; false; }
  local gone
  sh -c 'exit 0' &
  gone=$!
  wait "$gone" || true
  jq -n --argjson pid "$gone" 'def s($n): ($ENV.VBW_NOW | fromdateiso8601) + $n | todateiso8601;
    {kind: "proof", run: null, session: "s1", pid: $pid, started_at: s(-60), ids: [], doing: "proving 12 of 40 checks",
     parts: {done: 12, total: 40}, proof: {done: 12, total: 40}, first_end: s(480), end: s(480), late: false}' > "$NOTE"
  run render
  [[ "$output" != *"proving"* && "$output" != *"step_pid"* ]] || { echo "$output"; false; }
}

@test "R190: the status line works no time out itself: with the run open and no note, no end time" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  note .
  run render
  [[ "${lines[0]}" == *"until"* ]] || { echo "${lines[0]}"; false; }
  rm -f "$NOTE"
  run render
  [[ "${lines[0]}" != *"until"* ]] || { echo "${lines[0]}"; false; }
}

# The state cell (docs/statusline.md): one clear state, colour coded like the panel.

# render_color: line 1 with colour on.
render_color() {
  jq -nc --arg d "$PROJECT" '{session_id: "s1", workspace: {project_dir: $d}, version: "2.1.286"}' | bash "$SL" | head -1
}

# hm_of FILE FIELD: the local clock of FILE's FIELD as the status line words it: today
# bare, tomorrow, yesterday, else the weekday, by calendar day (so 25 hours ago just after
# midnight is the day before yesterday).
hm_of() {
  jq -r --arg f "$2" 'def day($e): $e | localtime | mktime / 86400 | floor;
    (.[$f] | fromdateiso8601) as $t | (day($t) - day($ENV.VBW_NOW | fromdateiso8601)) as $d
    | (if $d == 0 then "" elif $d == 1 then "tomorrow " elif $d == -1 then "yesterday " else ($t | strflocaltime("%A ")) end) + ($t | strflocaltime("%H:%M"))' "$1"
}

@test "C1: a running step reads 'working', what it is doing, minutes so far and 'until around' its clock time, in the accent colour" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  note .
  run render
  [[ "${lines[0]}" == *"│ ● working: building P1.1, P1.2 · 1 of 2 · 5 min, until around $(hm end)" ]] || { echo "${lines[0]}"; false; }
  out=$(render_color)
  [[ "$out" == *$'\033[38;5;141m● working: building'* ]] || { echo "$out" | od -c | head; false; }
}

@test "C1: a gate reads 'needs you', the action and since when, in amber" {
  jq -nc 'def s($n): ($ENV.VBW_NOW | fromdateiso8601) + $n | todateiso8601; {action: "approve", gate: true, instruction: "x", detail: {}, since: s(-90000)}' > .vbw/runtime/next.json
  run render
  [[ "${lines[0]}" == *"│ ⚑ needs you: approve · since $(hm_of .vbw/runtime/next.json since)" ]] || { echo "${lines[0]}"; false; }
  out=$(render_color)
  [[ "$out" == *$'\033[38;5;214m⚑ needs you: approve'* ]] || { echo "$out" | od -c | head; false; }
}

@test "C1: a gate with no 'since' still reads 'needs you' and the action" {
  printf '%s\n' '{"action":"approve","gate":true,"instruction":"x","detail":{}}' > .vbw/runtime/next.json
  run render
  [[ "${lines[0]}" == *"│ ⚑ needs you: approve" ]] || { echo "${lines[0]}"; false; }
}

@test "C1: a shipped milestone reads 'idle' with when it shipped, in green" {
  step_edit '.milestone.status = "shipped" | .shipped = [{id: .milestone.id, title: "Pay", at: ((($ENV.VBW_NOW | fromdateiso8601) - 7200) | todateiso8601)}]'
  jq '{at: .shipped[0].at}' .vbw/record.json > "$TEST_ROOT/at.json"
  run render
  [[ "${lines[0]}" == *"│ ✓ idle: M1 shipped $(hm_of "$TEST_ROOT/at.json" at)" ]] || { echo "${lines[0]}"; false; }
  out=$(render_color)
  [[ "$out" == *$'\033[38;5;77m✓ idle: M1 shipped'* ]] || { echo "$out" | od -c | head; false; }
}

@test "C1: nothing running and nothing waiting reads 'idle' with the next step" {
  printf '%s\n' '{"action":"build","gate":false,"instruction":"x","detail":{}}' > .vbw/runtime/next.json
  run render
  [[ "${lines[0]}" == *"│ ✓ idle: build is next" ]] || { echo "${lines[0]}"; false; }
}

@test "C1: the three state colours are the panel palette's accent, need and progress colours in 256-colour codes" {
  command -v node > /dev/null || skip "node is not installed"
  # The xterm-256 colour-cube index of each palette colour, computed from panel-palette.js.
  run node --input-type=module -e "
    const p = await import('$REPO_ROOT/plugin/hooks/panel-palette.js')
    const lv = [0, 95, 135, 175, 215, 255]
    const idx = (c) => { const v = p.rgb(c); const [r, g, b] = [v >> 16 & 255, v >> 8 & 255, v & 255].map((x) => lv.indexOf(x)); return 16 + 36 * r + 6 * g + b }
    console.log([idx(p.ACCENT), idx(p.NEED), idx(p.PROGRESS)].join(' '))"
  [ "$output" = "141 214 77" ] || { echo "$output"; false; }
  grep -qF 'c("38;5;141"; "● working' "$PLUGIN_ROOT/scripts/statusline.jq"
  grep -qF 'c("38;5;214"; "⚑ needs you' "$PLUGIN_ROOT/scripts/statusline.jq"
  grep -qF 'c("38;5;77"; "✓ idle' "$PLUGIN_ROOT/scripts/statusline.jq"
}

# R240 (T211, D558): the end time reaches the status line from a step note exactly as a
# run writes it, and the real-user suite's status line pattern reads it. The steptime
# scenario recorded no status line time in about 120 samples on 2026-10-31 while the
# chat and Comms had it; these cases hold the render on the real note shape and tie the
# suite's pattern to the status line's wording, so the two can never diverge unseen.

# L3_STATUS_UNTIL: the one pattern tools/l3-suite.sh reads the status line's end time
# with, taken from the suite itself (its one top-level definition).
suite_pattern() {
  local line
  line=$(grep -m1 '^L3_STATUS_UNTIL=' "$REPO_ROOT/tools/l3-suite.sh") || { echo "tools/l3-suite.sh defines no top-level L3_STATUS_UNTIL"; return 1; }
  printf '%s\n' "$line" > "$TEST_ROOT/pattern.sh"
  # shellcheck disable=SC1091
  . "$TEST_ROOT/pattern.sh"
  [ -n "${L3_STATUS_UNTIL:-}" ] || { echo "L3_STATUS_UNTIL is empty"; return 1; }
}

@test "R240: a build note exactly as a run writes it (units and road keys) shows the end time in the step's first minute, then with the minutes" {
  step_seed build 600 2 5
  "$VBW" run start build P1.1 > /dev/null
  # The note the kernel wrote: every key step_start writes, plus the road.
  for k in kind run session pid started_at ids doing parts proof first_end end late units road; do
    jq -e --arg k "$k" 'has($k)' "$NOTE" > /dev/null || { echo "the run's note has no $k:"; cat "$NOTE"; false; }
  done
  jq -e '.end != null and .end == .first_end' "$NOTE" > /dev/null || { echo "the run's note has no end:"; cat "$NOTE"; false; }
  run render
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"● working: building P1.1 · 0 of 1 · until around $(hm end)"* ]] || { echo "${lines[0]}"; cat "$NOTE"; false; }
  [[ "${lines[0]}" != *" min, until"* ]] || { echo "a minutes prefix in the first minute: ${lines[0]}"; false; }
  step_back 300
  run render
  [[ "${lines[0]}" == *"● working: building P1.1 · 0 of 1 · 5 min, until around $(hm end)"* ]] || { echo "${lines[0]}"; false; }
}

@test "R240: a proof note exactly as plugin/lib/proofsteps.sh writes it at its start (proof null, road key) shows its end time" {
  jq -n --argjson pid "$LIVE" 'def s($n): ($ENV.VBW_NOW | fromdateiso8601) + $n | todateiso8601;
    {kind: "proof", run: null, session: "s1", pid: $pid, started_at: s(-20), ids: [], doing: "proving 0 of 6 checks",
     parts: {done: 0, total: 6}, proof: null, first_end: s(60), end: s(60), late: false, road: null}' > "$NOTE"
  run render
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"● working: proving 0 of 6 checks · until around $(hm end)"* ]] || { echo "${lines[0]}"; false; }
}

@test "R240: the real-user suite's status line pattern reads the HH:MM the status line prints, so the two cannot diverge unseen" {
  suite_pattern
  step_seed build 600 2 5
  "$VBW" run start build P1.1 > /dev/null
  run render
  local got
  got=$(printf '%s\n' "${lines[0]}" | grep -oE "$L3_STATUS_UNTIL" | head -1 | grep -oE '[0-9]{2}:[0-9]{2}$' || true)
  [ "$got" = "$(hm end | grep -oE '[0-9]{2}:[0-9]{2}$')" ] || { echo "pattern '$L3_STATUS_UNTIL' read '$got' from: ${lines[0]}"; false; }
}
