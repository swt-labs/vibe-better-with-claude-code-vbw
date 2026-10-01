#!/usr/bin/env bash
# vbw run start plan | build PLAN... | fix FIX... ; vbw run end
# The run lease (docs/workflows.md): which files a workflow's agents may write.
# The guards hold every subagent to it while it is active.

VBW_LEASE_HOURS=24

cmd_run() {
  local sub="${1:-}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    start) [ $# -ge 1 ] || vbw_usage_error "usage: vbw run start plan | build PLAN... | fix FIX..." ;;
    end) [ $# -eq 0 ] || vbw_usage_error "usage: vbw run end" ;;
    *) vbw_usage_error "usage: vbw run start KIND [IDS...] | vbw run end" ;;
  esac
  vbw_require_project
  if [ "$sub" = end ]; then
    # Plans an interrupted builder left "building" go back to the next wave.
    local run
    run=$(record_read | jq -r '.lease.run // "no run"')
    record_update '.lease = null | (.plans[] | select(.status == "building")).status = "planned"'
    record_commit "chore(vbw): record after $run"
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
    plan) [ "$ids" = "[]" ] || vbw_usage_error "usage: vbw run start plan" ;;
    build|fix) [ "$ids" != "[]" ] || vbw_usage_error "usage: vbw run start $kind IDS..." ;;
    *) vbw_usage_error "run kind must be plan, build or fix" ;;
  esac
  local problem
  problem=$(printf '%s' "$record" | jq -r --arg k "$kind" --argjson ids "$ids" '[
    if $k == "build" then
      (.plans | map(select(.status == "done") | .id)) as $done
      | $ids[] as $i | [.plans[] | select(.id == $i)][0] as $p
      | if $p == null then "unknown plan \($i)"
        elif ($p.status | IN("planned", "building") | not) then "\($i) is \($p.status), not ready to build"
        elif any($p.after[]; . as $a | any($done[]; . == $a) | not) then "\($i) waits for \($p.after | join(", "))"
        else empty end
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
     else null end) as $files
    | .lease = {run: "\($k)-\($at | gsub("[-:]"; ""))", kind: $k, started_at: $at, files: $files}
    | if $k == "build" then (.plans[] | select(.id as $i | any($ids[]; . == $i))).status = "building" else . end' \
    --arg k "$kind" --argjson ids "$ids" --arg at "$(vbw_now)"
  jq -r '.lease | "run \(.run) started; agents may write: \(if .files == null then "any file (protected checks excepted)" else (.files | join(", ")) end)"' "$VBW_RECORD"
}
