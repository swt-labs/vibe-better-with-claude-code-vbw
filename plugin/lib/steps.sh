#!/usr/bin/env bash
# The step history and the running step's note (R190, docs/panel.md).
#
# History: $(git-common-dir)/vbw/steps.json, {"steps": [{kind, run, started_at,
# ended_at, seconds, parts?}]}, the latest 50 of each kind in time order. It is
# a cache of what this project's steps took: a missing, damaged or unwritable
# file never fails a step; it only means no end time yet.
#
# Note: .vbw/runtime/step.json, written only by the kernel, atomically, while a
# step runs: {kind, run, session, pid, started_at, ids, doing, parts, proof,
# first_end, end, late}. A time is UTC ISO 8601 to the second; first_end and end
# are null when there is no basis (fewer than 3 finished steps of the kind).
# JSON is read and written only through jq.

# The kernel's one wording of a step, for vbw status, vbw next and vbw run start
# (the panel's words, D425). $t is the moment, in epoch seconds.
# step_clock($iso; $t): the local 24-hour time of a UTC time; "tomorrow HH:MM",
# "yesterday HH:MM" or the weekday when it is not today.
# step_words($s; $t): a note's time: 'about 12 min, until around 14:20' (a well-founded
# estimate), 'usually about 18 min (15 to 21 min, rough guess from 2 runs), until around 14:23 (14:20 to 14:26)'
# (a rough one, R270: $s carries end_low, end_high, rough and runs; one figure when the
# ends agree), 'less than a minute, ...', 'until around 14:35, later than usual' (with
# parts), 'until around 14:20, 6 min late' (without), or 'no end time yet (...)'.
# step_label($kind; $ids; $n): what a step is: 'Building P1.1, P1.2 and P1.3'.
# step_say($s; $t): the sentence VBW says before a step starts; $s has kind,
# ids, parts (a number or {done, total}), end, end_low, end_high, rough, runs, late and, for a proof, why ({reason,
# count}: the reason most of its units run again).
# step_sentence($s; $t): what a running step is doing, its progress and its time.
# shellcheck disable=SC2016,SC2034
VBW_STEP_DEFS='def vbw_now: (($ENV.VBW_NOW // "") | if . == "" then now else fromdateiso8601 end);
def step_day($e): $e | localtime | mktime / 86400 | floor;
def step_clock($iso; $t):
  ($iso | fromdateiso8601) as $e
  | ($e | localtime | strftime("%H:%M")) as $hm
  | (step_day($e) - step_day($t)) as $d
  | if $d == 0 then $hm
    elif $d == 1 then "tomorrow \($hm)"
    elif $d == -1 then "yesterday \($hm)"
    else "\($e | localtime | strftime("%A")) \($hm)" end;
def step_mins($sec): [1, ($sec / 60 | round)] | max;
def step_words($s; $t):
  if $s.end == null then "no end time yet (VBW has timed fewer than 3 steps like this here)"
  else (($s.end | fromdateiso8601) - $t) as $left
    | "until around \(step_clock($s.end; $t))" as $at
    | (($s.rough == true) and $s.end_low != null and $s.end_high != null) as $rg
    | (if $rg then " (rough guess from \($s.runs // 0) \(if ($s.runs // 0) == 1 then "run" else "runs" end))" else "" end) as $tag
    | (($s.parts // null) != null) as $hp
    | if $hp and ($s.late == true or $left <= 0) then "\($at), later than usual\($tag)"
      elif ($hp | not) and $left <= -60 then "\($at), \(-$left / 60 | floor) min late\($tag)"
      elif $left < 60 then (if $left > 0 then "less than a minute, \($at)" else $at end) + $tag
      elif $rg then
        ([($s.end_low | fromdateiso8601), ($s.end | fromdateiso8601)] | min) as $lo
        | ([($s.end_high | fromdateiso8601), ($s.end | fromdateiso8601)] | max) as $hi
        | step_mins($lo - $t) as $lm | step_mins($hi - $t) as $hm
        | if $lm == $hm then "roughly \($lm) min, \($at)\($tag)"
          else ([[($s.end_typical // $s.end | fromdateiso8601), $lo] | max, $hi] | min) as $ty
            | "usually about \(step_mins($ty - $t)) min (\($lm) to \($hm) min, rough guess from \($s.runs // 0) \(if ($s.runs // 0) == 1 then "run" else "runs" end)), until around \(step_clock(($ty | todateiso8601); $t)) (\(step_clock(($lo | todateiso8601); $t)) to \(step_clock(($hi | todateiso8601); $t)))" end
      else "about \(step_mins($left)) min, \($at)" end end;
def step_and: if length < 2 then join("") else (.[:-1] | join(", ")) + " and " + .[-1] end;
def step_label($k; $ids; $n):
  if $k == "build" then "Building \($ids | step_and)"
  elif $k == "fix" then "Fixing \($ids | step_and)"
  elif $k == "qa" then (if ($ids | length) > 0 then "Checking \($ids | step_and)" else "Checking the built work" end)
  elif $k == "plan" then "Planning the work"
  elif $k == "proof" then "Proving \($n) \(if $n == 1 then "check" else "checks" end)"
  else "Mapping the project" end;
# step_move($t): a note whose parts.done just changed, with its end moved to the
# pace of this run when that ends after the first end time (D424, D429), marked later
# than usual; never earlier than the first end time, unchanged while nothing is done.
def step_move($t):
  if .first_end == null or .parts.done == 0 then .
  else ($t - (.started_at | fromdateiso8601)) as $el
    | ($t + ($el / .parts.done * (.parts.total - .parts.done) | round)) as $proj
    | (.first_end | fromdateiso8601) as $fe
    | (if $proj > $fe then $proj else $fe end) as $end
    | .end = ($end | todateiso8601) | .late = ($end > $fe) end;
def step_say($s; $t):
  step_label($s.kind; $s.ids // []; if ($s.parts | type) == "object" then $s.parts.total else ($s.parts // 0) end)
  + ": " + step_words($s; $t)
  + (if $s.kind == "proof" and ($s.why | type) == "object" then "; top reason: \($s.why.reason) (\($s.why.count) \(if $s.why.count == 1 then "unit" else "units" end))" else "" end);
def step_sentence($s; $t):
  $s.doing
  + (if ($s.parts // null) != null and ($s.proof // null) == null and $s.kind != "proof" then " · \($s.parts.done) of \($s.parts.total)" else "" end)
  + " · " + step_words($s; $t);
'

# shellcheck source=road.sh
. "$VBW_LIB/road.sh"

# step_history_file: the history's path, empty outside a git repository.
step_history_file() {
  local common
  # Asked of the project, not of the current folder (inside a clean copy that is a repository of its own).
  common=$(git -C "${VBW_ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || return 0
  vbw_out '%s/vbw/steps.json\n' "$common"
}

step_note_file() {
  printf '%s/step.json\n' "$VBW_RUNTIME"
}

# step_kind_has_parts KIND: builds, fixes and proofs count their parts.
step_kind_has_parts() {
  case "$1" in build | fix | proof) return 0 ;; esac
  return 1
}

# step_estimate KIND SIZE: the estimate of a step of KIND and SIZE as one JSON object
# {seconds, low, high, runs, rough} (lib/steps-expect.jq, R270), seconds and the ends
# null with runs 0 when the history gives no basis; empty when the history cannot be read.
# step_expect KIND SIZE: the estimate's seconds alone, empty without a basis. SIZE is JSON: build [{id, tier, tasks, breaks}]
# (the wave's plans), fix {tier}, plan {reqs}, qa [{id, tier}], proof {units: [names]}
# (a bare number for a proof counts that many unknown units). The ladders are
# lib/steps-expect.jq's (R191). Each unit's last seconds come from run-times.json,
# which the save writes beside the run store (lib/proofreuse.sh), never from the
# store: it holds every read list and can reach hundreds of MB. A missing, damaged
# or unreadable history or run times only means less to go on.
step_estimate() {
  local file runs size out
  file=$(step_history_file)
  [ -n "$file" ] && [ -f "$file" ] || return 0
  [ -f "$VBW_LIB/steps-expect.jq" ] || return 0
  runs="$(dirname "$file")/run-times.json"
  size=$2
  case "$size" in
    '') return 0 ;;
    *[!0-9]*) ;;
    *) size=$(jq -nc --argjson n "$size" '{units: [range(0; $n) | "unit:\(.)"]}') ;;
  esac
  # A proof's size names every unit (Linux caps one argument at 128 KB): through a file.
  out=$(jq -n -c --slurpfile h <(jq -c 'select(type == "object" and (.steps | type) == "array")' "$file" 2> /dev/null) \
    --slurpfile runs <(jq -c 'select(type == "object" and (.runs | type) == "object")' "$runs" 2> /dev/null) \
    --arg kind "$1" --slurpfile size <(printf '%s' "$size") -f "$VBW_LIB/steps-expect.jq" 2> /dev/null) || return 0
  vbw_out '%s\n' "$out"
}

step_expect() {
  step_estimate "$@" | jq -r '.seconds // empty' 2> /dev/null || true
}

# step_record LEASE_JSON: add the run that just ended to the history, with its
# parts from its note. Best effort, never fails the caller.
step_record() {
  local file now tmp note extra='{}' record
  file=$(step_history_file)
  [ -n "$file" ] || return 0
  [ ! -d "$file" ] || return 0
  now=$(vbw_now)
  tmp="$file.$$"
  note=$(step_note_file)
  if [ -f "$note" ]; then
    record=$(record_read 2> /dev/null) || record='{}'
    extra=$(printf '%s' "$record" | jq -c --arg run "$(printf '%s' "$1" | jq -r '.run')" --slurpfile n "$note" '
      ($n[0] // {}) as $n
      | if $n.run != $run then {} else
          (if ($n.parts | type) == "object" then {parts: $n.parts.total} else {} end)
          + (if $n.kind == "build" then {units: [($n.units // [])[] | select(.seconds != null)]}
             elif $n.kind == "fix" then {fixes: $n.ids} + (if $n.tier != null then {tier: $n.tier} else {} end)
             elif $n.kind == "plan" and $n.reqs != null then {reqs: $n.reqs}
             elif $n.kind == "qa" then
               {phases: [$n.ids[] as $i | {id: $i, tier: (([.phases[]? | select(.id == $i)][0].tier) // "standard")}]}
             else {} end) end' 2> /dev/null) || extra='{}'
    [ -n "$extra" ] || extra='{}'
  fi
  mkdir -p "$(dirname "$file")" 2> /dev/null || return 0
  { jq -c --arg now "$now" --argjson extra "$extra" --slurpfile old <(jq -c 'select(type == "object" and (.steps | type) == "array")' "$file" 2> /dev/null) '
      ([$old[0].steps[]? | select(type == "object" and (.kind | type) == "string")]
        + [{kind, run, started_at, ended_at: $now,
            seconds: (($now | fromdateiso8601) - (.started_at | fromdateiso8601))} + $extra])
      # Steps that end in the same second keep the order they were recorded in.
      | {steps: (to_entries | group_by(.value.kind) | map(.[-50:]) | add | sort_by(.value.ended_at, .key) | map(.value))}' <<< "$1" > "$tmp" \
    && mv -f "$tmp" "$file"; } 2> /dev/null || rm -f "$tmp" 2> /dev/null || true
  return 0
}

# step_live_note RUN: print the note when it is a running step, else print
# nothing. A note with a process (a proof of its own) is live while the process
# is; any other is live while its run is the open run (RUN, empty: none).
step_live_note() {
  local note pid
  note=$(step_note_file)
  [ -f "$note" ] || return 0
  jq -e 'type == "object" and (.kind | type) == "string"' "$note" > /dev/null 2>&1 || return 0
  pid=$(jq -r '.pid // empty' "$note" 2> /dev/null) || return 0
  if [ -n "$pid" ]; then
    kill -0 "$pid" 2> /dev/null || return 0
    jq -c . "$note" 2> /dev/null || true
    return 0
  fi
  jq -c --arg run "$1" 'select($run != "" and .run == $run)' "$note" 2> /dev/null || true
}

# step_note_clean RUN: remove a note that is not a running step.
step_note_clean() {
  [ -f "$(step_note_file)" ] || return 0
  [ -n "$(step_live_note "$1")" ] || rm -f "$(step_note_file)" 2> /dev/null || true
  return 0
}

# step_note_write JSON: replace the note atomically; never fails the caller.
step_note_write() {
  local note tmp
  note=$(step_note_file)
  tmp="$note.$$"
  { mkdir -p "$VBW_RUNTIME" && printf '%s\n' "$1" > "$tmp" && mv -f "$tmp" "$note"; } 2> /dev/null || rm -f "$tmp" 2> /dev/null || true
  return 0
}

# step_qa_phases RECORD: the phases vbw next would send to QA: built phases of
# the milestone whose QA is due (lib/qa.jq's recheck, lib/rigor-defs.jq's
# needs_qa), the same rule as next.jq's $to_verify.
step_qa_phases() {
  local qa
  qa=$(qa_state "$1" 2> /dev/null) || { echo '[]'; return 0; }
  printf '%s' "$1" | jq -c --slurpfile qa <(printf '%s' "$qa") "$VBW_JQ_DEFS"'.milestone.id as $m
    | [.requirements[] | select(.milestone == $m)] as $current
    | [.phases[] | select(.milestone == $m and $qa[0].recheck[.id] != null and needs_qa(.tier // "standard"; $current)) | .id]' 2> /dev/null || echo '[]'
}

# The jq definition of step_size, shared with the one run that judges vbw next (lib/cmd-next.sh),
# which works out the size of the step beside its answer.
# shellcheck disable=SC2016
VBW_STEP_SIZE_DEFS='def step_size_prog($k; $ids):
    def tier_of($pid): ([.phases[]? | select(.id == $pid)][0].tier) // "standard";
    if $k == "build" then
      [$ids[] as $i | ([.plans[]? | select(.id == $i)][0]) as $p
        | {id: $i, tier: tier_of($p.phase // ""), tasks: (($p.tasks // []) | length), breaks: (owed_rules($i) | length)}]
    elif $k == "fix" then
      ([.fixes[]? | select(.id as $i | any($ids[]; . == $i)) | .req | select(. != null)]) as $rq
      | [.phases[]? | select(any(.reqs[]?; . as $r | any($rq[]; . == $r))) | (.tier // "standard")]
      | {tier: (if length == 0 then null else (map(tier_rank) | max) as $m | tiers[$m] end)}
    elif $k == "plan" then
      .milestone.id as $m
      | {reqs: ([.requirements[]? | select(.milestone == $m and .status != "proven" and .status != "accepted")] | length)}
    elif $k == "qa" then
      [$ids[] as $i | {id: $i, tier: tier_of($i)}]
    else null end;
'

# step_size RECORD KIND IDS_JSON: the size of a step for step_expect, from the
# record: build [{id, tier, tasks, breaks}] (a plan's tier is its phase's, standard
# when the phase has none; breaks: the rules it owes the mutation check,
# owed_rules), fix {tier} (the highest tier among the phases of the
# fixes' requirements, null when no phase serves them), plan {reqs} (the active
# milestone's requirements not proven or accepted), qa [{id, tier}].
step_size() {
  printf '%s' "$1" | jq -c --arg k "$2" --argjson ids "$3" "$VBW_JQ_DEFS$VBW_STEP_SIZE_DEFS"'step_size_prog($k; $ids)' 2> /dev/null || echo null
}

# step_road RECORD NEXT NOTE: the road (lib/road.sh) with the running build's
# plans counted as the run started them: a plan done during the step leaves the
# step's own piece, not the rest, so the rest of the road stays what it was when
# the step began and only the step's own end moves (R191.36, D438).
step_road() {
  local rec="$1"
  if [ -n "${3:-}" ]; then
    rec=$(printf '%s' "$1" | jq -c --slurpfile n <(printf '%s' "$3") '
      ($n[0] // {}) as $n
      | if $n.kind == "build" then .plans |= map(if .status == "done" and (.id as $i | any($n.ids[]?; . == $i)) then .status = "building" else . end) else . end' 2> /dev/null) || rec=$1
  fi
  road_compute "$rec" "$2" "${3:-}"
}

# step_road_input: vbw next's answer for the road, {} when it cannot be judged.
step_road_input() {
  # shellcheck source=cmd-next.sh
  . "$VBW_LIB/cmd-next.sh"
  next_answer 2> /dev/null || echo '{}'
}

# step_road_note_set [NEXT [START]]: the live note gets the road computed now from
# the record and the note as it is. NEXT is the answer to use (step_road_input when
# empty). START=start counts the road's seconds from the step's own start, which
# is the moment of a run that just began, not the moment the sum was done. No note
# stays no note; a road that cannot be told is null.
step_road_note_set() {
  local note record cur next="${1:-}" road out
  note=$(step_note_file)
  [ -f "$note" ] || return 0
  cur=$(jq -c . "$note" 2> /dev/null) || return 0
  [ -n "$cur" ] || return 0
  record=$(record_read) || return 0
  [ -n "$next" ] || next=$(step_road_input)
  road=$(step_road "$record" "$next" "$cur")
  out=$(printf '%s' "$cur" | jq -c --argjson road "${road:-null}" --arg start "${2:-}" '.road = $road
    | if $start == "start" and (.road.seconds? // null) != null
      then .road.seconds = ((.road.end | fromdateiso8601) - (.started_at | fromdateiso8601)) else . end' 2> /dev/null) || return 0
  [ -z "$out" ] || step_note_write "$out"
}

# step_road_status RECORD STEP_JSON [INPUT]: the road vbw status carries: the live note's
# own road while a step runs (STEP_JSON is the note, or null), else the road now.
# INPUT, a command, prints vbw next's answer for the road (default step_road_input).
step_road_status() {
  local road note=""
  road=$(printf '%s' "$2" | jq -c 'select(type == "object") | .road | select(type == "object")' 2> /dev/null) || road=
  if [ -n "$road" ]; then printf '%s\n' "$road"; return 0; fi
  [ "$2" = null ] || note=$2
  step_road "$1" "$(${3:-step_road_input})" "$note"
}

# step_start KIND IDS_JSON: write the note of the run that just started (the
# open run of the record), after removing a note that is not live.
step_start() {
  local kind="$1" ids="$2" record lease parts=null doing expect first_end=null size est
  record=$(record_read)
  lease=$(printf '%s' "$record" | jq -c '.lease // empty')
  [ -n "$lease" ] || return 0
  step_note_clean "$(printf '%s' "$lease" | jq -r '.run')"
  if [ "$kind" = qa ]; then
    # shellcheck source=cmd-next.sh
    . "$VBW_LIB/cmd-next.sh"
    ids=$(step_qa_phases "$record")
  fi
  if step_kind_has_parts "$kind"; then
    parts=$(printf '%s' "$ids" | jq -c '{done: 0, total: length}')
  fi
  doing=$(printf '%s' "$ids" | jq -r --arg k "$kind" '
    if $k == "build" then "building \(join(", "))"
    elif $k == "fix" then "fixing \(join(", "))"
    elif $k == "qa" then (if length > 0 then "checking \(join(", "))" else "checking the built work" end)
    elif $k == "plan" then "planning"
    else "mapping the project" end')
  size=$(step_size "$record" "$kind" "$ids")
  est=$(step_estimate "$kind" "$size")
  [ -n "$est" ] || est='{"seconds":null,"low":null,"high":null,"runs":0,"rough":false}'
  expect=$(printf '%s' "$est" | jq -r '.seconds // empty')
  [ -z "$expect" ] || first_end=$(printf '%s' "$lease" | jq -r --argjson e "$expect" '(.started_at | fromdateiso8601) + $e | todateiso8601')
  step_note_write "$(printf '%s' "$lease" | jq -c --arg k "$kind" --argjson ids "$ids" --argjson parts "$parts" --arg doing "$doing" --arg fe "$first_end" --argjson size "$size" --argjson est "$est" '
    def at($s): if $s == null then null else (.started_at | fromdateiso8601) + $s | todateiso8601 end;
    {kind: $k, run, session: (.session // null), pid: null, started_at, ids: $ids, doing: $doing, parts: $parts, proof: null,
     first_end: (if $fe == "null" then null else $fe end), end: (if $fe == "null" then null else $fe end),
     end_low: at($est.low), end_high: at($est.high), end_typical: at($est.typical), rough: ($est.rough == true), runs: ($est.runs // 0), late: false}
    + (if $k == "build" then {units: [$size[]? | . + {seconds: null}]}
       elif $k == "fix" then {tier: ($size.tier // null)}
       elif $k == "plan" then {reqs: ($size.reqs // null)}
       else {} end)')"
  step_road_note_set "" start
}

# step_replan_say RECORD: the sentence of a planning run of the milestone's open
# requirements plus one (the cost of a yes to a suggestion that adds a requirement,
# R229): the size and the words come from the same code as step.say for a plan step.
step_replan_say() {
  local size est
  size=$(step_size "$1" plan '[]' | jq -c '.reqs += 1' 2> /dev/null) || size=
  est=$(step_estimate plan "$size")
  [ -n "$est" ] || est=null
  jq -nr --argjson e "$est" "$VBW_STEP_DEFS"'(vbw_now | floor) as $t
    | def at($s): if $s == null then null else $t + $s | todateiso8601 end;
    {kind: "plan", ids: [], parts: null, end: at($e.seconds), end_low: at($e.low), end_high: at($e.high), end_typical: at($e.typical),
     rough: ($e.rough == true), runs: ($e.runs // 0), late: false}
    | step_say(.; $t)'
}

# step_plan_done: a plan was just recorded done; count the running build's
# parts done from the record, and when this run's own pace ends after the first
# end time, move the end to that projection and mark it late (D424). The end
# never goes earlier than the first end time.
step_plan_done() {
  local run note out
  run=$(record_read | jq -r '.lease.run // ""')
  [ -n "$(step_live_note "$run")" ] || return 0
  note=$(step_note_file)
  out=$(jq -c --slurpfile r "$VBW_RECORD" "$VBW_STEP_DEFS"'
    . as $n | ($r[0].plans) as $pl
    | select($n.kind == "build" and ($n.parts | type) == "object")
    | ([$n.ids[] | select(. as $i | any($pl[]; .id == $i and .status == "done"))] | length) as $done
    | .parts.done = $done
    | (vbw_now | floor) as $t
    | .units = [(.units // [])[] | if .seconds == null and (. as $u | any($pl[]; .id == $u.id and .status == "done"))
        then .seconds = ($t - (($n.started_at | fromdateiso8601))) else . end]
    | step_move($t)' "$note" 2> /dev/null) || return 0
  [ -z "$out" ] || step_note_write "$out"
  # The milestone's end moves with the step's, at once (D438).
  step_road_note_set
}

# step_status RUN: the running step as vbw status --json gives it: the live
# note, plus minutes_late (whole minutes past first_end for a step without
# parts, else null), or null.
step_status() {
  local live
  live=$(step_live_note "$1")
  if [ -z "$live" ]; then echo null; return 0; fi
  printf '%s' "$live" | jq -c "$VBW_STEP_DEFS"'. + {minutes_late: (if .parts == null and .first_end != null
      then (((vbw_now | floor) - (.first_end | fromdateiso8601)) / 60 | floor | if . >= 1 then . else null end) else null end)}' 2> /dev/null || echo null
}

# step_say_note: the sentence of the note just written (run start), then the road's, nothing
# without a note.
step_say_note() {
  local note
  note=$(step_note_file)
  [ -f "$note" ] || return 0
  jq -r "$VBW_STEP_DEFS"'step_say(.; vbw_now | floor), (.road.say? // empty)' "$note" 2> /dev/null || true
}

# step_proof_plan RECORD FULL: what a proof would run now, as {units, top}: the
# names of the units (a JSON array of check:ID, file:PATH and command:NAME) and the
# reason most of them run again ({reason, count}, null when none runs), planned
# by the proof's own reuse rule (cmd-prove.sh) without running anything. The plan
# is cached in .vbw/runtime/proof-units.json as {head, index, record, store, full,
# units, top}: head is the committed tree, index the SHA-256 of the git index's
# entries (git ls-files -s: the test files are listed from the index, so a staged
# new test file counts), record and store the SHA-256 of the record file and of the
# run store file (an absent store counts as empty). It is reused only while every
# part matches, else planned again and the file rewritten; a damaged file, or one
# an older VBW wrote without top, is planned again.
step_proof_plan() {
  local head idx rec store cache tmp plan storef
  # shellcheck source=proofreuse.sh
  . "$VBW_LIB/proofreuse.sh"
  head=$(vbw_head_tree 2> /dev/null) || head=
  idx=$(git -C "$VBW_ROOT" ls-files -s -z 2> /dev/null | vbw_sha256) || idx=
  rec=$(vbw_sha256 < "$VBW_RECORD" 2> /dev/null) || rec=
  storef=$(proofreuse_store_file 2> /dev/null) || storef=
  if [ -n "$storef" ] && [ -f "$storef" ]; then store=$(vbw_sha256 < "$storef" 2> /dev/null) || store=
  else store=$(printf '' | vbw_sha256); fi
  cache="$VBW_RUNTIME/proof-units.json"
  if [ -n "$head" ] && [ -n "$idx" ] && [ -n "$rec" ] && [ -n "$store" ] && [ -f "$cache" ] \
    && plan=$(jq -ce --arg h "$head" --arg i "$idx" --arg r "$rec" --arg s "$store" --argjson f "${2:-0}" '
        select(type == "object" and .head == $h and .index == $i and .record == $r and .store == $s and .full == $f
          and has("top") and (.units | type) == "array" and all(.units[]; type == "string")) | {units, top}' "$cache" 2> /dev/null) \
    && [ -n "$plan" ]; then
    printf '%s\n' "$plan"
    return 0
  fi
  plan=$(step_proof_units_plan "$1" "$2")
  if [ -n "$head" ] && [ -n "$idx" ] && [ -n "$rec" ] && [ -n "$store" ] && printf '%s' "$plan" | jq -e '(.units | type) == "array"' > /dev/null 2>&1; then
    tmp="$cache.$$"
    # The unit list grows with the project (Linux caps one argument at 128 KB): through a pipe.
    { mkdir -p "$VBW_RUNTIME" && printf '%s' "$plan" | jq -c --arg h "$head" --arg i "$idx" --arg r "$rec" --arg s "$store" --argjson f "${2:-0}" \
        '{head: $h, index: $i, record: $r, store: $s, full: $f, units: .units, top: .top}' > "$tmp" && mv -f "$tmp" "$cache"; } 2> /dev/null || rm -f "$tmp" 2> /dev/null || true
  fi
  vbw_out '%s\n' "$plan"
}

# step_proof_units RECORD FULL: the names of the units a proof would run now, a
# JSON array (the plan's units).
step_proof_units() {
  step_proof_plan "$@" | jq -c '.units'
}

# step_proof_units_plan RECORD FULL: the uncached planning behind step_proof_units,
# as {units, top}: the unit names, and the reason most of them run again
# ({reason, count}, null when none runs).
step_proof_units_plan() {
  (
    cd "$VBW_ROOT" || exit 1
    # shellcheck source=cmd-prove.sh
    . "$VBW_LIB/cmd-prove.sh"
    local causes alln=0
    proofreuse_plan "$1" "$2"
    causes=$(proofcauses_find "$1" "$2" "$(vbw_head_tree 2> /dev/null)")
    [ -z "$causes" ] || alln=1
    testfiles_plan "$1" "$alln"
    [ -z "$causes" ] || prove_plan_all "$1"
    # The same list the proof itself names (held checks and unapproved commands left out), in one jq.
    CHECK_HELD=$(contract_held "$1")
    jq -nc --slurpfile u <(prove_unit_names "$1") --slurpfile t <(prove_plan_object "$1" "$causes" | prooftime_top) '{units: $u[0], top: $t[0]}'
  ) 2> /dev/null || echo '{"units": [], "top": null}'
}

# step_next RECORD NEXT [FULL]: the step vbw next --json carries: {kind, ids, parts,
# seconds, low, high, runs, rough, end, end_low, end_high, say} for an answer that runs a step (plan, build, fix, qa, a
# proof with units left to run), else null. A kind without parts has parts null.
# RECORD may be vbw next's working record (lib/cmd-next.sh); the proof's reuse plan
# reads FULL, the record itself, when it is given.
step_next() {
  local kind ids='[]' parts=null full units n est size=null plan why=null
  case "$(printf '%s' "$2" | jq -r .action)" in
    plan) kind=plan ;;
    build) kind=build ids=$(printf '%s' "$2" | jq -c .detail.plans) ;;
    fix) kind=fix ids=$(printf '%s' "$2" | jq -c .detail.fixes) ;;
    qa) kind=qa ids=$(printf '%s' "$2" | jq -c .detail.phases) ;;
    prove)
      kind=proof
      full=0
      printf '%s' "$2" | jq -e '.detail.full == true' > /dev/null && full=1
      plan=$(step_proof_plan "${3:-$1}" "$full")
      units=$(printf '%s' "$plan" | jq -c '.units' 2> /dev/null) || units='[]'
      why=$(printf '%s' "$plan" | jq -c '.top' 2> /dev/null) || why=null
      parts=$(printf '%s' "$units" | jq 'length' 2> /dev/null) || parts=0
      [ "${parts:-0}" -gt 0 ] 2> /dev/null || { echo null; return 0; }
      size=$(printf '%s' "$units" | jq -c '{units: .}') ;;
    *) echo null; return 0 ;;
  esac
  step_kind_has_parts "$kind" && [ "$parts" = null ] && parts=$(printf '%s' "$ids" | jq 'length')
  n=$parts
  [ "$n" = null ] && n=0
  # NP_STEP_SIZE: the size vbw next worked out beside its answer (lib/cmd-next.sh), when it has it.
  if [ "$kind" != proof ]; then
    if [ -n "${NP_STEP_SIZE:-}" ]; then size=$NP_STEP_SIZE; else size=$(step_size "$1" "$kind" "$ids"); fi
  fi
  est=$(step_estimate "$kind" "$size")
  [ -n "$est" ] || est=null
  jq -nc --arg k "$kind" --argjson ids "$ids" --argjson parts "$parts" --argjson e "$est" --argjson why "$why" "$VBW_STEP_DEFS"'
    (vbw_now | floor) as $t
    | def at($s): if $s == null then null else $t + $s | todateiso8601 end;
    {kind: $k, ids: $ids, parts: $parts, seconds: $e.seconds, typical: $e.typical, low: $e.low, high: $e.high, runs: ($e.runs // 0),
     rough: ($e.rough == true), end: at($e.seconds), end_low: at($e.low), end_high: at($e.high), end_typical: at($e.typical)}
    | (if $why != null then . + {why: $why} else . end)
    | . + {say: step_say(.; $t)}'
}
