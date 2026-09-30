#!/usr/bin/env bash
# The contract (docs/proof.md): requirements, checks, plans without their
# status, and the contents of every check's files. Approved = its hash has
# consent in the clone's git directory.

# contract_hash RECORD_JSON: SHA-256 over a canonical rendering of the contract.
# Each file contributes its path and its content digest ("missing" if absent).
contract_hash() {
  local f
  {
    printf '%s' "$1" | jq -cS '{requirements: [.requirements[] | {id, text, proof}],
                                checks: .checks, plans: [.plans[] | del(.status)]}'
    while IFS= read -r -d '' f; do
      printf '\0%s\0' "$f"
      if [ -f "$VBW_ROOT/$f" ]; then vbw_sha256 < "$VBW_ROOT/$f"; else printf 'missing\n'; fi
    done < <(printf '%s' "$1" | jq -j '[.checks[].files // [] | .[]] | unique[] | . + "\u0000"')
  } | vbw_sha256
}

contract_approved() {
  consent_has contract "$1"
}
