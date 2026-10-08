#!/usr/bin/env bash
# The contract (docs/proof.md): requirements, checks, plans without their
# status, the saved test results folders when the spec names any, and the
# contents of every check's files. Approved = its hash has
# consent in the clone's git directory.

# contract_hash RECORD_JSON: SHA-256 over a canonical rendering of the contract.
# Each file contributes its path and its content digest ("missing" if absent).
contract_hash() {
  local f
  {
    contract_core "$1"
    while IFS= read -r -d '' f; do
      printf '\0%s\0' "$f"
      if [ -f "$VBW_ROOT/$f" ]; then vbw_sha256 < "$VBW_ROOT/$f"; else printf 'missing\n'; fi
    done < <(printf '%s' "$1" | jq -j '[.checks[].files // [] | .[]] | unique[] | . + "\u0000"')
  } | vbw_sha256
}

# contract_core RECORD_JSON: the contract's structure (requirements, checks,
# plans, and results only when present, so older contracts keep their hash),
# canonical, without the bytes of any check file.
contract_core() {
  printf '%s' "$1" | jq -cS '{requirements: [.requirements[] | {id, text, proof} + (if has("rules") then {rules} else {} end)],
                              checks: .checks, plans: [.plans[] | del(.status, .note)]}
                             + (if .project.results then {results: .project.results} else {} end)'
}

# contract_shape RECORD_JSON: the fingerprint of that structure alone. Each
# approval remembers it (consent kind "shape") beside the full hash, so edits
# to check files alone can wait for one approval before proof.
contract_shape() {
  contract_core "$1" | vbw_sha256
}

# contract_waiting RECORD_JSON: succeed when the contract may run: approved
# exactly (prints nothing), or approved apart from the bytes of check files
# (prints those files, sorted, one per line). Fails for any other contract.
contract_waiting() {
  local f d old="$VBW_RUNTIME/approved-contract.json" out="" all=""
  contract_approved "$(contract_hash "$1")" && return 0
  consent_has shape "$(contract_shape "$1")" || return 1
  while IFS= read -r -d '' f; do
    all="$all$f"$'\n'
    d=missing
    [ ! -f "$VBW_ROOT/$f" ] || d=$(vbw_sha256 < "$VBW_ROOT/$f")
    [ "$(jq -r --arg f "$f" '.files[$f] // "new"' "$old" 2> /dev/null)" = "$d" ] || out="$out$f"$'\n'
  done < <(printf '%s' "$1" | jq -j '[.checks[].files // [] | .[]] | unique[] | . + "\u0000"')
  printf '%s' "${out:-$all}"
}

contract_approved() {
  consent_has contract "$1"
}

# commands_approved RECORD_JSON: the user approved every project command's
# exact argv (a command edited in spec.md needs approving again).
commands_approved() {
  local name argv a
  while IFS= read -r -d '' name; do
    argv=()
    while IFS= read -r -d '' a; do argv+=("$a"); done \
      < <(printf '%s' "$1" | jq -j --arg n "$name" '.commands[$n][] + "\u0000"')
    consent_has command "$(vbw_sha256_argv "${argv[@]}")" || return 1
  done < <(printf '%s' "$1" | jq -j '.commands | keys[] | . + "\u0000"')
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
    requirements: (.requirements | map({key: .id, value: ({text, proof} + (if has("rules") then {rules} else {} end))}) | from_entries),
    checks: (.checks | map({key: .id, value: .}) | from_entries),
    plans: (.plans | map({key: .id, value: del(.status, .note)}) | from_entries),
    commands: .commands,
    files: $files} + (if .project.results then {results: .project.results} else {} end)'
}
