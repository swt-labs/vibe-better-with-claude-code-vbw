#!/usr/bin/env bash
# vbw prove: run exactly what the user approved and record the evidence
# (docs/proof.md). Nothing unapproved ever executes.

# shellcheck source=checks.sh
. "$VBW_LIB/checks.sh"
# shellcheck source=proofcopy.sh
. "$VBW_LIB/proofcopy.sh"
# shellcheck source=proofreuse.sh
. "$VBW_LIB/proofreuse.sh"
# shellcheck source=cmd-next.sh
. "$VBW_LIB/cmd-next.sh"

VBW_FIX_CAP=3
VBW_COMMAND_TIMEOUT=900

cmd_prove() {
  local full=0
  case $# in
    0) ;;
    1) [ "$1" = --full ] || vbw_usage_error "usage: vbw prove [--full]"; full=1 ;;
    *) vbw_usage_error "usage: vbw prove [--full]" ;;
  esac
  vbw_require_project
  cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  local record checks commands scope tree head ev at mark=""
  # This session's Stop hook waits while the mark names a live process (R98).
  if [ -n "$(vbw_session)" ]; then
    mark="$VBW_RUNTIME/proving.$(vbw_session)"
    printf '%s\n' "$$" > "$mark" && vbw_guard_add file "$mark"
  fi
  VBW_DIE_HOOK=proofcopy_warn_stale
  record=$(record_read)
  checks_begin "$record" strict
  proofreuse_plan "$record" "$full"
  at=$(vbw_now)
  # The marker stays until the evidence is recorded: a proof cut short reuses nothing next time.
  : > "$(proofreuse_marker)" || vbw_die "cannot write $(proofreuse_marker)"
  checks='{}' commands='{}'
  if [ ${#TODO_CHECKS[@]} -gt 0 ] || [ "$TODO_COMMANDS" != '[]' ]; then
    proofcopy_create
    proofcopy_verify "$CHECK_HASH" "$record"
    # Checks and commands run on the clean copy; evidence and the record stay here.
    cd "$PROOF_COPY" || vbw_die "cannot enter the clean copy"
    [ ${#TODO_CHECKS[@]} -eq 0 ] || checks=$(checks_run_all "$record" "${TODO_CHECKS[@]}")
    commands=$(prove_commands "$record" "$TODO_COMMANDS")
    cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
    proofcopy_remove
  fi
  checks_end
  checks_record_passes "$record" "$checks" "$CHECK_HASH"
  checks=$(proofreuse_join "$(printf '%s' "$record" | jq -c '[.checks[].id]')" "$REUSE_CHECKS" "$(proofreuse_stamp "$record" check "$checks" "$at")")
  commands=$(proofreuse_join "$PROVE_NAMES" "$REUSE_COMMANDS" "$(proofreuse_stamp "$record" command "$commands" "$at")")
  scope=$(prove_scope "$record")
  tree=$(vbw_code_tree) || vbw_die "cannot fingerprint the project files"
  head=$(vbw_head_tree) || vbw_die "cannot fingerprint the committed code"
  # tree: the working folder (QA freshness, R12); head: the committed code the
  # checks ran on, so committing unproved edits later makes the proof stale.
  # full: nothing reused, no quick stand-in, every full command ran (R111).
  ev=$(jq -n --arg at "$at" --arg h "$CHECK_HASH" --argjson standin "$QUICK_STANDIN" --arg tree "$tree" --arg head "$head" \
    --argjson c "$checks" --argjson m "$commands" --argjson s "$scope" \
    '{at: $at, contract: $h, tree: $tree, head: $head, checks: $c, commands: $m, scope: $s,
      full: (($standin | not) and all($c[]; (.reused // false) | not) and all($m[]; (.reused // false) | not)
             and all($m | to_entries[] | select(.key != "quick"); .value.status != "skipped")),
      passed: (all($c[]; .status == "pass") and all($m[]; .status == "pass" or .status == "skipped") and ($s | length) == 0)}')
  record_update "$VBW_JQ_DEFS$(cat "$VBW_LIB/prove.jq")" --argjson ev "$ev" --argjson cap "$VBW_FIX_CAP" --argjson cur "$(qa_combined "$record")" --arg at "$at"
  rm -f "$(proofreuse_marker)"
  # The evidence is part of the plan of record: commit it, so a proof never
  # leaves VBW's own file modified in the user's working tree.
  record_commit "chore(vbw): proof $(jq -r 'if .evidence.passed then "passed" else "not passed" end' "$VBW_RECORD")"
  # shellcheck disable=SC2034
  VBW_DIE_HOOK=; proofcopy_warn_stale
  [ -z "$mark" ] || vbw_guard_drop "$mark"
  prove_summary "$full"
}

# Project commands: run only those whose exact argv the user approved.
prove_commands() {
  local name argv a all='{}' res
  # $2: JSON array of the command names to run.
  while IFS= read -r -d '' name; do
    argv=()
    while IFS= read -r -d '' a; do argv+=("$a"); done \
      < <(printf '%s' "$1" | jq -j --arg n "$name" '.commands[$n][] + "\u0000"')
    if consent_has command "$(vbw_sha256_argv "${argv[@]}")"; then
      checks_exec "$VBW_COMMAND_TIMEOUT" "$CHECK_OUT/cmd-$name.out" "${argv[@]}"
      res=$(checks_result "$CHECK_OUT/cmd-$name.out" "$VBW_COMMAND_TIMEOUT" 0)
    else
      res='{"status":"skipped","exit":null,"seconds":0,"tail":"not approved"}'
    fi
    all=$(printf '%s' "$all" | jq -c --arg n "$name" --argjson r "$res" '. + {($n): $r}')
  done < <(printf '%s' "$1" | jq -j --argjson t "$2" '.commands | keys[] | select(. as $k | $t | index($k)) | . + "\u0000"')
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
  } | jq -R -s -c --argjson r "$1" "$VBW_JQ_DEFS"'
    ($r.plans | map({key: .id, value: .files}) | from_entries) as $files
    | [split("\n")[] | select(length > 0) | split("\u001f") | select($files[.[1]] != null)
       | select(.[2] as $f | any($files[.[1]][]; covers($f)) | not)
       | "\(.[0]) (\(.[1])) changed \(.[2]), which is not in the plan"]'
}

# One screen: what ran, what it means, what is next.
prove_summary() {
  jq -r --argjson fullrun "$1" '.evidence as $e
    | ($e.checks | to_entries[] | "  \(.key) \(.value.status)\(if .value.status == "fail" then " (exit \(.value.exit))" else "" end) \(.value.seconds)s\(if .value.reused then " reused (proof of \(.value.at))" else "" end)"
        + (if .value.status == "pass" then "" else ": " + (.value.tail | split("\n") | last // "") end)),
      ($e.commands | to_entries[] | "  \(.key) \(.value.status)\(if .value.status == "skipped" then ": not approved" else " \(.value.seconds)s\(if .value.reused then " reused (proof of \(.value.at))" else "" end)" end)"),
      (if $fullrun == 1 then empty else "  checks: \([$e.checks[] | select(.reused | not)] | length) ran, \([$e.checks[] | select(.reused)] | length) reused" end),
      (if $e.full != false then "  proof: full" else
        "  proof: partial [" + ([ (if any(($e.checks[], $e.commands[]); .reused) then "results reused" else empty end),
          (if ($e.commands | has("quick") and (.quick.status != "skipped") and (has("test") | not)) then "quick stood in for the test command" else empty end),
          ($e.commands | to_entries[] | select(.key != "quick" and .value.status == "skipped") | "\(.key) not approved") ] | join(", ")) + "]" end),
      (if ($e.scope | length) == 0 then "  scope ok" else ($e.scope[] | "  scope: " + .) end),
      (.requirements[] | select(.proof == "auto") | "\(.id) \(.status)"),
      (.fixes[] | select(.status == "open" or .status == "escalated") | "\(.id) \(.status) (\(.req // .command), attempts \(.attempts)): \(.note)"),
      (if $e.passed then "proved" else "not proved" end)' "$VBW_RECORD"
  jq -e '.evidence.passed' "$VBW_RECORD" > /dev/null
}
