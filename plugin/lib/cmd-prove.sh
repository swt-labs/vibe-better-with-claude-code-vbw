#!/usr/bin/env bash
# vbw prove: run exactly what the user approved and record the evidence
# (docs/proof.md). Nothing unapproved ever executes.

# shellcheck source=checks.sh
. "$VBW_LIB/checks.sh"

VBW_FIX_CAP=3
VBW_COMMAND_TIMEOUT=900

cmd_prove() {
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw prove"
  vbw_require_project
  cd "$VBW_ROOT" || vbw_die "cannot enter $VBW_ROOT"
  local record checks commands scope tree ev at
  record=$(record_read)
  checks_begin "$record"
  checks=$(checks_run_all "$record")
  commands=$(prove_commands "$record")
  checks_end
  scope=$(prove_scope "$record")
  tree=$(vbw_code_tree) || vbw_die "cannot fingerprint the project files"
  at=$(vbw_now)
  ev=$(jq -n --arg at "$at" --arg h "$CHECK_HASH" --arg tree "$tree" \
    --argjson c "$checks" --argjson m "$commands" --argjson s "$scope" \
    '{at: $at, contract: $h, tree: $tree, checks: $c, commands: $m, scope: $s,
      passed: (all($c[]; .status == "pass") and all($m[]; .status == "pass" or .status == "skipped") and ($s | length) == 0)}')
  record_update "$VBW_JQ_DEFS$(cat "$VBW_LIB/prove.jq")" --argjson ev "$ev" --argjson cap "$VBW_FIX_CAP" --arg at "$at"
  # The evidence is part of the plan of record: commit it, so a proof never
  # leaves VBW's own file modified in the user's working tree.
  record_commit "chore(vbw): proof $(jq -r 'if .evidence.passed then "passed" else "not passed" end' "$VBW_RECORD")"
  prove_summary
}

# Project commands: run only those whose exact argv the user approved.
prove_commands() {
  local name argv a all='{}' res
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
  } | jq -R -s -c --argjson r "$1" "$VBW_JQ_DEFS"'
    ($r.plans | map({key: .id, value: .files}) | from_entries) as $files
    | [split("\n")[] | select(length > 0) | split("\u001f") | select($files[.[1]] != null)
       | select(.[2] as $f | any($files[.[1]][]; covers($f)) | not)
       | "\(.[0]) (\(.[1])) changed \(.[2]), which is not in the plan"]'
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
