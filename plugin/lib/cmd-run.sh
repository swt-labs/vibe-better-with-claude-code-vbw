#!/usr/bin/env bash
# vbw run start plan | build PLAN... | fix FIX... | qa | map ; vbw run end
# The run lease (docs/workflows.md): which files a workflow's agents may write.
# The guards hold every subagent to it while it is active. QA and mapping runs
# write nothing (files []); a plan run writes .vbw/ and test files (R75); the lease also tells the autonomy gate that a
# workflow is still running.

VBW_LEASE_HOURS=24

# shellcheck source=steps.sh
. "$VBW_LIB/steps.sh"
# shellcheck source=sessions.sh
. "$VBW_LIB/sessions.sh"

# run_id KIND AT: the id of a run of KIND started at AT (the time, to the
# second): KIND-20260101T120000Z, unique among the runs the record holds. A
# second run started in the same second gets -2, a third -3 (R173: a run's
# cost is kept by its id, so two runs never share one).
run_id() {
  local base
  base="$1-$(printf '%s' "$2" | tr -d ':-')"
  jq -r --arg b "$base" '[.costs.runs[]?.id | select(. == $b or startswith($b + "-"))] | length
    | if . == 0 then $b else "\($b)-\(. + 1)" end' "$VBW_RECORD"
}

cmd_run() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    start) [ $# -ge 1 ] || vbw_usage_error "usage: vbw run start plan | build PLAN... | fix FIX... | qa | map" ;;
    end) { [ $# -eq 0 ] || { [ $# -eq 1 ] && { [ "$1" = "--owner-closed" ] || [ "$1" = "--map" ]; }; }; } || vbw_usage_error "usage: vbw run end [--owner-closed | --map < MAP]" ;;
    confirm) [ $# -ge 1 ] || vbw_usage_error "usage: vbw run confirm ID..." ;;
    state) [ $# -ge 1 ] || vbw_usage_error "usage: vbw run state ID..." ;;
    *) vbw_usage_error "usage: vbw run start KIND [IDS...] | vbw run confirm ID... | vbw run state ID... | vbw run end [--owner-closed | --map < MAP]" ;;
  esac
  vbw_require_project
  if [ "$sub" = confirm ]; then
    # One line per plan, fix or phase of the open run: was its state or verdict
    # recorded? Changes nothing. Exit 1 when any was not.
    local ids report
    ids=$(printf '%s\n' "$@" | jq -R . | jq -sc 'map(select(length > 0))')
    report=$(record_read | jq -r --argjson ids "$ids" '
      .lease as $l | if $l == null then "error: no run is open: nothing to confirm"
      else $ids[] as $i
        | if $l.kind == "build" then
            ([.plans[] | select(.id == $i)][0]) as $p
            | if $p == null then "error: unknown plan \($i)"
              elif ($p.status | IN("done", "blocked")) then "\($i): recorded (\($p.status))"
              else "\($i): not recorded (still \($p.status))" end
          elif $l.kind == "fix" then
            ([.fixes[] | select(.id == $i)][0]) as $f
            | if $f == null then "error: unknown fix \($i)"
              elif $f.status == "open" then "\($i): not recorded (still open)"
              else "\($i): recorded (\($f.status))" end
          elif $l.kind == "qa" then
            ([.phases[] | select(.id == $i)][0]) as $p
            | if $p == null then "error: unknown phase \($i)"
              elif ($p.qa.at // null) != null and (($p.qa.at | fromdateiso8601) >= ($l.started_at | fromdateiso8601)) then "\($i): recorded (\($p.qa.result))"
              else "\($i): not recorded (no verdict from this run)" end
          else "error: a \($l.kind) run has nothing to confirm" end
      end')
    case "$report" in *"error: "*)
      local why
      why=$(printf '%s\n' "$report" | grep -m1 'error: ' | sed 's/^error: //')
      case "$why" in
        "no run is open"*) vbw_die "$why"$'\n'"Next: nothing to do; vbw status shows what each plan and fix recorded" ;;
        unknown*) vbw_die "$why"$'\n'"Next: confirm the ids this run was started with (vbw status names them)" ;;
        *) vbw_die "$why"$'\n'"Next: only build, fix and qa runs are confirmed; end this run with vbw run end" ;;
      esac ;;
    esac
    printf '%s\n' "$report"
    case "$report" in *"not recorded"*) return 1 ;; esac
    return 0
  fi
  if [ "$sub" = state ]; then
    # The kernel's own answer after a run's close step: {open, recorded}, one JSON
    # line. open: a run lease is held. recorded: each named plan (done or blocked),
    # fix (no longer open) or phase (a QA verdict from the latest QA run, also once
    # it ended) to whether its result is recorded. Writes nothing; an id that is
    # none of them is refused by name.
    local sids sreport
    sids=$(printf '%s\n' "$@" | jq -R . | jq -sc 'map(select(length > 0))')
    sreport=$(record_read | jq -c --argjson ids "$sids" '
      ([(.costs.runs // [])[] | select(.kind == "qa") | .started | select(. != null)]
        + [.lease | select(. != null and .kind == "qa") | .started_at] | max) as $qa
      | [$ids[] as $i
        | if any(.plans[]; .id == $i) then {k: $i, v: ([.plans[] | select(.id == $i)][0].status | IN("done", "blocked"))}
          elif any(.fixes[]; .id == $i) then {k: $i, v: ([.fixes[] | select(.id == $i)][0].status != "open")}
          elif any(.phases[]; .id == $i) then
            {k: $i, v: (([.phases[] | select(.id == $i)][0].qa.at // null) as $at
              | $at != null and $qa != null and (($at | fromdateiso8601) >= ($qa | fromdateiso8601)))}
          else {k: $i, unknown: true} end] as $r
      | if any($r[]; .unknown) then {unknown: [$r[] | select(.unknown) | .k][0]}
        else {open: (.lease != null), recorded: ($r | map({(.k): .v}) | add // {})} end')
    case "$sreport" in
      '{"unknown"'*) vbw_die "unknown id $(printf '%s' "$sreport" | jq -r .unknown): it is no plan, fix or phase"$'\n'"Next: name the ids the run was started with (vbw status lists them)" ;;
    esac
    printf '%s\n' "$sreport"
    return 0
  fi
  if [ "$sub" = end ]; then
    # Plans an interrupted Dev left "building" go back to the next wave.
    # Only the session that owns the run ends it, unless the user states the
    # owner is closed or the run is over VBW_LEASE_HOURS old.
    local run me refusal holder map='' kind
    # --map (#731): a map run ends with the map its workflow returned, on stdin. The
    # map is written before the record commit, so that commit holds it. Refused,
    # nothing is written.
    if [ "${1:-}" = "--map" ]; then
      map=$(mktemp "$VBW_RUNTIME/map.XXXXXX") || vbw_die "cannot create a temporary file in $VBW_RUNTIME: the map was not saved"$'\n'"Next: make $VBW_RUNTIME writable, then end the run with the map again"
      vbw_guard_add file "$map"
      cat > "$map"
      [ -s "$map" ] || { vbw_guard_drop "$map"; vbw_usage_error "usage: vbw run end --map < MAP (the map on stdin; it was empty)"; }
      kind=$(record_read | jq -r '.lease.kind // empty')
      case "$kind" in
        map) ;;
        '') vbw_die "no run is open: the map was not saved"$'\n'"Next: vbw run start map, then end it with this map again" ;;
        *) vbw_die "the open run is a $kind run, not a map run: the map was not saved"$'\n'"Next: let that run finish (vbw status), then map again" ;;
      esac
    fi
    # No run open: nothing to end, nothing to record (a workflow ends its own run).
    record_read | jq -e '.lease != null' > /dev/null || { printf 'no run is open\n'; return 0; }
    me=$(vbw_session)
    holder=$(holder_display "$(record_read | jq -r '.lease.session // empty')")
    refusal=$(record_read | jq -r --arg me "$me" --arg holder "$holder" --argjson h "$VBW_LEASE_HOURS" --arg closed "${1:-}" '
      .lease | select(. != null and .session != null and .session != $me
        and $closed != "--owner-closed" and (now - (.started_at | fromdateiso8601) <= $h * 3600))
      | "run \(.run) belongs to another session, \($holder)\(if $me == "" then " (this session is unknown)" else "" end). Next: wait for it, or if the user says that session is closed, vbw run end --owner-closed"')
    [ -z "$refusal" ] || vbw_die "$refusal"
    if [ -n "$map" ]; then
      mv "$map" "$VBW_DIR/map.md"
      vbw_guard_drop "$map"
    fi
    run=$(record_read | jq -r '.lease.run // "no run"')
    local lease sid opening closing cost
    lease=$(record_read | jq -c '.lease // empty')
    # The run's cost: this session's end figures minus the opening figures; null
    # (unknown, never 0) when either is missing or the run has no session.
    # shellcheck source=costs.sh
    . "$VBW_LIB/costs.sh"
    sid=$(printf '%s' "$lease" | jq -r '.session // empty')
    opening=$(printf '%s' "$lease" | jq -c '.cost // null')
    closing=$(costs_figures "$sid")
    cost=$(costs_diff "$closing" "$opening")
    local m
    m=$(record_read | jq -r .milestone.id)
    record_update '(.lease | {id: .run, kind, session: (.session // null), milestone: $m, started: .started_at, ended: $at, cost: $cost}) as $r
      | .lease = null | (.plans[] | select(.status == "building")).status = "planned"
      | .requirements |= map(del(.queued))
      | .costs.runs = ((.costs.runs // []) + [$r]) | .costs.milestones = (.costs.milestones // {})' \
      --arg m "$m" --arg at "$(vbw_now)" --argjson cost "$cost"
    record_commit "chore(vbw): record after $run"
    holder_clear
    if [ -n "$lease" ]; then step_record "$lease"; fi
    rm -f "$(step_note_file)" 2> /dev/null || true
    printf 'run ended\n'
    return 0
  fi

  local kind="$1" record ids
  shift
  record=$(record_read)
  local open holder
  holder=$(holder_display "$(printf '%s' "$record" | jq -r '.lease.session // empty')")
  open=$(printf '%s' "$record" | jq -r --arg me "$(vbw_session)" --arg holder "$holder" --argjson h "$VBW_LEASE_HOURS" '
    .lease | select(. != null and (now - (.started_at | fromdateiso8601) <= $h * 3600))
    | if .session != null and .session != $me
      then "a run is active (\(.run)) in another session, \($holder). Next: wait for it, or check vbw status"
      else "a run is active (\(.run)) in this session. Next: wait for it, or vbw run end" end')
  [ -z "$open" ] || vbw_die "$open"
  ids=$(printf '%s\n' "$@" | jq -R . | jq -sc 'map(select(length > 0))')
  case "$kind" in
    plan|qa|map) [ "$ids" = "[]" ] || vbw_usage_error "usage: vbw run start $kind" ;;
    build|fix) [ "$ids" != "[]" ] || vbw_usage_error "usage: vbw run start $kind IDS..." ;;
    *) vbw_usage_error "run kind must be plan, build, fix, qa or map" ;;
  esac
  local problem
  problem=$(printf '%s' "$record" | jq -r --arg k "$kind" --argjson ids "$ids" "$VBW_JQ_DEFS"'[
    if $k == "build" then
      (.plans | map(select(.status == "done") | .id)) as $done
      | $ids[] as $i | [.plans[] | select(.id == $i)][0] as $p
      | if $p == null then "unknown plan \($i). Next: check the id with vbw status"
        elif ($p.status | IN("planned", "building") | not) then "\($i) is \($p.status), not ready to build. Next: build a plan that is planned (vbw next shows which)"
        elif any($p.after[]; . as $a | any($done[]; . == $a) | not) then "\($i) waits for \($p.after | join(", ")). Next: build those first, or run vbw next"
        else empty end,
      # Builders share one working tree: one wave never shares a file (a
      # directory entry shares every file under it).
      ([.plans[] | select(.id as $i | any($ids[]; . == $i)) | {id, files}]) as $w
      | ([range(0; $w | length) as $a | range($a + 1; $w | length) as $b
          | $w[$a].files[] as $x | $w[$b].files[] as $y
          | select(($x | covers($y)) or ($y | covers($x))) | if ($x | length) <= ($y | length) then $x else $y end]
         | unique[]
         | "more than one plan in this wave writes \(.): build them in separate waves. Next: start one of them now and the other after it ends (vbw next shows the waves)")
    elif $k == "fix" then
      $ids[] as $i | [.fixes[] | select(.id == $i)][0] as $f
      | if $f == null then "unknown fix \($i). Next: check the id with vbw status" elif $f.status != "open" then "\($i) is \($f.status), not open. Next: start only fixes that are open (vbw status lists them)" else empty end
    else empty end] | .[0] // empty')
  [ -z "$problem" ] || vbw_die "$problem"

  # shellcheck source=costs.sh
  . "$VBW_LIB/costs.sh"
  local at runid
  at=$(vbw_now)
  runid=$(run_id "$kind" "$at")
  holder_write "$runid" "$(vbw_session)"
  record_update '
    (if $k == "build" then [.plans[] | select(.id as $i | any($ids[]; . == $i)) | .files[]] | unique
     elif $k == "fix" then
       ([.fixes[] | select(.id as $i | any($ids[]; . == $i))]) as $fx
       | if any($fx[]; has("command")) then null
         else [$fx[].req as $q | .plans[] | select(any(.reqs[]; . == $q)) | .files[]] | unique end
     elif $k == "qa" or $k == "map" then []
     else [".vbw/"] end) as $files
    | (if $k == "fix" and any(.fixes[] | select(.id as $i | any($ids[]; . == $i)); has("req") and .req != null) then
         # A requirement fix, whatever its source (R194): the Dev may edit the
         # check files of the fixes requirements that no other requirement
         # uses. When a fix of the run comes from QA (R160) it may also add test files.
         ([.fixes[] | select(.id as $i | any($ids[]; . == $i)) | .req | select(. != null)] | unique) as $qs
         | ([$qs[] as $q | [.checks[] | select(.req == $q) | (.files // [])[]] as $mine
            | [.checks[] | select(.req != $q) | (.files // [])[]] as $others
            | ($mine - $others)[]] | unique) as $own
         | (if any(.fixes[] | select(.id as $i | any($ids[]; . == $i)); .source == "qa") then {new_tests: true} else {} end)
           + {editable: $own}
       else {} end) as $qa
    | .lease = {run: $run, kind: $k, started_at: $at, files: $files}
       + (if $me == "" then {} else {session: $me} end) + $qa
       + (if $cost == null then {} else {cost: $cost} end)
    | if $k == "build" then (.plans[] | select(.id as $i | any($ids[]; . == $i))).status = "building" else . end' \
    --arg k "$kind" --arg me "$(vbw_session)" --argjson ids "$ids" --arg at "$at" --arg run "$runid" \
    --argjson cost "$(costs_figures "$(vbw_session)")"
  step_start "$kind" "$ids"
  step_say_note
  jq -r '.lease | "run \(.run) started; agents may write: \(if .files == null then "any file (protected checks excepted)" else (.files | join(", ")) end)"' "$VBW_RECORD"
}
