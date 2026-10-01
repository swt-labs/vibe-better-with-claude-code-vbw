#!/usr/bin/env bash
# Running approved checks and commands (docs/proof.md), shared by vbw check and
# vbw prove. Nothing runs unless the current contract is approved; every argv
# is executed directly, never through a shell, with stdin closed and a timeout.

# checks_begin RECORD: die unless the contract is approved. Sets CHECK_HASH and
# CHECK_OUT, a fresh output directory for this invocation (parallel builders
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

# checks_run RECORD ID: run one check; print its result object.
checks_run() {
  local record="$1" id="$2" argv=() a t want re
  while IFS= read -r -d '' a; do argv+=("$a"); done \
    < <(printf '%s' "$record" | jq -j --arg id "$id" '.checks[] | select(.id == $id) | .run[] + "\u0000"')
  t=$(printf '%s' "$record" | jq -r --arg id "$id" '.checks[] | select(.id == $id) | .timeout // 300')
  want=$(printf '%s' "$record" | jq -r --arg id "$id" '.checks[] | select(.id == $id) | .exit // 0')
  re=$(printf '%s' "$record" | jq -r --arg id "$id" '.checks[] | select(.id == $id) | .output // ""')
  checks_exec "$t" "$CHECK_OUT/$id.out" "${argv[@]}"
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
  printf '%s' "$results" | jq -e 'all(.[]; .status == "pass")' > /dev/null \
    || vbw_die "$what: $(printf '%s' "$results" | jq -r '[to_entries[] | select(.value.status != "pass") | "\(.key) \(.value.status)"] | join(", ")')"
}
