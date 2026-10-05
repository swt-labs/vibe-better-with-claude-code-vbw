#!/usr/bin/env bash
# What each QA pass covered (R47, R49; docs/proof.md). For each phase of the
# active milestone: a digest of its files, of its tests (its requirements'
# checks and their files) as committed (HEAD), and of its goal and plan; the
# combined digest adds the same three of every phase it builds on. The combined
# digest is the pass's qa.tree in the record (no new field). The per-input
# digests live in this clone's cache $(git-common-dir)/vbw/qa.json, which only
# names the reason: missing or damaged reads as no cache. lib/qa.jq decides.

# qa_tree: read paths (one per line), print the digest of what HEAD holds there.
qa_tree() {
  local p=() l
  while IFS= read -r l; do p+=("$l"); done
  { [ ${#p[@]} -eq 0 ] || git -C "$VBW_ROOT" ls-tree -r HEAD -- "${p[@]}"; } | vbw_sha256
}

# qa_digests RECORD: {Pn: {files, tests, plan, combined, deps}} for the active
# milestone's phases; deps lists every phase Pn builds on.
qa_digests() {
  local id line own='{}' out='{}' cl
  while read -r id line; do
    own=$(printf '%s' "$own" | jq -c --arg id "$id" --arg f "$(jq -r '.files[]' <<< "$line" | qa_tree)" --arg p "$(jq -c '.plan' <<< "$line" | vbw_sha256)" \
      --arg t "$({ jq -c '.checks' <<< "$line"; jq -r '.check_files[]' <<< "$line" | qa_tree; } | vbw_sha256)" '. + {($id): {files: $f, tests: $t, plan: $p}}')
  done < <(printf '%s' "$1" | jq -r '. as $r | $r.phases[] | select(.milestone == $r.milestone.id) | . as $ph
    | ([$r.checks[] | select(.req as $q | $ph.reqs | index($q))] | sort_by(.id)) as $ch
    | "\(.id) " + ({files: ([$r.plans[] | select(.phase == $ph.id) | .files[]?] | unique),
       checks: [$ch[] | {id, req, run, files}], check_files: ([$ch[] | .files[]?] | unique),
       plan: {goal: $ph.goal, criteria: $ph.criteria, reqs: $ph.reqs,
              plans: [$r.plans[] | select(.phase == $ph.id) | {id, title, reqs, files, after, tasks}]}} | tojson)')
  cl=$(printf '%s' "$1" | jq -c --argjson inputs null --argjson cache null -f "$VBW_LIB/qa.jq" | jq -c '.closure')
  while IFS=$'\t' read -r id line; do
    out=$(printf '%s' "$out" | jq -c --arg id "$id" --arg c "$(printf '%s' "$line" | vbw_sha256)" --argjson own "$own" --argjson cl "$cl" \
      '. + {($id): ($own[$id] + {combined: $c, deps: $cl[$id]})}')
  done < <(jq -nr --argjson own "$own" --argjson cl "$cl" '$own | keys[] | . as $k | [$k, ([$k] + $cl[$k] | map("\(.) \($own[.].files) \($own[.].tests) \($own[.].plan)") | join(";"))] | @tsv')
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

# qa_cache_put PHASE DIGESTS: remember what PHASE's pass covered: its own digests
# and those of every phase it builds on. Locked; a damaged file starts afresh.
qa_cache_put() {
  local file tmp
  file=$(qa_cache_file)
  mkdir -p "${file%/*}" && vbw_lock_take "${file%.json}.lock" "the QA cache"
  tmp=$(mktemp "${file%/*}/qa.XXXXXX") || vbw_die "cannot write ${file%/*}"
  vbw_guard_add file "$tmp"
  qa_cache_read | jq -c --arg p "$1" --argjson d "$2" 'def own: {files, tests, plan};
    (. // {}) + {($p): (($d[$p] | own) + {deps: ([$d[$p].deps[] | {key: ., value: ($d[.] | own)}] | from_entries)})}' > "$tmp" && mv "$tmp" "$file"
  vbw_guard_drop "$tmp"
  vbw_guard_drop "${file%.json}.lock"
}
