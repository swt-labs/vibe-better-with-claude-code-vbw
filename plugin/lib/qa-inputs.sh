#!/usr/bin/env bash
# What each QA pass covered (R47, R49; docs/proof.md). For each phase of the
# active milestone: a digest of its files, of its tests (its requirements'
# checks and their files) as committed (HEAD), of its goal and plan, and of its
# [auto] requirements (id and text; a [human] one is not an input); the
# combined digest adds the tests of every phase it builds on: a phase relies on
# what another's checks promise, not on its code, documents or plan. The combined
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
QA_FP_VERSION=2

# vbw_scratch_json VAR VALUE: put VALUE in a new file inside .vbw/runtime, removed when the
# command ends or fails (vbw_guard_add), and set VAR to its path. For a jq call that
# record_update makes: bash 3.2 closes a <(...) handed to a function as soon as the
# function runs another program, so there the value goes in as --slurpfile NAME "$VAR".
# Not a command substitution: the guard must belong to the caller. Drop it with
# vbw_guard_drop when done.
vbw_scratch_json() {
  local _f
  mkdir -p "$VBW_RUNTIME"
  _f=$(mktemp "$VBW_RUNTIME/$1.XXXXXX") || vbw_die "cannot create a temporary file in $VBW_RUNTIME"
  vbw_guard_add file "$_f"
  printf '%s' "$2" > "$_f" || vbw_die "cannot write $_f"
  printf -v "$1" '%s' "$_f"
}

# qa_tree REV: read paths (one per line), print the digest of what commit REV holds there,
# each path in the repository that tracks it (vbw_repos; a folder entry also covers each
# submodule inside it, vbw_plan_paths). A submodule is read at its own HEAD when REV is
# HEAD, as vbw_head_tree counts it (vbw commit never moves its pointer), else at the commit
# REV points it at. A project without submodules digests exactly what it always did.
qa_tree() {
  local p=() l r s rels
  while IFS= read -r l; do p+=("$l"); done
  {
    if [ ${#p[@]} -gt 0 ]; then
      vbw_plan_paths "${p[@]}"
      for r in ${VBW_REPOS[@]+"${VBW_REPOS[@]}"}; do
        rels=()
        while IFS= read -r -d '' l; do rels+=("$l"); done < <(vbw_in_repo "$r")
        if [ -z "$r" ]; then
          git -C "$VBW_ROOT" ls-tree -r "$1" -- "${rels[@]}"
        else
          s=HEAD
          [ "$1" = HEAD ] || s=$(git -C "$VBW_ROOT" rev-parse -q --verify "$1:$r" 2> /dev/null) || s=
          printf '%s\n' "$r"
          [ -z "$s" ] || git -C "$VBW_ROOT/$r" ls-tree -r "$s" -- "${rels[@]}"
        fi
      done
    fi
  } | vbw_sha256
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
    own=$(printf '%s' "$own" | jq -c --arg id "$id" --arg f "$(printf '%s' "$line" | jq -r '.files[]' | qa_tree "$rev")" --arg p "$(printf '%s' "$line" | jq -c '.plan' | vbw_sha256)" --arg q "$(printf '%s' "$line" | jq -c '.auto' | vbw_sha256)" \
      --arg t "$({ printf '%s' "$line" | jq -c '.checks'; printf '%s' "$line" | jq -r '.check_files[]' | qa_tree "$rev"; } | vbw_sha256)" '. + {($id): {files: $f, tests: $t, plan: $p, reqs: $q}}')
  done < <(printf '%s' "$1" | jq -r --slurpfile res <(printf '%s' "$res") "$VBW_JQ_DEFS"'$res[0] as $res | . as $r | $r.phases[] | select(.milestone == $r.milestone.id) | . as $ph
    | ([$r.checks[] | select(.req as $q | $ph.reqs | index($q))] | sort_by(.id)) as $ch
    | ([$r.requirements[] | select(.proof == "auto") | .id]) as $aid
    | [$r.plans[] | select(.phase == $ph.id) | [.files[]? | select((startswith(".vbw/") or startswith("./.vbw/")) | not)]] as $pf
    | (all($pf[]; all(.[]; is_doc))) as $docs_only | [$ch[] | (.files // [])[], (.run // [])[]] as $used
    | "\(.id) " + ({files: ([$pf[][] | select(. as $f | $docs_only or any($used[]; . == $f) or ((is_doc or any($res[]?; covers($f))) | not))] | unique),
       checks: [$ch[] | {id, req, run, files}], check_files: ([$ch[] | .files[]?] | unique),
       auto: [$r.requirements[] | select(.proof == "auto" and (.id as $q | $ph.reqs | index($q))) | {id, text}],
       plan: {goal: $ph.goal, criteria: $ph.criteria,
              plans: [$r.plans[] | select(.phase == $ph.id) | {id, title, reqs: [.reqs[]? | select(. as $q | $aid | index($q))], files, after, tasks}]}} | tojson)')
  cl=$(printf '%s' "$1" | jq -c --argjson fpv "$QA_FP_VERSION" --argjson inputs null --argjson cache null "$VBW_JQ_DEFS$(cat "$VBW_LIB/qa.jq")" | jq -c '.closure')
  while IFS=$'\t' read -r id line; do
    out=$(printf '%s' "$out" | jq -c --arg id "$id" --arg c "$(printf '%s' "$line" | vbw_sha256)" --slurpfile own <(printf '%s' "$own") --slurpfile cl <(printf '%s' "$cl") \
      '. + {($id): ($own[0][$id] + {combined: $c, deps: $cl[0][$id]})}')
  done < <(jq -nr --slurpfile own <(printf '%s' "$own") --slurpfile cl <(printf '%s' "$cl") '$own[0] as $own | $cl[0] as $cl | $own | keys[] | . as $k | [$k, (["\($k) \($own[$k].files) \($own[$k].tests) \($own[$k].plan) \($own[$k].reqs)"] + [$cl[$k][] | "\(.) \($own[.].tests)"] | join(";"))] | @tsv')
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
  local file tmp dg commit="${3:-}"
  [ -n "$commit" ] || commit=$(git -C "$VBW_ROOT" rev-parse HEAD 2> /dev/null) || commit=
  file=$(qa_cache_file)
  mkdir -p "${file%/*}" && vbw_lock_take "${file%.json}.lock" "the QA cache"
  tmp=$(mktemp "${file%/*}/qa.XXXXXX") || vbw_die "cannot write ${file%/*}"
  vbw_guard_add file "$tmp"
  vbw_scratch_json dg "$2"
  qa_cache_read | jq -c --arg p "$1" --slurpfile dg "$dg" --argjson v "$QA_FP_VERSION" --arg c "$commit" --arg t "${4:-}" 'def own: {files, tests, plan, reqs};
    $dg[0] as $d | (. // {}) + {($p): (($d[$p] | own) + {combined: $d[$p].combined, version: $v, deps: ([$d[$p].deps[] | {key: ., value: ($d[.] | own)}] | from_entries)}
      + (if $c != "" then {commit: $c} else {} end) + (if $t != "" then {tree: $t} else {} end))}' > "$tmp" && mv "$tmp" "$file"
  vbw_guard_drop "$tmp"
  vbw_guard_drop "$dg"
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
  tree=$(printf '%s' "$2" | jq -r '.tree // empty')
  [ -n "$tree" ] || return 0
  while IFS= read -r c; do
    if git -C "$VBW_ROOT" show "$c:.vbw/record.json" 2> /dev/null | jq -e --arg p "$1" --slurpfile q <(printf '%s' "$2") 'any(.phases[]; .id == $p and .qa == $q[0])' > /dev/null 2>&1; then
      vbw_out '%s\n' "$c"
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
    c=$(qa_pass_commit "$id" "$qa" "$(printf '%s' "$cache" | jq -r --arg p "$id" '.[$p].commit // empty')")
    [ -n "$c" ] || continue
    rec=$(git -C "$VBW_ROOT" show "$c:.vbw/record.json" 2> /dev/null) || continue
    old=$(qa_digests "$rec" "$c" 2> /dev/null) || continue
    printf '%s' "$old" | jq -e --arg p "$id" 'has($p)' > /dev/null || continue
    qa_cache_put "$id" "$old" "$c" "$(printf '%s' "$qa" | jq -r '.tree')"
  done < <(printf '%s' "$1" | jq -r --slurpfile dg <(printf '%s' "$2") --slurpfile cg <(printf '%s' "$cache") --argjson v "$QA_FP_VERSION" '$dg[0] as $d | $cg[0] as $c | . as $r
    | $r.phases[] | select(.milestone == $r.milestone.id and .qa.result == "pass" and .qa.tree != ($d[.id].combined // .qa.tree)
        and ((($c | if type == "object" then . else {} end)[.id] | type == "object" and ((.version // 0) != $v))))
    | select(.id as $i | [$r.plans[] | select(.phase == $i)] | length > 0 and all(.[]; .status == "done")) | .id')
}
