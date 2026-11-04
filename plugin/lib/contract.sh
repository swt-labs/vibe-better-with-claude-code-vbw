#!/usr/bin/env bash
# The contract (docs/proof.md): requirements with their rules (a retired rule
# and its reason included, so rewording or retiring one needs approval again),
# checks, plans without their status, the saved test results folders and the
# test file form when the spec names them, and the contents of every check's
# files. Approved = its hash has consent in the clone's git directory.

# The contract's jq definitions (R249): the one place the contract core and the
# list of check files are written, so vbw next and vbw status can emit the core
# beside their other fields in their one pass over the record (lib/cmd-next.sh)
# and the shell hashes it, with no second parse of the record. canon puts every
# object's keys in sorted order, as jq -S prints them: contract_core | canon |
# tojson is the line jq -cS prints for contract_core.
# shellcheck disable=SC2016
VBW_CONTRACT_DEFS='def canon: if type == "object" then to_entries | map(.value |= canon) | sort_by(.key) | from_entries
  elif type == "array" then map(canon) else . end;
def contract_core: {requirements: [.requirements[] | select(.queued | not) | {id, text, proof} + (if has("rules") then {rules} else {} end)],
                    checks: [.checks[] | del(.amendments)], plans: [.plans[] | del(.status, .note, .mutations, .amendments, .awaits)]}
                   + (if .project.results then {results: .project.results} else {} end)
                   + (if .project.leave_out then {leave_out: .project.leave_out} else {} end)
                   + (if .test_files then {test_files} else {} end);
def contract_files: [.checks[].files // [] | .[]] | unique;
def without_fix: .checks |= map(select(has("fix") | not));
'

# contract_hash RECORD_JSON: SHA-256 over a canonical rendering of the contract.
# Each file contributes its path and its content digest ("missing" if absent).
contract_hash() {
  contract_hash_from "$(contract_core "$1")" "$(printf '%s' "$1" | jq -c "$VBW_CONTRACT_DEFS"'contract_files')"
}

# contract_hash_from CORE FILES_JSON: contract_hash of a contract whose core line
# (contract_core's output) and list of check files (a JSON array of paths) the
# caller already has. The paths are piped into the loop, which writes every byte
# the hash reads (its own and vbw_sha256's): run in a child, the loop has no live
# child of its own whose exit could interrupt a write (vbw_out, core.sh), and
# costs nothing per file.
contract_hash_from() {
  local f
  {
    printf '%s\n' "$1"
    printf '%s' "$2" | jq -j '.[] + "\u0000"' | while IFS= read -r -d '' f; do
      printf '\0%s\0' "$f"
      if [ -f "$VBW_ROOT/$f" ]; then vbw_sha256 < "$VBW_ROOT/$f"; else printf 'missing\n'; fi
    done
  } | vbw_sha256
}

# contract_core RECORD_JSON: the contract's structure (requirements, checks,
# plans, and results and leave_out only when present, so older contracts keep their hash),
# canonical, without the bytes of any check file. A plan's amendments and awaits and a
# check's amendments are left out (R250): an amendment changes no check's assertion, so
# it never moves the hash; the files an amendment added stay in.
contract_core() {
  printf '%s' "$1" | jq -cS "$VBW_CONTRACT_DEFS"'contract_core'
}

# contract_shape RECORD_JSON: the fingerprint of that structure alone, without
# the checks a fix added (they carry "fix"). Each approval remembers it (consent
# kind "shape") beside the full hash, so edits to check files and the checks a
# fix adds can wait for one approval before proof.
contract_shape() {
  printf '%s' "$1" | jq -cS "$VBW_CONTRACT_DEFS"'without_fix | contract_core' | vbw_sha256
}

# contract_held RECORD_JSON: the ids, one per line, of the checks a fix added
# that the last approval does not hold as they are (new or changed): nothing
# runs them before the user approves. Empty when the contract is approved exactly.
contract_held() {
  contract_approved "$(contract_hash "$1")" && return 0
  printf '%s' "$1" | jq -r --slurpfile old "$VBW_RUNTIME/approved-contract.json" '.checks[] | select(has("fix")) | . as $c
    | select($old[0].checks[$c.id] != ($c | del(.amendments))) | .id' 2> /dev/null \
    || printf '%s' "$1" | jq -r '.checks[] | select(has("fix")) | .id'
}

# contract_waiting RECORD_JSON: succeed when the contract may run: approved
# exactly (prints nothing), or approved apart from the bytes of check files
# (prints those files, sorted, one per line; a check a fix added counts with all
# its files until approved). Fails for any other contract.
contract_waiting() {
  contract_waiting_with "$1" "$(contract_hash "$1")"
}

# contract_waiting_with RECORD_JSON HASH [SHAPE]: contract_waiting for a caller that
# already has the contract's hash (contract_hash) and, when it has it, the shape
# (contract_shape; worked out here otherwise, and only when the hash is not approved).
contract_waiting_with() {
  local f d old="$VBW_RUNTIME/approved-contract.json" out="" all="" held="" shape="${3:-}"
  contract_approved "$2" && return 0
  [ -n "$shape" ] || shape=$(contract_shape "$1")
  consent_has shape "$shape" || return 1
  # One path per line: a shell variable cannot hold NUL bytes (bash 5 warns, bash 3.2 drops them).
  held=$(printf '%s' "$1" | jq -r --slurpfile old "$old" '.checks[] | select(has("fix")) | . as $c
    | select($old[0].checks[$c.id] != ($c | del(.amendments))) | .files[]?' 2> /dev/null) \
    || held=$(printf '%s' "$1" | jq -r '.checks[] | select(has("fix")) | .files[]?')
  while IFS= read -r -d '' f; do
    all="$all$f"$'\n'
    d=missing
    [ ! -f "$VBW_ROOT/$f" ] || d=$(vbw_sha256 < "$VBW_ROOT/$f")
    if [ "$(jq -r --arg f "$f" '.files[$f] // "new"' "$old" 2> /dev/null)" != "$d" ] \
      || printf '%s\n' "$held" | grep -xF -- "$f" > /dev/null; then
      out="$out$f"$'\n'
    fi
  done < <(printf '%s' "$1" | jq -j '[.checks[].files // [] | .[]] | unique[] | . + "\u0000"')
  printf '%s' "${out:-$all}"
}

contract_approved() {
  consent_has contract "$1"
}

# test_files_hash RECORD_JSON: the fingerprint of the test file form (canonical
# {run, files}); the consent kind "test_files" holds it.
test_files_hash() {
  printf '%s' "$1" | jq -cS '.test_files' | vbw_sha256
}

# commands_approved RECORD_JSON: the user approved every project command's
# exact argv and the test file form, when there is one (a command or form edited
# in spec.md needs approving again).
commands_approved() {
  local name argv a
  while IFS= read -r -d '' name; do
    argv=()
    while IFS= read -r -d '' a; do argv+=("$a"); done \
      < <(printf '%s' "$1" | jq -j --arg n "$name" '.commands[$n][] + "\u0000"')
    consent_has command "$(vbw_sha256_argv "${argv[@]}")" || return 1
  done < <(printf '%s' "$1" | jq -j '.commands | keys[] | . + "\u0000"')
  printf '%s' "$1" | jq -e 'has("test_files") | not' > /dev/null || consent_has test_files "$(test_files_hash "$1")"
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
  printf '%s' "$1" | jq -c --slurpfile f_files <(printf '%s' "$files") '$f_files[0] as $files | {
    requirements: (.requirements | map(select(.queued | not)) | map({key: .id, value: ({text, proof} + (if has("rules") then {rules} else {} end))}) | from_entries),
    checks: (.checks | map({key: .id, value: del(.amendments)}) | from_entries),
    plans: (.plans | map({key: .id, value: del(.status, .note, .mutations, .amendments, .awaits)}) | from_entries),
    commands: .commands,
    files: $files} + (if .project.results then {results: .project.results} else {} end)
    + (if .project.leave_out then {leave_out: .project.leave_out} else {} end)
    + (if .test_files then {test_files} else {} end)'
}

# contract_amendments_block RECORD_JSON: the amendments recorded since the last approval, the
# block vbw show contract --changes, vbw show contract and vbw ship share (R250): the heading
# and one line per amendment, two-space indented, plans then checks in record order. Prints
# nothing when none is recorded.
contract_amendments_block() {
  printf '%s' "$1" | jq -r '[(.plans[], .checks[]) | .id as $i | (.amendments // [])[]
      | "  \($i): \(.what) (\(.at), session \(.session // "unknown"))"]
    | if length > 0 then "amendments since the last approval:", .[] else empty end'
}
