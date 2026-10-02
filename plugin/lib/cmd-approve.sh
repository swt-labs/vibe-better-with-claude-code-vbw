#!/usr/bin/env bash
# vbw approve: the user approves the contract and the project commands
# (docs/proof.md). Reached through /vbw:approve, which only the user can invoke;
# the guard hooks refuse it from agents. Consent goes to the clone's git
# directory, where a repository cannot ship it.

# shellcheck source=cmd-spec.sh
. "$VBW_LIB/cmd-spec.sh"

cmd_approve() {
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw approve"
  vbw_require_project
  local record problems hash
  record=$(record_read)
  problems=$(approve_problems "$record")
  if [ -n "$problems" ]; then
    printf 'vbw: the contract is not ready for approval:\n' >&2
    printf '%s\n' "$problems" | sed 's/^/  /' >&2
    exit 1
  fi
  hash=$(contract_hash "$record")
  if contract_approved "$hash"; then
    printf 'contract %s is already approved\n' "${hash:0:12}"
  else
    consent_grant contract "$hash" "$(printf '%s' "$record" | jq -c \
      '{requirements: (.requirements | length), checks: (.checks | length), plans: (.plans | length)}')"
    record_update "$VBW_JQ_DEFS"'.decisions += [{id: (.decisions | next_id("D")), at: $at,
        text: "Contract approved: \(.requirements | length) requirements, \(.checks | length) checks, \(.plans | length) plans (\($h[0:12]))"}]' \
      --arg h "$hash" --arg at "$(vbw_now)"
    record_commit "chore(vbw): approve contract ${hash:0:12}"
    printf 'approved contract %s\n' "${hash:0:12}"
  fi
  # What was approved, so the next approval can show only what changed
  # (vbw show contract --changes). Per clone, like the consent itself.
  contract_doc "$record" > "$VBW_RUNTIME/approved-contract.json.$$" \
    && mv "$VBW_RUNTIME/approved-contract.json.$$" "$VBW_RUNTIME/approved-contract.json"
  approve_commands "$record"
}

# One line per reason the contract cannot be approved yet (empty = ready).
approve_problems() {
  local parsed f
  if ! parsed=$(spec_parse 2> /dev/null); then
    printf 'spec.md is invalid (vbw spec check)\n'
  elif ! printf '%s' "$1" | jq -e --argjson p "$parsed" \
      '[.requirements[] | {id, text, proof}] == [$p.requirements[] | {id, text, proof}]
        and ($p.commands == null or .commands == $p.commands)' > /dev/null; then
    printf 'spec.md and the record differ (vbw spec sync)\n'
  fi
  printf '%s' "$1" | jq -r '
    (select((.requirements | length) == 0) | "no requirements"),
    (.checks as $c | .requirements[] | select(.proof == "auto")
      | select(.id as $id | any($c[]; .req == $id) | not) | "\(.id) has no check")'
  while IFS= read -r -d '' f; do
    [ -f "$VBW_ROOT/$f" ] || printf 'check file missing: %s\n' "$f"
  done < <(printf '%s' "$1" | jq -j '[.checks[].files // [] | .[]] | unique[] | . + "\u0000"')
}

# Consent to every project command, by argv hash.
approve_commands() {
  local name argv a
  while IFS= read -r -d '' name; do
    argv=()
    while IFS= read -r -d '' a; do argv+=("$a"); done \
      < <(printf '%s' "$1" | jq -j --arg n "$name" '.commands[$n][] + "\u0000"')
    consent_grant command "$(vbw_sha256_argv "${argv[@]}")" \
      "$(printf '%s' "$1" | jq -c --arg n "$name" '{name: $n, argv: .commands[$n]}')"
    printf 'approved command %s: %s\n' "$name" "${argv[*]}"
  done < <(printf '%s' "$1" | jq -j '.commands | keys[] | . + "\u0000"')
}
