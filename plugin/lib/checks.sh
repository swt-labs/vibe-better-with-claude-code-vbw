#!/usr/bin/env bash
# Running approved checks and commands (docs/proof.md), shared by vbw check and
# vbw prove. Nothing runs unless the current contract is approved; every argv
# is executed directly, never through a shell, with stdin closed and a timeout.

# checks_begin RECORD [strict]: die unless the contract is approved. Check
# files edited since the approval wait for it (CHECK_WAITING): the checks still
# run and the files are named, but with "strict" (proof) it dies. Sets
# CHECK_HASH and CHECK_OUT, a fresh output directory for this invocation
# (parallel Devs each get their own). Called directly, never in $(...).
checks_begin() {
  local waiting
  CHECK_HASH=$(contract_hash "$1")
  CHECK_WAITING=$(contract_waiting "$1") \
    || vbw_die "the contract is not approved, or changed since it was approved: review it (vbw show contract), then ask the user with the approval menu (AskUserQuestion)"
  if [ -n "$CHECK_WAITING" ]; then
    waiting=$(printf '%s' "$CHECK_WAITING" | tr '\n' ' ')
    [ "${2:-}" != strict ] || vbw_die "check files changed since it was approved are waiting for approval: ${waiting% }: review them, then ask the user with the approval menu (AskUserQuestion)"
    printf 'vbw: waiting for approval (changed since approved): %s\n' "${waiting% }" >&2
  fi
  CHECK_OUT=$(mktemp -d "$VBW_RUNTIME/run.XXXXXX") || vbw_die "cannot create a directory in $VBW_RUNTIME"
  vbw_guard_add dir "$CHECK_OUT"
}

# Removes the output directory (also on error or interrupt, through the guard).
checks_end() {
  vbw_guard_drop "$CHECK_OUT"
}

# checks_exec TIMEOUT OUTFILE ARGV...: run ARGV from the project root, output to
# OUTFILE, stopped at TIMEOUT seconds. Sets CHECK_CODE and CHECK_SECONDS.
checks_exec() {
  local t="$1" out="$2"
  shift 2
  SECONDS=0
  CHECK_CODE=0
  # A signal ignored by the environment stays ignored in its children (some CI
  # runners start everything with SIGALRM/SIGTERM ignored). So timeout escalates
  # to SIGKILL, which cannot be ignored, and perl resets SIGALRM before the alarm.
  if command -v timeout > /dev/null 2>&1; then
    timeout -k 5 "$t" "$@" > "$out" 2>&1 < /dev/null || CHECK_CODE=$?
  else
    perl -e '$SIG{ALRM} = "DEFAULT"; alarm shift @ARGV; exec { $ARGV[0] } @ARGV or do { print STDERR "cannot run $ARGV[0]: $!\n"; exit 127 }' \
      "$t" "$@" > "$out" 2>&1 < /dev/null || CHECK_CODE=$?
  fi
  CHECK_SECONDS=$SECONDS
}

# checks_result OUTFILE TIMEOUT EXPECT_EXIT [OUTPUT_REGEX]: the result object.
# A run that lasted its whole timeout and failed was stopped by it.
checks_result() {
  jq -n --rawfile out "$1" --argjson code "$CHECK_CODE" --argjson secs "$CHECK_SECONDS" \
    --argjson t "$2" --argjson want "$3" --arg re "${4:-}" '
    ($out | split("\n") | map(select(length > 0)) | .[-20:] | join("\n") | .[-2000:]) as $tail
    | if $code != 0 and $secs >= $t then {status: "timeout", exit: null, seconds: $secs, tail: $tail}
      else {status: (if $code == $want and ($re == "" or ($out | test($re))) then "pass" else "fail" end),
            exit: $code, seconds: $secs, tail: $tail} end'
}

# The exclusion gate (R45), under .vbw/runtime/gate: every running check is a
# registration file "reg.PID.ID" holding "alone" or "shared". An alone check
# runs when nothing else is registered; a shared check runs when no alone check
# is registered and none is waiting. A short mutex directory makes the look and
# the registration one step. Registrations of a dead process are taken over
# (kill -0 is only a liveness probe), and every hold is released on exit,
# or interrupt through the guard.

# checks_gate_live FILE: the process named in the file's name (NAME.PID...) is alive.
checks_gate_live() {
  local pid="${1##*/}"
  pid="${pid#*.}"
  pid="${pid%%.*}"
  [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null
}

# checks_gate_blocker KIND: print the check blocking KIND ("alone" or "shared")
# and return 0, or return 1 when nothing blocks. Dead registrations are dropped.
checks_gate_blocker() {
  local kind="$1" f id
  for f in "$VBW_RUNTIME"/gate/reg.* "$VBW_RUNTIME"/gate/want.*; do
    [ -e "$f" ] || continue
    checks_gate_live "$f" || { rm -f "$f"; continue; }
    id="${f##*.}"
    case "${f##*/}" in
      want.*) [ "$kind" = shared ] || continue ;;
      *) [ "$kind" = alone ] || [ "$(cat "$f" 2> /dev/null)" = alone ] || continue ;;
    esac
    printf '%s\n' "$id"
    return 0
  done
  return 1
}

# checks_gate_enter ID ALONE: wait for the gate, then register this check.
checks_gate_enter() {
  local id="$1" kind=shared g="$VBW_RUNTIME/gate" idle=0 want='' owner
  [ "$2" != true ] || kind=alone
  mkdir -p "$g" || vbw_die "cannot create $g"
  while :; do
    if mkdir "$g/mutex" 2> /dev/null; then
      # The lock can vanish before its owner is written (taken as stale): retry.
      { printf '%s\n' "$$" > "$g/mutex/pid"; } 2> /dev/null || { sleep 0.1; continue; }
      vbw_guard_add dir "$g/mutex"
      idle=0
      if checks_gate_blocker "$kind" > /dev/null; then
        # An alone check that has to wait holds back new shared checks, so it is not starved.
        if [ "$kind" = alone ] && [ -z "$want" ]; then
          want="$g/want.$$.$id"
          : > "$want"
          vbw_guard_add file "$want"
        fi
      else
        [ -z "$want" ] || vbw_guard_drop "$want"
        printf '%s\n' "$kind" > "$g/reg.$$.$id"
        vbw_guard_add file "$g/reg.$$.$id"
        vbw_guard_drop "$g/mutex"
        return 0
      fi
      vbw_guard_drop "$g/mutex"
    else
      # A mutex whose owner is gone (or never wrote its pid) is taken over.
      idle=$((idle + 1))
      # The owner is read once: empty means a handover in progress, never a dead owner.
      owner=$(cat "$g/mutex/pid" 2> /dev/null)
      if [ -n "$owner" ]; then
        checks_gate_live "x.$owner" || rm -rf "$g/mutex"
      elif [ "$idle" -gt 50 ]; then
        rm -rf "$g/mutex"
      fi
    fi
    sleep 0.1
  done
}

# checks_gate_leave ID: release this check's registration.
checks_gate_leave() {
  vbw_guard_drop "$VBW_RUNTIME/gate/reg.$$.$1"
}

# checks_lost ID: the result of a check whose runner ended without leaving one.
checks_lost() {
  jq -n --arg id "$1" '{status: "skipped", exit: null, seconds: 0,
    tail: "not run: the runner of \($id) ended without a result (it was killed or crashed)"}'
}

# checks_run RECORD ID: run one check; print its result object.
checks_run() {
  local record="$1" id="$2" argv=() a t want re
  while IFS= read -r -d '' a; do argv+=("$a"); done \
    < <(printf '%s' "$record" | jq -j --arg id "$id" '.checks[] | select(.id == $id) | .run[] + "\u0000"')
  t=$(printf '%s' "$record" | jq -r --arg id "$id" '.checks[] | select(.id == $id) | .timeout // 300')
  want=$(printf '%s' "$record" | jq -r --arg id "$id" '.checks[] | select(.id == $id) | .exit // 0')
  re=$(printf '%s' "$record" | jq -r --arg id "$id" '.checks[] | select(.id == $id) | .output // ""')
  checks_gate_enter "$id" "$(printf '%s' "$record" | jq -r --arg id "$id" '.checks[] | select(.id == $id) | .alone // false')"
  checks_exec "$t" "$CHECK_OUT/$id.out" "${argv[@]}"
  checks_gate_leave "$id"
  checks_result "$CHECK_OUT/$id.out" "$t" "$want" "$re"
}

# checks_run_all RECORD [ID...]: {C1: result, ...} for the given checks (all
# when none are given); dies on an unknown id before running anything.
checks_run_all() {
  local record="$1" id all='{}' res
  shift
  local ids=("$@")
  if [ ${#ids[@]} -eq 0 ]; then
    while IFS= read -r id; do [ -n "$id" ] && ids+=("$id"); done < <(printf '%s' "$record" | jq -r '.checks[].id')
  fi
  [ ${#ids[@]} -gt 0 ] || { printf '{}\n'; return 0; }
  for id in "${ids[@]}"; do
    printf '%s' "$record" | jq -e --arg id "$id" 'any(.checks[]; .id == $id)' > /dev/null || vbw_die "unknown check $id"
  done
  local jobs
  jobs=$(vbw_check_jobs) || jobs=1
  if [ "$jobs" -le 1 ] || [ ${#ids[@]} -le 1 ]; then
    for id in "${ids[@]}"; do
      res=$(checks_run "$record" "$id") || res=
      [ -n "$res" ] || res=$(checks_lost "$id")
      all=$(printf '%s' "$all" | jq -c --arg id "$id" --argjson r "$res" '. + {($id): $r}')
    done
    printf '%s\n' "$all"
    return 0
  fi
  # In parallel, at most $jobs at a time (bash 3.2 has no wait -n: finished
  # jobs are counted with jobs -r). Each check runs in its own subshell, owning
  # no guard of the parent, and leaves its result in a file; the gate still
  # keeps alone checks by themselves. Results are joined in the checks' own order.
  local n=0 pid pids=()
  for id in "${ids[@]}"; do
    while [ "$(jobs -r | wc -l)" -ge "$jobs" ]; do sleep 0.05; done
    n=$((n + 1))
    (
      vbw_guard_reset
      res=$(checks_run "$record" "$id") || exit 1
      printf '%s\n' "$res" > "$CHECK_OUT/$n.res.tmp" && mv "$CHECK_OUT/$n.res.tmp" "$CHECK_OUT/$n.res"
    ) &
    pids+=($!)
    # An alone check is at the gate before the next check starts, so a shared
    # check launched after it never runs first.
    [ "$(printf '%s' "$record" | jq -r --arg id "$id" '.checks[] | select(.id == $id) | .alone // false')" != true ] || while kill -0 "$!" 2> /dev/null && [ ! -e "$VBW_RUNTIME/gate/reg.$$.$id" ] && [ ! -e "$VBW_RUNTIME/gate/want.$$.$id" ]; do sleep 0.05; done
  done
  # Job notices (Killed, not a child) are the shell's own: silenced here.
  for pid in "${pids[@]}"; do { wait "$pid" || true; } 2> /dev/null; done
  n=0
  for id in "${ids[@]}"; do
    n=$((n + 1))
    [ -s "$CHECK_OUT/$n.res" ] || checks_lost "$id" > "$CHECK_OUT/$n.res"
    all=$(printf '%s' "$all" | jq -c --arg id "$id" --slurpfile r "$CHECK_OUT/$n.res" '. + {($id): $r[0]}')
  done
  printf '%s\n' "$all"
}

# Recorded passes (R43). A check's served files are its own files and the files
# of every plan that serves its requirement. Its fingerprint is the committed
# content of those paths (HEAD), so it moves only when a served file changes in
# a commit. A check with no declared files, or a served path that is not in
# HEAD, has no fingerprint: it is always run and never recorded.

# checks_served RECORD ID: the check's served paths, one per line.
checks_served() {
  printf '%s' "$1" | jq -r --arg id "$2" '. as $r | .checks[] | select(.id == $id and ((.files // []) | length) > 0)
    | .req as $q | ((.files) + [$r.plans[] | select(any(.reqs[]; . == $q)) | .files[]]) | unique[]'
}

# checks_fingerprint RECORD ID: print the fingerprint, or return 1 when there is none.
checks_fingerprint() {
  local p sha lines=""
  while IFS= read -r p; do
    sha=$(git -C "$VBW_ROOT" rev-parse --verify -q "HEAD:$p") || return 1
    lines="$lines$p $sha"$'\n'
  done < <(checks_served "$1" "$2")
  [ -n "$lines" ] || return 1
  printf '%s' "$lines" | vbw_sha256
}

# checks_served_dirty RECORD ID: succeed when a served file has uncommitted changes.
checks_served_dirty() {
  local files=() p
  while IFS= read -r p; do files+=("$p"); done < <(checks_served "$1" "$2")
  [ -n "$(vbw_dirty_files ${files[@]+"${files[@]}"})" ]
}

# checks_unchanged RECORD ID: print the time of the recorded pass and succeed
# when it matches the current contract hash and fingerprint, with nothing dirty.
checks_unchanged() {
  local fp pass
  fp=$(checks_fingerprint "$1" "$2") || return 1
  checks_served_dirty "$1" "$2" && return 1
  contract_approved "$(contract_hash "$1")" || return 1
  pass=$(jq -r --arg id "$2" --arg h "$(contract_hash "$1")" --arg fp "$fp" \
    '.[$id] // empty | select(type == "object" and .contract == $h and .tree == $fp) | .at // empty' "$(checks_passes_file)" 2> /dev/null) || return 1
  [ -n "$pass" ] && printf '%s\n' "$pass"
}

# The passes live in the clone, never in the record (they change on every run
# and would make the record's history noise): $(git common dir)/vbw/passes.json,
# {check id: {at, contract, tree}}. A missing or damaged file means no reuse.
checks_passes_file() {
  local common
  common=$(git -C "$VBW_ROOT" rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || vbw_die "not a git repository"
  printf '%s/vbw/passes.json\n' "$common"
}

# checks_record_passes RECORD RESULTS HASH: record a pass for each passing
# check whose served files are all committed; drop the entry of every other
# check that ran.
checks_record_passes() {
  local id fp at new='{}' ran file lock cur tmp
  at=$(vbw_now)
  ran=$(printf '%s' "$2" | jq -c 'keys')
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    fp=$(checks_fingerprint "$1" "$id") || continue
    checks_served_dirty "$1" "$id" && continue
    new=$(printf '%s' "$new" | jq -c --arg id "$id" --arg at "$at" --arg h "$3" --arg fp "$fp" '. + {($id): {at: $at, contract: $h, tree: $fp}}')
  done < <(printf '%s' "$2" | jq -r 'to_entries[] | select(.value.status == "pass") | .key')
  file=$(checks_passes_file)
  mkdir -p "${file%/*}" || vbw_die "cannot create ${file%/*}"
  lock="${file%.json}.lock"
  vbw_lock_take "$lock" "passes"
  cur=$(jq -c 'if type == "object" then . else {} end' "$file" 2> /dev/null) || cur='{}'
  tmp=$(mktemp "${file%/*}/passes.XXXXXX") || vbw_die "cannot create a temporary file in ${file%/*}"
  printf '%s' "$cur" | jq -c --argjson ran "$ran" --argjson new "$new" \
    'with_entries(select(.key as $k | $ran | index($k) | not)) + $new' > "$tmp" && mv "$tmp" "$file"
  vbw_guard_drop "$lock"
}

# checks_must_pass RECORD WHAT CHECK...: run the checks now and die with
# "WHAT: <the failing checks>" unless every one passes. No checks: nothing runs.
checks_must_pass() {
  local record="$1" what="$2" results
  shift 2
  [ $# -gt 0 ] || return 0
  cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  checks_begin "$record"
  results=$(checks_run_all "$record" "$@")
  checks_end
  checks_record_passes "$record" "$results" "$CHECK_HASH"
  printf '%s' "$results" | jq -e 'all(.[]; .status == "pass")' > /dev/null \
    || vbw_die "$what: $(printf '%s' "$results" | jq -r '[to_entries[] | select(.value.status != "pass") | "\(.key) \(.value.status)"] | join(", ")')"
}
