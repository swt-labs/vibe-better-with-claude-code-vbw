#!/usr/bin/env bash
# Test files as units of a proof (docs/proof.md, R167). With an approved
# single-file form (the spec's "## Test files": a run argv naming {file} once
# and git pathspecs) each test file is a unit of its own, run in a slot copy
# with its read list saved and reused by the one reuse rule of proofreuse.sh.
# The test command and the quick command then do not run (D179: no test file
# runs twice in one proof; a file an approved check runs runs only as that
# check). Without a form the test command runs whole.

# shellcheck source=proofreuse.sh
. "$VBW_LIB/proofreuse.sh"

# testfiles_on RECORD: succeed when the record carries a form. No file runs
# before checks_approved, which dies unless the contract, and so the form, is
# approved (vbw fix done plans before it, and asks only when a file will run).
testfiles_on() { printf '%s' "$1" | jq -e 'has("test_files")' > /dev/null; }

# testfiles_id PATH: the short name of a test file's unit (a file name cannot
# be one: the gate and the output folder take it as a file name).
testfiles_id() { printf 'tf-%s\n' "$(printf '%s' "$1" | vbw_sha256 | cut -c1-12)"; }

# testfiles_ids PATH...: the testfiles_id of each path, one per line in their
# order, from one hashing pass whatever their number: each path is written to a
# numbered file of a scratch folder in CHECK_OUT, and one command hashes them all.
testfiles_ids() {
  local d n=0 p
  [ $# -gt 0 ] || return 0
  d=$(mktemp -d "$CHECK_OUT/ids.XXXXXX") || vbw_die "cannot create a directory in $CHECK_OUT"
  for p in "$@"; do
    printf '%s' "$p" > "$d/$n"
    n=$((n + 1))
  done
  (
    cd "$d" || exit 1
    p=0
    while [ "$p" -lt "$n" ]; do printf '%s\0' "$p"; p=$((p + 1)); done \
      | if command -v sha256sum > /dev/null 2>&1; then xargs -0 sha256sum; else xargs -0 shasum -a 256; fi
  ) | awk '{ print "tf-" substr($1, 1, 12) }'
  rm -rf "$d"
}

# testfiles_ls PATHSPEC...: the committed files one form's pathspecs match, NUL
# separated, by their project paths. A submodule's files count only for the
# pathspecs that name it (start with its path and a /), matched inside it, and
# only for the submodules vbw_subs finds (one level, checked out): those the
# proof copy holds, at their own HEAD. So a pattern such as */tests/*.sh never
# picks up a vendored submodule's tests, and a submodule's pointer is no file. An
# exclude that names a submodule (:!, :^ or :(exclude)) is passed into it. A
# project without submodules lists as it did before them: one git, no filter.
testfiles_ls() {
  local specs=("$@") subs=() rel=() inc a s
  [ $# -gt 0 ] || return 0
  # vbw_subs finds none without .gitmodules, or a .git file (a copy may hold it in its index only).
  if [ -f "$VBW_ROOT/.gitmodules" ] || [ -f "$VBW_ROOT/.git" ]; then
    while IFS= read -r -d '' s; do subs+=("$s"); done < <(vbw_subs)
  fi
  if [ ${#subs[@]} -eq 0 ]; then
    git -C "$VBW_ROOT" ls-files -z -- "${specs[@]}"
    return
  fi
  git -C "$VBW_ROOT" ls-files -z -- "${specs[@]}" \
    | jq -Rj --argjson s "$(printf '%s\0' "${subs[@]}" | jq -Rsc 'split("\u0000")[:-1]')" \
      'split("\u0000")[:-1][] | select(. as $p | any($s[]; . == $p) | not) | . + "\u0000"'
  for s in "${subs[@]}"; do
    rel=() inc=''
    for a in "${specs[@]}"; do
      case "$a" in
        "$s"/*) rel+=(":(top)${a#"$s"/}") inc=1 ;;
        ":!$s"/* | ":^$s"/*) rel+=(":(top,exclude)${a#*"$s"/}") ;;
        ":(exclude)$s"/*) rel+=(":(top,exclude)${a#*"$s"/}") ;;
      esac
    done
    [ -n "$inc" ] || continue
    git -C "$VBW_ROOT/$s" ls-files -z -- "${rel[@]}" \
      | jq -Rj --arg s "$s" 'split("\u0000")[:-1][] | $s + "/" + . + "\u0000"'
  done
}

# testfiles_owned RECORD: the committed files each form's pathspecs match, as a
# JSON array of {p, i} (the project path and the form's index in tf_forms), in
# form order and git's order within a form. A file two forms match is listed twice.
# RECORD may also be a parsed spec (vbw spec check and sync refuse such a file).
testfiles_owned() {
  local n i=0 specs a
  n=$(printf '%s' "$1" | jq "$VBW_JQ_DEFS"'tf_forms | length')
  while [ "$i" -lt "$n" ]; do
    specs=()
    while IFS= read -r -d '' a; do specs+=("$a"); done < <(printf '%s' "$1" | jq -j --argjson i "$i" "$VBW_JQ_DEFS"'tf_forms[$i].files[] + "\u0000"')
    testfiles_ls ${specs[@]+"${specs[@]}"} | jq -Rsc --argjson i "$i" 'split("\u0000")[:-1] | map({p: ., i: $i})'
    i=$((i + 1))
  done | jq -sc 'add // []'
}

# testfiles_index RECORD: TF_INDEX, the test files of the proof as JSON:
# owned [{p, i}] (each file once, by the first form that matches it, minus every
# file the run of an approved check names), dups [{p, forms}] (files two forms
# match, which fail the test command: a file never runs twice, nor is it dropped,
# silently), match [N per form] (the files each form matches before the approved
# checks' files are taken out, R169) and map {p: i} (for the fingerprints,
# PROOFREUSE_TFMAP). TF_PATHS, the owned paths in order.
testfiles_index() {
  local p
  TF_INDEX=$(testfiles_owned "$1" | jq -c --slurpfile r <(printf '%s' "$1") "$VBW_JQ_DEFS"'
    ($r[0] | tf_forms) as $fs | [$r[0].checks[].run[]] as $run | . as $all
    | (reduce $all[] as $x ({seen: {}, out: []}; if .seen[$x.p] then . else .seen[$x.p] = true | .out += [$x] end) | .out) as $one
    | {owned: [$one[] | select(.p as $p | any($run[]; . == $p) | not)],
       dups: [$all | group_by(.p)[] | select(length > 1) | {p: .[0].p, forms: map($fs[.i].name // "unnamed")}],
       match: [range(0; $fs | length) as $i | [$all[] | select(.i == $i)] | length]}
    | .map = ([.owned[] | {key: .p, value: .i}] | from_entries)')
  # shellcheck disable=SC2034 # read by proofreuse_fps_need
  PROOFREUSE_TFMAP=$(printf '%s' "$TF_INDEX" | jq -c '.map')
  TF_PATHS=()
  while IFS= read -r -d '' p; do TF_PATHS+=("$p"); done < <(printf '%s' "$TF_INDEX" | jq -j '.owned[].p + "\u0000"')
}

# testfiles_fp RECORD PATH: fingerprint of a test file's approved definition
# (a one-unit front over the batch of proofreuse_fps_need).
testfiles_fp() { proofreuse_fp_of "$1" "file:$2"; }

# testfiles_keys: the unit keys of the paths in TF_PATHS, as a JSON array.
testfiles_keys() {
  if [ ${#TF_PATHS[@]} -eq 0 ]; then printf '[]\n'; return 0; fi
  printf '%s\0' "${TF_PATHS[@]}" | jq -Rsc 'split("\u0000")[:-1] | map("file:" + .)'
}

# testfiles_plan RECORD ALL [KIND]: after proofreuse_plan. With a form, takes the test
# and quick commands out of the proof and sets TF_PATHS (the test files, an
# array), TF_REUSE (reused results, JSON path -> result), TF_TODO (array of
# the paths that run) and TF_WHY (JSON path -> why it runs). ALL (1): nothing
# is reused. KIND (third argument) is "fix" for vbw fix done, which the proof's
# "nothing committed" cause does not apply to. Without a form all of them are empty.
# The files' fingerprints come from one pass and the reuse rule runs over all of them at once.
testfiles_plan() {
  local record="$1" off='' head='' keys verdicts p
  TF_PATHS=() TF_TODO=() TF_REUSE='{}' TF_WHY='{}'
  TF_INDEX='{"owned": [], "dups": [], "match": [], "map": {}}'
  testfiles_on "$record" || return 0
  PROVE_NAMES=$(printf '%s' "$PROVE_NAMES" | jq -c '. - ["test", "quick"]')
  TODO_COMMANDS=$(printf '%s' "$TODO_COMMANDS" | jq -c '. - ["test", "quick"]')
  REUSE_COMMANDS=$(printf '%s' "$REUSE_COMMANDS" | jq -c 'del(.test, .quick)')
  WHY_COMMANDS=$(printf '%s' "$WHY_COMMANDS" | jq -c 'del(.test, .quick)')
  # shellcheck disable=SC2034 # read by cmd_prove
  QUICK_STANDIN=false
  testfiles_index "$record"
  [ ${#TF_PATHS[@]} -gt 0 ] || return 0
  keys=$(testfiles_keys)
  proofreuse_fps_need "$record" "$keys"
  if [ "$2" = 1 ]; then
    TF_TODO=("${TF_PATHS[@]}")
    return 0
  fi
  off=$(proofreuse_allowed "$record" "${3:-prove}") || true
  if [ -z "$off" ]; then
    head=$(vbw_head_tree) || head=
    [ -n "$head" ] || off='no committed code'
  fi
  verdicts=$(proofreuse_judge "$keys" "$head" "$off")
  proofreuse_unpack "$verdicts" "file:"
  TF_REUSE=$PU_REUSE TF_WHY=$PU_WHY
  TF_TODO=(${PU_TODO[@]+"${PU_TODO[@]}"})
  # A clone with no recorded run has nothing to compare with: no line gives a reason of its own.
  if printf '%s' "$PROOFREUSE_STORE" | jq -e '(.runs | length) == 0' > /dev/null; then TF_WHY='{}'; fi
}

# testfiles_run RECORD: run the test files in TF_TODO, each as a unit of its
# own (several at a time, in slot copies); {path: result}, each result with
# "id" (its output file's name) and its read list. The units' names come from
# one hashing pass (testfiles_ids), the units from one jq pass over the record:
# the argv of the file's form (TF_INDEX) with {file} replaced by the file's path
# relative to the form's dir, the dir the unit runs in, and the command timeout
# (the seconds a test file may take, as a project command).
testfiles_run() {
  local ids res
  [ ${#TF_TODO[@]} -gt 0 ] || { printf '{}\n'; return 0; }
  ids=$(testfiles_ids "${TF_TODO[@]}")
  res=$(checks_run_units "$(printf '%s' "$1" | jq -c --argjson d "$VBW_COMMAND_TIMEOUT" --slurpfile x <(printf '%s' "$TF_INDEX") \
    --rawfile p <(printf '%s\0' "${TF_TODO[@]}") --rawfile n <(printf '%s' "$ids") "$VBW_JQ_DEFS"'
    (.settings.command_timeout // $d) as $t | tf_forms as $fs
    | ($p | split("\u0000")[:-1]) as $ps | ($n | split("\n")) as $ns
    | [range(0; $ps | length) as $k | $ns[$k] as $id | $fs[$x[0].map[$ps[$k]] // 0] as $f
       | (if $f.dir == null then $ps[$k] else $ps[$k] | ltrimstr($f.dir + "/") end) as $rel
       | {name: $id, out: "\($id).out", argv: [$f.run[] | split("{file}") | join($rel)], timeout: $t, exit: 0, output: "", alone: false}
         + (if $f.dir == null then {} else {dir: $f.dir} end)]')")
  printf '%s' "$res" | jq -c --rawfile p <(printf '%s\0' "${TF_TODO[@]}") --rawfile n <(printf '%s' "$ids") '. as $r
    | ($p | split("\u0000")[:-1]) as $ps | ($n | split("\n")) as $ns
    | [range(0; $ps | length) as $k | {key: $ps[$k], value: ($r[$ns[$k]] + {id: $ns[$k]})}] | from_entries'
}

# testfiles_save RECORD FILES TREE AT: record the runs that really happened in
# the store (read list included, and the test file itself: a changed test file
# always runs). Through proofreuse_merge, under the store's lock. The
# fingerprints come from the one pass (proofreuse_fps_need).
testfiles_save() {
  local new
  proofreuse_fps_need "$1" "$(printf '%s' "$2" | jq -c 'keys | map("file:" + .)')"
  new=$(jq -nc --slurpfile r <(printf '%s' "$2") --slurpfile f <(printf '%s' "$PROOFREUSE_FPS") --arg tree "$3" --arg at "$4" '
    [$r[0] | keys[] as $p | .[$p] as $x
     | select($x.status != "skipped" and $x.status != "waiting")
     | {key: ("file:" + $p), value: {fp: ($f[0]["file:" + $p] // ""), tree: $tree, status: $x.status, at: $at, seconds: $x.seconds, tail: ($x.tail // ""),
         reads: (if $x.reads == null then null else ($x.reads + [$p] | unique) end), kernel_reads: ($x.kernel_reads // []), dirs: ($x.dirs // []), git: ($x.git // false)}}]
    | from_entries')
  proofreuse_merge "$new"
}

# testfiles_finish RECORD RESULTS AT: the results of the test files for the
# evidence, in the files' order: the new ones stamped with their definition's
# fingerprint, the time and the reason they ran, joined with the reused ones.
# With named forms each result names its form.
testfiles_finish() {
  local out order
  out=$(proofreuse_annotate "$1" file "$2" "$3" "$TF_WHY")
  # No test file left to run gives an empty order: printf with no argument would print one NUL.
  if [ ${#TF_PATHS[@]} -eq 0 ]; then order='[]'
  else order=$(printf '%s\0' "${TF_PATHS[@]}" | jq -Rsc 'split("\u0000")[:-1]'); fi
  proofreuse_join "$order" "$TF_REUSE" "$out" \
    | jq -c --slurpfile x <(printf '%s' "$TF_INDEX") --slurpfile r <(printf '%s' "$1") "$VBW_JQ_DEFS"'($r[0] | tf_forms) as $fs
      | with_entries(.key as $p | .value |= (del(.reads, .kernel_reads, .dirs, .git, .id) | if .reused and .status == "pass" then .exit = 0 else . end
          | ($fs[$x[0].map[$p] // 0].name) as $n | if $n == null then . else . + {form: $n} end))'
}

# testfiles_command RECORD RESULTS: the test command's place in the evidence when the
# test files ran in its stead: one result, passing when every test file passed
# (reused when every one was), so a failing test file fails the proof, opens a
# fix for the test command and QA sees the suite's state. It fails, naming them,
# when a form's pathspecs match no committed file (R169) or a file is matched by
# two forms (TF_INDEX). With no test file left to run otherwise: a pass that says
# every matching file runs as an approved check. With named forms the command
# names each form's run.
testfiles_command() {
  printf '%s' "$2" | jq -c --slurpfile x <(printf '%s' "$TF_INDEX") --slurpfile rec <(printf '%s' "$1") "$VBW_JQ_DEFS"'
    ($rec[0] | tf_forms) as $fs | $x[0] as $ix
    | ((if ($fs | length) == 1 and $fs[0].name == null then $fs[0].run | join(" ")
        else [$fs[] | "\(.name): \(.run | join(" "))"] | join("; ") end) + " (one test file per run)") as $cmd
    | ([range(0; $fs | length) as $i | select(($ix.match[$i] // 0) == 0) | $fs[$i]
        | if .name == null then "the test-file form matches no tracked file (\(.files | join(" "))): add the test files, or change the form in .vbw/spec.md"
          else "test file form \(.name) matches no tracked file (\(.files | join(" "))): add its test files, or change the form in .vbw/spec.md" end]
       + [$ix.dups[] | "\(.p) is matched by forms \(.forms | join(" and ")): a test file belongs to one form; change the forms in .vbw/spec.md"]) as $wrong
    | [.[]] as $r | [$r[] | select(.status != "pass")] as $bad
    | if ($wrong | length) > 0 then
        {status: "fail", exit: 1, seconds: ([$r[].seconds // 0] | add // 0 | . * 10 | round / 10),
         tail: ($wrong + [to_entries[] | select(.value.status != "pass") | "\(.key) \(.value.status)"] | join("\n")), command: $cmd, of_files: true}
      elif ($r | length) == 0 then
        {status: "pass", exit: 0, seconds: 0, tail: "every file the form matches runs as an approved check; nothing is left to run as a test file", command: $cmd, of_files: true}
      else
        {status: (if ($bad | length) == 0 then "pass" elif all($bad[]; .status == "timeout") then "timeout" else "fail" end),
         exit: (if ($bad | length) == 0 then 0 else null end), seconds: ([$r[].seconds // 0] | add // 0 | . * 10 | round / 10),
         tail: ([to_entries[] | select(.value.status != "pass") | "\(.key) \(.value.status)"] | join("\n")),
         command: $cmd, of_files: true}
        + (if all($r[]; .reused) then {reused: true, at: ([$r[].at] | max)} else {} end)
      end'
}
