#!/usr/bin/env bash
# The units' own time (docs/proof.md, "Unit time and the budget per unit"): the
# seconds each check, project command and test file took when it last ran, as
# the evidence holds them. Reports only: no time ever fails a proof (a busy
# machine never fails one). A unit over the budget (settings.check_budget
# seconds, VBW_CHECK_BUDGET when unset) is named, nothing more. Every report
# reads the evidence, which holds the current units only: the record's checks,
# the project commands the proof covers and the test files the form matches
# now. A clone keeps the unit time each milestone started with in
# $(git common dir)/vbw/unit-time.json ({milestones: {ID: {seconds, units, at}}}),
# never in the record, for vbw ship. JSON only through jq.

VBW_CHECK_BUDGET=120

# The jq definitions every report shares, over an evidence-shaped object
# ({checks, commands, test_files}): unit_times lists the units in the
# evidence's order as {k: name, s: seconds, reused}, leaving out a check that
# waited or was skipped, a project command that was skipped and the test
# command's line for its test files (its seconds are theirs); slowest sorts
# them, slowest first, ties in that order.
# shellcheck disable=SC2016 # a jq program
UNITTIME_DEFS='def r1: . * 10 | round / 10;
# The time of a unit as the reports print it: tenths under 10 s, whole seconds from 10 s (a whole value prints as before).
def sec: r1 | if . >= 10 then round else . end;
def unit_times: [((.checks // {}) | to_entries[] | select(.value.status != "waiting" and .value.status != "skipped")),
    ((.commands // {}) | to_entries[] | select(.value.status != "skipped" and (.value.of_files | not))),
    ((.test_files // {}) | to_entries[])]
  | map({k: .key, s: (.value.seconds // 0), reused: (.value.reused // false)});
def slowest: sort_by(-.s);
def unit_total: {seconds: (map(.s) | add // 0 | r1), units: length};
def ran_line($b): [unit_times[] | select(.reused | not)] as $ran
  | if ($ran | length) == 0 then empty else
      ($ran | slowest) as $s | ($ran | map(.s) | add) as $t | ($s[:3] | map(.s) | add) as $top
      | [$s[] | select(.s > $b) | .k] as $over
      | "slowest units: " + ($s[:3] | map("\(.k) \(.s | sec) s") | join(", "))
        + (if $t > 0 then " (\($top * 100 / $t | round)% of \($t | sec) s unit time)" else " (each under a second)" end)
        + (if ($over | length) == 0 then ""
           else "; over budget (more than \($b) s): " + ($over[:5] | join(", "))
             + (if ($over | length) > 5 then " and \(($over | length) - 5) more (vbw show evidence)" else "" end) end)
    end;
def evidence_block($b): unit_times as $u | ($u | slowest) as $s | ($u | unit_total) as $t
  | [$s[] | select(.s > $b)] as $over
  | "  unit time: \($t.seconds | sec) s in \($t.units) unit\(if $t.units == 1 then "" else "s" end), each as it last ran\(if $t.units > 0 then "; the slowest:" else "" end)",
    ($s[:10][] | "    \(.k) \(.s | sec) s"),
    "  over budget (more than \($b) s a unit): \(if ($over | length) == 0 then "none" else $over | length end)",
    ($over[] | "    \(.k) \(.s | sec) s");'

# unittime_budget: the seconds a unit may take before it is named over budget,
# from the record on stdin.
unittime_budget() {
  jq -r --argjson d "$VBW_CHECK_BUDGET" '.settings.check_budget // $d'
}

# unittime_ran_line BUDGET: from an evidence-shaped object on stdin, one line: the
# three slowest units that ran (reused ones did not), the share of the ran units'
# time they took, and the ran units over BUDGET seconds (five named, the rest
# counted). Nothing when no unit ran.
unittime_ran_line() {
  jq -r --argjson b "$1" "${UNITTIME_DEFS}ran_line(\$b)"
}

# unittime_total: {seconds, units} of the evidence on stdin; null evidence is zero.
unittime_total() {
  jq -c "${UNITTIME_DEFS}"'if type == "object" then unit_times | unit_total else {seconds: 0, units: 0} end'
}

# unittime_file: the clone's figures file (shared by the clone's worktrees).
unittime_file() {
  local common
  common=$(git -C "$VBW_ROOT" rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || return 1
  vbw_out '%s/vbw/unit-time.json\n' "$common"
}

# unittime_start MILESTONE: keep the unit time MILESTONE starts with: the record's
# evidence now (the last proof of the milestone before it; no evidence is zero).
# Atomic, under a lock beside the file. A file that cannot be written leaves the
# milestone start as it is: vbw ship then says it has no figure to compare with.
unittime_start() {
  local file lock tmp
  file=$(unittime_file) || return 0
  mkdir -p "${file%/*}" 2> /dev/null || return 0
  lock="${file%.json}.lock"
  vbw_lock_take "$lock" "this clone's unit-time figures"
  tmp=$(mktemp "${file%/*}/unit-time.XXXXXX" 2> /dev/null) || { vbw_guard_drop "$lock"; return 0; }
  vbw_guard_add file "$tmp"
  # A missing or damaged file starts again with this milestone's figure.
  jq -c '.evidence' "$VBW_RECORD" | unittime_total \
    | jq -c --slurpfile old <(jq -c 'select(type == "object" and (.milestones | type) == "object")' "$file" 2> /dev/null) \
      --arg m "$1" --arg at "$(vbw_now)" '. as $t | ($old[0] // {milestones: {}}) | .milestones[$m] = ($t + {at: $at})' > "$tmp" 2> /dev/null \
    && mv "$tmp" "$file"
  vbw_guard_drop "$tmp"
  vbw_guard_drop "$lock"
  return 0
}

# unittime_ship_line MILESTONE: vbw ship's line: the unit time of the record's
# evidence and its change since MILESTONE started, or that this clone kept no
# figure from its start.
unittime_ship_line() {
  local file
  file=$(unittime_file) || file=
  jq -c '.evidence' "$VBW_RECORD" | unittime_total \
    | jq -r --arg m "$1" --slurpfile f <(jq -c 'select(type == "object" and (.milestones | type) == "object")' "$file" 2> /dev/null) "$UNITTIME_DEFS"'
      def units($n): "\($n) unit\(if $n == 1 then "" else "s" end)";
      . as $now | ($f[0].milestones[$m] // null) as $b
      | "unit time: \($now.seconds | sec) s in \(units($now.units))"
        + (if $b == null or ($b.seconds | type) != "number" then "; this clone kept no figure from the start of \($m)"
           else ($now.seconds - $b.seconds | r1) as $d
             | ", \(if $d >= 0 then "+\($d | sec)" else "-\(-$d | sec)" end) s since \($m) started (\($b.seconds | sec) s in \(units($b.units // 0)))" end)'
}
