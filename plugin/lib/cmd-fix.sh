#!/usr/bin/env bash
# vbw fix check FIX < CHECK: an open fix QA opened registers its regression test
# as a check of the finding's requirement (run, files and the optional exit,
# output, timeout, alone, as vbw apply takes them; the next free C id, marked
# fix: FIX). Any other fix is refused with what to do instead.
# vbw fix done ID [ID...] | retry ID (docs/proof.md). "done" is verified, not claimed:
# for a requirement's fix, none of the files it may touch has uncommitted
# changes, and the checks of every finished requirement pass now (the one reuse
# rule of vbw prove picks which run, in clean copies), so a fix cannot quietly break other work. Then, for a requirement
# proved by checks, or a project command, it awaits proof: the next vbw prove
# closes it or counts a failed attempt. For a [human] requirement no check can
# decide, so the fix closes and the requirement returns to the user for
# acceptance. `retry` reopens an escalated fix for one more attempt (the user's
# decision at the cap; a further failure escalates again). Several fixes close in
# one command: the candidate checks run once, a failing check
# fails the fixes whose files serve it (every named fix when it serves none), and a fix that cannot close is named while the
# others still close; the exit code is non-zero when any could not.

# cmd_fix_files RECORD ID: the files the fix's requirement may touch, NUL-separated.
cmd_fix_files() {
  printf '%s' "$1" | jq -j --arg f "$2" '
    [.fixes[] | select(.id == $f)][0].req as $q
    | select($q != null) | [.plans[] | select(any(.reqs[]; . == $q)) | .files[]] | unique[] | . + "\u0000"'
}

# cmd_fix_checks RECORD ID: the checks of the finished requirements the fix's files serve.
cmd_fix_checks() {
  local files=() f
  while IFS= read -r -d '' f; do files+=("$f"); done < <(cmd_fix_files "$1" "$2")
  printf '%s' "$1" | jq -r --slurpfile files \
    <(printf '%s\n' ${files[@]+"${files[@]}"} | jq -R . | jq -sc 'map(select(length > 0))') '
    $files[0] as $files | . as $r
    | [.requirements[] | .id as $q | [$r.plans[] | select(any(.reqs[]; . == $q))] as $ps
       | select(($ps | length) > 0 and all($ps[]; .status == "done")
                and any($ps[].files[]; . as $x | any($files[]; . == $x))) | $q] as $reqs
    | .checks[] | select(.req as $q | any($reqs[]; . == $q)) | .id'
}

# cmd_fix_finished_checks RECORD: the checks of every finished requirement (it
# has plans and all are done).
cmd_fix_finished_checks() {
  printf '%s' "$1" | jq -r '. as $r
    | [.requirements[] | .id as $q | [$r.plans[] | select(any(.reqs[]; . == $q))] as $ps
       | select(($ps | length) > 0 and all($ps[]; .status == "done")) | $q] as $reqs
    | .checks[] | select(.req as $q | any($reqs[]; . == $q)) | .id'
}

# cmd_fix_check FIX: the check document on stdin becomes a check of the finding's requirement.
cmd_fix_check() {
  [ $# -eq 1 ] || vbw_usage_error "usage: vbw fix check FIX < CHECK  (a JSON object: run, files and optionally exit, output, timeout, alone)"
  vbw_require_project
  local id="$1" doc record why
  doc=$(cat)
  printf '%s' "$doc" | jq -e 'type == "object" and (keys - ["run", "files", "exit", "output", "timeout", "alone"]) == []
      and (.run | type == "array") and (.files | type == "array" and length > 0)' > /dev/null 2>&1 \
    || vbw_usage_error "the check is a JSON object on stdin: run (argv array), files (the test files it runs, non-empty) and optionally exit, output, timeout, alone"
  record=$(record_read)
  why=$(printf '%s' "$record" | jq -r --arg f "$id" '[.fixes[] | select(.id == $f)][0] as $x
    | if $x == null then "unknown fix \($f)"
      elif $x.status != "open" then "\($f) is \($x.status), not open: its checks can no longer change; QA opens a new fix if the problem remains"
      elif $x.source != "qa" then "\($f) was not opened by QA: only the fix of a QA finding adds a regression test; a proof failure is fixed in the code its check already tests, and a new check goes through the plan (vbw next)"
      else empty end')
  [ -z "$why" ] || vbw_die "$why"
  local f
  while IFS= read -r f; do
    [ -f "$VBW_ROOT/$f" ] || vbw_die "$f does not exist: create the test file before registering it"
  done < <(printf '%s' "$doc" | jq -r '.files[] | strings')
  record_update "$VBW_JQ_DEFS"'[.fixes[] | select(.id == $f)][0].req as $q
    | .checks += [{id: (.checks | next_id("C")), req: $q} + $d + {fix: $f}]' --arg f "$id" --argjson d "$doc"
  jq -r --arg f "$id" '.checks[-1] | "\(.id) added to \(.req) by \($f)"' "$VBW_RECORD"
}

# fix_unit_lines RESULTS ORDER WHY REUSED: one line per unit, in ORDER (a JSON
  # array of names): a reused one says since when it passed, one that ran gives
  # the proof summary's line (status, exit, seconds, why it ran, the last line of
  # a failing one's output). WHY and REUSED map a name to text.
fix_unit_lines() {
  printf '%s' "$1" | jq -r --argjson order "$2" --argjson w "$3" --argjson re "$4" "$UNITTIME_DEFS"'. as $r | $order[] | . as $k
    | if $re[$k] then "\($k) unchanged since its pass (\($re[$k]))"
      elif $r[$k] then $r[$k] | "\($k) \(.status)\(if .status == "fail" or .status == "timeout" then " (exit \(.exit // "none"))" else "" end) \(.seconds | sec)s\(if $w[$k] then " ran: \($w[$k])" else "" end)\(if .status == "pass" then "" else ": " + ((.tail // "") | split("\n") | last // "") end)"
      else empty end'
}

# vbw fix restore FILE...: the user chose to bring each FILE, delivered by a plan and
# changed outside any plan (the last proof's deviations, no decision covering it),
# back to what its plan made. Each gets one fix naming it (restore), on the plan's
# first requirement; the proof closes it once the file no longer deviates. All or
# nothing: an unknown or already restoring file refuses the whole command.
cmd_fix_restore() {
  [ $# -ge 1 ] || vbw_usage_error "usage: vbw fix restore FILE [FILE...]"
  vbw_require_project
  local record dv dvf files why
  record=$(record_read)
  # shellcheck source=cmd-next.sh
  . "$VBW_LIB/cmd-next.sh"
  dv=$(qa_deviations "$record")
  # The record update reads the deviations from a file of its own (a pipe would be gone by then).
  vbw_scratch_json dvf "$dv"
  files=$(printf '%s\n' "$@" | jq -R . | jq -sc 'unique')
  why=$(printf '%s' "$record" | jq -r --slurpfile dv <(printf '%s' "$dv") --argjson fs "$files" '. as $r
    | [$dv[0][]?[] | select(.decision == null)] as $d
    | $fs[] as $f
    | ([$r.fixes[] | select(.restore == $f and (.status | IN("open", "fixed"))) | .id][0]) as $by
    | if any($d[]; .file == $f) | not then "\($f) is not a file its plan delivered that changed outside any plan (vbw show evidence lists them)"
      elif $by != null then "\($f) is already being restored by \($by)"
      else empty end')
  [ -z "$why" ] || vbw_die "$(printf '%s' "$why" | head -1)"
  record_update "$VBW_JQ_DEFS"'. as $r | [$dv[0][]?[] | select(.decision == null)] as $d
    | reduce $fs[] as $f (.;
        first($d[] | select(.file == $f)) as $x
        | .fixes += [{id: next_fix_id, req: first($r.plans[] | select(.id == $x.plan) | .reqs[0]), restore: $f, attempts: 0, status: "open",
            note: "Restore \($f): \($x.plan) delivered it (commit \($x.commit[0:12])) and it was \($x.change) outside any plan; the user chose to bring it back to what \($x.plan) made"}])' \
    --slurpfile dv "$dvf" --argjson fs "$files"
  vbw_guard_drop "$dvf"
  jq -r --argjson fs "$files" '.fixes[] | select(.status == "open" and (.restore | IN($fs[]))) | "\(.id) opened for \(.req): restore \(.restore)"' "$VBW_RECORD"
}

cmd_fix() {
  local mode="${1:-}"
  [ "$mode" != check ] || { shift; cmd_fix_check "$@"; return; }
  [ "$mode" != restore ] || { shift; cmd_fix_restore "$@"; return; }
  { [ "$mode" = "done" ] && [ $# -ge 2 ]; } || { [ "$mode" = retry ] && [ $# -eq 2 ]; } \
    || vbw_usage_error "usage: vbw fix done ID [ID...] | fix retry ID | fix check FIX < CHECK | fix restore FILE [FILE...]"
  shift
  vbw_require_project
  local record id
  if [ "$mode" = retry ]; then
    record=$(record_read)
    id="$1"
    printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f)' > /dev/null || vbw_die "unknown fix $id"
    # The user decides to try again after the cap: one more attempt.
    printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f and .status == "escalated")' > /dev/null \
      || vbw_die "$id is not escalated"
    record_update '(.fixes[] | select(.id == $f)).status = "open"' --arg f "$id"
    printf '%s reopened for one more attempt\n' "$id"
    return 0
  fi

  # The checks of every finished requirement are the candidates; the one reuse
  # rule of vbw prove picks which run, on clean copies, and their read lists are kept.
  # shellcheck source=checks.sh
  . "$VBW_LIB/checks.sh"
  # shellcheck source=proofcopy.sh
  . "$VBW_LIB/proofcopy.sh"
  # shellcheck source=proofreuse.sh
  . "$VBW_LIB/proofreuse.sh"
  # shellcheck source=proofcauses.sh
  . "$VBW_LIB/proofcauses.sh"
  # shellcheck source=testfiles.sh
  . "$VBW_LIB/testfiles.sh"
  # shellcheck source=proofsteps.sh
  . "$VBW_LIB/proofsteps.sh"
  # shellcheck source=unittime.sh
  . "$VBW_LIB/unittime.sh"
  # VBW's own steps tile the command up to its record step (R202): the reading
  # and the judging of the named fixes are planning; a wait for a slot is not.
  prooftime_begin
  record=$(record_read)

  # Each named fix is judged alone: unknown, not open and dirty fixes are named
  # and left out; the rest are candidates.
  local ids=() bad=0 dirty f seen=" "
  local fl=()
  for id in "$@"; do
    case "$seen" in *" $id "*) continue ;; esac
    seen="$seen$id "
    if ! printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f)' > /dev/null; then
      printf 'vbw: unknown fix %s\n' "$id" >&2
      bad=1
      continue
    fi
    if ! printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f and .status == "open")' > /dev/null; then
      printf 'vbw: %s is not open\n' "$id" >&2
      bad=1
      continue
    fi
    fl=()
    while IFS= read -r -d '' f; do fl+=("$f"); done < <(cmd_fix_files "$record" "$id")
    dirty=$(vbw_dirty_files ${fl[@]+"${fl[@]}"})
    if [ -n "$dirty" ]; then
      printf 'vbw: %s has uncommitted changes in: %s (commit them with vbw commit PLAN "fix(scope): ...")\n' "$id" "$dirty" >&2
      bad=1
      continue
    fi
    ids+=("$id")
  done

  local own_json cands_json tf_json obuf='' ebuf='' wait_files='' wf mine todo=() cands=() c at results='{}' held head noreads causes='' keys served='[]' tfres='{}' tfbad='' off wmap='{}' rmap='{}' tfwant=0 began=0
  # The run and its slot store open before the planning, which holds vbw:plan
  # (R202); the contract must be approved only when something will run.
  [ ${#ids[@]} -eq 0 ] || { mkdir -p "$VBW_RUNTIME" || vbw_die "cannot create $VBW_RUNTIME"; checks_open; began=1; }
  prooftime_step planning
  slots_hold vbw:plan || true
  prooftime_mark
  if [ ${#ids[@]} -gt 0 ]; then
    for id in "${ids[@]}"; do
      served=$(printf '%s' "$served" | jq -c --slurpfile s <(cmd_fix_checks "$record" "$id" | jq -R . | jq -sc 'map(select(length > 0))') '. + $s[0] | unique')
    done
    held=$(contract_held "$record")
    # Check files new or changed since the approval wait for it, whatever opened the fix.
    wait_files=$(contract_waiting "$record") || wait_files=
    # T174: nothing is proven before the user approves them, and no agent can ask for that,
    # so no check runs now (a long re-check would only wait for the approval): the fixes
    # await the proof that follows it, which runs every check.
    if [ -n "$wait_files" ]; then
      # A file is named only where a check these fixes serve reads it.
      mine=$(printf '%s' "$wait_files" | jq -R . | jq -rs --argjson served "$served" --slurpfile rec <(printf '%s' "$record") \
        'map(select(length > 0)) | map(select(. as $f | any($rec[0].checks[]; (.id as $i | $served | index($i)) and ((.files // []) | index($f))))) | join(", ")')
      printf 'check files are waiting for approval, so no check runs before it%s\n' "${mine:+: $mine}"
      printf 'the user approves them first (vbw next asks); then vbw prove runs every check\n'
    fi
    cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
    mkdir -p "$VBW_RUNTIME" || vbw_die "cannot create $VBW_RUNTIME"
    proofsteps_clean
    noreads=$(reads_probe "$VBW_RUNTIME" 2>&1) || true
    head=$(vbw_head_tree 2> /dev/null) || head=
    # Any cause (R168) runs every candidate check, as it does in vbw prove, except
    # "nothing committed since the last passing proof": that proof is what fix done wants.
    causes=
    [ -n "$wait_files" ] || causes=$(proofcauses_find "$record" 0 "$head" fix)
    while IFS= read -r c; do
      [ -z "$c" ] || vbw_out 'every candidate check runs: %s\n' "$c"
    done < <(printf '%s\n' "$causes")
    # shellcheck disable=SC2034 # read by proofreuse_judge
    PROOFREUSE_STORE=$(proofreuse_store_read)
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      if printf '%s\n' "$held" | grep -x -- "$c" > /dev/null; then
        # A check a fix added waits for the user's approval: the fix closes with the approved checks.
        vbw_out '%s waits for the user'"'"'s approval (a check %s added: %s); vbw next asks, then vbw prove runs it\n' "$c" \
          "$(printf '%s' "$record" | jq -r --arg c "$c" '.checks[] | select(.id == $c) | .fix')" \
          "$(printf '%s' "$record" | jq -r --arg c "$c" '.checks[] | select(.id == $c) | .files | join(", ")')"
        continue
      fi
      mine=''
      while IFS= read -r wf; do
        [ -n "$wf" ] || continue
        printf '%s' "$record" | jq -e --arg c "$c" --arg f "$wf" 'any(.checks[]; .id == $c and ((.files // []) | index($f)))' > /dev/null && mine="$mine${mine:+, }$wf"
      done <<< "$wait_files"
      if [ -n "$mine" ]; then
        vbw_out '%s reads %s, waiting for approval; vbw next asks, then vbw prove runs it\n' "$c" "$mine"
        continue
      fi
      cands+=("$c")
    done < <([ -n "$wait_files" ] || cmd_fix_finished_checks "$record")
    # The candidates' reuse, decided together: one pass for the fingerprints, one for the rule.
    if [ ${#cands[@]} -gt 0 ] && [ -n "$causes" ]; then
      todo=("${cands[@]}")
    elif [ ${#cands[@]} -gt 0 ]; then
      keys=$(printf '%s\0' "${cands[@]}" | jq -Rsc 'split("\u0000")[:-1] | map("check:" + .)')
      proofreuse_fps_need "$record" "$keys"
      proofreuse_unpack "$(proofreuse_judge "$keys" "$head" "")" "check:"
      wmap=$PU_WHY
      todo=(${PU_TODO[@]+"${PU_TODO[@]}"})
      rmap=$(printf '%s' "$PU_REUSE" | jq -c 'map_values(.at)')
    fi
  fi
  # A test command that failed as test files is re-run on its own, file by file,
  # through the approved single-file form, never as the whole test command. The
  # files are planned as a proof plans them (a file that did not pass runs, the
  # one reuse rule decides the rest), except for the proof's "nothing committed" cause.
  # shellcheck disable=SC2034 # TF_INDEX is read by testfiles_run and testfiles_command
  TF_PATHS=() TF_TODO=() TF_REUSE='{}' TF_WHY='{}' TF_INDEX='{"owned": [], "dups": [], "match": [], "map": {}}'
  # shellcheck disable=SC2034 # read by testfiles_plan
  PROVE_NAMES='[]' TODO_COMMANDS='[]' REUSE_COMMANDS='{}' WHY_COMMANDS='{}'
  if [ ${#ids[@]} -gt 0 ] && [ -z "$wait_files" ] && testfiles_on "$record"; then
    for id in "${ids[@]}"; do
      printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f and .command == "test")' > /dev/null && tfwant=1
    done
    if [ "$tfwant" = 1 ]; then
      if [ -n "$causes" ]; then testfiles_plan "$record" 1 fix; else testfiles_plan "$record" 0 fix; fi
    fi
  fi
  slots_release vbw:plan
  if [ ${#todo[@]} -gt 0 ] || [ ${#TF_TODO[@]} -gt 0 ]; then
    checks_approved "$record"
    at=$(vbw_now)
    off=false
    [ -z "$noreads" ] || off=true
    c=${#todo[@]}
    [ "$c" -ge ${#TF_TODO[@]} ] || c=${#TF_TODO[@]}
    prooftime_step planning
    slots_hold vbw:copies || true
    prooftime_mark
    proofcopy_create_slots "$(proofcopy_slots "$c")"
    prooftime_step copies
    slots_release vbw:copies
    proofsteps_begin "$((${#todo[@]} + ${#TF_TODO[@]}))" "$({
      for c in ${todo[@]+"${todo[@]}"}; do printf 'check:%s\n' "$c"; done
      for c in ${TF_TODO[@]+"${TF_TODO[@]}"}; do printf 'file:%s\n' "$c"; done
    } | proofsteps_names)"
    prooftime_step copies
    # Each unit counts its own read tracking; the units' commands are no step.
    [ ${#todo[@]} -eq 0 ] || results=$(checks_run_all "$record" "${todo[@]}")
    [ ${#TF_TODO[@]} -eq 0 ] || tfres=$(testfiles_run "$record")
    prooftime_mark
    # A failure's complete output stays readable under vbw prove's names (R195).
    checks_keep "$results" '{}' "$tfres"
    prooftime_step saving
    proofcopy_release
    prooftime_step copies
    checks_end
    began=0
    proofsteps_units "$results" '{}' "$tfres"
    proofsteps_end
    results=$(printf '%s' "$results" | jq -c --argjson off "$off" "$PROVE_FLAT")
    tfres=$(printf '%s' "$tfres" | jq -c --argjson off "$off" "$PROVE_FLAT")
    prooftime_step saving
    slots_hold vbw:save || true
    prooftime_mark
    proofreuse_save "$record" "$results" '{}' "$head" "$at"
    [ "$tfres" = '{}' ] || testfiles_save "$record" "$tfres" "$head" "$at"
    prooftime_step saving
    slots_release vbw:save
    tfbad=$(printf '%s' "$tfres" | jq -r '[to_entries[] | select(.value.status != "pass") | "\(.key) \(.value.status)"] | join(", ")')
  else
    prooftime_step planning
  fi
  [ "$began" -eq 0 ] || checks_end

  # The fixes are judged and the record written before anything prints, so the
  # report lines can carry the record's time; what the judging says is printed after them.
  # Each fix ends as it would alone. A failing check fails the named fixes whose
  # files serve it, or every named fix when it serves none of them.
  local closed=() failed human fixed='[]' humans='[]'
  for id in ${ids[@]+"${ids[@]}"}; do
    if [ -n "$tfbad" ] && printf '%s' "$record" | jq -e --arg f "$id" 'any(.fixes[]; .id == $f and .command == "test")' > /dev/null; then
      ebuf="$ebuf$(printf 'vbw: %s: these test files still do not pass: %s\n' "$id" "$tfbad")"$'\n'
      bad=1
      continue
    fi
    failed=$(printf '%s' "$results" | jq -r --slurpfile mine <(cmd_fix_checks "$record" "$id" | jq -R . | jq -sc 'map(select(length > 0))') --argjson all "$served" \
      '$mine[0] as $mine | [to_entries[] | select(.value.status != "pass" and (.key as $k | ($mine | index($k)) or (($all | index($k)) | not))) | "\(.key) \(.value.status)"] | join(", ")')
    if [ -n "$failed" ]; then
      ebuf="$ebuf$(printf 'vbw: %s broke finished work: these checks of finished requirements do not pass: %s\n' "$id" "$failed")"$'\n'
      bad=1
      continue
    fi
    human=$(printf '%s' "$record" | jq -r --arg f "$id" '. as $r | [.fixes[] | select(.id == $f)][0] as $x
      | any($r.requirements[]; .id == $x.req and .proof == "human")')
    if [ "$human" = true ]; then
      humans=$(printf '%s' "$humans" | jq -c --arg f "$id" '. + [$f]')
    else
      fixed=$(printf '%s' "$fixed" | jq -c --arg f "$id" '. + [$f]')
    fi
    closed+=("$id")
  done
  [ ${#closed[@]} -eq 0 ] || record_update '. as $r | (.fixes[] | select(.id as $i | $fixed | index($i))).status = "fixed"
      | (.fixes[] | select(.id as $i | $humans | index($i))).status = "closed"
      | (.requirements[] | select(.id as $q | any($r.fixes[]; (.id as $i | $humans | index($i)) and .req == $q))).status = "open"' \
      --argjson fixed "$fixed" --argjson humans "$humans"
  # Judging the fixes and writing the record are the record step; the split is read
  # after it, so the wall covers every step but the units' own tracking (R202).
  prooftime_step record
  own_json=$(prooftime_total)
  if [ ${#closed[@]} -gt 0 ]; then
    proofsteps_fix_done "${#closed[@]}"
    for id in "${closed[@]}"; do
      if printf '%s' "$humans" | jq -e --arg f "$id" 'index($f)' > /dev/null; then
        obuf="$obuf$(printf '%s closed: its requirement goes back to the user for acceptance\n' "$id")"$'\n'
      else
        obuf="$obuf$(printf '%s fixed: vbw prove decides\n' "$id")"$'\n'
      fi
    done
  fi
  # What ran and what was reused, checks first and then test files, each in its
  # record's order, in the proof summary's wording; then both counts, after
  # every per-unit line as the proof summary prints them, every time (D304).
  local order
  order=$(printf '%s\n' ${cands[@]+"${cands[@]}"} | jq -R . | jq -sc 'map(select(length > 0))')
  cands_json=$order
  fix_unit_lines "$results" "$order" "$wmap" "$rmap"
  if [ ${#TF_PATHS[@]} -gt 0 ]; then order=$(printf '%s\n' "${TF_PATHS[@]}" | jq -R . | jq -sc 'map(select(length > 0))'); else order='[]'; fi
  tf_json=$order
  fix_unit_lines "$tfres" "$order" "$TF_WHY" "$(printf '%s' "$TF_REUSE" | jq -c 'map_values(.at)')"
  printf 'checks: %s ran, %s reused\n' "${#todo[@]}" "$(printf '%s' "$rmap" | jq 'length')"
  printf 'test files: %s ran, %s reused\n' "${#TF_TODO[@]}" "$(printf '%s' "$TF_REUSE" | jq 'length')"
  # The two report lines, from this round's results, reuse map and causes, then the
  # slowest units that ran (unittime.sh). All but the split grow with the project
  # (the reused results carry their read lists): by file.
  local units_json
  units_json=$(jq -n -c --argjson own "$own_json" --rawfile causes <(printf '%s' "$causes") --slurpfile o <(printf '%s' "$cands_json") --slurpfile t <(printf '%s' "$tf_json") \
    --slurpfile w <(printf '%s' "$wmap") --slurpfile r <(printf '%s' "$rmap") --slurpfile tw <(printf '%s' "$TF_WHY") --slurpfile tr <(printf '%s' "$TF_REUSE" | jq -c 'map_values(true)') \
    --slurpfile st <(printf '%s' "$results" | jq -c 'map_values({status, seconds})') --slurpfile tfst <(printf '%s' "$tfres" | jq -c 'map_values({status, seconds})') \
    '$o[0] as $order | $t[0] as $tfo | $w[0] as $why | $r[0] as $re | $tw[0] as $tfwhy | $tr[0] as $tfre
    | {own: $own, causes: ($causes | split("\n") | map(select(length > 0))),
      checks: ($order | map({key: ., value: (if $re[.] then {status: "pass", reused: true} else {status: ($st[0][.].status // "pass"), seconds: ($st[0][.].seconds // 0)} + (if $why[.] then {why: $why[.]} else {} end) end)}) | from_entries),
      test_files: ($tfo | map({key: ., value: (if $tfre[.] then {status: "pass", reused: true} else {status: ($tfst[0][.].status // "pass"), seconds: ($tfst[0][.].seconds // 0)} + (if $tfwhy[.] then {why: $tfwhy[.]} else {} end) end)}) | from_entries)}')
  printf '%s' "$units_json" | prooftime_lines
  printf '%s' "$units_json" | unittime_ran_line "$(printf '%s' "$record" | unittime_budget)"
  printf '%s' "$ebuf" >&2
  printf '%s' "$obuf"

  prooftime_end
  slots_say
  return "$bad"
}
