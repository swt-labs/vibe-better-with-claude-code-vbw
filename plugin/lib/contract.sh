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

# contract_doc RECORD_JSON: the contract as JSON, for comparing two approvals:
# requirements, checks and plans by id, and each check file's digest.
contract_doc() {
  local f files='{}'
  while IFS= read -r -d '' f; do
    if [ -f "$VBW_ROOT/$f" ]; then
      files=$(printf '%s' "$files" | jq -c --arg f "$f" --arg d "$(vbw_sha256 < "$VBW_ROOT/$f")" '. + {($f): $d}')
    else
      files=$(printf '%s' "$files" | jq -c --arg f "$f" '. + {($f): "missing"}')
    fi
  done < <(printf '%s' "$1" | jq -j '[.checks[].files // [] | .[]] | unique[] | . + "\u0000"')
  printf '%s' "$1" | jq -c --argjson files "$files" '{
    requirements: (.requirements | map({key: .id, value: {text, proof}}) | from_entries),
    checks: (.checks | map({key: .id, value: .}) | from_entries),
    plans: (.plans | map({key: .id, value: del(.status, .note)}) | from_entries),
    files: $files}'
}
