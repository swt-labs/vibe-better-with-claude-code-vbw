#!/usr/bin/env bash
# Delivered files (docs/proof.md): a plan delivers the files its own commits
# (VBW-Plan: trailer) added or changed, and HEAD must still hold each as VBW's
# last commit of it left it. VBW's commits carry a VBW-Plan: trailer naming a
# plan of the record or a VBW-Fix: trailer naming a fix of the record. A later
# one moves a file on: a later plan's change or removal is delivered work, and a
# plan that deletes a file delivers nothing for it. Any other difference at HEAD
# (a hand edit, a hand deletion, a revert by hand, a merge) is a deviation. Only
# the current milestone's plans are checked. Files under .vbw/, the check files
# (their approval guards them) and the files in the project's results folders
# are not deliverables. Only the record's own history is read (lib/history.sh):
# plan ids restart with a new record, so a commit older than the record (a
# retired roadmap's VBW-Plan: P1.1) delivered nothing for today's P1.1. vbw
# prove keeps the deviations in its evidence; lib/qa.jq gives each to QA with
# the decision that covers it, if any.

# shellcheck source=history.sh
. "$VBW_LIB/history.sh"

# DELIVERED_JQ, over git's stream (git log -z --topo-order --no-renames --raw:
# per commit a header "hash, unit separator, commit time, unit separator,
# VBW-Plan values, unit separator, VBW-Fix values", the values separated by
# commas, then per changed path ":old-mode new-mode old-blob new-blob status"
# and the path; a merge lists nothing) and the record ($rec). Newest first, for
# each path: the first of VBW's commits (what it left there and when), the
# newest plan commit (its plan owns the file) and the commits without VBW's
# provenance newer than that first one (by). A commit a park undid ($undone: the
# messages of the park's reverts, "This reverts commit HASH.") is passed over: its
# change is gone, so it delivered nothing, even where a later plan took its
# plan's id (T163); the revert itself counts as any commit outside a plan. Out:
# the files the current milestone's plans own and VBW left in place, [{file,
# plan, commit, at, state ("mode blob"), by}]. Each record is built once, so a
# commit of 20,000 files costs no more per path than a small one. Each path is
# named by its project path: $pre (the submodule's folder and a slash, "" for
# the project) before what git printed. VBW_JQ_DEFS prepended (covers).
# shellcheck disable=SC2016 # a jq program
DELIVERED_JQ='$rec[0] as $r
  | ([$undone | scan("This reverts commit ([0-9a-f]{40,64})\\.") | {key: .[0], value: true}] | from_entries) as $gone
  | ([$r.phases[] | select(.milestone == $r.milestone.id) | .id]) as $now
  | ([$r.plans[] | {key: .id, value: .phase}] | from_entries) as $phase
  | ([$r.fixes[]? | {key: .id, value: true}] | from_entries) as $fixes
  | ([$r.checks[] | (.files // [])[]] | unique) as $cf
  | ($r.project.results // []) as $res
  | split("\u0000") as $t
  | [foreach range(0; $t | length) as $k ({e: null, c: null, o: null};
      if .e != null then .o = {c: .c, f: ($pre + $t[$k]), e: .e} | .e = null
      else ($t[$k] | sub("^\n+"; "")) as $x
        | if $x == "" then .o = null
          elif ($x | startswith(":")) then .e = ($x[1:] | split(" ")) | .o = null
          else ($x | split("\u001f")) as $h
            | (($h[2] // "") | split(",")) as $pl
            | .c = {h: $h[0], t: ($h[1] | tonumber), p: (first($pl[] | select($phase[.] != null)) // null),
                    v: (any($pl[]; $phase[.] != null) or any(($h[3] // "") | split(",")[]; $fixes[.] != null))}
            | .o = null
          end
      end;
      .o // empty)]
  | reduce .[] as $e ({};
      if .[$e.f].own != null or $gone[$e.c.h] then .
      else .[$e.f] |= ((. // {exp: null, own: null, by: []})
        | if .exp != null then .
          elif $e.c.v then .exp = {commit: $e.c.h, at: $e.c.t, state: (if $e.e[4] == "D" then null else "\($e.e[1]) \($e.e[3])" end)}
          else .by += [$e.c.h] end
        | if .own == null and $e.c.p != null then .own = $e.c.p else . end)
      end)
  | [to_entries[] | .key as $f | .value
     | select(.own != null and .exp.state != null and ($phase[.own] | IN($now[]))
         and ($f | startswith(".vbw/") | not) and (any($cf[]; covers($f)) | not) and (any($res[]; covers($f)) | not))
     | {file: $f, plan: .own, commit: .exp.commit, at: (.exp.at | todate), state: .exp.state, by}]'

# DELIVERED_HEAD_JQ, over what HEAD holds for those files ($head: git ls-tree -r
# -z, "mode type blob", a tab and the path per entry, the path after $pre) and
# the files ($d): the deviations, [{file, plan, commit, at, change (deleted or
# changed), by}], by plan and file.
# shellcheck disable=SC2016 # a jq program
DELIVERED_HEAD_JQ='($head | split("\u0000") | map(select(length > 0) | index("\t") as $i
    | {key: ($pre + .[$i + 1:]), value: (.[0:$i] | split(" ") | "\(.[0]) \(.[2])")}) | from_entries) as $now
  | [$d[0][] | ($now[.file]) as $n | select($n != .state)
     | {file, plan, commit, at, change: (if $n == null then "deleted" else "changed" end), by}]
  | sort_by(.plan, .file)'

# DELIVERED_DEFS, jq text prepended where a deviation is shown (the proof's summary,
# vbw show evidence, vbw show phase, vbw qa record's refusal): deviation_line, on a
# deviation, "FILE (PLAN) deleted|changed outside any plan, by COMMIT, ..." (the
# commits that changed it, 12 digits each; a merge's change names the commit it
# differs from). The QA brief (workflows/verifying.js) says it in the same words.
# shellcheck disable=SC2016,SC2034 # jq text, used by cmd-prove.sh, cmd-show.sh and cmd-qa.sh
DELIVERED_DEFS='def deviation_line: "\(.file) (\(.plan)) \(.change) outside any plan"
  + (if (.by | length) > 0 then ", by \([.by[] | .[0:12]] | join(", "))" else ", since \(.commit[0:12])" end);
'

# delivered_deviations RECORD: the deviations of the current milestone's plans
# (above), as a JSON array. In each repository VBW commits in (history_repos:
# the project and each submodule, whose files a plan names by project path),
# git lists the record's own history once to find how far back the oldest
# commit naming one of those plans lies, walks it once to there, reads the
# park's reverts once (only when there are any) and lists HEAD once for the
# files found; jq does the rest, so the shell runs the same commands whatever
# the length of the history or the number of files.
delivered_deviations() {
  local dir n out r g i=0 HISTORY_ARGS HISTORY_REPOS
  mkdir -p "$VBW_RUNTIME" || vbw_die "cannot create $VBW_RUNTIME"
  dir=$(mktemp -d "$VBW_RUNTIME/delivered.XXXXXX") || vbw_die "cannot create a temporary folder in $VBW_RUNTIME"
  vbw_guard_add dir "$dir"
  printf '%s' "$1" > "$dir/rec.json" || vbw_die "cannot write $dir/rec.json"
  # The messages of the park's reverts, which name the commits each undid: one listing per repository, none without a park.
  printf '%s' "$1" | jq -r '(.loop.items // [])[].reverts[]?' > "$dir/reverts"
  history_repos
  for r in "${HISTORY_REPOS[@]}"; do
    i=$((i + 1))
    g="$VBW_ROOT${r:+/$r}"
    history_args_in "$r"
    n=$(git -C "$g" log -z --topo-order --format='%(trailers:key=VBW-Plan,valueonly,separator=%x2C)' "${HISTORY_ARGS[@]}" 2> /dev/null \
      | jq -R -s --slurpfile rec "$dir/rec.json" '$rec[0] as $r | ([$r.phases[] | select(.milestone == $r.milestone.id) | .id]) as $now
          | ([$r.plans[] | select(.phase | IN($now[])) | .id]) as $mine
          | split("\u0000") | map(ltrimstr("\n") | split(",") | any(.[]; IN($mine[]))) | (rindex(true) // -1) + 1') || n=0
    if [ "${n:-0}" -gt 0 ]; then
      git -C "$g" log -z --topo-order --no-renames --raw --no-abbrev --max-count="$n" \
        --format='%H%x1f%ct%x1f%(trailers:key=VBW-Plan,valueonly,separator=%x2C)%x1f%(trailers:key=VBW-Fix,valueonly,separator=%x2C)' "${HISTORY_ARGS[@]}" > "$dir/log" 2> /dev/null \
        || { vbw_guard_drop "$dir"; vbw_die "internal error: the check of delivered files could not read the history${r:+ of $r}"; }
    else
      : > "$dir/log"
    fi
    : > "$dir/undone"
    [ ! -s "$dir/reverts" ] || git -C "$g" log --stdin --no-walk=unsorted --ignore-missing --format='%B%x00' < "$dir/reverts" > "$dir/undone" 2> /dev/null || : > "$dir/undone"
    jq -R -s -c --slurpfile rec "$dir/rec.json" --rawfile undone "$dir/undone" --arg pre "${r:+$r/}" "$VBW_JQ_DEFS$DELIVERED_JQ" "$dir/log" > "$dir/mine" \
      || { vbw_guard_drop "$dir"; vbw_die "internal error: the check of delivered files could not read the history${r:+ of $r}"; }
    # A listing that fails is no listing: reading it as empty would call every file deleted.
    jq -j --arg pre "${r:+$r/}" '.[] | (.file | ltrimstr($pre)) + "\u0000"' "$dir/mine" | xargs -0 -r git -C "$g" --literal-pathspecs ls-tree -r -z HEAD -- > "$dir/head" 2> /dev/null \
      || { vbw_guard_drop "$dir"; vbw_die "internal error: the check of delivered files could not list HEAD${r:+ of $r}"; }
    jq -n -c --slurpfile d "$dir/mine" --rawfile head "$dir/head" --arg pre "${r:+$r/}" "$DELIVERED_HEAD_JQ" > "$dir/dev.$i" \
      || { vbw_guard_drop "$dir"; vbw_die "internal error: the check of delivered files could not read HEAD${r:+ of $r}"; }
  done
  out=$(jq -s -c 'add | sort_by(.plan, .file)' "$dir"/dev.*) \
    || { vbw_guard_drop "$dir"; vbw_die "internal error: the check of delivered files could not read HEAD"; }
  vbw_guard_drop "$dir"
  printf '%s\n' "$out"
}
