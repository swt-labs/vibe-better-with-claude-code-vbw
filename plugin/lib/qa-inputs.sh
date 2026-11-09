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

# jq definitions the one pass over the record (lib/cmd-next.sh, R249) shares with the
# functions below, so a caller that has the record's facts from its pass passes them on and
# the record is not parsed again for each:
#   qa_listing($res): one line per phase of the active milestone, "Pn {json}": the inputs its
#     digests are made of (files, checks, check files, auto requirements, plan); $res is
#     project.results, or null while the contract naming it is not approved;
#   qa_settle_in: the active milestone's passed phases, {id, qa, built}, what qa_settle reads;
#   qa_prog($inputs; $cache): lib/qa.jq (run with --argjson fpv).
# shellcheck disable=SC2016
VBW_QA_DEFS='def qa_listing($res): . as $r | $r.phases[] | select(.milestone == $r.milestone.id) | . as $ph
    | ([$r.checks[] | select(.req as $q | $ph.reqs | index($q))] | sort_by(.id)) as $ch
    | ([$r.requirements[] | select(.proof == "auto") | .id]) as $aid
    | [$r.plans[] | select(.phase == $ph.id) | [.files[]? | select((startswith(".vbw/") or startswith("./.vbw/")) | not)]] as $pf
    | (all($pf[]; all(.[]; is_doc))) as $docs_only | [$ch[] | (.files // [])[], (.run // [])[]] as $used
    | "\(.id) " + ({files: ([$pf[][] | select(. as $f | $docs_only or any($used[]; . == $f) or ((is_doc or any($res[]?; covers($f))) | not))] | unique),
       checks: [$ch[] | {id, req, run, files}], check_files: ([$ch[] | .files[]?] | unique),
       auto: [$r.requirements[] | select(.proof == "auto" and (.id as $q | $ph.reqs | index($q))) | {id, text}],
       plan: {goal: $ph.goal, criteria: $ph.criteria,
              plans: [$r.plans[] | select(.phase == $ph.id) | {id, title, reqs: [.reqs[]? | select(. as $q | $aid | index($q))], files, after, tasks}]}} | tojson);
def qa_settle_in: . as $r | [$r.phases[] | select(.milestone == $r.milestone.id and .qa.result == "pass")
    | {id, qa, built: (.id as $i | [$r.plans[] | select(.phase == $i)] | length > 0 and all(.[]; .status == "done"))}];
def qa_prog($inputs; $cache):
'"$(cat "$VBW_LIB/qa.jq")"'
;
'

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

# The awk program that picks, from a repository's tree listing (git ls-tree -r), the lines
# a path set covers, as ls-tree with those pathspecs would print them. RELS holds the
# pathspecs, separated by \037. A pathspec is normalised as git does (a leading ./, //, /./
# and x/.. folded; "." or nothing is the whole repository); with a trailing / it covers only
# what is inside that folder, without it the entry itself too; it is no glob. A path git
# quotes (a control character, a quote, a backslash, a byte above 127) is read back to its
# bytes before it is compared; the line itself is printed as git wrote it.
# shellcheck disable=SC2016
QA_TREE_AWK='
function unq(s,   i, c, o, d) {
  s = substr(s, 2, length(s) - 2); o = ""
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c != "\\") { o = o c; continue }
    i++; c = substr(s, i, 1)
    if (c ~ /[0-7]/) { d = substr(s, i, 3); i += 2; o = o sprintf("%c", substr(d, 1, 1) * 64 + substr(d, 2, 1) * 8 + substr(d, 3, 1)) }
    else if (c == "a") o = o "\007"
    else if (c == "b") o = o "\010"
    else if (c == "t") o = o "\011"
    else if (c == "n") o = o "\012"
    else if (c == "v") o = o "\013"
    else if (c == "f") o = o "\014"
    else if (c == "r") o = o "\015"
    else o = o c
  }
  return o
}
BEGIN {
  n = split(ENVIRON["RELS"], raw, "\037"); k = 0; all = 0
  for (i = 1; i <= n; i++) {
    r = raw[i]; slash = (r ~ /\/$/); m = split(r, seg, "/"); d = 0; bad = 0
    for (j = 1; j <= m; j++) {
      if (seg[j] == "" || seg[j] == ".") continue
      if (seg[j] == "..") { if (d == 0) { bad = 1; break } d--; continue }
      d++; stack[d] = seg[j]
    }
    if (bad) continue
    if (d == 0) { all = 1; continue }
    r = stack[1]; for (j = 2; j <= d; j++) r = r "/" stack[j]
    k++; rel[k] = r; sl[k] = slash
  }
}
{
  t = index($0, "\t")
  if (t == 0) next
  if (all) { print; next }
  p = substr($0, t + 1)
  if (substr(p, 1, 1) == "\"") p = unq(p)
  for (i = 1; i <= k; i++) {
    if ((!sl[i] && p == rel[i]) || substr(p, 1, length(rel[i]) + 1) == rel[i] "/") { print; break }
  }
}'

# The trees qa_tree_load read: the repository each was read in ("" is the project's own) and
# its listing.
QA_TREE_REPOS=()
QA_TREE_LISTS=()

# qa_tree_load REV LISTING: read, once, the tree of commit REV of every repository the phases
# of LISTING (qa_listing's lines) name a file in: one git ls-tree -r per repository, however
# many phases, a submodule once too (each repository as qa_tree reads it: a submodule at its
# own HEAD when REV is HEAD, as vbw_head_tree counts it, else at the commit REV points it at).
# The listing is limited to the files of all the phases together while that fits on a command
# line; the whole tree otherwise.
qa_tree_load() {
  local u=() l r s rels size
  QA_TREE_REPOS=()
  QA_TREE_LISTS=()
  while IFS= read -r l; do u+=("$l"); done < <(printf '%s\n' "$2" | jq -Rr 'sub("^[^ ]+ "; "") | fromjson | .files[], .check_files[]')
  [ ${#u[@]} -gt 0 ] || return 0
  vbw_plan_paths "${u[@]}"
  for r in ${VBW_REPOS[@]+"${VBW_REPOS[@]}"}; do
    rels=()
    size=0
    while IFS= read -r -d '' l; do
      rels+=("$l")
      size=$((size + ${#l} + 1))
    done < <(vbw_in_repo "$r")
    [ "$size" -le 65536 ] || rels=(.)
    if [ -z "$r" ]; then
      l=$(git -C "$VBW_ROOT" ls-tree -r "$1" -- "${rels[@]}")
    else
      s=HEAD
      [ "$1" = HEAD ] || s=$(git -C "$VBW_ROOT" rev-parse -q --verify "$1:$r" 2> /dev/null) || s=
      l=
      [ -z "$s" ] || l=$(git -C "$VBW_ROOT/$r" ls-tree -r "$s" -- "${rels[@]}")
    fi
    QA_TREE_REPOS+=("$r")
    QA_TREE_LISTS+=("$l")
  done
}

# qa_tree: read paths (one per line), print the digest of what the commit qa_tree_load read
# holds there, each path in the repository that tracks it (vbw_repos; a folder entry also
# covers each submodule inside it, vbw_plan_paths): the repository's lines of the tree
# listing, a submodule's after its own folder name. A project without submodules digests
# exactly what it always did.
qa_tree() {
  local p=() l r i rels
  while IFS= read -r l; do p+=("$l"); done
  {
    if [ ${#p[@]} -gt 0 ]; then
      vbw_plan_paths "${p[@]}"
      for r in ${VBW_REPOS[@]+"${VBW_REPOS[@]}"}; do
        rels=
        while IFS= read -r -d '' l; do rels="$rels${rels:+$'\037'}$l"; done < <(vbw_in_repo "$r")
        [ -z "$r" ] || vbw_out '%s\n' "$r"
        i=0
        while [ "$i" -lt ${#QA_TREE_REPOS[@]} ] && [ "${QA_TREE_REPOS[$i]}" != "$r" ]; do i=$((i + 1)); done
        [ "$i" -lt ${#QA_TREE_REPOS[@]} ] || continue
        printf '%s\n' "${QA_TREE_LISTS[$i]}" | RELS=$rels LC_ALL=C awk "$QA_TREE_AWK"
      done
    fi
  } | vbw_sha256
}

# qa_digests RECORD [REV]: {Pn: {files, tests, plan, reqs, combined, deps}} for the active
# milestone's phases as commit REV (default HEAD) holds their files and checks'
# files and RECORD their goal, plans and requirements; deps lists every phase Pn builds on.
qa_digests() {
  local id line own='{}' out='{}' cl lst res=null rev="${2:-HEAD}" pre=0
  # The caller's pass (QA_PRE_LISTING, QA_PRE_CLOSURE: set by next_decide for the record it
  # judged) stands in for the two reads of the record, for the current commit only.
  [ "$rev" = HEAD ] && [ -n "${QA_PRE_CLOSURE:-}" ] && pre=1
  if [ "$pre" = 0 ] && printf '%s' "$1" | jq -e '(.project.results // []) != []' > /dev/null && contract_waiting "$1" > /dev/null; then
    res=$(printf '%s' "$1" | jq -c '.project.results')
  fi
  # Each repository's tree of the commit is read once for all the phases (qa_tree_load).
  if [ "$pre" = 1 ]; then lst=$QA_PRE_LISTING
  else lst=$(printf '%s' "$1" | jq -r --argjson res "$res" "$VBW_JQ_DEFS$VBW_QA_DEFS"'qa_listing($res)'); fi
  [ -z "$lst" ] || qa_tree_load "$rev" "$lst"
  while read -r id line; do
    own=$(printf '%s' "$own" | jq -c --arg id "$id" --arg f "$(printf '%s' "$line" | jq -r '.files[]' | qa_tree)" --arg p "$(printf '%s' "$line" | jq -c '.plan' | vbw_sha256)" --arg q "$(printf '%s' "$line" | jq -c '.auto' | vbw_sha256)" \
      --arg t "$({ printf '%s' "$line" | jq -c '.checks'; printf '%s' "$line" | jq -r '.check_files[]' | qa_tree; } | vbw_sha256)" '. + {($id): {files: $f, tests: $t, plan: $p, reqs: $q}}')
  done < <([ -z "$lst" ] || printf '%s\n' "$lst")
  if [ "$pre" = 1 ]; then cl=$QA_PRE_CLOSURE
  else cl=$(printf '%s' "$1" | jq -c --argjson fpv "$QA_FP_VERSION" "$VBW_JQ_DEFS$VBW_QA_DEFS"'qa_prog(null; null) | .closure'); fi
  while IFS=$'\t' read -r id line; do
    out=$(printf '%s' "$out" | jq -c --arg id "$id" --arg c "$(printf '%s' "$line" | vbw_sha256)" --slurpfile own <(printf '%s' "$own") --slurpfile cl <(printf '%s' "$cl") \
      '. + {($id): ($own[0][$id] + {combined: $c, deps: $cl[0][$id]})}')
  done < <(jq -nr --slurpfile own <(printf '%s' "$own") --slurpfile cl <(printf '%s' "$cl") '$own[0] as $own | $cl[0] as $cl | $own | keys[] | . as $k | [$k, (["\($k) \($own[$k].files) \($own[$k].tests) \($own[$k].plan) \($own[$k].reqs)"] + [$cl[$k][] | "\(.) \($own[.].tests)"] | join(";"))] | @tsv')
  vbw_out '%s\n' "$out"
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
  local id cache qa c old rec settle="${QA_PRE_SETTLE:-}"
  cache=$(qa_cache_read)
  # The passed phases, from the caller's pass when it has one (QA_PRE_SETTLE), else from the record.
  [ -n "$settle" ] || settle=$(printf '%s' "$1" | jq -c "$VBW_QA_DEFS"'qa_settle_in')
  while IFS= read -r id; do
    qa=$(printf '%s' "$settle" | jq -c --arg p "$id" '.[] | select(.id == $p) | .qa')
    c=$(qa_pass_commit "$id" "$qa" "$(printf '%s' "$cache" | jq -r --arg p "$id" '.[$p].commit // empty')")
    [ -n "$c" ] || continue
    rec=$(git -C "$VBW_ROOT" show "$c:.vbw/record.json" 2> /dev/null) || continue
    old=$(qa_digests "$rec" "$c" 2> /dev/null) || continue
    printf '%s' "$old" | jq -e --arg p "$id" 'has($p)' > /dev/null || continue
    qa_cache_put "$id" "$old" "$c" "$(printf '%s' "$qa" | jq -r '.tree')"
  done < <(printf '%s' "$settle" | jq -r --slurpfile dg <(printf '%s' "$2") --slurpfile cg <(printf '%s' "$cache") --argjson v "$QA_FP_VERSION" '$dg[0] as $d | $cg[0] as $c
    | .[] | select(.qa.tree != ($d[.id].combined // .qa.tree)
        and ((($c | if type == "object" then . else {} end)[.id] | type == "object" and ((.version // 0) != $v)))
        and .built) | .id')
}
