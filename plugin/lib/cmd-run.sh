#!/usr/bin/env bash
# vbw run start plan | build PLAN... | fix FIX... | qa | map ; vbw run end
# The run lease (docs/workflows.md): which files a workflow's agents may write.
# The guards hold every subagent to it while it is active. QA and mapping runs
# write nothing (files []); a plan run writes .vbw/ and test files (R75); the lease also tells the autonomy gate that a
# workflow is still running.

VBW_LEASE_HOURS=24

cmd_run() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    start) [ $# -ge 1 ] || vbw_usage_error "usage: vbw run start plan | build PLAN... | fix FIX... | qa | map" ;;
    end) { [ $# -eq 0 ] || { [ $# -eq 1 ] && [ "$1" = "--owner-closed" ]; }; } || vbw_usage_error "usage: vbw run end [--owner-closed]" ;;
    confirm) [ $# -ge 1 ] || vbw_usage_error "usage: vbw run confirm ID..." ;;
    *) vbw_usage_error "usage: vbw run start KIND [IDS...] | vbw run confirm ID... | vbw run end [--owner-closed]" ;;
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
    case "$report" in *"error: "*) vbw_die "$(printf '%s\n' "$report" | grep -m1 'error: ' | sed 's/^error: //')" ;; esac
    printf '%s\n' "$report"
    case "$report" in *"not recorded"*) return 1 ;; esac
    return 0
  fi
  if [ "$sub" = end ]; then
    # Plans an interrupted Dev left "building" go back to the next wave.
    # Only the session that owns the run ends it, unless the user states the
    # owner is closed or the run is over VBW_LEASE_HOURS old.
    local run me refusal
    me=$(vbw_session)
    refusal=$(record_read | jq -r --arg me "$me" --argjson h "$VBW_LEASE_HOURS" --arg closed "${1:-}" '
      .lease | select(. != null and .session != null and .session != $me
        and $closed != "--owner-closed" and (now - (.started_at | fromdateiso8601) <= $h * 3600))
      | "run \(.run) belongs to another session\(if $me == "" then " (this session is unknown)" else "" end): wait for it, or if the user says that session is closed, vbw run end --owner-closed"')
    [ -z "$refusal" ] || vbw_die "$refusal"
    run=$(record_read | jq -r '.lease.run // "no run"')
    local lease
    lease=$(record_read | jq -c '.lease // empty')
    record_update '.lease = null | (.plans[] | select(.status == "building")).status = "planned"'
    record_commit "chore(vbw): record after $run"
    [ -z "$lease" ] || vbw_step_add "$lease"
    printf 'run ended\n'
    return 0
  fi

  local kind="$1" record ids
  shift
  record=$(record_read)
  printf '%s' "$record" | jq -e --argjson h "$VBW_LEASE_HOURS" \
    '.lease == null or (now - (.lease.started_at | fromdateiso8601) > $h * 3600)' > /dev/null \
    || vbw_die "a run is active ($(printf '%s' "$record" | jq -r .lease.run)): vbw run end first"
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
      | if $p == null then "unknown plan \($i)"
        elif ($p.status | IN("planned", "building") | not) then "\($i) is \($p.status), not ready to build"
        elif any($p.after[]; . as $a | any($done[]; . == $a) | not) then "\($i) waits for \($p.after | join(", "))"
        else empty end,
      # Builders share one working tree: one wave never shares a file (a
      # directory entry shares every file under it).
      ([.plans[] | select(.id as $i | any($ids[]; . == $i)) | {id, files}]) as $w
      | ([range(0; $w | length) as $a | range($a + 1; $w | length) as $b
          | $w[$a].files[] as $x | $w[$b].files[] as $y
          | select(($x | covers($y)) or ($y | covers($x))) | if ($x | length) <= ($y | length) then $x else $y end]
         | unique[]
         | "more than one plan in this wave writes \(.): build them in separate waves (vbw next)")
    elif $k == "fix" then
      $ids[] as $i | [.fixes[] | select(.id == $i)][0] as $f
      | if $f == null then "unknown fix \($i)" elif $f.status != "open" then "\($i) is \($f.status), not open" else empty end
    else empty end] | .[0] // empty')
  [ -z "$problem" ] || vbw_die "$problem"

  record_update '
    (if $k == "build" then [.plans[] | select(.id as $i | any($ids[]; . == $i)) | .files[]] | unique
     elif $k == "fix" then
       ([.fixes[] | select(.id as $i | any($ids[]; . == $i))]) as $fx
       | if any($fx[]; has("command")) then null
         else [$fx[].req as $q | .plans[] | select(any(.reqs[]; . == $q)) | .files[]] | unique end
     elif $k == "qa" or $k == "map" then []
     else [".vbw/"] end) as $files
    | .lease = {run: "\($k)-\($at | gsub("[-:]"; ""))", kind: $k, started_at: $at, files: $files}
       + (if $me == "" then {} else {session: $me} end)
    | if $k == "build" then (.plans[] | select(.id as $i | any($ids[]; . == $i))).status = "building" else . end' \
    --arg k "$kind" --arg me "$(vbw_session)" --argjson ids "$ids" --arg at "$(vbw_now)"
  jq -r '.lease | "run \(.run) started; agents may write: \(if .files == null then "any file (protected checks excepted)" else (.files | join(", ")) end)"' "$VBW_RECORD"
}
