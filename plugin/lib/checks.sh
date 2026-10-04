#!/usr/bin/env bash
# Running approved checks and commands (docs/proof.md), shared by vbw check and
# vbw prove. Nothing runs unless the current contract is approved; every argv
# is executed directly, never through a shell, with stdin closed and a timeout.

# checks_begin RECORD: die unless the contract is approved. Sets CHECK_HASH and
# CHECK_OUT, a fresh output directory for this invocation (parallel Devs
# each get their own). Called directly, never in $(...).
checks_begin() {
  CHECK_HASH=$(contract_hash "$1")
  contract_approved "$CHECK_HASH" \
    || vbw_die "the contract is not approved, or changed since it was approved: review it (vbw show contract), then /vbw:approve"
  CHECK_OUT=$(mktemp -d "$VBW_RUNTIME/run.XXXXXX") || vbw_die "cannot create a directory in $VBW_RUNTIME"
}

checks_end() {
  rm -rf "$CHECK_OUT"
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
# interrupt or timeout through the guard.

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
  local id="$1" kind=shared g="$VBW_RUNTIME/gate" limit="${VBW_CHECK_WAIT_SECONDS:-900}" start blocker= idle=0 want=
  [ "$2" != true ] || kind=alone
  mkdir -p "$g" || vbw_die "cannot create $g"
  start=$(date +%s)
  while :; do
    if mkdir "$g/mutex" 2> /dev/null; then
      printf '%s\n' "$$" > "$g/mutex/pid"
      vbw_guard_add dir "$g/mutex"
      idle=0
      if blocker=$(checks_gate_blocker "$kind"); then
        # An alone check that has to wait holds back new shared checks, so it is not starved.
        if [ "$kind" = alone ] && [ -z "$want" ]; then
          want="$g/want.$$.$id"
          : > "$want"
          vbw_guard_add file "$want"
        fi
      else
        blocker=
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
      if [ -f "$g/mutex/pid" ]; then
        checks_gate_live "x.$(cat "$g/mutex/pid" 2> /dev/null)" || rm -rf "$g/mutex"
      elif [ "$idle" -gt 50 ]; then
        rm -rf "$g/mutex"
      fi
    fi
    if [ $(( $(date +%s) - start )) -ge "$limit" ]; then
      [ -z "$want" ] || vbw_guard_drop "$want"
      vbw_die "check $id waited ${limit}s for ${blocker:-the check gate}: raise VBW_CHECK_WAIT_SECONDS or find what holds it (.vbw/runtime/gate)"
    fi
    sleep 0.1
  done
}

# checks_gate_leave ID: release this check's registration.
checks_gate_leave() {
  vbw_guard_drop "$VBW_RUNTIME/gate/reg.$$.$1"
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
  for id in "${ids[@]}"; do
    res=$(checks_run "$record" "$id")
    all=$(printf '%s' "$all" | jq -c --arg id "$id" --argjson r "$res" '. + {($id): $r}')
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
  pass=$(printf '%s' "$1" | jq -r --arg id "$2" --arg h "$(contract_hash "$1")" --arg fp "$fp" \
    '.passes[$id] // empty | select(.contract == $h and .tree == $fp) | .at')
  [ -n "$pass" ] && printf '%s\n' "$pass"
}

# checks_record_passes RECORD RESULTS HASH: record a pass for each passing
# check whose served files are all committed; drop the entry of every other
# check that ran.
checks_record_passes() {
  local id fp at new='{}' ran
  at=$(vbw_now)
  ran=$(printf '%s' "$2" | jq -c 'keys')
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    fp=$(checks_fingerprint "$1" "$id") || continue
    checks_served_dirty "$1" "$id" && continue
    new=$(printf '%s' "$new" | jq -c --arg id "$id" --arg at "$at" --arg h "$3" --arg fp "$fp" '. + {($id): {at: $at, contract: $h, tree: $fp}}')
  done < <(printf '%s' "$2" | jq -r 'to_entries[] | select(.value.status == "pass") | .key')
  record_update '.passes = (((.passes // {}) | with_entries(select(.key as $k | $ran | index($k) | not))) + $new)
    | if .passes == {} then del(.passes) else . end' --argjson ran "$ran" --argjson new "$new"
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
