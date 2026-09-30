#!/usr/bin/env bash
# vbw prove [--expect-red [CHECK...]]: run exactly what the user approved and
# record the evidence (docs/proof.md). Nothing unapproved ever executes.

VBW_FIX_CAP=3
VBW_COMMAND_TIMEOUT=900

cmd_prove() {
  local red=0
  if [ "${1:-}" = "--expect-red" ]; then
    red=1
    shift
  fi
  [ $red -eq 1 ] || [ $# -eq 0 ] || vbw_usage_error "usage: vbw prove [--expect-red [CHECK...]]"
  vbw_require_project
  cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  local record hash
  record=$(record_read)
  hash=$(contract_hash "$record")
  contract_approved "$hash" \
    || vbw_die "the contract is not approved, or changed since it was approved: review it (vbw show contract), then /vbw:approve"
  PROVE_OUT="$VBW_RUNTIME/prove"
  rm -rf "$PROVE_OUT"
  mkdir -p "$PROVE_OUT"

  if [ $red -eq 1 ]; then
    prove_red "$record" "$@"
    return
  fi

  local checks commands scope ev
  checks=$(prove_checks "$record")
  commands=$(prove_commands "$record")
  scope=$(prove_scope "$record")
  ev=$(jq -n --arg at "$(vbw_now)" --arg h "$hash" --argjson c "$checks" --argjson m "$commands" --argjson s "$scope" \
    '{at: $at, contract: $h, checks: $c, commands: $m, scope: $s,
      passed: (all($c[]; .status == "pass") and all($m[]; .status == "pass" or .status == "skipped") and ($s | length) == 0)}')
  record_update "$VBW_JQ_DEFS$(cat "$VBW_LIB/prove.jq")" --argjson ev "$ev" --argjson cap "$VBW_FIX_CAP"
  prove_summary
}

# prove_exec TIMEOUT OUTFILE ARGV...: run ARGV from the project root, stdin
# closed, stdout+stderr to OUTFILE, stopped at TIMEOUT seconds. Sets PROVE_CODE
# and PROVE_SECONDS. Never a shell: ARGV is executed as given.
prove_exec() {
  local t="$1" out="$2"
  shift 2
  SECONDS=0
  PROVE_CODE=0
  if command -v timeout > /dev/null 2>&1; then
    timeout "$t" "$@" > "$out" 2>&1 < /dev/null || PROVE_CODE=$?
  else
    perl -e 'alarm shift @ARGV; exec { $ARGV[0] } @ARGV or do { print STDERR "cannot run $ARGV[0]: $!\n"; exit 127 }' \
      "$t" "$@" > "$out" 2>&1 < /dev/null || PROVE_CODE=$?
  fi
  PROVE_SECONDS=$SECONDS
}

# prove_result OUTFILE TIMEOUT EXPECT_EXIT [OUTPUT_REGEX]: the result object.
# A run that lasted its whole timeout and failed was stopped by it.
prove_result() {
  jq -n --rawfile out "$1" --argjson code "$PROVE_CODE" --argjson secs "$PROVE_SECONDS" \
    --argjson t "$2" --argjson want "$3" --arg re "${4:-}" '
    ($out | split("\n") | map(select(length > 0)) | .[-20:] | join("\n") | .[-2000:]) as $tail
    | if $code != 0 and $secs >= $t then {status: "timeout", exit: null, seconds: $secs, tail: $tail}
      else {status: (if $code == $want and ($re == "" or ($out | test($re))) then "pass" else "fail" end),
            exit: $code, seconds: $secs, tail: $tail} end'
}

# Run one check by id; print its result object.
prove_check() {
  local record="$1" id="$2" argv=() a t want re
  while IFS= read -r -d '' a; do argv+=("$a"); done \
    < <(printf '%s' "$record" | jq -j --arg id "$id" '.checks[] | select(.id == $id) | .run[] + "\u0000"')
  t=$(printf '%s' "$record" | jq -r --arg id "$id" '.checks[] | select(.id == $id) | .timeout // 300')
  want=$(printf '%s' "$record" | jq -r --arg id "$id" '.checks[] | select(.id == $id) | .exit // 0')
  re=$(printf '%s' "$record" | jq -r --arg id "$id" '.checks[] | select(.id == $id) | .output // ""')
  prove_exec "$t" "$PROVE_OUT/$id.out" "${argv[@]}"
  prove_result "$PROVE_OUT/$id.out" "$t" "$want" "$re"
}

# All checks: {C1: result, ...}.
prove_checks() {
  local id all='{}' res
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    res=$(prove_check "$1" "$id")
    all=$(printf '%s' "$all" | jq -c --arg id "$id" --argjson r "$res" '. + {($id): $r}')
  done < <(printf '%s' "$1" | jq -r '.checks[].id')
  printf '%s\n' "$all"
}

# Project commands: run only those whose exact argv the user approved.
prove_commands() {
  local name argv a all='{}' res
  while IFS= read -r -d '' name; do
    argv=()
    while IFS= read -r -d '' a; do argv+=("$a"); done \
      < <(printf '%s' "$1" | jq -j --arg n "$name" '.commands[$n][] + "\u0000"')
    if consent_has command "$(vbw_sha256_argv "${argv[@]}")"; then
      prove_exec "$VBW_COMMAND_TIMEOUT" "$PROVE_OUT/cmd-$name.out" "${argv[@]}"
      res=$(prove_result "$PROVE_OUT/cmd-$name.out" "$VBW_COMMAND_TIMEOUT" 0)
    else
      res='{"status":"skipped","exit":null,"seconds":0,"tail":"not approved"}'
    fi
    all=$(printf '%s' "$all" | jq -c --arg n "$name" --argjson r "$res" '. + {($n): $r}')
  done < <(printf '%s' "$1" | jq -j '.commands | keys[] | . + "\u0000"')
  printf '%s\n' "$all"
}

# Scope: every commit whose VBW-Plan trailer names a plan in the record changes
# only that plan's files. Prints a JSON array of violations.
prove_scope() {
  local entry sha plan f
  {
    while IFS= read -r -d '' entry; do
      sha=${entry%%$'\x1f'*}
      plan=${entry#*$'\x1f'}
      plan=${plan%%$'\n'*}
      [ -n "$plan" ] || continue
      while IFS= read -r -d '' f; do
        printf '%s\x1f%s\x1f%s\n' "${sha:0:12}" "$plan" "$f"
      done < <(git diff-tree -z --no-commit-id --name-only -r --root "$sha")
    done < <(git log -z --format='%H%x1f%(trailers:key=VBW-Plan,valueonly)' 2> /dev/null)
  } | jq -R -s -c --argjson r "$1" '
    ($r.plans | map({key: .id, value: .files}) | from_entries) as $files
    | [split("\n")[] | select(length > 0) | split("\u001f") | select($files[.[1]] != null)
       | select(.[2] as $f | any($files[.[1]][]; . == $f) | not)
       | "\(.[0]) (\(.[1])) changed \(.[2]), which is not in the plan"]'
}

# Red-first: the given checks (all when none) must fail before building.
prove_red() {
  local record="$1" id green=0 res
  shift
  local ids=("$@")
  if [ ${#ids[@]} -eq 0 ]; then
    while IFS= read -r id; do [ -n "$id" ] && ids+=("$id"); done < <(printf '%s' "$record" | jq -r '.checks[].id')
  fi
  [ ${#ids[@]} -gt 0 ] || vbw_die "no checks to run"
  for id in "${ids[@]}"; do
    printf '%s' "$record" | jq -e --arg id "$id" 'any(.checks[]; .id == $id)' > /dev/null || vbw_die "unknown check $id"
  done
  for id in "${ids[@]}"; do
    res=$(prove_check "$record" "$id")
    if printf '%s' "$res" | jq -e '.status == "pass"' > /dev/null; then
      printf '%s passed before building: it proves nothing\n' "$id"
      green=1
    else
      printf '%s' "$res" | jq -r --arg id "$id" '"\($id) red (\(.status)), as expected"'
    fi
  done
  return $green
}

# One screen: what ran, what it means, what is next.
prove_summary() {
  jq -r '.evidence as $e
    | ($e.checks | to_entries[] | "  \(.key) \(.value.status)\(if .value.status == "fail" then " (exit \(.value.exit))" else "" end) \(.value.seconds)s"
        + (if .value.status == "pass" then "" else ": " + (.value.tail | split("\n") | last // "") end)),
      ($e.commands | to_entries[] | "  \(.key) \(.value.status)\(if .value.status == "skipped" then ": not approved" else " \(.value.seconds)s" end)"),
      (if ($e.scope | length) == 0 then "  scope ok" else ($e.scope[] | "  scope: " + .) end),
      (.requirements[] | select(.proof == "auto") | "\(.id) \(.status)"),
      (.fixes[] | select(.status == "open" or .status == "escalated") | "\(.id) \(.status) (\(.req // .command), attempts \(.attempts)): \(.note)"),
      (if $e.passed then "proved" else "not proved" end)' "$VBW_RECORD"
  jq -e '.evidence.passed' "$VBW_RECORD" > /dev/null
}
