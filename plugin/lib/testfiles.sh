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

# testfiles_list RECORD: the test files, NUL separated: the committed files the
# declared pathspecs match, minus every file the run of an approved check names.
# A submodule's files count, by their project paths (--recurse-submodules: the
# pathspecs are matched as the project's, inside each submodule): the proof copy
# holds each submodule at its own HEAD (docs/workflows.md, "Submodules").
testfiles_list() {
  local specs=() a
  while IFS= read -r -d '' a; do specs+=("$a"); done < <(printf '%s' "$1" | jq -j '.test_files.files[] + "\u0000"')
  [ ${#specs[@]} -gt 0 ] || return 0
  git -C "$VBW_ROOT" ls-files -z --recurse-submodules -- ${specs[@]+"${specs[@]}"} \
    | jq -Rs -j --slurpfile r <(printf '%s' "$1") '[$r[0].checks[].run[]] as $run
        | split("\u0000")[] | . as $p | select(length > 0 and (any($run[]; . == $p) | not)) | . + "\u0000"'
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
  testfiles_on "$record" || return 0
  PROVE_NAMES=$(printf '%s' "$PROVE_NAMES" | jq -c '. - ["test", "quick"]')
  TODO_COMMANDS=$(printf '%s' "$TODO_COMMANDS" | jq -c '. - ["test", "quick"]')
  REUSE_COMMANDS=$(printf '%s' "$REUSE_COMMANDS" | jq -c 'del(.test, .quick)')
  WHY_COMMANDS=$(printf '%s' "$WHY_COMMANDS" | jq -c 'del(.test, .quick)')
  # shellcheck disable=SC2034 # read by cmd_prove
  QUICK_STANDIN=false
  while IFS= read -r -d '' p; do TF_PATHS+=("$p"); done < <(testfiles_list "$record")
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
# the form's argv with {file} replaced, and the command timeout (the seconds a
# test file may take, as a project command).
testfiles_run() {
  local ids res
  [ ${#TF_TODO[@]} -gt 0 ] || { printf '{}\n'; return 0; }
  ids=$(testfiles_ids "${TF_TODO[@]}")
  res=$(checks_run_units "$(printf '%s' "$1" | jq -c --argjson d "$VBW_COMMAND_TIMEOUT" \
    --rawfile p <(printf '%s\0' "${TF_TODO[@]}") --rawfile n <(printf '%s' "$ids") '
    (.settings.command_timeout // $d) as $t | .test_files.run as $run
    | ($p | split("\u0000")[:-1]) as $ps | ($n | split("\n")) as $ns
    | [range(0; $ps | length) as $k | $ns[$k] as $id
       | {name: $id, out: "\($id).out", argv: [$run[] | split("{file}") | join($ps[$k])], timeout: $t, exit: 0, output: "", alone: false}]')")
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
         reads: (if $x.reads == null then null else ($x.reads + [$p] | unique) end), dirs: ($x.dirs // []), git: ($x.git // false)}}]
    | from_entries')
  proofreuse_merge "$new"
}

# testfiles_finish RECORD RESULTS AT: the results of the test files for the
# evidence, in the files' order: the new ones stamped with their definition's
# fingerprint, the time and the reason they ran, joined with the reused ones.
testfiles_finish() {
  local out order
  out=$(proofreuse_annotate "$1" file "$2" "$3" "$TF_WHY")
  # No test file left to run gives an empty order: printf with no argument would print one NUL.
  if [ ${#TF_PATHS[@]} -eq 0 ]; then order='[]'
  else order=$(printf '%s\0' "${TF_PATHS[@]}" | jq -Rsc 'split("\u0000")[:-1]'); fi
  proofreuse_join "$order" "$TF_REUSE" "$out" \
    | jq -c 'map_values(del(.reads, .dirs, .git, .id) | if .reused and .status == "pass" then .exit = 0 else . end)'
}

# testfiles_matches RECORD: how many committed files the form's pathspecs match,
# before the files an approved check runs are taken out (a submodule's included,
# as testfiles_list counts them).
testfiles_matches() {
  local specs=() a
  while IFS= read -r -d '' a; do specs+=("$a"); done < <(printf '%s' "$1" | jq -j '.test_files.files[] + "\u0000"')
  [ ${#specs[@]} -gt 0 ] || { printf '0\n'; return 0; }
  git -C "$VBW_ROOT" ls-files -z --recurse-submodules -- ${specs[@]+"${specs[@]}"} | tr -cd '\000' | wc -c | tr -d ' '
}

# testfiles_command RECORD RESULTS: the test command's place in the evidence when the
# test files ran in its stead: one result, passing when every test file passed
# (reused when every one was), so a failing test file fails the proof, opens a
# fix for the test command and QA sees the suite's state. With no test file left
# to run (R169): a pass that says every matching file runs as an approved check,
# or, when the pathspecs match no committed file, a failure that names them.
testfiles_command() {
  printf '%s' "$2" | jq -c --arg run "$(printf '%s' "$1" | jq -r '.test_files.run | join(" ")')" \
    --argjson matches "$(testfiles_matches "$1")" --arg specs "$(printf '%s' "$1" | jq -r '.test_files.files | join(" ")')" '
    [.[]] as $r | [$r[] | select(.status != "pass")] as $bad
    | if ($r | length) == 0 then
        (if $matches > 0 then {status: "pass", exit: 0, seconds: 0, tail: "every file the form matches runs as an approved check; nothing is left to run as a test file"}
         else {status: "fail", exit: 1, seconds: 0, tail: "the test-file form matches no tracked file (\($specs)): add the test files, or change the form in .vbw/spec.md"} end)
        + {command: ($run + " (one test file per run)"), of_files: true}
      else
        {status: (if ($bad | length) == 0 then "pass" elif all($bad[]; .status == "timeout") then "timeout" else "fail" end),
         exit: (if ($bad | length) == 0 then 0 else null end), seconds: ([$r[].seconds // 0] | add // 0 | . * 10 | round / 10),
         tail: ([to_entries[] | select(.value.status != "pass") | "\(.key) \(.value.status)"] | join("\n")),
         command: ($run + " (one test file per run)"), of_files: true}
        + (if all($r[]; .reused) then {reused: true, at: ([$r[].at] | max)} else {} end)
      end'
}
