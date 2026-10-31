#!/usr/bin/env bash
# The one reuse rule of vbw prove and vbw fix done (docs/proof.md, R166) and
# the clone's store of recorded runs. A unit (a check, a project command or a
# test file) is run again only when something it depends on changed; its read
# list, written down by the run itself, says what it depends on. A check
# depends as well on what the contract ties it to: the files of its
# requirement's plans. One of them added or deleted runs the check again whether
# or not it read the file, since a check may test whether a path exists without
# opening it (R168); the read list cannot see such a test.
#
# Planning and saving work on all the units of a proof at once (R202): the
# fingerprints of the units' definitions come from one pass, the rule is one jq
# over every unit, and git is asked once per distinct recorded tree. The number
# of processes does not grow with the number of units.

# A run result's read list ({files, dirs: [{path, fp}], git}) as the store keeps it (null when
# none was written down). A listed folder keeps its fingerprint (the names directly inside it),
# so a later proof can tell that its listing changed even when no file directly inside did.
# A project command (its test run above all) gets this many seconds unless settings.command_timeout says otherwise (R153).
VBW_COMMAND_TIMEOUT=3600
# shellcheck disable=SC2034 # read by cmd_prove and cmd_fix
PROVE_FLAT='map_values(if $off or (.reads | type) != "object" then . + {reads: null}
  else . + {dirs: .reads.dirs, git: .reads.git, reads: .reads.files} end)'

# The fingerprints of the units' approved definitions. PROOFREUSE_FPS is the map
# unit key ("check:ID", "command:NAME", "file:PATH") -> fingerprint (a JSON
# object kept in the process; PROOFREUSE_FPS_RECORD is the record text it was
# computed from). A fingerprint is the SHA-256 of the unit's canonical bytes:
#   check:   its approved definition as key-sorted compact JSON, then a newline;
#   command: the time limit and the argv, each ended by a NUL;
#   file:    the same, with the form's argv for that test file.
PROOFREUSE_FPS=${PROOFREUSE_FPS:-'{}'}
PROOFREUSE_FPS_RECORD=${PROOFREUSE_FPS_RECORD-}
# What the contract ties each check to: "check:ID" -> the files of the plans of
# the check's requirement (each entry a path, a folder ending in "/", or "*"),
# from the same pass over the record as the fingerprints (empty until one ran).
PROOFREUSE_TIES=${PROOFREUSE_TIES:-'{}'}
# The reuse planning's per-process caches: the diffs between every recorded tree and the
# committed code (valid for one store and one head), and the store itself.
PROOFREUSE_DIFFS=${PROOFREUSE_DIFFS-}
PROOFREUSE_DIFFS_HEAD=${PROOFREUSE_DIFFS_HEAD-}
PROOFREUSE_DIFFS_STORE=${PROOFREUSE_DIFFS_STORE-}

# Input: $keys (a JSON array of unit keys), $rec (the record), $have (the map so far). Output, per key without a fingerprint yet:
# key, kind (l: one line, z: NUL-ended fields), field count, fields, all NUL-ended.
# shellcheck disable=SC2016 # a jq program
PROOFREUSE_EMIT_JQ='def srt: if type == "object" then . as $o | reduce ($o | keys[]) as $k ({}; .[$k] = ($o[$k] | srt))
    elif type == "array" then map(srt) else . end;
  $keys[0] as $keys | $rec[0] as $r | ((($r.settings // {}).command_timeout // $d) | tostring) as $lim
  | $keys[] | select($have[0][.] == null) | . as $k
  | if startswith("check:") then
      ($k | ltrimstr("check:")) as $id | first($r.checks[]? | select(.id == $id)) as $c
      | $k, "\u0000", "l", "\u0000", "1", "\u0000", ($c | {id, req, run, exit, output, timeout, alone, files} | srt | tojson), "\u0000"
    elif startswith("command:") then
      ($k | ltrimstr("command:")) as $n | [$lim] + [$r.commands[$n][]?]
      | $k, "\u0000", "z", "\u0000", (length | tostring), "\u0000", (.[] | ., "\u0000")
    elif startswith("file:") then
      ($k | ltrimstr("file:")) as $f | [$lim] + [$r.test_files.run[]? | split("{file}") | join($f)]
      | $k, "\u0000", "z", "\u0000", (length | tostring), "\u0000", (.[] | ., "\u0000")
    else empty end'

# proofreuse_hashes DIR COUNT: the SHA-256 of the files 0 to COUNT-1 in DIR, one
# hex digest per line, from one sha256sum (or shasum) process.
proofreuse_hashes() {
  local names=() i out line
  [ "$2" -gt 0 ] || return 0
  for ((i = 0; i < $2; i++)); do names+=("$i"); done
  if command -v sha256sum > /dev/null 2>&1; then
    out=$(cd "$1" && sha256sum "${names[@]}") || return 1
  else
    out=$(cd "$1" && shasum -a 256 "${names[@]}") || return 1
  fi
  while IFS= read -r line; do printf '%s\n' "${line%% *}"; done <<< "$out"
}

# proofreuse_scratch: makes a scratch folder under the runtime folder and
# prints its path; the caller registers it with vbw_guard_add and drops it.
proofreuse_scratch() {
  mkdir -p "$VBW_RUNTIME" || vbw_die "cannot create $VBW_RUNTIME"
  mktemp -d "$VBW_RUNTIME/reuse.XXXXXX" || vbw_die "cannot create a temporary folder in $VBW_RUNTIME"
}

# proofreuse_ties RECORD: what the contract ties each check to, as a JSON object
# "check:ID" -> the files of the plans of the check's requirement (the entries as
# the plans list them: a path, a folder ending in "/", or "*"). A check judges
# what its requirement's plans deliver, so one of those files added or deleted
# runs it again whether or not its run read the file (the rule's tie clause).
proofreuse_ties() {
  printf '%s' "$1" | jq -c '. as $r | [(.checks // [])[] | {key: ("check:" + .id),
    value: (.req as $q | [$r.plans[]? | select(any(.reqs[]?; . == $q)) | .files[]? | strings] | unique)}] | from_entries'
}

# proofreuse_fps_need RECORD KEYS: makes sure PROOFREUSE_FPS has the fingerprint
# of each unit key in KEYS (a JSON array); call it in the current shell, not in a
# pipe, so the map stays. The missing ones are computed
# in one pass (one jq, one sha256 process, one jq) whatever their number. A
# record that differs from the one the map came from starts the map again, and
# sets PROOFREUSE_TIES from that record.
proofreuse_fps_need() {
  local dir n=0 key mode cnt i f fields=()
  if [ "$PROOFREUSE_FPS_RECORD" != "$1" ]; then
    PROOFREUSE_FPS='{}'
    PROOFREUSE_FPS_RECORD=$1
    PROOFREUSE_TIES=$(proofreuse_ties "$1")
  fi
  dir=$(proofreuse_scratch)
  vbw_guard_add dir "$dir"
  mkdir "$dir/u"
  : > "$dir/keys"
  while IFS= read -r -d '' key && IFS= read -r -d '' mode && IFS= read -r -d '' cnt; do
    fields=()
    for ((i = 0; i < cnt; i++)); do
      IFS= read -r -d '' f || true
      fields+=("$f")
    done
    if [ "$mode" = l ]; then printf '%s\n' "${fields[0]}" > "$dir/u/$n"; else printf '%s\0' ${fields[@]+"${fields[@]}"} > "$dir/u/$n"; fi
    printf '%s\0' "$key" >> "$dir/keys"
    n=$((n + 1))
  done < <(jq -n -j --argjson d "$VBW_COMMAND_TIMEOUT" --slurpfile rec <(printf '%s' "$1") --slurpfile have <(printf '%s' "$PROOFREUSE_FPS") --slurpfile keys <(printf '%s' "$2") "$PROOFREUSE_EMIT_JQ")
  if [ "$n" -gt 0 ]; then
    proofreuse_hashes "$dir/u" "$n" > "$dir/hashes" || { vbw_guard_drop "$dir"; vbw_die "cannot fingerprint the units"; }
    PROOFREUSE_FPS=$(jq -nc --slurpfile have <(printf '%s' "$PROOFREUSE_FPS") --rawfile k "$dir/keys" --rawfile h "$dir/hashes" \
      '$have[0] + ([($k | split("\u0000"))[:-1], ($h | split("\n"))[:-1]] | transpose | map({key: .[0], value: .[1]}) | from_entries)')
  fi
  vbw_guard_drop "$dir"
}

# proofreuse_fp_of RECORD KEY: the fingerprint of one unit (a one-unit front over
# the same pass).
proofreuse_fp_of() {
  proofreuse_fps_need "$1" "$(jq -nc --arg k "$2" '[$k]')"
  printf '%s' "$PROOFREUSE_FPS" | jq -r --arg k "$2" '.[$k] // empty'
}

# proofreuse_check_fp RECORD ID: fingerprint of a check's approved definition.
proofreuse_check_fp() { proofreuse_fp_of "$1" "check:$2"; }

# proofreuse_command_fp RECORD NAME: fingerprint of a project command's argv
# and the time limit it runs under (settings.command_timeout, else the default).
proofreuse_command_fp() { proofreuse_fp_of "$1" "command:$2"; }

# proofreuse_proved RECORD HEAD: succeed when nothing changed since the
# record's last passing proof (evidence.passed): the record is as that proof
# left it (its fingerprint without the evidence equals evidence.record, so the
# contract, the commands and every decision, verdict or backlog item are as
# proved: D296, D302), the project's files have the fingerprint it recorded
# (vbw_code_tree equals evidence.tree) and the committed code is the tree it
# ran on (HEAD, the committed code's tree, equals evidence.head, when the
# evidence carries one). Any change makes the next proof reuse what the read
# lists allow (R103). It reads trees and fingerprints only, never a commit
# subject, so a record commit landing after other commits changes nothing (R175).
proofreuse_proved() {
  local tree ev_head ev_rec
  printf '%s' "$1" | jq -e '.evidence.passed == true' > /dev/null 2>&1 || return 1
  ev_rec=$(printf '%s' "$1" | jq -r '.evidence.record // empty')
  [ -n "$ev_rec" ] && [ "$ev_rec" = "$(printf '%s' "$1" | jq -c 'del(.evidence)' | vbw_sha256)" ] || return 1
  tree=$(printf '%s' "$1" | jq -r '.evidence.tree // empty')
  [ -n "$tree" ] && [ "$(vbw_code_tree 2> /dev/null)" = "$tree" ] || return 1
  ev_head=$(printf '%s' "$1" | jq -r '.evidence.head // empty')
  [ -z "$ev_head" ] || [ "$ev_head" = "$2" ]
}

# proofreuse_allowed RECORD [KIND]: succeed when this proof may reuse anything;
# print why not otherwise (D173): not when the code is the code the last
# passing proof proved (proofreuse_proved): a second prove is a deliberate
# re-run, as when something outside the committed code (installed dependencies,
# ignored files) changed. KIND fix: that reason never applies (D270), a passing
# proof of the same code is exactly what vbw fix done needs. A proof cut short
# stops nothing: it saved no run, or runs as complete as any proof's.
proofreuse_allowed() {
  if [ "${2:-prove}" != fix ] && proofreuse_proved "$1" "$(vbw_head_tree 2> /dev/null)"; then
    printf 'proving again with nothing committed\n'
    return 1
  fi
}

# The store of recorded runs lives in the clone, never in the record (it
# changes on every run and would make the record's history noise):
# $(git common dir)/vbw/runs.json, {runs: {"check:ID" | "command:NAME" |
# "file:PATH": {fp, tree, status, at, seconds, tail, reads, dirs, git}}}.
# fp: fingerprint of the unit's approved definition; tree: the committed code
# it ran on; reads: the project files it opened (null: none was written down;
# empty for a run that read through git); dirs: the folders it listed; git: it
# read the project through git. The store holds runs and nothing else (a form
# field an older VBW wrote is dropped on reading). A missing or damaged store
# means nothing is reused.
proofreuse_store_file() {
  local common
  common=$(git -C "$VBW_ROOT" rev-parse --path-format=absolute --git-common-dir 2> /dev/null) || vbw_die "not a git repository"
  printf '%s/vbw/runs.json\n' "$common"
}

# proofreuse_store_read: the store, or an empty one when it is missing or damaged.
proofreuse_store_read() {
  jq -c 'if type == "object" and (.runs | type) == "object" then {runs} else error("shape") end' \
    "$(proofreuse_store_file)" 2> /dev/null || printf '{"runs":{}}\n'
}

# proofreuse_merge NEW [DROP]: the one writer of the store. NEW (a JSON object
# key -> run) is merged over the recorded runs, after the runs of DROP (a JSON
# array of keys: units that no longer exist) are taken out. A run that read the
# project through git keeps no read list (reads and dirs empty): it runs again
# whatever changed, so its list can never vouch for it, and git's walk of the
# whole project put every file on it (a 669 MB store of 1,048 runs, 2026-10-28);
# the lists an older VBW kept for such runs go at the next save. Beside the
# store goes run-times.json, {runs: {key: {seconds}}}: each run's seconds alone,
# which the time estimates read (lib/steps.sh, lib/road.sh), never the store.
# The read-modify-write runs under a lock beside the store and ends in atomic moves.
proofreuse_merge() {
  local file lock tmp times
  file=$(proofreuse_store_file)
  mkdir -p "${file%/*}" || vbw_die "cannot create ${file%/*}"
  lock="${file%.json}.lock"
  vbw_lock_take "$lock" "runs"
  tmp=$(mktemp "${file%/*}/runs.XXXXXX") || vbw_die "cannot create a temporary file in ${file%/*}"
  vbw_guard_add file "$tmp"
  times=$(mktemp "${file%/*}/run-times.XXXXXX") || vbw_die "cannot create a temporary file in ${file%/*}"
  vbw_guard_add file "$times"
  proofreuse_store_read | jq -c --slurpfile nw <(printf '%s' "$1") --slurpfile dr <(printf '%s' "${2:-[]}") \
    '{runs: ((.runs | del(.[$dr[0][]])) + $nw[0] | map_values(if type == "object" and .git == true then .reads = [] | .dirs = [] else . end))}' > "$tmp" \
    && jq -c '{runs: ([.runs | to_entries[] | select(.value | type == "object") | {key, value: {seconds: .value.seconds}}] | from_entries)}' "$tmp" > "$times" \
    && mv "$tmp" "$file" && mv "$times" "${file%/*}/run-times.json"
  vbw_guard_drop "$times"
  vbw_guard_drop "$tmp"
  vbw_guard_drop "$lock"
}

# proofreuse_stale RECORD FILES: the units of the store as this proof read it
# (PROOFREUSE_STORE) that no longer exist, as a JSON array of keys for the save
# to drop, so the store holds current units only. A unit exists while it is a
# check or a project command of the record, or a test file of FILES (the keys
# of the files the form matches now, a JSON array; a file an approved check
# runs is that check). The store is shared by the clone's worktrees, so a unit
# another worktree still has keeps its run: a check or command its record
# names (records that cannot be read keep them all), a test file present at
# that path in its folder. Nothing stale costs no git command; the other
# worktrees' records are read only for a stale check or command. A proof copy
# is no other worktree.
proofreuse_stale() {
  local cand line wt real here others=() recs=() kept=() k have='"none"'
  cand=$(jq -nc --slurpfile st <(printf '%s' "${PROOFREUSE_STORE-}") --slurpfile r <(printf '%s' "$1") --slurpfile f <(printf '%s' "$2") '
    ([($r[0].checks // [])[] | "check:" + .id] + [($r[0].commands // {}) | keys[] | "command:" + .] + $f[0]
     | map({key: ., value: true}) | from_entries) as $now
    | [($st[0].runs? // {}) | keys[] | select($now[.] | not)]') || { printf '[]\n'; return 0; }
  [ "$cand" != '[]' ] || { printf '[]\n'; return 0; }
  here=$(cd "$VBW_ROOT" && pwd -P) || here=$VBW_ROOT
  while IFS= read -r -d '' line; do
    case "$line" in "worktree "*) wt=${line#worktree } ;; *) continue ;; esac
    case "$wt" in */.vbw/runtime/proof.*) continue ;; esac
    real=$(cd "$wt" 2> /dev/null && pwd -P) || continue
    [ "$real" = "$here" ] || others+=("$real")
  done < <(git -C "$VBW_ROOT" worktree list --porcelain -z 2> /dev/null \
    || git -C "$VBW_ROOT" worktree list --porcelain 2> /dev/null | tr '\n' '\0')
  if [ ${#others[@]} -gt 0 ]; then
    while IFS= read -r -d '' k; do
      for wt in "${others[@]}"; do
        if [ -e "$wt/${k#file:}" ]; then kept+=("$k"); break; fi
      done
    done < <(printf '%s' "$cand" | jq -j '.[] | select(startswith("file:")) | . + "\u0000"')
    if printf '%s' "$cand" | jq -e 'any(.[]; startswith("file:") | not)' > /dev/null; then
      for wt in "${others[@]}"; do [ ! -f "$wt/.vbw/record.json" ] || recs+=("$wt/.vbw/record.json"); done
      if [ ${#recs[@]} -gt 0 ]; then
        have=$(jq -n -c '[inputs | ((.checks // [])[]? | "check:\(.id)"), ((.commands // {}) | keys[]? | "command:" + .)] | unique' "${recs[@]}" 2> /dev/null) || have='"all"'
      fi
    fi
  fi
  # have: "none" (no other record), "all" (one could not be read: keep every check and command), or their keys.
  printf '%s\0' ${kept[@]+"${kept[@]}"} | jq -Rs -c --slurpfile c <(printf '%s' "$cand") --slurpfile hv <(printf '%s' "$have") '
    (split("\u0000")[:-1] | map({key: ., value: true}) | from_entries) as $kept
    | ($hv[0] | if . == "none" then {} elif . == "all" then null else map({key: ., value: true}) | from_entries end) as $h
    | [$c[0][] | select(($kept[.] | not) and (if startswith("file:") then true elif $h == null then false else ($h[.] | not) end))]'
}

# proofreuse_save RECORD CHECKS COMMANDS TREE AT [DROP]: record the runs that
# really happened (CHECKS and COMMANDS: JSON objects name -> result, with the
# read list the runner collected) on the committed code TREE. A unit that was
# not run (skipped, waiting) leaves its earlier run alone. The runs of DROP (a
# JSON array of keys, proofreuse_stale) leave the store. The fingerprints come
# from the one pass (proofreuse_fps_need).
proofreuse_save() {
  local new
  proofreuse_fps_need "$1" "$(jq -nc --slurpfile c <(printf '%s' "$2") --slurpfile m <(printf '%s' "$3") \
    '[($c[0] | keys[] | "check:" + .), ($m[0] | keys[] | "command:" + .)]')"
  new=$(jq -nc --slurpfile c <(printf '%s' "$2") --slurpfile m <(printf '%s' "$3") --slurpfile f <(printf '%s' "$PROOFREUSE_FPS") \
    --arg tree "$4" --arg at "$5" '
    def runs($kind; $res): $res | keys[] as $n | $res[$n] as $x
      | select($x.status != "skipped" and $x.status != "waiting")
      | {key: "\($kind):\($n)", value: {fp: ($f[0]["\($kind):\($n)"] // ""), tree: $tree, status: $x.status, at: $at, seconds: $x.seconds,
          tail: ($x.tail // ""), reads: ($x.reads // null), dirs: ($x.dirs // []), git: ($x.git // false)}};
    [runs("check"; $c[0]), runs("command"; $m[0])] | from_entries')
  proofreuse_merge "$new" "${6:-[]}"
}

# proofreuse_annotate RECORD KIND RESULTS AT WHY: each result that really ran
# (KIND check, command or file; RESULTS a JSON object name -> result) carries the
# fingerprint of its approved definition, the time it ran and the reason it had
# to run (WHY: JSON object name -> reason). Prints the stamped results.
proofreuse_annotate() {
  proofreuse_fps_need "$1" "$(printf '%s' "$3" | jq -c --arg kind "$2" '[keys[] | $kind + ":" + .]')"
  printf '%s' "$3" | jq -c --arg kind "$2" --arg at "$4" --slurpfile f <(printf '%s' "$PROOFREUSE_FPS") --slurpfile w <(printf '%s' "$5") '
    with_entries(.key as $n | .value += ({fp: ($f[0][$kind + ":" + $n] // ""), at: $at}
      + (if $w[0][$n] and .value.status != "skipped" then {why: $w[0][$n]} else {} end)))'
}

# proofreuse_diffs HEAD: sets PROOFREUSE_DIFFS, a JSON object recorded tree ->
# the files that differ between that tree and the committed code HEAD
# ([{s: status letter, p: path}]), or null when the tree is unknown. One git
# diff-tree per distinct tree of PROOFREUSE_STORE. Cached for the same store
# and head, so planning and the proof's causes share it.
proofreuse_diffs() {
  local dir tree
  if [ -n "$PROOFREUSE_DIFFS" ] && [ "$PROOFREUSE_DIFFS_HEAD" = "$1" ] && [ "$PROOFREUSE_DIFFS_STORE" = "${PROOFREUSE_STORE-}" ]; then
    return 0
  fi
  dir=$(proofreuse_scratch)
  vbw_guard_add dir "$dir"
  : > "$dir/stream"
  # A submodule moved between the trees (vbw_head_tree counts it at its own HEAD)
  # makes the code that tree's runs ran on unknown: git lists only the submodule's
  # folder, never the files that changed inside it, so no read list can vouch.
  local subs=() p
  while IFS= read -r -d '' p; do subs+=("$p"); done < <(vbw_subs)
  # Per tree: the tree, the name-status pairs git printed, then =OK or =FAIL (a status is never "=").
  while IFS= read -r -d '' tree; do
    printf '%s\0' "$tree" >> "$dir/stream"
    if [ ${#subs[@]} -gt 0 ] && ! git -C "$VBW_ROOT" diff-tree -r -z --quiet "$tree" "$1" -- "${subs[@]}" 2> /dev/null; then
      printf '=FAIL\0' >> "$dir/stream"
    elif git -C "$VBW_ROOT" diff-tree -z -r --no-renames --name-status "$tree" "$1" >> "$dir/stream" 2> /dev/null; then
      printf '=OK\0' >> "$dir/stream"
    else
      printf '=FAIL\0' >> "$dir/stream"
    fi
  done < <(printf '%s' "${PROOFREUSE_STORE-}" | jq -j '[.runs[]? | select(type == "object") | .tree | select(type == "string")] | unique[] + "\u0000"')
  PROOFREUSE_DIFFS=$(jq -Rs -c 'split("\u0000") as $F
    | def endof($j): if (($F[$j] // "=") | startswith("=")) then $j else endof($j + 2) end;
      def sec($i): if ($F[$i] // "") == "" then empty
        else endof($i + 1) as $e
          | {key: $F[$i], value: (if $F[$e] == "=OK" then [range($i + 1; $e; 2) | {s: $F[.][0:1], p: $F[. + 1]}] else null end)}, sec($e + 1) end;
      reduce sec(0) as $x ({}; . + {($x.key): $x.value})' "$dir/stream")
  PROOFREUSE_DIFFS_HEAD=$1
  PROOFREUSE_DIFFS_STORE=${PROOFREUSE_STORE-}
  vbw_guard_drop "$dir"
}

# The one reuse rule over every unit at once. Input (all through --slurpfile):
# $keys (array of unit keys), $st (the store), $fps (key -> fingerprint), $df
# (the diffs of proofreuse_diffs), $tied (what the contract ties each check to,
# proofreuse_ties) and $off (a reason that stops all reuse, or ""). It runs
# after VBW_JQ_DEFS (covers: a plan's file entry against a path).
# Per unit, in order: the reason it must run ({key, why}) or its reused result
# ({key, result}); a unit that passed its other tests but whose diff adds or
# removes a file carries {pending: the listed folders with a fingerprint}, which
# the folders' fingerprints on the committed code settle.
# shellcheck disable=SC2016 # a jq program
PROOFREUSE_RULE_JQ='def parent: if test("/") then sub("/[^/]*$"; "") else "." end;
  $st[0].runs as $runs | $df[0] as $df | $fps[0] as $fps
  | def verdict($k):
      ($runs[$k] | if type == "object" then . else null end) as $e
      | if $off != "" then {key: $k, why: $off}
        elif $e == null then {key: $k, why: "never passed"}
        else
          (if $any != 1 and $e.status != "pass" then "last result failed"
           elif ($e.reads | type) != "array" then "no read list"
           elif $e.fp != $fps[$k] then "definition changed"
           elif $e.git == true then "reads the project through git"
           else null end) as $r1
          | if $r1 != null then {key: $k, why: $r1}
            else
              ($e | {status, exit: null, seconds, tail, at, fp, reads, dirs, git, reused: true}) as $res
              | ($df[($e.tree | tostring)]) as $ch
              | if $ch == null then {key: $k, why: "the code it ran on is unknown"}
                elif ($ch | length) == 0 then {key: $k, result: $res}
                else
                  ($e.reads | map({key: ., value: true}) | from_entries) as $reads
                  | [($e.dirs // [])[] | strings] as $plain
                  | ($tied[0][$k] // []) as $tie
                  | (([$ch[] | select($reads[.p]) | if .s == "D" then "\(.p) deleted" else "\(.p) changed" end]
                      + [$ch[] | select(.s == "A" or .s == "D") | (.p | parent) as $d | select($plain | index($d)) | "\($d) listing changed"]
                      + [$ch[] | select(.s == "A" or .s == "D") | select(.p as $p | any($tie[]; . == "*" or covers($p)))
                          | if .s == "D" then "\(.p) deleted" else "\(.p) added" end])
                     | first // null) as $r2
                  | if $r2 != null then {key: $k, why: $r2}
                    elif any($ch[]; .s == "A" or .s == "D") then
                      {key: $k, result: $res, pending: [($e.dirs // [])[] | objects | select(.fp != null) | {path, fp}]}
                    else {key: $k, result: $res} end
                end
            end
        end;
    [$keys[0][] | verdict(.)] as $units
    | {units: $units, need: ([$units[] | .pending[]? | .path] | unique)}'

# Input: the committed code's file list ($ls, NUL separated) and the folders to
# fingerprint ($need). Output, per folder: its path and the bytes whose SHA-256
# is the folder's fingerprint (the names directly inside it among the tracked
# files and folders, as [folder, sorted unique names] in compact JSON), NUL-ended.
# shellcheck disable=SC2016 # a jq program
PROOFREUSE_DIRS_JQ='($need[0] | map({key: ., value: true}) | from_entries) as $want
  | ($ls | split("\u0000") | map(select(length > 0))) as $f
  | (reduce $f[] as $p ({}; ($p | split("/")) as $parts
      | reduce range(0; $parts | length) as $i (.;
          (if $i == 0 then "." else ($parts[0:$i] | join("/")) end) as $a
          | if $want[$a] then .[$a] += [$parts[$i]] else . end))) as $names
  | $need[0][] | ., "\u0000", ([., (($names[.] // []) | unique)] | tojson), "\u0000"'

# shellcheck disable=SC2016 # a jq program
PROOFREUSE_SETTLE_JQ='$s[0].units | map(. as $u
    | (first($u.pending[]? | select($h[0][.path] != .fp) | "\(.path) listing changed") // null) as $w
    | if $w != null then {key: $u.key, why: $w} else del(.pending) end)'

# proofreuse_judge KEYS HEAD OFF [ANY]: the one reuse rule applied to the units KEYS
# (a JSON array of unit keys) against PROOFREUSE_STORE, PROOFREUSE_FPS and
# PROOFREUSE_TIES, on the committed code HEAD; OFF is a reason that stops all reuse
# (then neither git nor the store's diffs are consulted). Prints [{key, why} |
# {key, result}] in KEYS' order: why is what proofreuse_reason prints, result the
# stored run as a reused result (it keeps the time it really ran, and its read
# list for the next proof). ANY 1: a failed run is judged like a passing one (the
# rule's other clauses apply whatever the status), for a caller that wants the
# read list of a run, not its pass.
proofreuse_judge() {
  local dir diffs='{}' n=0 path bytes need
  if [ -z "$3" ] && [ -n "$2" ]; then
    proofreuse_diffs "$2"
    diffs=$PROOFREUSE_DIFFS
  fi
  dir=$(proofreuse_scratch)
  vbw_guard_add dir "$dir"
  jq -nc --slurpfile keys <(printf '%s' "$1") --slurpfile st <(printf '%s' "${PROOFREUSE_STORE-}") --slurpfile fps <(printf '%s' "$PROOFREUSE_FPS") \
    --slurpfile df <(printf '%s' "$diffs") --slurpfile tied <(printf '%s' "$PROOFREUSE_TIES") --arg off "$3" --argjson any "${4:-0}" \
    "$VBW_JQ_DEFS$PROOFREUSE_RULE_JQ" > "$dir/stage1" || { vbw_guard_drop "$dir"; vbw_die "internal error: the reuse rule failed"; }
  printf '{}' > "$dir/folders"
  need=$(jq -c '.need' "$dir/stage1")
  if [ "$need" != '[]' ]; then
    # A listed folder with a recorded fingerprint: its entries on the committed code must read the same.
    # Only an added or deleted file can change a listing, so nothing is computed for a content change.
    mkdir "$dir/u"
    : > "$dir/keys"
    git -C "$VBW_ROOT" ls-tree -r -z --name-only "$2" > "$dir/ls" 2> /dev/null || : > "$dir/ls"
    while IFS= read -r -d '' path && IFS= read -r -d '' bytes; do
      printf '%s' "$bytes" > "$dir/u/$n"
      printf '%s\0' "$path" >> "$dir/keys"
      n=$((n + 1))
    done < <(jq -n -j --slurpfile need <(printf '%s' "$need") --rawfile ls "$dir/ls" "$PROOFREUSE_DIRS_JQ")
    proofreuse_hashes "$dir/u" "$n" > "$dir/hashes" || { vbw_guard_drop "$dir"; vbw_die "cannot fingerprint the listed folders"; }
    jq -nc --rawfile k "$dir/keys" --rawfile h "$dir/hashes" \
      '[($k | split("\u0000"))[:-1], ($h | split("\n"))[:-1]] | transpose | map({key: .[0], value: .[1]}) | from_entries' > "$dir/folders"
  fi
  jq -c --slurpfile s "$dir/stage1" --slurpfile h "$dir/folders" -n "$PROOFREUSE_SETTLE_JQ"
  vbw_guard_drop "$dir"
}

# proofreuse_reason KEY FP HEAD [RECORD]: the one reuse rule for one unit (a front
# over proofreuse_judge). Succeeds, printing nothing, when the unit's pass may be
# reused: its last result passed, its definition fingerprint FP is unchanged, it
# has a read list and did not read through git, and one git diff-tree between
# the tree it ran on and the committed code HEAD shows no file of its read list
# changed or deleted, no listed folder whose listing changed (a file or
# sub-folder added or removed directly inside it; a folder recorded without a
# fingerprint is judged by the changed files' parents) and, for a check given its
# RECORD, no file of its requirement's plans added or deleted. Otherwise fails and
# prints the reason. Reads the store from PROOFREUSE_STORE (a JSON text).
proofreuse_reason() {
  local PROOFREUSE_FPS PROOFREUSE_TIES="$PROOFREUSE_TIES" verdict why
  PROOFREUSE_FPS=$(jq -nc --arg k "$1" --arg fp "$2" '{($k): $fp}')
  [ $# -lt 4 ] || PROOFREUSE_TIES=$(proofreuse_ties "$4")
  verdict=$(proofreuse_judge "$(jq -nc --arg k "$1" '[$k]')" "$3" "") || return 1
  why=$(printf '%s' "$verdict" | jq -r '.[0].why // empty')
  [ -z "$why" ] || { printf '%s\n' "$why"; return 1; }
}

# proofreuse_current KEY FP HEAD [RECORD]: like proofreuse_reason, but a run that
# failed is current too (the one reuse rule, whatever the status). Succeeds printing
# nothing when the stored run is current; else prints the reason and fails.
proofreuse_current() {
  local PROOFREUSE_FPS PROOFREUSE_TIES="$PROOFREUSE_TIES" verdict why
  PROOFREUSE_FPS=$(jq -nc --arg k "$1" --arg fp "$2" '{($k): $fp}')
  [ $# -lt 4 ] || PROOFREUSE_TIES=$(proofreuse_ties "$4")
  verdict=$(proofreuse_judge "$(jq -nc --arg k "$1" '[$k]')" "$3" "" 1) || return 1
  why=$(printf '%s' "$verdict" | jq -r '.[0].why // empty')
  [ -z "$why" ] || { printf '%s\n' "$why"; return 1; }
}

# proofreuse_names RECORD FULL: sets PROVE_NAMES (JSON array of the command
# names this proof covers) and QUICK_STANDIN (true when the approved quick
# command stands in for the test command). Full: every command but quick. Plain:
# an approved quick replaces test; a quick that is named but not approved is
# listed (and so reported skipped) and the test command runs (R111).
proofreuse_names() {
  local argv=() a
  # shellcheck disable=SC2034 # read by cmd_prove
  QUICK_STANDIN=false
  if [ "$2" = 1 ]; then
    PROVE_NAMES=$(printf '%s' "$1" | jq -c '.commands | keys - ["quick"]')
    return 0
  fi
  PROVE_NAMES=$(printf '%s' "$1" | jq -c '.commands | keys')
  printf '%s' "$1" | jq -e '.commands | has("quick") and has("test")' > /dev/null || return 0
  while IFS= read -r -d '' a; do argv+=("$a"); done \
    < <(printf '%s' "$1" | jq -j '.commands.quick[] + "\u0000"')
  if consent_has command "$(vbw_sha256_argv "${argv[@]}")"; then
    # shellcheck disable=SC2034 # read by cmd_prove
    QUICK_STANDIN=true
    PROVE_NAMES=$(printf '%s' "$PROVE_NAMES" | jq -c '. - ["test"]')
  fi
}

# proofreuse_unpack VERDICTS PREFIX: splits the verdicts of the units whose key
# starts with PREFIX ("check:", "command:" or "file:"), the prefix taken off:
# sets PU_REUSE (JSON object name -> reused result), PU_WHY (JSON object name ->
# the reason it runs), PU_TODO_JSON (JSON array of the names that run, in order)
# and PU_TODO (the same, a bash array).
proofreuse_unpack() {
  local n i name
  PU_TODO=()
  {
    IFS= read -r -d '' PU_REUSE
    IFS= read -r -d '' PU_WHY
    IFS= read -r -d '' PU_TODO_JSON
    IFS= read -r -d '' n
    for ((i = 0; i < n; i++)); do
      IFS= read -r -d '' name
      PU_TODO+=("$name")
    done
  } < <(printf '%s' "$1" | jq -j --arg p "$2" '
    map(select(.key | startswith($p)) | .key |= ltrimstr($p)) as $u
    | ($u | map(select(.result) | {key, value: .result}) | from_entries | tojson), "\u0000",
      ($u | map(select(.why) | {key, value: .why}) | from_entries | tojson), "\u0000",
      ($u | map(select(.why) | .key) | tojson), "\u0000",
      ($u | map(select(.why)) | length | tostring), "\u0000",
      ($u[] | select(.why) | .key, "\u0000")')
}

# proofreuse_plan RECORD [FULL]: FULL (1) only picks which commands belong to a
# full proof; the reuse rule is the same. Sets REUSE_CHECKS and REUSE_COMMANDS
# (the reused results, as JSON objects), TODO_CHECKS (array) and TODO_COMMANDS
# (JSON array of names), which are what has to run, and WHY_CHECKS and
# WHY_COMMANDS (JSON objects name -> the reason it has to run).
proofreuse_plan() {
  local record="$1" head='' off='' keys verdicts
  proofreuse_names "$record" "${2:-0}"
  REUSE_CHECKS='{}' REUSE_COMMANDS='{}' TODO_CHECKS=() TODO_COMMANDS='[]' WHY_CHECKS='{}' WHY_COMMANDS='{}'
  PROOFREUSE_STORE=$(proofreuse_store_read)
  off=$(proofreuse_allowed "$record") || true
  if [ -z "$off" ]; then
    head=$(vbw_head_tree) || head=
    [ -n "$head" ] || off='no committed code'
  fi
  keys=$(printf '%s' "$record" | jq -c --argjson names "$PROVE_NAMES" '[(.checks // [])[] | "check:" + .id] + ($names | map("command:" + .))')
  proofreuse_fps_need "$record" "$keys"
  verdicts=$(proofreuse_judge "$keys" "$head" "$off")
  proofreuse_unpack "$verdicts" "check:"
  # shellcheck disable=SC2034 # read by cmd_prove and cmd_fix
  REUSE_CHECKS=$PU_REUSE WHY_CHECKS=$PU_WHY
  # shellcheck disable=SC2034 # read by cmd_prove
  TODO_CHECKS=(${PU_TODO[@]+"${PU_TODO[@]}"})
  proofreuse_unpack "$verdicts" "command:"
  # shellcheck disable=SC2034 # read by cmd_prove
  REUSE_COMMANDS=$PU_REUSE WHY_COMMANDS=$PU_WHY TODO_COMMANDS=$PU_TODO_JSON
}

# proofreuse_join ORDER REUSED NEW: one object in ORDER (a JSON array of names).
proofreuse_join() {
  jq -nc --slurpfile o <(printf '%s' "$1") --slurpfile a <(printf '%s' "$2") --slurpfile b <(printf '%s' "$3") \
    '$a[0] as $a | $b[0] as $b | $o[0] | map({key: ., value: ($b[.] // $a[.])}) | from_entries'
}
