#!/usr/bin/env bash
# vbw approve: the user approves the contract and the project commands
# (docs/proof.md). Reached through /vbw:approve, which only the user can invoke;
# the guard hooks refuse it from agents. Consent goes to the clone's git
# directory, where a repository cannot ship it.

# shellcheck source=cmd-spec.sh
. "$VBW_LIB/cmd-spec.sh"

cmd_approve() {
  local want=""
  case "$#:${1:-}" in
    0:) ;;
    2:--hash) want=$2
      [[ "$want" =~ ^[0-9a-f]{12}$ ]] || vbw_usage_error "usage: vbw approve --hash FINGERPRINT (the 12-character fingerprint from vbw show contract)" ;;
    *) vbw_usage_error "usage: vbw approve [--hash FINGERPRINT]" ;;
  esac
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
  [ -z "$want" ] || [ "$want" = "${hash:0:12}" ] \
    || vbw_die "the contract changed since you were asked (now ${hash:0:12}): review it again (vbw show contract); nothing was approved"
  approve_record "$record" "$hash" "$(approve_text "$record" "$hash")"
}

# approve_text RECORD HASH: the decision's words for the user's approval.
approve_text() {
  printf '%s' "$1" | jq -r "$VBW_JQ_DEFS"'
    def express_text: . as $r | [.phases[] | select(.milestone == $r.milestone.id and .tier == "express") | .id as $p | .reqs as $q
        | "express: \($p) (\([$q[], ($r.checks[] | select(.req as $c | any($q[]; . == $c)) | .id), ($r.plans[] | select(.phase == $p) | .id)] | join(", ")))"]
      | if length > 0 then "; " + join("; ") else "" end;
    "Contract approved: \(.requirements | length) requirements, \(.checks | length) checks, \(.plans | length) plans (\($h[0:12]))\(express_text)"' --arg h "$2"
}

# approve_record RECORD HASH DECISION_TEXT [WHO]: every write of an approval, whoever gives it (the user's
# vbw approve; the loop on the user's behalf, lib/loop-step.sh): the decision with that text and its
# strict commit (taken back when the commit fails), consent for the contract, then the shape, the
# approved-contract snapshot and the project commands. With the contract already approved, a project
# command or test-file form not consented to yet is approved on its own, with its decision ("Project
# commands approved WHO: ...", WHO the approver's words, empty for the user) and commit first (F200).
approve_record() {
  local record=$1 hash=$2 who="${4:-}" pending changed=null
  if contract_approved "$hash"; then
    printf 'contract %s is already approved\n' "${hash:0:12}"
    pending=$(approve_pending "$record")
    [ -z "$pending" ] || approve_decide "Project commands approved${who:+ $who}: $pending" "chore(vbw): approve commands" "the commands are"
  else
    # #705: the plans this approval changes since the last one (their contract part, not their status),
    # so a decision recorded before it still reaches the Dev of a plan it left as it was
    # (vbw show decisions --since-approval PLAN). With no earlier snapshot every plan counts as changed.
    [ ! -f "$VBW_RUNTIME/approved-contract.json" ] \
      || changed=$(contract_doc "$record" | jq -c --slurpfile old "$VBW_RUNTIME/approved-contract.json" \
        '[.plans | to_entries[] | select($old[0].plans[.key]? != .value) | .key]') || changed=null
    approve_decide "$3" "chore(vbw): approve contract ${hash:0:12}" "the contract is" "$changed"
    consent_grant contract "$hash" "$(printf '%s' "$record" | jq -c \
      '{requirements: (.requirements | length), checks: (.checks | length), plans: (.plans | length)}')"
    printf 'approved contract %s\n' "${hash:0:12}"
  fi
  # Its structure alone: later edits to check files wait for one approval before proof.
  consent_grant shape "$(contract_shape "$record")" '{}'
  # What was approved, so the next approval can show only what changed
  # (vbw show contract --changes). Per clone, like the consent itself.
  approve_snapshot "$record"
  # The git-read excuses this approval takes with it (R264): the next gate lists only the later ones.
  contract_git_excuses "$record" > "$VBW_RUNTIME/git-excuses-seen.json.$$" \
    && mv "$VBW_RUNTIME/git-excuses-seen.json.$$" "$VBW_RUNTIME/git-excuses-seen.json"
  approve_commands "$record"
}

# approve_repin RECORD: an amendment (vbw apply --amend, R250) keeps the contract approved: the consent for
# the amended contract's hash and shape and the approved-contract snapshot are written for it, as the
# approval wrote them for the contract before. No decision and no commit: nobody was asked.
approve_repin() {
  consent_grant contract "$(contract_hash "$1")" "$(printf '%s' "$1" | jq -c \
    '{requirements: (.requirements | length), checks: (.checks | length), plans: (.plans | length)}')"
  consent_grant shape "$(contract_shape "$1")" '{}'
  approve_snapshot "$1"
}

# approve_snapshot RECORD: write .vbw/runtime/approved-contract.json: the contract's document
# (contract_doc) plus the approval's commit id (HEAD, after the approval commit) and each check
# file's git blob id (git hash-object of the approved bytes, written to the object store so the
# approved content can be read back), so a later added-to file is told from a waiting one (R269).
approve_snapshot() {
  local doc blobs commit
  doc=$(contract_doc "$1")
  blobs=$(contract_blobs "$1")
  commit=$(git -C "$VBW_ROOT" rev-parse --verify -q HEAD 2> /dev/null) || commit=
  printf '%s' "$doc" | jq -c --argjson blobs "$blobs" --arg commit "$commit" \
    '. + {blobs: $blobs} + (if $commit == "" then {} else {commit: $commit} end)' > "$VBW_RUNTIME/approved-contract.json.$$" \
    && mv "$VBW_RUNTIME/approved-contract.json.$$" "$VBW_RUNTIME/approved-contract.json"
}

# approve_decide TEXT SUBJECT WHAT [PLANS]: the approval's decision with TEXT and its strict commit with SUBJECT;
# the decision is taken back when the commit fails (no approval without its commit), naming WHAT is not approved.
# PLANS, a JSON array of plan ids, is kept on the decision as the plans the approval changed.
approve_decide() {
  local before
  before=$(cat "$VBW_RECORD")
  record_update "$VBW_JQ_DEFS"'
    .decisions += [{id: (.decisions | next_id("D")), at: $at, text: $text} + (if $plans == null then {} else {plans: $plans} end)]
    # The approval takes the recorded amendments with it (R250); the files and awaits they added stay.
    | .plans |= map(del(.amendments)) | .checks |= map(del(.amendments))' \
    --arg text "$1" --arg at "$(vbw_now)" --argjson plans "${4:-null}"
  if ! record_commit --strict "$2"; then
    record_update '.decisions |= map(select(.id != $d))' --arg d "$(printf '%s' "$before" | jq -r '.decisions | (map(.id | ltrimstr("D") | tonumber) | max // 0) + 1 | "D\(.)"')"
    vbw_die "the approval commit failed (reason above); $3 not approved"
  fi
}

# approve_pending RECORD: the project commands and the test-file form not consented to yet,
# "name (argv)" each, joined by "; "; empty when every one is approved.
approve_pending() {
  local name argv a out=""
  while IFS= read -r -d '' name; do
    argv=()
    while IFS= read -r -d '' a; do argv+=("$a"); done \
      < <(printf '%s' "$1" | jq -j --arg n "$name" '.commands[$n][] + "\u0000"')
    consent_has command "$(vbw_sha256_argv ${argv[@]+"${argv[@]}"})" || out="$out${out:+; }$name (${argv[*]+"${argv[*]}"})"
  done < <(printf '%s' "$1" | jq -j '.commands | keys[] | . + "\u0000"')
  if printf '%s' "$1" | jq -e 'has("test_files")' > /dev/null && ! consent_has test_files "$(test_files_hash "$1")"; then
    out="$out${out:+; }test files ($(printf '%s' "$1" | jq -r "$VBW_JQ_DEFS"'if .test_files | type == "object" then "\(.test_files.run | join(" ")); \(.test_files.files | join(" "))"
      else [tf_forms[] | tf_say] | join("; ") end'))"
  fi
  printf '%s' "$out"
}

# One line per reason the contract cannot be approved yet (empty = ready).
approve_problems() {
  local parsed f
  if ! parsed=$(spec_parse 2> /dev/null); then
    printf 'spec.md is invalid (vbw spec check)\n'
  elif ! printf '%s' "$1" | jq -e --slurpfile f_p <(printf '%s' "$parsed") \
      '$f_p[0] as $p | [.requirements[] | {id, text, proof}] == [$p.requirements[] | {id, text, proof}]
        and ($p.commands == null or .commands == $p.commands)
        and ((.test_files // null) == $p.test_files)
        and ((.project.results // null) == ($p.results // null))
        and ((.project.leave_out // null) == (($p.leave_out // null) | if . == null then null else map(.path) end))' > /dev/null; then
    printf 'spec.md and the record differ (vbw spec sync)\n'
  fi
  printf '%s' "$1" | jq -r "$VBW_JQ_DEFS"'
    (select((.requirements | length) == 0) | "no requirements"),
    (. as $r | .requirements[] | select(.proof == "auto")
      | select(.id as $id | any($r.checks[]; .req == $id) | not) | select(doc_only($r) | not) | "\(.id) has no check"),
    (. as $r | .requirements[] | select(.proof == "auto" and (.rules | type) == "array" and all(.rules[]; type == "object" and has("retired")) and (doc_only($r) | not))
      | "\(.id) has no rules listed (vbw apply with rules)")'
  while IFS= read -r -d '' f; do
    [ -f "$VBW_ROOT/$f" ] || vbw_out 'check file missing: %s\n' "$f"
  done < <(printf '%s' "$1" | jq -j '[.checks[].files // [] | .[]] | unique[] | . + "\u0000"')
  # An own file a project rule hides that VBW's .gitignore lines cannot un-hide (R208).
  (cd "$VBW_ROOT" && record_hidden) || true
}

# Consent to every project command, by argv hash, and to the test file form.
approve_commands() {
  local name argv a
  if printf '%s' "$1" | jq -e 'has("test_files")' > /dev/null; then
    consent_grant test_files "$(test_files_hash "$1")" "$(printf '%s' "$1" | jq -c '.test_files')"
    printf '%s' "$1" | jq -r "$VBW_JQ_DEFS"'tf_forms[] | "approved test file form: \(tf_say)"'
  fi
  while IFS= read -r -d '' name; do
    argv=()
    while IFS= read -r -d '' a; do argv+=("$a"); done \
      < <(printf '%s' "$1" | jq -j --arg n "$name" '.commands[$n][] + "\u0000"')
    consent_grant command "$(vbw_sha256_argv "${argv[@]}")" \
      "$(printf '%s' "$1" | jq -c --arg n "$name" '{name: $n, argv: .commands[$n]}')"
    vbw_out 'approved command %s: %s\n' "$name" "${argv[*]}"
  done < <(printf '%s' "$1" | jq -j '.commands | keys[] | . + "\u0000"')
}
