#!/usr/bin/env bash
# Reuse of the last proof's results by vbw prove (docs/proof.md, R103, R110).
# A check's pass is reused when its approved definition and the committed
# content of its served files are unchanged; a command's, when the committed
# code is the proof's own. Anything else runs.

# proofreuse_check_fp RECORD ID: fingerprint of a check's approved definition.
proofreuse_check_fp() {
  printf '%s' "$1" | jq -cS --arg id "$2" '.checks[] | select(.id == $id)
    | {id, req, run, exit, output, timeout, alone, files}' | vbw_sha256
}

# proofreuse_command_fp RECORD NAME: fingerprint of a project command's argv.
proofreuse_command_fp() {
  local argv=() a
  while IFS= read -r -d '' a; do argv+=("$a"); done \
    < <(printf '%s' "$1" | jq -j --arg n "$2" '.commands[$n][] + "\u0000"')
  vbw_sha256_argv ${argv[@]+"${argv[@]}"}
}

# proofreuse_marker: the unfinished marker (present while a proof runs, and
# left behind by one that was interrupted or failed to record).
proofreuse_marker() { printf '%s/prove.unfinished\n' "$VBW_RUNTIME"; }

# proofreuse_last RECORD: print the last proof's evidence when its results may
# be looked at for reuse (passed or not); fail when it may not.
proofreuse_last() {
  [ ! -e "$(proofreuse_marker)" ] || return 1
  # Nothing at all changed since that proof (it is the last commit, VBW's own
  # files are clean and the working folder is the committed code): a second
  # prove is a deliberate re-run, as when something outside the committed code
  # (installed dependencies, ignored files) changed.
  if [ "$(git -C "$VBW_ROOT" log -1 --format=%s 2> /dev/null)" = 'chore(vbw): proof passed' ] \
    && [ -z "$(git -C "$VBW_ROOT" status --porcelain -z -- .vbw 2> /dev/null | tr -d '\000')" ] \
    && [ "$(vbw_code_tree)" = "$(vbw_head_tree)" ]; then
    return 1
  fi
  printf '%s' "$1" | jq -ce '.evidence | select(type == "object")'
}

# proofreuse_commands_ok EVIDENCE: succeed when the committed code is the very
# code of that passing proof (R103), which is what project commands need.
proofreuse_commands_ok() {
  local head tree
  head=$(vbw_head_tree) && [ -n "$head" ] || return 1
  tree=$(vbw_code_tree) || return 1
  [ "$tree" = "$head" ] || return 1
  printf '%s' "$1" | jq -e --arg head "$head" '.passed == true and .head == $head' > /dev/null
}

# proofreuse_names RECORD FULL: sets PROVE_NAMES (JSON array of the command
# names this proof covers) and QUICK_STANDIN (true when the approved quick
# command stands in for the test command). Full: every command but quick. Plain:
# an approved quick replaces test; a quick that is named but not approved is
# listed (and so reported skipped) and the test command runs (R111).
proofreuse_names() {
  local argv=() a
  # shellcheck disable=SC2034 # read by cmd_prove
  QUICK_STANDIN=false
  if [ "$2" = 1 ]; then
    PROVE_NAMES=$(printf '%s' "$1" | jq -c '.commands | keys - ["quick"]')
    return 0
  fi
  PROVE_NAMES=$(printf '%s' "$1" | jq -c '.commands | keys')
  printf '%s' "$1" | jq -e '.commands | has("quick") and has("test")' > /dev/null || return 0
  while IFS= read -r -d '' a; do argv+=("$a"); done \
    < <(printf '%s' "$1" | jq -j '.commands.quick[] + "\u0000"')
  if consent_has command "$(vbw_sha256_argv "${argv[@]}")"; then
    # shellcheck disable=SC2034 # read by cmd_prove
    QUICK_STANDIN=true
    PROVE_NAMES=$(printf '%s' "$PROVE_NAMES" | jq -c '. - ["test"]')
  fi
}

# proofreuse_plan RECORD [FULL]: with FULL = 1 nothing is reused. Sets REUSE_CHECKS and REUSE_COMMANDS (the reused
# results, as JSON objects), and TODO_CHECKS (array) and TODO_COMMANDS (JSON
# array of names), which are what has to run. A check is reused when its last
# result passed and both its approved definition and the committed content of
# the files it depends on (R110) are what they were; a command, by R103.
proofreuse_plan() {
  local record="$1" ev='' id fp sp old name
  proofreuse_names "$record" "${2:-0}"
  REUSE_CHECKS='{}' REUSE_COMMANDS='{}' TODO_CHECKS=() TODO_COMMANDS='[]'
  if [ "${2:-0}" = 1 ]; then ev=; else ev=$(proofreuse_last "$record") || ev=; fi
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    fp=$(proofreuse_check_fp "$record" "$id")
    old=
    if [ -n "$ev" ] && sp=$(checks_fingerprint "$record" "$id"); then
      old=$(printf '%s' "$ev" | jq -c --arg id "$id" --arg fp "$fp" --arg sp "$sp" \
        '.checks[$id] // empty | select(.status == "pass" and .fp == $fp and .served == $sp)')
    fi
    if [ -n "$old" ]; then
      REUSE_CHECKS=$(printf '%s' "$REUSE_CHECKS" | jq -c --arg id "$id" --argjson r "$old" '. + {($id): ($r + {reused: true})}')
    else
      TODO_CHECKS+=("$id")
    fi
  done < <(printf '%s' "$record" | jq -r '.checks[].id')
  if [ -n "$ev" ] && ! proofreuse_commands_ok "$ev"; then ev=; fi
  while IFS= read -r -d '' name; do
    fp=$(proofreuse_command_fp "$record" "$name")
    old=
    [ -z "$ev" ] || old=$(printf '%s' "$ev" | jq -c --arg n "$name" --arg fp "$fp" \
      '.commands[$n] // empty | select(.status == "pass" and .fp == $fp)')
    if [ -n "$old" ]; then
      REUSE_COMMANDS=$(printf '%s' "$REUSE_COMMANDS" | jq -c --arg n "$name" --argjson r "$old" '. + {($n): ($r + {reused: true})}')
    else
      TODO_COMMANDS=$(printf '%s' "$TODO_COMMANDS" | jq -c --arg n "$name" '. + [$n]')
    fi
  done < <(printf '%s' "$PROVE_NAMES" | jq -j '.[] + "\u0000"')
}

# proofreuse_stamp RECORD KIND RESULTS AT: add each new result's fingerprint
# (KIND check or command), for a check also the fingerprint of the committed
# content of the files it depends on, and the time it really ran.
proofreuse_stamp() {
  local name fp sp out="$3"
  while IFS= read -r -d '' name; do
    if [ "$2" = check ]; then fp=$(proofreuse_check_fp "$1" "$name"); else fp=$(proofreuse_command_fp "$1" "$name"); fi
    out=$(printf '%s' "$out" | jq -c --arg n "$name" --arg fp "$fp" --arg at "$4" '.[$n] += {fp: $fp, at: $at}')
    if [ "$2" = check ] && sp=$(checks_fingerprint "$1" "$name"); then
      out=$(printf '%s' "$out" | jq -c --arg n "$name" --arg sp "$sp" '.[$n] += {served: $sp}')
    fi
  done < <(printf '%s' "$3" | jq -j 'keys[] | . + "\u0000"')
  printf '%s\n' "$out"
}

# proofreuse_join ORDER REUSED NEW: one object in ORDER (a JSON array of names).
proofreuse_join() {
  jq -nc --argjson o "$1" --argjson a "$2" --argjson b "$3" \
    '$o | map({key: ., value: ($b[.] // $a[.])}) | from_entries'
}
