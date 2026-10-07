#!/usr/bin/env bash
# Reuse of the last passing proof's results by vbw prove (docs/proof.md, R103).
# A result is reused only when the code is the proof's own and the approved
# definition it came from is unchanged; anything else runs.

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

# proofreuse_evidence RECORD: print the evidence when its results may be reused.
proofreuse_evidence() {
  local head tree
  [ ! -e "$(proofreuse_marker)" ] || return 1
  # Nothing at all changed since that proof (it is the last commit and VBW's own
  # files are clean): a second prove is a deliberate re-run, as when something
  # outside the committed code (installed dependencies, ignored files) changed.
  [ "$(git -C "$VBW_ROOT" log -1 --format=%s 2> /dev/null)" != 'chore(vbw): proof passed' ] \
    || [ -n "$(git -C "$VBW_ROOT" status --porcelain -z -- .vbw 2> /dev/null | tr -d '\000')" ] || return 1
  head=$(vbw_head_tree) && [ -n "$head" ] || return 1
  tree=$(vbw_code_tree) || return 1
  [ "$tree" = "$head" ] || return 1
  printf '%s' "$1" | jq -ce --arg head "$head" '.evidence
    | select(type == "object" and .passed == true and .head == $head)'
}

# proofreuse_plan RECORD: sets REUSE_CHECKS and REUSE_COMMANDS (the reused
# results, as JSON objects), and TODO_CHECKS (array) and TODO_COMMANDS (JSON
# array of names), which are what has to run.
proofreuse_plan() {
  local record="$1" ev='' id fp old name
  REUSE_CHECKS='{}' REUSE_COMMANDS='{}' TODO_CHECKS=() TODO_COMMANDS='[]'
  ev=$(proofreuse_evidence "$record") || ev=
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    fp=$(proofreuse_check_fp "$record" "$id")
    old=
    [ -z "$ev" ] || old=$(printf '%s' "$ev" | jq -c --arg id "$id" --arg fp "$fp" \
      '.checks[$id] // empty | select(.status == "pass" and .fp == $fp)')
    if [ -n "$old" ]; then
      REUSE_CHECKS=$(printf '%s' "$REUSE_CHECKS" | jq -c --arg id "$id" --argjson r "$old" '. + {($id): ($r + {reused: true})}')
    else
      TODO_CHECKS+=("$id")
    fi
  done < <(printf '%s' "$record" | jq -r '.checks[].id')
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
  done < <(printf '%s' "$record" | jq -j '.commands | keys[] | . + "\u0000"')
}

# proofreuse_stamp RECORD KIND RESULTS AT: add each new result's fingerprint
# (KIND check or command) and the time it really ran.
proofreuse_stamp() {
  local name fp out="$3"
  while IFS= read -r -d '' name; do
    if [ "$2" = check ]; then fp=$(proofreuse_check_fp "$1" "$name"); else fp=$(proofreuse_command_fp "$1" "$name"); fi
    out=$(printf '%s' "$out" | jq -c --arg n "$name" --arg fp "$fp" --arg at "$4" '.[$n] += {fp: $fp, at: $at}')
  done < <(printf '%s' "$3" | jq -j 'keys[] | . + "\u0000"')
  printf '%s\n' "$out"
}

# proofreuse_join ORDER REUSED NEW: one object in ORDER (a JSON array of names).
proofreuse_join() {
  jq -nc --argjson o "$1" --argjson a "$2" --argjson b "$3" \
    '$o | map({key: ., value: ($b[.] // $a[.])}) | from_entries'
}
