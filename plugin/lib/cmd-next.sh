#!/usr/bin/env bash
# vbw next [--json]: the next lifecycle step (docs/next.md), from the record,
# the approval state of its contract, and whether the code changed since proof.

# shellcheck source=interview.sh
. "$VBW_LIB/interview.sh"
# shellcheck source=qa-inputs.sh
. "$VBW_LIB/qa-inputs.sh"
# shellcheck source=effort.sh
. "$VBW_LIB/effort.sh"
# shellcheck source=cmd-approve.sh
. "$VBW_LIB/cmd-approve.sh"
# shellcheck source=steps.sh
. "$VBW_LIB/steps.sh"
# shellcheck source=sessions.sh
. "$VBW_LIB/sessions.sh"

# next_holder RECORD: the display name of the lease's session, empty without a lease session.
next_holder() {
  local sid
  sid=$(printf '%s' "$1" | jq -r '.lease.session // empty')
  [ -z "$sid" ] || holder_display "$sid"
}

# qa_state RECORD [DIGESTS]: lib/qa.jq's answer (closure, recheck, standing, interleaved, problems).
# The one judgment of whether a pass stands; a pass of another fingerprint
# version is first fingerprinted again at its own commit (qa_settle).
qa_state() {
  local d="${2:-}"
  [ -n "$d" ] || d=$(qa_digests "$1")
  qa_settle "$1" "$d"
  printf '%s' "$1" | jq -c --slurpfile in <(printf '%s' "$d") --slurpfile ch <(qa_cache_read) --argjson fpv "$QA_FP_VERSION" "$VBW_JQ_DEFS"'$in[0] as $inputs | $ch[0] as $cache | '"$(cat "$VBW_LIB/qa.jq")"
}

# qa_deviations RECORD: lib/qa.jq's deviations alone ({Pn: [{file, plan, change, commit, by,
# decision}]}): the proof's evidence and the decisions decide them, so no digest is computed.
qa_deviations() {
  printf '%s' "$1" | jq -c --argjson inputs null --argjson cache null "$VBW_JQ_DEFS$(cat "$VBW_LIB/qa.jq")" | jq -c '.deviations'
}

# qa_combined RECORD [DIGESTS]: {Pn: the phase's current fingerprint}: what a
# standing pass holds in qa.tree (D91). A pass that stands across a fingerprint
# version is held by the qa.tree it has.
qa_combined() {
  local d="${2:-}"
  [ -n "$d" ] || d=$(qa_digests "$1")
  qa_state "$1" "$d" | jq -c --slurpfile dg <(printf '%s' "$d") --slurpfile rc <(printf '%s' "$1") '$dg[0] as $d | $rc[0] as $r | . as $s | $d | map_values(.combined)
    + ([$r.phases[] | select(.id as $i | $s.standing | index($i)) | select(.qa.tree != null) | {(.id): .qa.tree}] | add // {})'
}

# The one pass over the record (R249): everything vbw next and vbw status read from
# a record of any size, worked out in one jq run, so a large record is parsed once
# (besides the schema probe of record_read). Four lines of output, each one line:
#   1. the contract core (VBW_CONTRACT_DEFS), which the shell hashes;
#   2. the core of the contract without the checks a fix added, when it has any
#      (empty otherwise: the shape is then the core's own);
#   3. {files, next_phase}: the check files, and the next free phase number (R106:
#      one after the highest phase number the record knows: phase and plan ids, plan
#      phases and the P-numbers decisions name; P65.1 counts as 65; letters before the
#      P do not);
#   5. the record's slim form (record_slim): the checks and the small facts the shell
#      judges from (commands, settings, the lease's run and session, the evidence's tree
#      and head, the interview, the project's legacy and results), so no part of the
#      answer parses the record again for one of them;
#   6. and 7. QA's listing of the phases of the active milestone as a JSON array of lines
#      (lib/qa-inputs.sh qa_listing), without and, when the project has results folders, with them;
#   8. QA's closure of the phases (lib/qa.jq without digests);
#   9. the passed phases qa_settle reads (qa_settle_in);
#   4. the working record: the record without the bodies of its finished history, a
#      record of a size that does not grow with the project's past. What is left out
#      is what no part of vbw next or vbw status reads: the goal and criteria of the
#      phases of a shipped milestone, the tasks of a done plan of such a phase, and the
#      text and reason of a decision, except the decisions made at or after the first
#      delivered file the last proof found changed outside any plan (lib/qa.jq names a
#      file in those). Anything that reads more reads the record itself.
# shellcheck disable=SC2016
VBW_NEXT_PASS='def next_phase_number: ([(.phases[].id), (.plans[] | .id, .phase), (.decisions[]?.text // empty), ((.parked // [])[].ids[]?)]
    | map(strings | [scan("(?<![A-Za-z0-9])P([0-9]+)") | .[0] | tonumber] | .[]) | max // 0 | . + 1);
def record_slim:
  ([.plans[] | select(.status == "done" and ((.awaits // []) | length) > 0) | {id, status, awaits}]) as $awaiting
  | (.evidence.checks // {}) as $ec
  | {checks, commands, settings, milestone,
     project: {name: .project.name, interview: .project.interview, legacy: .project.legacy, results: .project.results},
     lease: (if .lease == null then null else {run: .lease.run, session: .lease.session} end),
     evidence: {tree: .evidence.tree, head: .evidence.head,
                checks: ([$awaiting[].awaits[]] | unique | map({key: ., value: {status: ($ec[.].status // null)}}) | from_entries)},
     shipped: [(.shipped // [])[] | {id, title}], parked: [(.parked // [])[] | {id, reason}],
     requirements: [.requirements[] | {id, milestone, status} + (if .queued then {queued: true} else {} end)],
     phases: [.phases[] | {id, milestone}], fixes: [.fixes[] | {status}], todos: [.todos[] | {status}],
     plans: $awaiting, recommendation: (.recommendation // null)}
  + (if has("test_files") then {test_files} else {} end) + (if has("converted") then {converted: true} else {} end);
def record_work:
  ((.shipped // []) | map(.id)) as $old
  | ([.phases[] | select(.milestone as $m | $old | index($m)) | .id]) as $old_phases
  | ((.evidence.deviations // []) as $dv | if ($dv | length) == 0 then null
      elif any($dv[]; (.at | type) != "string") then "" else ([$dv[].at] | min) end) as $from
  | .phases |= map(if (.milestone as $m | $old | index($m)) then del(.goal, .criteria) else . end)
  | .plans |= map(if .status == "done" and (.phase as $p | $old_phases | index($p)) then del(.tasks) else . end)
  | .decisions |= map(if $from != null and ((.at // "") >= $from) then . else del(.text, .why) end);
. as $r
| ($r | contract_core | canon | tojson),
  (if any($r.checks[]; has("fix")) then ($r | without_fix | contract_core | canon | tojson) else "" end),
  ({files: ($r | contract_files), next_phase: ($r | next_phase_number)} | tojson),
  ($r | record_work | tojson),
  ($r | record_slim | tojson),
  ([$r | qa_listing(null)] | tojson),
  (if ($r.project.results // []) != [] then [$r | qa_listing($r.project.results)] | tojson else "" end),
  ($r | qa_prog(null; null) | .closure | tojson),
  ($r | qa_settle_in | tojson)'

# next_prepare: read the record and make everything vbw next and vbw status judge
# from, in one pass (VBW_NEXT_PASS). Sets, in the caller's shell: NP_RECORD (the
# record), NP_WORK (its working record: what every part of the answer reads in its
# place), NP_NEXT_PHASE, NP_FILES (the check files, a JSON array) and NP_PASS (the
# pass's output file, removed when the command ends; the contract's hash and shape
# are worked out from it by next_decide, only when an answer is judged). Exits like
# record_read when the record cannot be read.
next_prepare() {
  vbw_require_project
  local facts
  NP_RECORD=$(record_read) || return $?
  mkdir -p "$VBW_RUNTIME"
  NP_PASS=$(mktemp "$VBW_RUNTIME/pass.XXXXXX") || vbw_die "cannot create a temporary file in $VBW_RUNTIME"
  vbw_guard_add file "$NP_PASS"
  printf '%s' "$NP_RECORD" | jq -r --argjson fpv "$QA_FP_VERSION" "$VBW_JQ_DEFS$VBW_QA_DEFS$VBW_CONTRACT_DEFS$VBW_NEXT_PASS" > "$NP_PASS" || vbw_die "record is corrupt: the contract cannot be read ($VBW_RECORD)" 3
  facts=$(sed -n 3p "$NP_PASS")
  NP_NEXT_PHASE=$(printf '%s' "$facts" | jq -r '.next_phase')
  NP_FILES=$(printf '%s' "$facts" | jq -c '.files')
  NP_WORK=$(sed -n 4p "$NP_PASS")
  NP_SLIM=$(sed -n 5p "$NP_PASS")
  NP_LISTING=$(sed -n 6p "$NP_PASS")
  NP_LISTING_RES=$(sed -n 7p "$NP_PASS")
  NP_CLOSURE=$(sed -n 8p "$NP_PASS")
  NP_SETTLE=$(sed -n 9p "$NP_PASS")
}

# next_answer: vbw next's answer without the step and the road (lib/next.jq), on
# stdout; it writes nothing. The one place the answer is judged, so the command,
# vbw status and the road (lib/road.sh) read the same one.
next_answer() {
  local rc=0
  next_prepare || return $?
  next_decide | jq -c '.next' || rc=$?
  # The pass's file is this call's own: a caller may run it in a subshell, whose
  # guard list dies with it, so it is removed here, not left to the command's end.
  vbw_guard_drop "$NP_PASS"
  return $rc
}

# next_road_input: next_decide's answer for the road, {} when it cannot be judged
# (step_road_status, after next_prepare).
next_road_input() {
  { next_decide 2> /dev/null | jq -c '.next'; } 2> /dev/null || echo '{}'
}

# next_decide: the answer next_prepare's record gives (see next_answer). Everything it
# judges besides the answer itself comes from the pass: the slim record, QA's listing and
# closure and the passed phases; the answer and QA's judgment of the phases (lib/qa.jq, lib/next.jq)
# are worked out in one run over the working record.
next_decide() {
  local core shape="" effort record slim hash counts approved=false changed=false legacy=false next qa waiting profile problems="" holder prev=/dev/null adoc=/dev/null
  local QA_PRE_LISTING QA_PRE_CLOSURE QA_PRE_SETTLE out digests cache wok=0
  record=$NP_WORK slim=$NP_SLIM
  # The contract's hash, and its shape while the hash is not approved, from the pass's core lines.
  core=$(sed -n 1p "$NP_PASS")
  hash=$(contract_hash_from "$core" "$NP_FILES")
  if ! contract_approved "$hash"; then
    shape=$(sed -n 2p "$NP_PASS")
    shape=$(printf '%s\n' "${shape:-$core}" | vbw_sha256)
  fi
  # Check files edited since the approval wait: the build goes on, the one approval comes before proof.
  if waiting=$(contract_waiting_with "$slim" "$hash" "$shape"); then
    wok=1
    commands_approved "$slim" && approved=true
  fi
  # An unapproved contract that approval would refuse is not offered for approval (R171).
  [ "$approved" = true ] || problems=$(approve_problems "$record")
  next_code_changed "$slim" && changed=true
  # A VBW 1 plan not yet converted (docs/convert.md).
  [ -d "$VBW_ROOT/.vbw-planning" ] && ! printf '%s' "$slim" | jq -e 'has("converted") or .project.legacy.choice == "fresh"' > /dev/null && legacy=true
  # Tracked files, and of those the code: outside .vbw/ and not documentation (is_doc).
  counts=$(git -C "$VBW_ROOT" ls-files -z 2> /dev/null | jq -Rs "$VBW_JQ_DEFS"'[split("\u0000")[] | select(length > 0)]
    | {tracked: length, code: ([.[] | select((startswith(".vbw/") or is_doc) | not)] | length)}')
  # The profile's effort table; a wrong table stops here, before any answer.
  effort=$(effort_table "$(printf '%s' "$slim" | jq -r '.settings.profile')" "$(printf '%s' "$slim" | jq -c '.settings.efforts // null')") || exit 1
  profile=$(interview_effective "$slim")
  holder=$(next_holder "$slim")
  # What each pass covered: the digests of the phases (the saved results folders count only while the contract naming them is approved), the passes
  # a VBW update settles, and this clone's cache; lib/qa.jq judges them below.
  # shellcheck disable=SC2034  # read by qa_digests and qa_settle
  if [ "$wok" = 1 ] && [ -n "$NP_LISTING_RES" ]; then QA_PRE_LISTING=$(printf '%s' "$NP_LISTING_RES" | jq -r '.[]'); else QA_PRE_LISTING=$(printf '%s' "$NP_LISTING" | jq -r '.[]'); fi
  # shellcheck disable=SC2034  # read by qa_digests and qa_settle
  QA_PRE_CLOSURE=$NP_CLOSURE QA_PRE_SETTLE=$NP_SETTLE
  digests=$(qa_digests "$record")
  qa_settle "$record" "$digests"
  cache=$(qa_cache_read)
  # The last answer (a gate's since) and, while not approved, the last approved contract (a re-approval).
  [ -f "$VBW_RUNTIME/next.json" ] && prev="$VBW_RUNTIME/next.json"
  [ "$approved" = true ] || [ ! -f "$VBW_RUNTIME/approved-contract.json" ] || adoc="$VBW_RUNTIME/approved-contract.json"
  local note="${NP_NOTE:-}" hist runs
  [ -n "$note" ] || note=null
  hist=$(step_history_file)
  runs=""
  [ -z "$hist" ] || runs="$(dirname "$hist")/run-times.json"
  out=$(printf '%s' "$record" | jq -c --rawfile prev "$prev" --slurpfile approved_doc "$adoc" --argjson effort "$effort" --argjson tracked "$counts" --argjson approved "$approved" --arg waiting "$waiting" --arg problems "$problems" --arg contract "$hash" \
    --argjson code_changed "$changed" --argjson legacy "$legacy" --slurpfile in <(printf '%s' "$digests") --slurpfile ch <(printf '%s' "$cache") --argjson fpv "$QA_FP_VERSION" --argjson profile "$profile" --arg session "$(vbw_session)" --arg holder "$holder" --argjson next_phase "$NP_NEXT_PHASE" --slurpfile tiers "$VBW_LIB/tiers.json" \
    --argjson want_step "${NP_WANT_STEP:-0}" --argjson want_road "${NP_WANT_ROAD:-0}" --slurpfile note <(printf '%s' "$note") \
    --slurpfile h <(jq -c 'select(type == "object" and (.steps | type) == "array")' "$hist" 2> /dev/null) \
    --slurpfile runs <(jq -c 'select(type == "object" and (.runs | type) == "object")' "$runs" 2> /dev/null) \
    "$VBW_JQ_DEFS$VBW_QA_DEFS$VBW_STEP_DEFS$VBW_STEP_SIZE_DEFS$(road_expect_defs)"'. as $work | [qa_prog($in[0]; $ch[0])] as $qa
    | def next_prog:
'"$(cat "$VBW_LIB/next.jq")"'
;
    (try next_prog catch {error: tostring}) as $n
    | (($n | has("error")) | not) as $ok
    | ($note[0] // {}) as $nn
    # The running build counts a plan done during the step as the run started it (R191.36, D438).
    | [$work | if $nn.kind == "build" then .plans |= map(if .status == "done" and (.id as $i | any($nn.ids[]?; . == $i)) then .status = "building" else . end) else . end] as $rec
    | [$n] as $next
    | def road_prog:
'"$(cat "$VBW_LIB/road.jq")"'
;
    {next: $n, qa: $qa[0],
       size: (if $want_step == 1 and $ok then
                (($n.action) as $a
                 | (if $a == "build" then ["build", $n.detail.plans] elif $a == "fix" then ["fix", $n.detail.fixes]
                    elif $a == "qa" then ["qa", $n.detail.phases] elif $a == "plan" then ["plan", []] else null end) as $ks
                 | if $ks == null then null else ($work | try step_size_prog($ks[0]; $ks[1]) catch null) end)
              else null end),
       road: (if $want_road == 1 and $ok then (try (null | road_prog) catch null) else null end)}')
  qa=$(printf '%s' "$out" | jq -c '.qa')
  # A plan that names a plan or phase that is not there cannot be judged.
  printf '%s' "$qa" | jq -e '.problems | any(.[]; contains("does not exist")) | not' > /dev/null || vbw_die "$(printf '%s' "$qa" | jq -r '.problems | join("; ")')"
  printf '%s' "$out" | jq -e '.next | has("error") | not' > /dev/null || vbw_die "$(printf '%s' "$out" | jq -r '.next.error')"
  printf '%s' "$out" | jq -c '{next, size, road}'
}

# The jq program of the stack packs (docs/packs.md): a pattern without a slash matches a file's
# basename, one with a slash the whole path; * matches within one path segment. $mf is the
# manifests, $r the working record, $tracked the tracked files (NUL separated, read only at the
# plan action), $pr the plugin folder. A project with no match gets neither packs nor packs_root.
NEXT_PACKS_JQ='def rx: split("*") | map(gsub("(?<c>[^A-Za-z0-9_])"; "\\\(.c)")) | join("[^/]*") | "^" + . + "$";
  def packs_of($files): [$mf[] | select(.patterns as $ps | any($files[]; . as $f | ($f | split("/") | last) as $b | any($ps[]; . as $p | (if contains("/") then $f else $b end) | test($p | rx)))) | .name];
  ([$r[0].plans[]? | {id, phase, p: packs_of(.files // [])} | select(.p | length > 0)]) as $pl
  | (if .action == "plan" then packs_of($tracked | split("\u0000") | map(select(. != ""))) else [] end) as $tp
  | {plans: ($pl | map({(.id): .p}) | add // {}),
     phases: ($pl | group_by(.phase) | map({(.[0].phase): ([.[].p[]] | unique)}) | add // {}),
     project: (([$pl[].p[]] + $tp) | unique)} as $k
  | if ($k.project | length) == 0 then . else . + {packs: ($k | with_entries(select(.value | length > 0))), packs_root: ($pr + "/packs")} end'

# next_tracked NEXT: the project's tracked files (git ls-files -z) at the plan action, where no
# plan exists yet for the Lead's pack; nothing otherwise. The answer's text is a cheap
# prefilter: the jq program checks the action itself.
next_tracked() {
  case $1 in *'"action":"plan"'*) git -C "$VBW_ROOT" ls-files -z 2> /dev/null || : ;; esac
}

# next_with_root NEXT: the command's --json answer: NEXT with the project folder (vbw root) and,
# for a project with a match, the packs of its plans, phases and files. One jq call whether or not
# a pack folder exists; a pack file is read only for its manifest.
next_with_root() {
  local f manifests=()
  for f in "$VBW_PLUGIN"/packs/*/pack.json; do
    [ ! -f "$f" ] || manifests+=("$f")
  done
  if [ "${#manifests[@]}" -eq 0 ]; then
    printf '%s\n' "$1" | jq -c --arg root "$VBW_ROOT" '. + {root: $root}'
    return
  fi
  printf '%s\n' "$1" | jq -c --arg root "$VBW_ROOT" --arg pr "$VBW_PLUGIN" --slurpfile mf <(cat "${manifests[@]}") --slurpfile r <(printf '%s' "$NP_WORK") --rawfile tracked <(next_tracked "$1") \
    ". + {root: \$root} | $NEXT_PACKS_JQ"
}

cmd_next() {
  vbw_require_project
  local next record step road hint replan out main=0
  [ "${FUNCNAME[1]:-main}" != main ] || main=1
  next_prepare || exit $?
  # Only the command asks for the step and the road (below): their size and sums are worked
  # out in the same run that judges the answer, from the live step's note.
  if [ "$main" = 1 ]; then
    NP_NOTE=$(step_live_note "$(printf '%s' "$NP_SLIM" | jq -r '.lease.run // ""')")
    NP_WANT_STEP=1 NP_WANT_ROAD=1
  fi
  out=$(next_decide) || exit $?
  next=$(printf '%s' "$out" | jq -c '.next')
  # The step to run, with its end time and the sentence to say (R190, D425), and the
  # road, the end of the milestone (R191, D438). Only the command asks for them: a
  # caller inside the kernel (the Stop hook's gate, ship, the loop) never pays for
  # the proof's reuse plan and keeps the road of the previous answer, so the
  # status line and Mission Control keep the last vbw next's road.
  if [ "$main" = 1 ]; then
    # The working record stands for the record in all of it; a proof's reuse plan reads the record itself.
    record=$NP_WORK
    # shellcheck disable=SC2034  # read by step_next
    NP_STEP_SIZE=$(printf '%s' "$out" | jq -c '.size | select(. != null)')
    step=$(step_next "$record" "$next" "$NP_RECORD")
    road=$(printf '%s' "$out" | jq -c '.road')
    next=$(printf '%s' "$next" | jq -c --argjson step "$step" --argjson road "${road:-null}" '. + {step: $step, road: $road}')
    # What a yes to a suggestion that adds a requirement costs at the approval (R229).
    if [ "$(printf '%s' "$next" | jq -r '.action')" = approve ]; then
      replan=$(step_replan_say "$record")
      next=$(printf '%s' "$next" | jq -c --arg r "$replan" '.detail.replan = $r')
    fi
    # The /rename hint (D444): once per clone, only for the command.
    hint=$(sessions_rename_hint "$(vbw_session)" "$VBW_ROOT" "$(basename "$VBW_ROOT")")
    next=$(printf '%s' "$next" | jq -c --arg hint "$hint" '. + {rename_hint: (if $hint == "" then null else $hint end)}')
  else
    road=$(jq -c '.road // empty' "$VBW_RUNTIME/next.json" 2> /dev/null) || road=
    [ -z "$road" ] || next=$(printf '%s' "$next" | jq -c --argjson road "$road" '. + {road: $road}')
    # A caller inside the kernel does not tell the router's amendments: the kept answer holds the ones already told (R250, D586).
    next=$(printf '%s' "$next" | jq -c --slurpfile p <(cat "$VBW_RUNTIME/next.json" 2> /dev/null || true) '.amendments = [] | .amendments_seen = (($p[0] // {}).amendments_seen // [])')
  fi
  # The status line shows the last answer (docs/statusline.md).
  printf '%s\n' "$next" > "$VBW_RUNTIME/next.json.$$" && mv "$VBW_RUNTIME/next.json.$$" "$VBW_RUNTIME/next.json"
  if [ "${1:-}" = "--json" ]; then
    # The project folder (vbw root), for the workflows' args: agents of a session started in a
    # subfolder work there. Only in the command's answer: the kept one, and what a caller inside
    # the kernel builds from it (the loop's step note), hold no path, so a copy of the project
    # never points back at it.
    if [ "${FUNCNAME[1]:-main}" = main ]; then
      next_with_root "$next"
    else
      printf '%s\n' "$next"
    fi
  else
    printf '%s\n' "$next" | jq -r '"\(.action)\(if .gate then " (needs you)" else "" end): \(.instruction)"'
  fi
}

# True when the project's files differ from the ones the last proof saw: the
# working folder (vbw_code_tree: content, so committing VBW's record never
# makes evidence stale) or the committed code the checks ran on (head: an edit
# proved while uncommitted and committed later was never proved). No evidence
# counts as no change: the evidence is already stale for lack of a proof.
next_code_changed() {
  local proved head now
  proved=$(printf '%s' "$1" | jq -r '.evidence.tree // empty')
  [ -n "$proved" ] || return 1
  now=$(vbw_code_tree) || return 0
  [ "$now" = "$proved" ] || return 0
  head=$(printf '%s' "$1" | jq -r '.evidence.head // empty')
  [ -n "$head" ] || return 1
  now=$(vbw_head_tree) || return 0
  [ "$now" != "$head" ]
}
