#!/usr/bin/env bash
# vbw check [--expect-red] [CHECK...]: run approved checks (all when none are
# given) and report; it writes to the record only an --expect-red run, kept in the
# evidence of the plans it concerns (R292). A Dev uses it red-first
# (--expect-red: every check must fail, or it proves nothing) and to see its
# own checks go green before it commits.

# shellcheck source=checks.sh
. "$VBW_LIB/checks.sh"
# shellcheck source=unittime.sh
. "$VBW_LIB/unittime.sh"
# shellcheck source=history.sh
. "$VBW_LIB/history.sh"

# RED_FIRST_DEFS (R292), on the record: red_own($p) is a plan's own checks (the checks of its
# live rules that name it or name no plan, every rule of a requirement it completes, else the
# checks of its requirements); red_ran_first($c) is true when a run of check $c came out red
# before the code commit of a plan that owns it (a plan's red_runs row with first true).
# vbw plan done reads these too.
RED_FIRST_DEFS='def red_own($p): . as $r | ([.plans[] | select(.id == $p)][0]) as $pl
  | if $pl == null then [] else
      [$pl.reqs[] as $q
        | select(any($r.checks[]; .req == $q))
        | (all($r.plans[]; .id == $p or .status == "done" or (any(.reqs[]; . == $q) | not))) as $completes
        | ([($r.requirements[] | select(.id == $q and .proof == "auto") | (.rules // [])[] | select(has("retired") | not))]) as $live
        | (if ($live | length) == 0 then [$r.checks[] | select(.req == $q) | .id]
           else [$live[] | select($completes or ((.plan // $p) == $p)) | .check] end)[]
        | select(. != null)] | unique end;
def red_ran_first($c): . as $r
  | [$r.plans[] | . as $pl | select(($r | red_own($pl.id)) | index($c)) | (.red_runs // [])[] | select(.first == true and .checks[$c] == "red")] | length > 0;
'

# red_keep RECORD RESULTS: keeps an --expect-red run in the evidence of each plan it concerns:
# the unfinished plans of the open build or fix run, or with no run open every unfinished
# plan, whose own checks it ran (red_runs: {at, head, checks, first}).
red_keep() {
  local record="$1" results="$2" ids id f files rows="{}" first head
  head=$(git -C "$VBW_ROOT" rev-parse HEAD 2> /dev/null) || return 0
  ids=$(printf '%s' "$record" | jq -r "$RED_FIRST_DEFS"'. as $r | ($r.lease.kind // "") as $k
    | [$r.plans[] | select(if $k == "build" or $k == "fix" then .status == "building" else (.status != "done" and .status != "blocked") end)
      | select(. as $pl | [($r | red_own($pl.id))[] | select(. as $c | $ARGS.named.ran | index($c))] | length > 0) | .id][]' \
    --argjson ran "$(printf '%s' "$results" | jq -c 'keys')")
  [ -n "$ids" ] || return 0
  for id in $ids; do
    files=()
    while IFS= read -r -d '' f; do files+=("$f"); done \
      < <(printf '%s' "$record" | jq -j --arg p "$id" '.plans[] | select(.id == $p) | .files[] | . + "\u0000"')
    if plan_has_commit "$id" ${files[@]+"${files[@]}"}; then first=false; else first=true; fi
    rows=$(printf '%s' "$rows" | jq -c --arg p "$id" --argjson f "$first" '. + {($p): $f}')
  done
  record_update "$RED_FIRST_DEFS"'. as $r | .plans |= map(. as $pl | if $firsts[.id] == null then . else
      .red_runs = ((.red_runs // []) + [{at: $at, head: $head, first: $firsts[.id],
        checks: ([($r | red_own($pl.id))[] | select(. as $c | $res[$c] != null) | {key: ., value: (if $res[.].status == "pass" then "green" else "red" end)}] | from_entries)}]) end)' \
    --argjson firsts "$rows" --argjson res "$(printf '%s' "$results" | jq -c 'map_values({status})')" --arg at "$(vbw_now)" --arg head "$head"
}

cmd_check() {
  local red=0
  if [ "${1:-}" = "--expect-red" ]; then
    red=1
    shift
  fi
  vbw_require_project
  cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  local record results
  record=$(record_read)
  checks_begin "$record"
  results=$(checks_run_all "$record" "$@")
  # A failure's complete output is kept (a pass removes nothing); --expect-red keeps no output.
  [ $red -eq 1 ] || checks_keep "$results" '{}' '{}' pass-leaves
  checks_end
  # --expect-red keeps the run in the evidence of the plans it concerns (R292).
  [ $red -eq 0 ] || [ "$results" = "{}" ] || red_keep "$record" "$results"
  [ "$results" != "{}" ] || vbw_die "no checks to run"
  local key line status
  while IFS=$'\x1f' read -r key status line; do
    vbw_out '%s\n' "$line"
    if [ $red -eq 0 ] && { [ "$status" = fail ] || [ "$status" = timeout ]; } && [ -f "$VBW_ROOT/$(checks_kept check "$key")" ]; then
      vbw_out '  full output: %s\n' "$(checks_kept check "$key")"
    fi
  done < <(printf '%s' "$results" | jq -r --argjson red "$red" "$UNITTIME_DEFS"'to_entries[]
    | "\(.key)\u001f\(.value.status)\u001f" + (if $red == 1 then
        (if .value.status == "pass" then "\(.key) passed before building: it proves nothing"
         else "\(.key) red (\(.value.status)), as expected" end)
      else
        "\(.key) \(.value.status) \(.value.seconds | sec)s" + (if .value.status == "pass" then ""
          else ": " + (.value.tail | split("\n") | last // "") end)
      end)')
  slots_say
  if [ $red -eq 1 ]; then
    printf '%s' "$results" | jq -e 'all(.[]; .status != "pass")' > /dev/null
  else
    printf '%s' "$results" | jq -e 'all(.[]; .status == "pass")' > /dev/null
  fi
}
