#!/usr/bin/env bash
# What each QA pass covered (R47, R49; docs/proof.md). For each phase of the
# active milestone: a digest of its files, of its tests (its requirements'
# checks and their files) as committed (HEAD), of its goal and plan, and of its
# [auto] requirements (id and text; a [human] one is not an input); the
# combined digest adds the same four of every phase it builds on. The combined
# digest is the pass's qa.tree in the record (no new field). The per-input
# digests live in this clone's cache $(git-common-dir)/vbw/qa.json, which only
# names the reason: missing or damaged reads as no cache. lib/qa.jq decides.
# The files digest leaves out .vbw/, documentation (is_doc) and, only while the
# contract naming them is approved, files in project.results folders (R115);
# a file a phase's check lists or runs stays in, and so does every file of a
# phase whose every plan lists only documentation: that is its code.

# The version of how qa_digests computes a phase's fingerprint: raised whenever
# that changes. A fingerprint stored without a version counts as version 0. A
# VBW update that raises it does not by itself send a passed phase back to QA:
# the pass is fingerprinted again at its own commit (qa_settle).
QA_FP_VERSION=1

# qa_tree REV: read paths (one per line), print the digest of what commit REV holds there.
qa_tree() {
  local p=() l
  while IFS= read -r l; do p+=("$l"); done
  { [ ${#p[@]} -eq 0 ] || git -C "$VBW_ROOT" ls-tree -r "$1" -- "${p[@]}"; } | vbw_sha256
}

# qa_digests RECORD [REV]: {Pn: {files, tests, plan, reqs, combined, deps}} for the active
# milestone's phases as commit REV (default HEAD) holds their files and checks'
# files and RECORD their goal, plans and requirements; deps lists every phase Pn builds on.
qa_digests() {
  local id line own='{}' out='{}' cl res=null rev="${2:-HEAD}"
  if printf '%s' "$1" | jq -e '(.project.results // []) != []' > /dev/null && contract_waiting "$1" > /dev/null; then
    res=$(printf '%s' "$1" | jq -c '.project.results')
  fi
  while read -r id line; do
    own=$(printf '%s' "$own" | jq -c --arg id "$id" --arg f "$(jq -r '.files[]' <<< "$line" | qa_tree "$rev")" --arg p "$(jq -c '.plan' <<< "$line" | vbw_sha256)" --arg q "$(jq -c '.auto' <<< "$line" | vbw_sha256)" \
      --arg t "$({ jq -c '.checks' <<< "$line"; jq -r '.check_files[]' <<< "$line" | qa_tree "$rev"; } | vbw_sha256)" '. + {($id): {files: $f, tests: $t, plan: $p, reqs: $q}}')
  done < <(printf '%s' "$1" | jq -r --argjson res "$res" "$VBW_JQ_DEFS"'. as $r | $r.phases[] | select(.milestone == $r.milestone.id) | . as $ph
    | ([$r.checks[] | select(.req as $q | $ph.reqs | index($q))] | sort_by(.id)) as $ch
    | ([$r.requirements[] | select(.proof == "auto") | .id]) as $aid
    | [$r.plans[] | select(.phase == $ph.id) | [.files[]? | select((startswith(".vbw/") or startswith("./.vbw/")) | not)]] as $pf
    | (all($pf[]; all(.[]; is_doc))) as $docs_only | [$ch[] | (.files // [])[], (.run // [])[]] as $used
    | "\(.id) " + ({files: ([$pf[][] | select(. as $f | $docs_only or any($used[]; . == $f) or ((is_doc or any($res[]?; covers($f))) | not))] | unique),
       checks: [$ch[] | {id, req, run, files}], check_files: ([$ch[] | .files[]?] | unique),
       auto: [$r.requirements[] | select(.proof == "auto" and (.id as $q | $ph.reqs | index($q))) | {id, text}],
       plan: {goal: $ph.goal, criteria: $ph.criteria,
              plans: [$r.plans[] | select(.phase == $ph.id) | {id, title, reqs: [.reqs[]? | select(. as $q | $aid | index($q))], files, after, tasks}]}} | tojson)')
  cl=$(printf '%s' "$1" | jq -c --argjson fpv "$QA_FP_VERSION" --argjson inputs null --argjson cache null -f "$VBW_LIB/qa.jq" | jq -c '.closure')
  while IFS=$'\t' read -r id line; do
    out=$(printf '%s' "$out" | jq -c --arg id "$id" --arg c "$(printf '%s' "$line" | vbw_sha256)" --argjson own "$own" --argjson cl "$cl" \
      '. + {($id): ($own[$id] + {combined: $c, deps: $cl[$id]})}')
  done < <(jq -nr --argjson own "$own" --argjson cl "$cl" '$own | keys[] | . as $k | [$k, ([$k] + $cl[$k] | map("\(.) \($own[.].files) \($own[.].tests) \($own[.].plan) \($own[.].reqs)") | join(";"))] | @tsv')
  printf '%s\n' "$out"
}

# qa_cache_file: this clone's record of what each pass covered.
qa_cache_file() {
  printf '%s/vbw/qa.json\n' "$(git -C "$VBW_ROOT" rev-parse --path-format=absolute --git-common-dir)"
}

# qa_cache_read: the cache as JSON, or null when it is missing or damaged.
qa_cache_read() {
  jq -c 'if type == "object" then . else null end' "$(qa_cache_file)" 2> /dev/null || printf 'null\n'
}

# qa_cache_put PHASE DIGESTS [COMMIT [TREE]]: remember what PHASE's pass covered:
# its own digests and those of every phase it builds on, the version of the
# method that computed them and the commit they were taken at (default HEAD).
# TREE, when given, is the qa.tree in the record that these digests vouch for.
# Locked; a damaged file starts afresh.
qa_cache_put() {
  local file tmp commit="${3:-}"
  [ -n "$commit" ] || commit=$(git -C "$VBW_ROOT" rev-parse HEAD 2> /dev/null) || commit=
  file=$(qa_cache_file)
  mkdir -p "${file%/*}" && vbw_lock_take "${file%.json}.lock" "the QA cache"
  tmp=$(mktemp "${file%/*}/qa.XXXXXX") || vbw_die "cannot write ${file%/*}"
  vbw_guard_add file "$tmp"
  qa_cache_read | jq -c --arg p "$1" --argjson d "$2" --argjson v "$QA_FP_VERSION" --arg c "$commit" --arg t "${4:-}" 'def own: {files, tests, plan, reqs};
    (. // {}) + {($p): (($d[$p] | own) + {combined: $d[$p].combined, version: $v, deps: ([$d[$p].deps[] | {key: ., value: ($d[.] | own)}] | from_entries)}
      + (if $c != "" then {commit: $c} else {} end) + (if $t != "" then {tree: $t} else {} end))}' > "$tmp" && mv "$tmp" "$file"
  vbw_guard_drop "$tmp"
  vbw_guard_drop "${file%.json}.lock"
}

# qa_pass_commit PHASE QA CACHED: the commit of a phase's pass: CACHED, the commit
# its cache entry names, when this clone has it; else the earliest commit whose
# .vbw/record.json holds this phase's qa entry QA (same tree and time). Prints
# nothing when there is none.
qa_pass_commit() {
  local c tree
  if [ -n "$3" ] && git -C "$VBW_ROOT" cat-file -e "$3^{commit}" 2> /dev/null; then
    printf '%s\n' "$3"
    return 0
  fi
  tree=$(jq -r '.tree // empty' <<< "$2")
  [ -n "$tree" ] || return 0
  while IFS= read -r c; do
    if git -C "$VBW_ROOT" show "$c:.vbw/record.json" 2> /dev/null | jq -e --arg p "$1" --argjson q "$2" 'any(.phases[]; .id == $p and .qa == $q)' > /dev/null 2>&1; then
      printf '%s\n' "$c"
      return 0
    fi
  done < <(git -C "$VBW_ROOT" log --reverse --format=%H -S"$tree" -- .vbw/record.json 2> /dev/null)
}

# qa_settle RECORD DIGESTS: for each built phase with a pass that no longer matches
# its fingerprint and whose stored fingerprint (this clone's cache entry) is of
# another version or has none: fingerprint the phase as it was at its pass's commit with the current
# method and put that in this clone's cache at the current version, vouching for
# the record's qa.tree. lib/qa.jq then judges: the same fingerprint now means the
# pass stands, a different one gives the usual reasons. No such commit: nothing
# is stored, and the phase is checked again as before. The history is read once
# per pass: after this the entry is current.
qa_settle() {
  local id cache qa c old rec
  cache=$(qa_cache_read)
  while IFS= read -r id; do
    qa=$(printf '%s' "$1" | jq -c --arg p "$id" '.phases[] | select(.id == $p) | .qa')
    c=$(qa_pass_commit "$id" "$qa" "$(jq -r --arg p "$id" '.[$p].commit // empty' <<< "$cache")")
    [ -n "$c" ] || continue
    rec=$(git -C "$VBW_ROOT" show "$c:.vbw/record.json" 2> /dev/null) || continue
    old=$(qa_digests "$rec" "$c" 2> /dev/null) || continue
    printf '%s' "$old" | jq -e --arg p "$id" 'has($p)' > /dev/null || continue
    qa_cache_put "$id" "$old" "$c" "$(jq -r '.tree' <<< "$qa")"
  done < <(printf '%s' "$1" | jq -r --argjson d "$2" --argjson c "$cache" --argjson v "$QA_FP_VERSION" '. as $r
    | $r.phases[] | select(.milestone == $r.milestone.id and .qa.result == "pass" and .qa.tree != ($d[.id].combined // .qa.tree)
        and ((($c | if type == "object" then . else {} end)[.id] | type == "object" and ((.version // 0) != $v))))
    | select(.id as $i | [$r.plans[] | select(.phase == $i)] | length > 0 and all(.[]; .status == "done")) | .id')
}
