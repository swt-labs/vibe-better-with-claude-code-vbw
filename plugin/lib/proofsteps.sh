#!/usr/bin/env bash
# A proof as a step (R190, docs/panel.md): vbw prove, and the proof inside vbw
# fix done, count the units they run (a check, a test file, a project command)
# in the running step's note, .vbw/runtime/step.json, as each one finishes.
#
# Three cases, decided once when the proof starts (proofsteps_begin):
#   own    no live note and no run of this session open: the proof writes a note
#          of its own (kind proof, run null, its pid, parts {done, total}, an end
#          time from the proof history) and removes it when it ends;
#   inside a note of this session's open build, fix or other run is live: the
#          proof only sets doing ("proving 12 of 40 checks") and proof {done,
#          total}, and clears them when it ends; parts and end time stay;
#   none   a live note of anything else (another session's step, another
#          proof): never touched.
# Before it starts, a note that is not live (an ended run's, a dead process's)
# is removed. When it ends, the units that really finished are recorded as a step
# of kind proof (nothing when none ran). Units count only while PROOFSTEPS_ON=1,
# so vbw check never touches the note. All of it is best effort: a note or a
# history that cannot be written never fails a proof. JSON only through jq.

# shellcheck source=steps.sh
. "$VBW_LIB/steps.sh"
# shellcheck source=qa-inputs.sh
. "$VBW_LIB/qa-inputs.sh"

# proofsteps_lock: one writer of the note at a time (a lock folder whose owner
# file decides, vbw_lock_dir). A lock whose owner process is gone, or whose owner
# never wrote its id for 5 s, is taken over by renaming its owner file
# (vbw_lock_takeover: of two waiters only one wins, and neither removes a lock a
# third took in between). The 5 s count from the last look that found an id:
# a look without one is often a moment (another process between its mkdir and
# its id, another waiter's rename while it checks), and counted from the start
# of the wait it let every long waiter in beside a live owner (13 at once in a
# proof whose updates were slow, 2026-10-28). A live owner's lock is never
# taken: after 500 looks the waiter gives up and its caller skips the update
# (the note is best effort). Fails, and the caller skips its update, where the
# runtime folder is missing.
proofsteps_lock() {
  local l="$VBW_RUNTIME/step.lock" i=0 owner quiet
  [ -d "$VBW_RUNTIME" ] || return 1
  quiet=$(vbw_lock_seconds)
  while ! vbw_lock_dir "$l"; do
    owner=$(vbw_lock_holder "$l/pid")
    if [ -n "$owner" ]; then
      quiet=$(vbw_lock_seconds)
      if ! kill -0 "$owner" 2> /dev/null; then vbw_lock_takeover "$l/pid" "$owner" && return 0; fi
    elif [ $(($(vbw_lock_seconds) - quiet)) -ge 5 ]; then
      vbw_lock_takeover "$l/pid" "" && return 0
    fi
    i=$((i + 1))
    [ "$i" -le 500 ] || return 1
    sleep 0.01
  done
  return 0
}

proofsteps_unlock() {
  rm -rf "$VBW_RUNTIME/step.lock" 2> /dev/null || true
}

# proofsteps_command_names RECORD NAMES: the project commands in NAMES (a JSON
# array) a proof will run, one per line: those whose exact argv the user approved.
proofsteps_command_names() {
  local name argv a
  while IFS= read -r -d '' name; do
    argv=()
    while IFS= read -r -d '' a; do argv+=("$a"); done \
      < <(printf '%s' "$1" | jq -j --arg n "$name" '.commands[$n][] + "\u0000"')
    if consent_has command "$(vbw_sha256_argv "${argv[@]}")"; then vbw_out '%s\n' "$name"; fi
  done < <(printf '%s' "$1" | jq -j --argjson t "$2" '.commands | keys[] | select(. as $k | $t | index($k)) | . + "\u0000"')
}

# proofsteps_commands RECORD NAMES: how many of those a proof will run.
proofsteps_commands() {
  proofsteps_command_names "$1" "$2" | wc -l | tr -d ' '
}

# proofsteps_names: the names of the units a proof will run, as a JSON array, from
# lines of NAME on stdin (check:ID, file:PATH, command:NAME).
proofsteps_names() {
  jq -R . | jq -sc 'map(select(length > 0))'
}

# proofsteps_units CHECKS COMMANDS FILES: what the proof's runs gave (JSON objects
# id -> result, command name -> result, test file path -> result), as one scratch
# file of the units that really ran, name -> {seconds}; its path is PS_UNITS. A held
# or skipped unit did not run. Results reach jq by file, never as an argument.
proofsteps_units() {
  local _u
  [ "${PROOFSTEPS_ON:-}" = 1 ] || return 0
  _u=$({ printf '%s' "$1" | jq -c '{prefix: "check:", r: .}'
         printf '%s' "$2" | jq -c '{prefix: "command:", r: .}'
         printf '%s' "$3" | jq -c '{prefix: "file:", r: .}'; } 2> /dev/null \
    | jq -sc 'map(.prefix as $p | .r | to_entries[] | select(.value | type == "object" and (.status // "") != "waiting" and (.status // "") != "skipped")
        | {key: ($p + .key), value: {seconds: (.value.seconds // 0)}}) | from_entries' 2> /dev/null) || return 0
  vbw_scratch_json PS_UNITS "$_u"
}

# proofsteps_clean: remove a note that is not a running step (an ended run's, a
# dead process's); a proof does it before anything else, even when it runs nothing.
proofsteps_clean() {
  proofsteps_lock || return 0
  step_note_clean "$(record_read | jq -r '.lease.run // ""')"
  proofsteps_unlock
}

# proofsteps_begin TOTAL [UNITS]: a proof of TOTAL units starts; UNITS (a JSON
# array of the units' names, proofsteps_names) sizes a proof of its own by those
# units. Sets PROOFSTEPS_ON, PS_MODE (own, inside or none) and what the later
# calls need.
proofsteps_begin() {
  local record lease run me live expect first_end=null size
  PROOFSTEPS_ON=1
  PS_TOTAL=$1
  PS_UNITS=
  # The names grow with the project (Linux caps one argument at 128 KB): through a pipe.
  size=$(printf '%s' "${2:-null}" | jq -c --argjson t "$1" '{units: (. // [range(0; $t) | "unit:\(.)"])}') || size=$1
  PS_MODE=none
  PS_ROAD_NEXT=
  PS_RUN=
  PS_DOING=
  PS_START=$(vbw_now)
  PS_COUNT="$VBW_RUNTIME/proofsteps.$$.count"
  mkdir -p "$VBW_RUNTIME" 2> /dev/null || true
  printf '0\n' > "$PS_COUNT" 2> /dev/null || true
  vbw_guard_add file "$PS_COUNT"
  me=$(vbw_session)
  record=$(record_read)
  lease=$(printf '%s' "$record" | jq -c '.lease // empty')
  run=$(printf '%s' "$lease" | jq -r '.run // ""')
  proofsteps_lock || return 0
  step_note_clean "$run"
  live=$(step_live_note "$run")
  if [ -z "$live" ]; then
    if [ -z "$lease" ] || ! printf '%s' "$lease" | jq -e --arg me "$me" '(.session // "") == $me' > /dev/null; then
      PS_MODE=own
      expect=$(step_expect proof "$size")
      # The end counts from the note's own start, never from a later second.
      [ -z "$expect" ] || first_end=$(jq -n -r --arg start "$PS_START" --argjson e "$expect" '($start | fromdateiso8601) + $e | todateiso8601')
      vbw_guard_add file "$(step_note_file)"
      step_note_write "$(jq -n -c --arg me "$me" --argjson pid "$$" --arg now "$PS_START" --argjson t "$PS_TOTAL" --arg fe "$first_end" '
        {kind: "proof", run: null, session: (if $me == "" then null else $me end), pid: $pid, started_at: $now, ids: [],
         doing: "proving 0 of \($t) checks", parts: {done: 0, total: $t}, proof: null,
         first_end: (if $fe == "null" then null else $fe end), end: (if $fe == "null" then null else $fe end), late: false}')"
      # The road the proof sits on; its answer stays for the units that follow.
      PS_ROAD_NEXT=$(step_road_input)
      step_road_note_set "$PS_ROAD_NEXT"
    fi
  elif printf '%s' "$live" | jq -e --arg me "$me" '.pid == null and (.session // "") == $me' > /dev/null; then
    PS_MODE=inside
    PS_RUN=$run
    PS_DOING=$(printf '%s' "$live" | jq -r '.doing')
    step_note_write "$(printf '%s' "$live" | jq -c --argjson t "$PS_TOTAL" '.proof = {done: 0, total: $t} | .doing = "proving 0 of \($t) checks"')"
  fi
  proofsteps_unlock
}

# proofsteps_note_update N: the note says N units done (the lock is held).
proofsteps_note_update() {
  local note out total=$PS_TOTAL before after
  [ "$PS_MODE" != none ] || return 0
  note=$(step_note_file)
  [ -f "$note" ] || return 0
  before=$(jq -r '.end // ""' "$note" 2> /dev/null) || before=
  [ "$1" -le "$total" ] || total=$1
  out=$(jq -c --argjson d "$1" --argjson t "$total" --arg mode "$PS_MODE" --arg run "$PS_RUN" --argjson pid "$$" "$VBW_STEP_DEFS"'
    if $mode == "own" then select(.kind == "proof" and .pid == $pid) | .parts = {done: $d, total: $t} | step_move(now | floor)
    else select(.pid == null and .run == $run and (.proof | type) == "object") | .proof = {done: $d, total: $t} end
    | .doing = "proving \($d) of \($t) checks"' "$note" 2> /dev/null) || return 0
  [ -z "$out" ] || step_note_write "$out"
  # A unit that made the proof late moves the milestone's end with it.
  after=$(printf '%s' "$out" | jq -r '.end // ""' 2> /dev/null) || after=''
  if [ "$PS_MODE" = own ] && [ "$before" != "$after" ]; then step_road_note_set "${PS_ROAD_NEXT:-}"; fi
}

# proofsteps_unit_done: a unit just finished (called from the unit's own
# process, in any lane). Counts it once, then rewrites the note.
proofsteps_unit_done() {
  local n
  [ "${PROOFSTEPS_ON:-}" = 1 ] || return 0
  proofsteps_lock || return 0
  n=$(cat "$PS_COUNT" 2> /dev/null) || n=0
  case "$n" in '' | *[!0-9]*) n=0 ;; esac
  n=$((n + 1))
  printf '%s\n' "$n" > "$PS_COUNT" 2> /dev/null || true
  proofsteps_note_update "$n"
  proofsteps_unlock
}

# proofsteps_record N [UNITS_FILE]: the history gets a step of kind proof with N
# parts and the units (name, own seconds) in UNITS_FILE, a JSON object name ->
# {seconds}. The latest 50 of each kind are kept. Best effort, never fails the caller.
proofsteps_record() {
  local file now tmp
  file=$(step_history_file)
  [ -n "$file" ] || return 0
  [ ! -d "$file" ] || return 0
  now=$(vbw_now)
  tmp="$file.$$"
  mkdir -p "$(dirname "$file")" 2> /dev/null || return 0
  { jq -n -c --arg now "$now" --arg start "$PS_START" --argjson parts "$1" \
      --slurpfile u <(jq -c 'select(type == "object")' "${2:-/dev/null}" 2> /dev/null) \
      --slurpfile old <(jq -c 'select(type == "object" and (.steps | type) == "array")' "$file" 2> /dev/null) '
      ([$old[0].steps[]? | select(type == "object" and (.kind | type) == "string")]
        + [{kind: "proof", run: "proof-\($start | gsub("[-:]"; ""))", started_at: $start, ended_at: $now,
            seconds: (($now | fromdateiso8601) - ($start | fromdateiso8601)), parts: $parts}
            + (if ($u | length) > 0 then {units: [$u[0] | to_entries[] | {name: .key, seconds: .value.seconds}]} else {} end)])
      | {steps: (group_by(.kind) | map(.[-50:]) | add | sort_by(.ended_at))}' > "$tmp" \
    && mv -f "$tmp" "$file"; } 2> /dev/null || rm -f "$tmp" 2> /dev/null || true
  return 0
}

# proofsteps_end: the proof ended. Removes its own note, or gives the step its
# own wording back; records the units that really finished, each with its own
# seconds from the file proofsteps_units wrote (PS_UNITS).
proofsteps_end() {
  local n note out
  [ "${PROOFSTEPS_ON:-}" = 1 ] || return 0
  n=$(cat "$PS_COUNT" 2> /dev/null) || n=0
  case "$n" in '' | *[!0-9]*) n=0 ;; esac
  if proofsteps_lock; then
    note=$(step_note_file)
    case "$PS_MODE" in
      own)
        if jq -e --argjson pid "$$" '.kind == "proof" and .pid == $pid' "$note" > /dev/null 2>&1; then
          vbw_guard_drop "$note"
        fi
        ;;
      inside)
        out=$(jq -c --arg run "$PS_RUN" --arg doing "$PS_DOING" 'select(.pid == null and .run == $run) | .proof = null | .doing = $doing' "$note" 2> /dev/null) || out=
        [ -z "$out" ] || step_note_write "$out"
        ;;
    esac
    proofsteps_unlock
  fi
  vbw_guard_drop "$PS_COUNT"
  PROOFSTEPS_ON=0
  [ "$n" -le 0 ] || proofsteps_record "$n" "${PS_UNITS:-}"
  [ -z "${PS_UNITS:-}" ] || vbw_guard_drop "$PS_UNITS"
  PS_UNITS=
  return 0
}

# proofsteps_fix_done N: vbw fix done closed N fixes: that many more parts done
# of the open fix step (this session's live note of kind fix).
proofsteps_fix_done() {
  local run note out
  [ "$1" -gt 0 ] || return 0
  run=$(record_read | jq -r '.lease.run // ""')
  [ -n "$(step_live_note "$run")" ] || return 0
  proofsteps_lock || return 0
  note=$(step_note_file)
  out=$(jq -c --argjson n "$1" --arg run "$run" "$VBW_STEP_DEFS"'select(.kind == "fix" and .pid == null and .run == $run and (.parts | type) == "object")
    | .parts.done = ([.parts.done + $n, .parts.total] | min) | step_move(now | floor)' "$note" 2> /dev/null) || out=
  [ -z "$out" ] || step_note_write "$out"
  proofsteps_unlock
}
