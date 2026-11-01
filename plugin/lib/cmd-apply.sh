#!/usr/bin/env bash
# vbw apply < PLAN_JSON: the Lead's one write (docs/workflows.md). Replaces
# the current milestone's phases, plans and checks in a single validated update:
#   {"phases": [{id, title, reqs, goal?, criteria?, tier?}],   (the Architect's)
#    "plans":  [{id, phase, title, reqs, files, after, tasks?, role?}],   (the Lead's)
#    "checks": [{id, req, run, files?, exit?, output?, timeout?, alone?}],
#    "rules":  [{req, text, check, plan?}]}   (optional, the Lead's: R31)
# A check may carry "alone": true (a boolean): it never runs beside another VBW check (R45).
# "rules" are the conditions, edges and error cases an [auto] requirement
# states, each with the check that tests it. When present, apply refuses a rule
# whose check is not in the plan or belongs to another requirement, a rule for a
# [human] requirement, and any unproven [auto] requirement of the plan's phases
# that lists no rules (earlier rules count). Without the key nothing changes.
# The phases and plans are the current milestone's; "checks" are the checks of
# its requirements. Earlier milestones' phases, plans and checks are kept (their
# checks keep guarding shipped work). Re-planning mid-milestone is allowed: a
# plan that has started must come back unchanged and keeps its status; every
# other plan is "planned". Refused while a build or fix run is open.
# Every phase gets its rigor tier here: the floor comes from rigor.sh; the
# Architect's optional tier may only raise it (a lower one is refused) and is
# kept as the phase's proposed tier (config rigor auto restores it), and
# settings.rigor forced to a tier overrides both. A phase that already existed
# keeps escalations, outcome and its qa verdict. A phase that has started (a plan
# not planned, or an escalation) or finished keeps its tier, reasons and predicted
# tier on every re-plan, forced rigor included (R159): the floor, the forced tier and
# the one-plan rule for express judge only the phases that have not started. A new
# phase may cover a requirement a started phase covers (R157).
# vbw apply --patch < DOC: only plans, checks and rules, merged by id (R80).
# A rule's address is Rn.k, its place among requirement Rn's rules (T168). A patch's
# rule may name one instead of req and text: {rule, text?, check?, plan?} rewords it
# (the fields given replace the rule's), {rule, retire: REASON} retires it. Any
# requirement's rule can be reached, a shipped milestone's too. A retired rule stays
# in its place with "retired": REASON, so no other address moves; it is owed no
# mutation break and judged by nothing, and every later apply keeps it where it is.
# vbw apply --add < DOC: new phases with their plans, checks and rules (R116),
# appended to the milestone; a phase id it already has, a requirement any
# phase covers (in any milestone) or that belongs to another milestone, or a
# plan or check id in use is refused and nothing changes. The full apply refuses
# what --add refuses about other milestones (a requirement another milestone owns,
# or one a phase of another milestone covers), through the one shared rule
# (foreign_reqs), before every other rule; its own milestone's phases are replaced.
# Every existing item stays as it was and keeps the tier it was accepted at:
# the rigor floor and the one-plan-per-express rule judge only the phases the
# doc brings (their signals see the whole milestone); every other rule above
# holds for the merged whole.

# Every mode takes an optional "test_files" (R167): the Lead's proposal of how the project's test
# runners run one test file. Either one form {run, files, dir?}, or an array of named forms
# {name, run, files, dir?} (#735), one per runner: run an argv naming {file} exactly once, files
# git pathspecs without spaces, dir the folder the form's runs start in ({file} is then the path
# relative to it, and every pathspec lies under it). A bad one is refused before anything changes:
# the section it becomes is parsed as the spec's own (docs/proof.md), and a committed file two
# forms match is refused. A good one is written as the spec's "## Test files" section, replacing
# an older one, and the spec is synced; the user approves the forms with the contract, and VBW
# never runs one that is not approved.

# shellcheck source=rigor.sh
. "$VBW_LIB/rigor.sh"
# shellcheck source=cmd-spec.sh
. "$VBW_LIB/cmd-spec.sh"
# shellcheck source=cmd-approve.sh
. "$VBW_LIB/cmd-approve.sh"

# foreign_reqs: the refusals --add and the full apply share. Only phases of other
# milestones count as covering (a new phase may cover a requirement of this
# milestone again: R157). $scope is "add" (--add: a requirement of this milestone
# that another milestone's phase covers is refused too) or "others" (the full apply).
FOREIGN_REQS_JQ='def foreign_reqs($r; $m; $p; $scope; $mode):
    [$p.phases[] | (.reqs | arrays)[]] as $reqs
    | [($reqs[] | . as $q | ([$r.phases[] | select(.milestone != $m) | select(any(.reqs[]; . == $q))][0]) | select(. != null)
         | select($scope == "add" or ([$r.requirements[] | select(.id == $q and .milestone == $m)] | length) == 0)
         | "\($q) is already covered by \(.id) (milestone \(.milestone)): \($mode) takes requirements that have no phase yet"),
       ($reqs[] | . as $q | ([$r.requirements[] | select(.id == $q and .milestone != $m)][0]) | select(. != null)
         | "\($q) belongs to milestone \(.milestone): \($mode) takes requirements of this milestone")];
'

# The rules' jq helpers (T168). rule_edit($ops; $a): the rule at address $a as the
# patch's address entries leave it. place($old; $live): a requirement's new rules,
# each retired rule of $old in its place and $live, the live rules, in the other
# places in order, then the rest of $live after them.
RULES_JQ='def rule_edit($ops; $a): ([$ops[] | select(.rule == $a)][0]) as $o
    | if $o == null then . elif $o | has("retire") then . + {retired: $o.retire} else . + ($o | del(.rule)) end;
  def place($old; $live): reduce $old[] as $x ({out: [], live: $live};
      if $x | has("retired") then .out += [$x] elif (.live | length) > 0 then .out += [.live[0]] | .live |= .[1:] else . end)
    | .out + .live;
'

# apply_refuse MESSAGE: every refusal names the mode it came from (R156).
# apply_next MESSAGE: the one next step of the kind of refusal MESSAGE is. Messages of the
# record's own validation (an unknown requirement, a duplicate id, ...) take the last arm.
apply_next() {
  case "$1" in
    *"is not an amendment"* | *"must be an array of objects"* | *"would lose "* | *"protected check file: a plan"*) echo "send that change with vbw apply --patch, then the user approves it; --amend takes only files added to a plan or a check and the checks a plan awaits" ;;
    "the contract is not approved"*) echo "send the change with vbw apply --patch, then the user approves it (vbw show contract)" ;;
    "a patch carries plans"*) echo "remove \"phases\" from the document, or send it to a full apply (vbw apply) to change phases" ;;
    "--add needs"*) echo "send --add a JSON object whose \"phases\" array holds the new phases, with their plans, checks and rules" ;;
    "test_files must be"*) echo "give test_files as {\"run\": [argv naming {file} once], \"files\": [git pathspecs]}, or as [{\"name\": \"webapp\", \"dir\": \"apps/webapp\", \"run\": [...], \"files\": [...]}] with one form per test runner, or leave it out" ;;
    "test_files: "*) echo "change test_files as the message says (docs/proof.md, Test files), or leave it out" ;;
    "no .vbw/spec.md"*) echo "restore .vbw/spec.md (git checkout -- .vbw/spec.md), then send the document again" ;;
    "apply needs a JSON object"*) echo "pipe one JSON object into vbw apply: {\"phases\": [], \"plans\": [], \"checks\": []}" ;;
    "apply needs phases"*) echo "give phases, plans and checks as arrays, and rules as [{req, text, check, plan?}] if present" ;;
    "a rule address ("*) echo "send the reword or retire as a patch of its own: vbw apply --patch with {\"rules\": [{\"rule\": \"Rn.k\", ...}]}" ;;
    "a rule address takes"*) echo "give {\"rule\": \"Rn.k\", \"text\": \"the new words\"} (check and plan may change too) to reword a rule, or {\"rule\": \"Rn.k\", \"retire\": \"why\"} to retire it" ;;
    *" has no rule "*) echo "name a rule by its place among its requirement's rules: vbw show req Rn lists them as Rn.k" ;;
    *"rules name a plan: name one"*) echo "name a plan on every rule of the requirement, or on none (vbw apply --patch rewords a rule: {\"rule\": \"Rn.k\", \"plan\": \"P1.1\"})" ;;
    *" is owned by two plans that build "*) echo "give each plan's rules a check of their own (a separate test file, or the same file with a case filter as a distinct check), or move the rules to one plan" ;;
    *" with a case filter ("*" that matches no case name"*)
      local file=${1#* runs }
      echo "write the cases the filter names into ${file%% with a case filter*} (each @test name matching the pattern), see them fail with the runner, then send the document again; or correct the pattern" ;;
    *"a retired rule stays as it is"*) echo "leave the retired rule as it is; add a new rule with {req, text, check} for the behaviour that stands now" ;;
    *"a patch changes each rule once"*) echo "keep one entry per rule address in the patch" ;;
    *"is already a phase"*) echo "give the new phase an unused id, or change the existing phase with a full apply" ;;
    *"is already a plan"* | *"is already a check"*) echo "give it an unused id, or change the existing one with vbw apply --patch" ;;
    *"whose work has not started"*) echo "change that phase with a full apply (vbw apply); add a phase beside it only once its work has started" ;;
    *"is already covered by"* | *"belongs to milestone"*) echo "take that requirement out of the phases in the document; plan only requirements of this milestone that have no phase yet" ;;
    *"not a phase this --add brings"*) echo "set the plan's phase to one of the phases of this --add, or send the plan with vbw apply --patch" ;;
    *"not a requirement of the phases this --add brings"*) echo "set its req to a requirement of the new phases, or send it with vbw apply --patch" ;;
    *"has an unknown field"*) echo "remove that field from the document; the allowed fields are in docs/workflows.md" ;;
    *"the tier must be"*) echo "set the phase's tier to express, standard or deep, or leave it out" ;;
    *" run is open"*) echo "end the open run (vbw run end), then plan again" ;;
    *"a plan that has started must stay"*) echo "put the plan back as the record has it (vbw show plan ID), and add a new plan for any further work" ;;
    *"its goal and criteria stay"*) echo "keep the phase's goal and criteria as they are, and add a new phase for the further work (vbw apply --add)" ;;
    *"has work started: its title"* | *"has work started: its requirements"*) echo "keep the phase as it is; add a new phase for the further work (vbw apply --add)" ;;
    *"a [human] requirement"*) echo "remove that rule: only [auto] requirements list rules" ;;
    *"which is not a check of"*) echo "name a check of that requirement in the rule, or add the check to the plan's checks" ;;
    *"lists no rules"*) echo "add one rule per condition, edge and error case to \"rules\", each with the check that tests it" ;;
    *"the Architect may only raise a tier"*) echo "raise the phase's tier to its floor or higher, or leave the tier out" ;;
    *"is express: one plan"*) echo "merge the phase's plans into one, or raise the phase's tier to standard" ;;
    *) echo "fix what the message names in the document, then run vbw apply again (vbw doctor checks the record)" ;;
  esac
}

# apply_empty_filter DOCFILE: for each check of the document that runs bats with a case filter
# (R220; env and timeout wrappers skipped), a refusal message when the pattern, an unanchored
# extended regular expression, matches no @test name of the .bats files the argv names, as they
# stand in the project folder. The kernel reads the files; it never runs the runner.
apply_empty_filter() {
  jq -r '(.checks // [])[]? | select(type == "object") | . as $c | (.run // []) | select(type == "array" and all(.[]; type == "string")) as $a
    | ({i: 0} | until(.i >= ($a | length) or ($a[.i] | IN("env", "timeout") | not);
        if $a[.i] == "env" then .i += 1 | until(.i >= ($a | length) or ($a[.i] | test("^[A-Za-z_][A-Za-z0-9_]*=|^-") | not); .i += 1)
        else .i += 1 | until(.i >= ($a | length) or ($a[.i] | test("^-|^[0-9.]+[smhd]?$") | not); .i += 1) end) | .i) as $s
    | select($s < ($a | length) and ($a[$s] | split("/") | last) == "bats")
    | (reduce $a[$s + 1:][] as $w ({skip: null, pat: null, f: false, words: []};
        if .skip != null then (if .skip == "pat" then .pat = $w else . end) | .skip = null
        elif $w == "--filter" or $w == "-f" then .skip = "pat" | .f = true
        elif ($w | startswith("--filter=")) then .pat = ($w | ltrimstr("--filter=")) | .f = true
        elif $w | IN("-j", "--jobs", "--filter-tags", "--filter-status", "--formatter", "-F", "--report-formatter", "--output", "--gather-test-outputs-in", "--setup-suite-file") then .skip = "x"
        elif ($w | startswith("-")) then .
        else .words += [$w] end))
    | select(.f and (.pat | type) == "string" and (.words | length) > 0)
    | ([$c.id, .pat] + .words) | join("\u001f")' "$1" 2> /dev/null \
    | while IFS=$'\037' read -r id pat words; do
      local w f names='' shown='' sep='' list wl
      IFS=$'\037' read -r -a wl <<< "$words"
      for w in ${wl[@]+"${wl[@]}"}; do
        list=()
        if [ -d "$VBW_ROOT/$w" ]; then
          for f in "$VBW_ROOT/$w"/*.bats; do
            if [ -f "$f" ]; then list+=("${f#"$VBW_ROOT"/}"); fi
          done
        else
          list+=("$w")
        fi
        for f in ${list[@]+"${list[@]}"}; do
          if [ -f "$VBW_ROOT/$f" ]; then
            shown="$shown$sep$f"
            names=$names$'\n'$(sed -n -E -e 's/^[[:space:]]*@test[[:space:]]+"(.*)"[[:space:]]*\{.*$/\1/p' -e "s/^[[:space:]]*@test[[:space:]]+'(.*)'[[:space:]]*\{.*\$/\\1/p" "$VBW_ROOT/$f")
          else
            shown="$shown$sep$f (missing)"
          fi
          sep=', '
        done
      done
      [ -n "$shown" ] || continue
      if ! grep -q -E -e "$pat" 2> /dev/null <<< "$names"; then
        printf '%s\n' "$id runs $shown with a case filter (--filter '$pat') that matches no case name in the file: the Lead writes the failing cases at planning, so a new check is red because its cases fail, never because none exist"
      fi
    done
}

# apply_refuse MESSAGE: every refusal names the mode it came from (R156) and ends with its next step (R162).
apply_refuse() { vbw_die "$MODE_NAME refused: $1"$'\n'"Next: $(apply_next "$1")"; }

# apply_internal MESSAGE: an internal failure; its next step is the same for every kind.
apply_internal() { vbw_die "internal error: $1"$'\n'"Next: run vbw doctor, then send the document again; report it if it fails again"; }

# apply_test_files_spec FORM: APPLY_TF_SPEC, a scratch copy of the spec whose "## Test files"
# section is FORM (replacing an older one, wherever it stands), refused unless it parses and no
# committed file is matched by two forms. A run line is plain words when they parse back to the
# same argv, else a JSON array.
apply_test_files_spec() {
  local spec="$VBW_DIR/spec.md" parsed hit
  mkdir -p "$VBW_RUNTIME" || apply_internal "cannot create $VBW_RUNTIME"
  APPLY_TF_SPEC=$(mktemp "$VBW_RUNTIME/spec.XXXXXX") || apply_internal "cannot create a temporary file in $VBW_RUNTIME"
  vbw_guard_add file "$APPLY_TF_SPEC"
  awk 'BEGIN { skip = 0 }
    /^#{1,2}[ \t]/ { skip = (tolower($0) ~ /^##[ \t]+test files[ \t\r]*$/) }
    !skip { print }' "$spec" > "$APPLY_TF_SPEC"
  [ ! -s "$APPLY_TF_SPEC" ] || [ -z "$(tail -c 1 "$APPLY_TF_SPEC")" ] || printf '\n' >> "$APPLY_TF_SPEC"
  printf '%s' "$1" | jq -r 'def runline: if all(.[]; test("\\s") | not) and (.[0] | startswith("[") | not) then join(" ") else tojson end;
    "\n## Test files\n",
    (if type == "object" then (if .dir == null then empty else "- dir: \(.dir)" end), "- run: \(.run | runline)", "- files: \(.files | join(" "))"
     else .[] | "- \(.name):", (if .dir == null then empty else "  - dir: \(.dir)" end), "  - run: \(.run | runline)", "  - files: \(.files | join(" "))" end)' >> "$APPLY_TF_SPEC"
  parsed=$(jq -Rs -f "$VBW_LIB/spec.jq" < "$APPLY_TF_SPEC") || apply_internal "cannot read the test-file form back"
  printf '%s' "$parsed" | jq -e '.errors == []' > /dev/null \
    || apply_refuse "test_files: $(printf '%s' "$parsed" | jq -r '.errors[0] | sub("^line [0-9]+: "; "")')"
  hit=$(spec_test_files_overlap "$parsed")
  [ -z "$hit" ] || apply_refuse "test_files: ${hit#*$'\t'}"
}

# apply_write_test_files: the spec becomes APPLY_TF_SPEC, then it is synced.
apply_write_test_files() {
  cat "$APPLY_TF_SPEC" > "$VBW_DIR/spec.md"
  rm -f "$APPLY_TF_SPEC"
  vbw_guard_drop "$APPLY_TF_SPEC"
  spec_sync "$(spec_parse)"
}

# The amendment's jq helpers (R250). adds($d): what the document $d adds to the record, one
# row per plan or check that gains a file or an awaited check ({kind, id, files, awaits}); whats: a row's amendment lines.
AMEND_JQ='def dedupe: reduce .[] as $x ([]; if index($x) then . else . + [$x] end);
  def newfiles($old; $new): [$new[]? | select(. as $f | ($old | index($f)) | not)] | dedupe;
  def adds($d): [(.plans[] | . as $p | ([$d.plans[]? | select(.id == $p.id)][0]) as $e | select($e != null)
        | {kind: "plans", id, files: newfiles($p.files; $e.files), awaits: newfiles($p.awaits // []; $e.awaits)}),
      (.checks[] | . as $c | ([$d.checks[]? | select(.id == $c.id)][0]) as $e | select($e != null)
        | {kind: "checks", id, files: newfiles($c.files // []; $e.files), awaits: []})]
    | map(select((.files | length) + (.awaits | length) > 0));
  def whats: [.files[] | "file \(.) added"] + [.awaits[] | "awaits \(.)"];
'

# apply_amend: vbw apply --amend < DOC, the main session's fourth mode (R250). DOC holds
# plans [{id, files?, awaits?}] and checks [{id, files?}]: files are additions only (the plan's
# or check's own files and more; never a protected check file on a plan), awaits name checks
# of the plan's own requirements. The contract must be approved; it stays approved (the
# approval is re-pinned for the amended contract) and an open run stays open (a plan's
# added file joins the lease of a building plan, a check's joins the protected files, at once).
# Each addition is recorded on the plan or check as an amendment {what, at, session}, the
# session by its 8-character short id, never a name (D445). Everything else is refused in one
# line that sends it to vbw apply --patch and the user's approval, the record unchanged.
apply_amend() {
  local doc=$1 record problem sess adds
  printf '%s' "$doc" | jq -e 'type == "object"' > /dev/null 2>&1 || apply_refuse "apply needs a JSON object on stdin"
  record=$(record_read)
  contract_approved "$(contract_hash "$record")" \
    || apply_refuse "the contract is not approved: an amendment keeps an approved contract as it is, so send this change with vbw apply --patch and the user's approval"
  problem=$(printf '%s' "$record" | jq -r --slurpfile f_d <(printf '%s' "$doc") '$f_d[0] as $d
    | "change it with vbw apply --patch, then the user approves it" as $tail
    | .checks as $ck | ([.checks[] | (.files // [])[]] | unique) as $prot
    | def top: ($d | keys - ["plans", "checks"])[0:1][] | "\(.) is not an amendment: \($tail)";
      def shape: ($d | to_entries[] | select(.key | IN("plans", "checks")) | select((.value | type == "array" and all(.[]; type == "object" and (.id | type == "string"))) | not)
        | "\(.key) must be an array of objects that each name a plan or check by its id");
      def entry($kind; $rows; $allowed):
        ($d[$kind] // [])[] | . as $e | ([$rows[] | select(.id == $e.id)][0]) as $row
        | if $row == null then "\($e.id) is not a \($kind | rtrimstr("s")) of the record: an amendment names one that exists"
          else ($e | keys[] | select(. as $k | $allowed | index($k) | not) | "\($e.id) \(.) is not an amendment: \($tail)"),
               (if ($e | has("files")) then
                  if ($e.files | type == "array" and all(.[]; type == "string" and length > 0)) | not then "\($e.id) files must be an array of paths"
                  else ($row.files // [])[] | . as $f | select(($e.files | index($f)) == null) | "\($e.id) files would lose \($f): a removal is not an amendment; \($tail)" end
                else empty end),
               (if $kind == "plans" and ($e | has("files")) and ($e.files | type == "array") then
                  $e.files[] | . as $f | select(($row.files | index($f)) == null and ($prot | index($f)) != null)
                  | "\($f) is a protected check file: a plan never takes one among its files; \($tail)"
                else empty end),
               (if $e | has("awaits") then
                  if ($e.awaits | type == "array" and all(.[]; type == "string")) | not then "\($e.id) awaits must be an array of check ids"
                  else $e.awaits[] | . as $a | ([$ck[] | select(.id == $a)][0]) as $c
                    | if $c == null then "\($a) is not a check of the record: \($e.id) awaits one that exists"
                      elif ($row.reqs | index($c.req)) == null then "\($a) is a check of \($c.req), which \($e.id) does not build (\($row.reqs | join(", "))): awaits names checks of the plan own requirements"
                      else empty end end
                else empty end)
          end;
      [top, shape, entry("plans"; .plans; ["id", "files", "awaits"]), entry("checks"; .checks; ["id", "files"])] | .[0] // empty' 2> /dev/null) \
    || apply_internal "cannot judge the amendment"
  [ -z "$problem" ] || apply_refuse "$problem"
  vbw_scratch df "$doc"
  sess=$(vbw_session)
  adds=$(printf '%s' "$record" | jq -r --slurpfile f_d "$df" "$AMEND_JQ"'adds($f_d[0])[] | . as $x | $x | whats[] | "\($x.id): \(.)"') \
    || apply_internal "cannot read the amendment"
  if [ -z "$adds" ]; then
    vbw_guard_drop "$df"
    printf 'nothing to amend: the plans and checks named already hold those files and awaited checks\n'
    return 0
  fi
  record_update "$AMEND_JQ"'$f_d[0] as $d | . as $r0 | adds($d) as $a
    | [$a[] | select(.kind == "plans" and (.id as $i | any($r0.plans[]; .id == $i and .status == "building"))) | .files[]] as $la
    | reduce $a[] as $x (.; (.[$x.kind][] | select(.id == $x.id))
        |= (.files += $x.files | (if ($x.awaits | length) > 0 then .awaits = ((.awaits // []) + $x.awaits) else . end)
            | .amendments = ((.amendments // []) + [$x | whats[] | {what: ., at: $at, session: (if $s == "" then null else $s[0:8] end)}])))
    | if .lease != null and .lease.kind == "build" and (.lease.files | type) == "array" then .lease.files = ((.lease.files + $la) | dedupe) else . end' \
    --slurpfile f_d "$df" --arg at "$(vbw_now)" --arg s "$sess"
  vbw_guard_drop "$df"
  approve_repin "$(record_read)"
  printf '%s\n' "$adds" | sed 's/^/amended /'
}

cmd_apply() {
  local patch=false add=false amend=false
  MODE_NAME="full apply"
  case "${1:-}" in --patch) patch=true; MODE_NAME="--patch"; shift ;; --add) add=true; MODE_NAME="--add"; shift ;; --amend) amend=true; MODE_NAME="--amend"; shift ;; esac
  [ $# -eq 0 ] || vbw_usage_error "usage: vbw apply < plan.json (full apply) | vbw apply --add < doc.json | vbw apply --patch < doc.json | vbw apply --amend < doc.json"
  vbw_require_project
  if [ "$amend" = true ]; then
    apply_amend "$(cat)"
    return 0
  fi
  local doc record problem merged filter hypo tiers judged one pdoc='{}' df tf pf of ids p form=null ops='[]' addr
  doc=$(cat)
  if printf '%s' "$doc" | jq -e 'type == "object" and has("test_files")' > /dev/null 2>&1; then
    form=$(printf '%s' "$doc" | jq -c '.test_files')
    printf '%s' "$form" | jq -e 'def form: (.run | type == "array" and length > 0 and all(.[]; type == "string" and length > 0)
             and ([.[] | [match("\\{file\\}"; "g")] | length] | add) == 1)
        and (.files | type == "array" and length > 0 and all(.[]; type == "string" and length > 0 and (test("\\s") | not)))
        and ((.dir // "x") | type == "string" and length > 0 and (test("\\s") | not));
      if type == "object" then (keys - ["dir"]) == ["files", "run"] and form
      else type == "array" and length > 0 and all(.[]; type == "object" and (keys - ["dir"]) == ["files", "name", "run"]
        and (.name | type == "string" and test("^[A-Za-z0-9_-]+$") and . != "run" and . != "files" and . != "dir") and form) end' > /dev/null 2>&1 \
      || apply_refuse "test_files must be {run, files, dir?}, or an array of named forms {name, run, files, dir?}: run an argv naming {file} exactly once, files a non-empty array of git pathspecs without spaces, dir a folder, name letters, digits, _ or -"
    # Judged before anything is written: the form goes into the spec after the record.
    [ -f "$VBW_DIR/spec.md" ] || apply_refuse "no .vbw/spec.md to write the test-file form into"
    apply_test_files_spec "$form"
    doc=$(printf '%s' "$doc" | jq -c 'del(.test_files)')
  fi
  # A rule address (T168) reaches a rule already in the record: only a patch takes one.
  addr=$(printf '%s' "$doc" | jq -r 'if type == "object" and (.rules | type) == "array"
      then [.rules[] | objects | select(has("rule")) | .rule | tostring][0] // empty else empty end' 2> /dev/null) || addr=''
  [ -z "$addr" ] || [ "$patch" = true ] \
    || apply_refuse "a rule address ($addr) is for vbw apply --patch: a full apply and --add take rules as {req, text, check, plan?}"
  if [ "$add" = true ]; then
    # --add: new phases with their plans, checks and rules, appended to the milestone;
    # every existing item stays as it is, its tier included; the rigor floor and the
    # one-plan-per-express rule judge the new phases only, every other rule the merged whole.
    printf '%s' "$doc" | jq -e 'type == "object" and (.phases | type == "array" and length > 0)
        and all(.phases[]; type == "object" and (.id | type == "string") and (.reqs | type == "array"))
        and all(.plans, .checks, .rules; . == null or (type == "array" and all(.[]; type == "object")))' > /dev/null 2>&1 \
      || apply_refuse "--add needs a JSON object with the new phases ({id, title, reqs}) and their plans, checks and rules"
    pdoc=$(printf '%s' "$doc" | jq -c '{phases, plans: (.plans // []), checks: (.checks // []), rules: (.rules // [])}')
    problem=$(record_read | jq -r --slurpfile f_p <(printf '%s' "$pdoc") "$FOREIGN_REQS_JQ"'$f_p[0] as $p | . as $r | .milestone.id as $m
      | ([.phases[] | select(.milestone == $m)]) as $ph | [$p.phases[].id] as $new | [$p.phases[].reqs[]] as $newreqs
      | [($p.phases[] | .id as $i | select(any($r.phases[]; .id == $i)) | "\($i) is already a phase\(if any($ph[]; .id == $i) then " of this milestone" else "" end): --add takes new phases only"),
         # A new phase may sit beside a started phase that covers the same requirement (R157);
         # before any work started, the existing phase is the one to change (R116).
         ($p.phases[] | (.reqs // [])[] | . as $q
           | ([$ph[] | select(any(.reqs[]; . == $q)) | . as $cp
                | select((($cp.escalations // []) == []) and (([$r.plans[] | select(.phase == $cp.id and .status != "planned")]) | length) == 0)][0]) as $cover
           | select($cover != null)
           | "\($q) is already covered by \($cover.id), whose work has not started: change \($cover.id) with a full apply; a new phase beside it is for work that has started"),
         foreign_reqs($r; $m; $p; "add"; "--add")[],
         ($p.plans[] | select(.phase as $x | $new | index($x) | not) | "\(.id // "a plan") is for \(.phase // "no phase"), not a phase this --add brings"),
         ($p.plans[] | select(.id as $i | any(($r.plans // [])[]; .id == $i)) | "\(.id) is already a plan: --add takes new plans only"),
         ($p.checks[] | select(.id as $i | any(($r.checks // [])[]; .id == $i)) | "\(.id) is already a check: --add takes new checks only"),
         ($p.checks[], $p.rules[] | select(.req as $q | $newreqs | index($q) | not)
           | "\(.id // "the rule \"\(.text)\"") is for \(.req), not a requirement of the phases this --add brings")]
      | .[0] // empty') || apply_internal "cannot read the added phases"
    [ -z "$problem" ] || apply_refuse "$problem"
    doc=$(record_read | jq -c --slurpfile f_p <(printf '%s' "$pdoc") '$f_p[0] as $p | .milestone.id as $m
      | ([.phases[] | select(.milestone == $m)]) as $ph
      | ([.requirements[] | select(.milestone == $m)]) as $rq
      | {phases: [($ph[] | {id, title, reqs} + with_entries(select(.key | IN("goal", "criteria")))
            + (if (.proposed // .tier) != null then {tier: (.proposed // .tier)} else {} end)), $p.phases[]],
         plans: ([.plans[] | select(.phase as $x | any($ph[]; .id == $x)) | with_entries(select(.key | IN("id", "phase", "title", "reqs", "files", "after", "tasks", "role")))] + $p.plans),
         checks: ([.checks[] | select(.req as $x | any($rq[]; .id == $x))] + $p.checks),
         rules: ([$rq[] | .id as $q | (.rules // [])[] | select(has("retired") | not) | {req: $q, text, check} + (if has("plan") then {plan} else {} end)] + $p.rules)}') \
      || apply_internal "cannot merge the added phases"
  elif [ "$patch" = true ]; then
    # --patch: plans, checks and rules to change, merged by id (rules by requirement and text)
    # into the milestone; the merged whole then meets every rule a full apply does.
    printf '%s' "$doc" | jq -e 'type == "object" and (has("phases") | not)' > /dev/null 2>&1 \
      || apply_refuse "a patch carries plans, checks and rules, never phases: change phases with a full apply"
    # The rules named by address (T168), judged before anything is merged.
    ops=$(printf '%s' "$doc" | jq -c '[(.rules // [])[]? | objects | select(has("rule"))]' 2> /dev/null) || ops='[]'
    problem=$(printf '%s' "$ops" | jq -r '[.[] | select(((.rule | type == "string" and test("^R[0-9]+\\.[1-9][0-9]*$")) | not)
        or (if has("retire") then (keys | sort) != ["retire", "rule"] or ((.retire | type == "string" and length > 0) | not)
            else (keys - ["rule", "text", "check", "plan"]) != [] or (keys | length) < 2 or any(del(.rule)[]; (type == "string" and length > 0) | not) end))]
      | if length > 0 then "a rule address takes {rule: \"Rn.k\", text?, check?, plan?} to reword a rule, or {rule: \"Rn.k\", retire: REASON} to retire it; \(.[0] | tojson) is neither" else empty end')
    [ -z "$problem" ] || apply_refuse "$problem"
    problem=$(record_read | jq -r --slurpfile f_o <(printf '%s' "$ops") '. as $r | $f_o[0] as $ops
      | [($ops | group_by(.rule)[] | select(length > 1) | "\(.[0].rule) is named twice: a patch changes each rule once"),
         ($ops[] | .rule as $a | ($a | capture("^(?<q>R[0-9]+)\\.(?<k>[0-9]+)$")) as $c | ($c.k | tonumber) as $k
           | ([$r.requirements[] | select(.id == $c.q)][0]) as $rq | (($rq.rules // []) | length) as $n
           | if $rq == null then "\($c.q) has no rule \($a) (there is no requirement \($c.q))"
             elif $k > $n then "\($c.q) has no rule \($a) (it has \(if $n == 0 then "none" else $n end))"
             elif ($rq.rules[$k - 1] | has("retired")) then "\($a) is retired (\($rq.rules[$k - 1].retired)): a retired rule stays as it is"
             else empty end)]
      | .[0] // empty') || apply_internal "cannot read the rule addresses"
    [ -z "$problem" ] || apply_refuse "$problem"
    pdoc=$(printf '%s' "$doc" | jq -c '{plans: (.plans // []), checks: (.checks // []), rules: (if (.rules | type) == "array" then [.rules[] | select((type == "object" and has("rule")) | not)] else .rules // [] end)}')
    # The milestone's live rules as the addresses leave them, then the rules by words merged in.
    doc=$(record_read | jq -c --slurpfile f_p <(printf '%s' "$pdoc") --slurpfile f_o <(printf '%s' "$ops") "$RULES_JQ"'$f_p[0] as $p | $f_o[0] as $ops | .milestone.id as $m
      | ([.phases[] | select(.milestone == $m)]) as $ph
      | ([.requirements[] | select(.milestone == $m)]) as $rq
      | def merge($old; $new; $keys): [$old[] | . as $o | ([$new[] | select(. as $n | $keys | all(. as $k | $n[$k] == $o[$k]))][0]) // $o]
          + [$new[] | . as $n | select(any($old[]; . as $o | $keys | all(. as $k | $n[$k] == $o[$k])) | not)];
      {phases: [$ph[] | {id, title, reqs} + with_entries(select(.key | IN("goal", "criteria")))
          + (if (.proposed // .tier) != null then {tier: (.proposed // .tier)} else {} end)],
       plans: merge([.plans[] | select(.phase as $x | any($ph[]; .id == $x)) | with_entries(select(.key | IN("id", "phase", "title", "reqs", "files", "after", "tasks", "role")))]; $p.plans; ["id"]),
       checks: merge([.checks[] | select(.req as $x | any($rq[]; .id == $x))]; $p.checks; ["id"]),
       rules: merge([$rq[] | .id as $q | (.rules // []) | to_entries[] | .key as $k | .value | rule_edit($ops; "\($q).\($k + 1)")
           | select(has("retired") | not) | {req: $q, text, check} + (if has("plan") then {plan} else {} end)]; $p.rules; ["req", "text"])}') \
      || apply_internal "cannot merge the patch"
  fi
  printf '%s' "$doc" | jq -e 'type == "object"' > /dev/null 2>&1 || apply_refuse "apply needs a JSON object on stdin"
  printf '%s' "$doc" | jq -e '(keys - ["phases", "plans", "checks", "rules"]) == [] and all(.phases, .plans, .checks; type == "array")
      and ((has("rules") | not) or (.rules | type == "array" and all(.[]; type == "object" and (keys - ["req", "text", "check", "plan"]) == [] and (.text | type == "string" and length > 0))))' \
    > /dev/null || apply_refuse "apply needs phases, plans and checks, each an array, and optionally rules: [{req, text, check, plan?}]"
  if [ "$add" = false ] && [ "$patch" = false ]; then
    problem=$(record_read | jq -r --slurpfile f_p <(printf '%s' "$doc") "$FOREIGN_REQS_JQ"'$f_p[0] as $p | . as $r | foreign_reqs($r; .milestone.id; $p; "others"; "full apply")[0] // empty') \
      || apply_internal "cannot read the phases' requirements"
    [ -z "$problem" ] || apply_refuse "$problem"
  fi
  problem=$(printf '%s' "$doc" | jq -r '[
      (.phases[] | . as $o | keys[] | select(IN("id", "title", "reqs", "goal", "criteria", "tier") | not) | "\($o.id // "a phase") has an unknown field: \(.)"),
      (.plans[] | . as $o | keys[] | select(IN("id", "phase", "title", "reqs", "files", "after", "tasks", "role") | not) | "\($o.id // "a plan") has an unknown field: \(.)")
    ] | .[0] // empty')
  [ -z "$problem" ] || apply_refuse "$problem"
  problem=$(printf '%s' "$doc" | jq -r '.phases[] | select(has("tier") and (.tier | IN("express", "standard", "deep") | not))
    | "\(.id // "a phase") has the tier \(.tier | tojson): the tier must be express, standard or deep"' | head -n 1)
  [ -z "$problem" ] || apply_refuse "$problem"
  record=$(record_read)
  # A patch of checks alone may land while a build run is open (R250): the plans keep their progress,
  # the run stays open, and the contract then waits for the user's approval of what the checks assert.
  printf '%s' "$record" | jq -e --argjson patch "$patch" --slurpfile f_p <(printf '%s' "$pdoc") --slurpfile f_o <(printf '%s' "$ops") \
    '.lease == null or .lease.kind == "plan"
      or ($patch and .lease.kind == "build" and ($f_p[0].plans | length) == 0 and ($f_p[0].rules | length) == 0 and ($f_o[0] | length) == 0)' > /dev/null \
    || apply_refuse "a $(printf '%s' "$record" | jq -r .lease.kind) run is open: plan again after it ends (vbw run end)"
  problem=$(printf '%s' "$record" | jq -r --slurpfile f_d <(printf '%s' "$doc") '$f_d[0] as $d | .milestone.id as $m
    | ([.phases[] | select(.milestone == $m) | .id]) as $mine
    | [.plans[] | select(.status != "planned" and (.phase as $p | any($mine[]; . == $p))) | . as $old
        | ([$d.plans[] | select(.id == $old.id)][0]) as $new
        | select($new == null or ($new | {phase, reqs, files, after: (.after // [])}) != ($old | {phase, reqs, files, after}))
        | "\($old.id) is \($old.status): a plan that has started must stay as it is (same phase, requirements, files and order)"]
    | .[0] // empty')
  [ -z "$problem" ] || apply_refuse "$problem"
  # A phase has started when one of its plans is no longer planned or it has an escalation:
  # its goal and criteria then stay (R158); a phase that has not started may change both.
  problem=$(printf '%s' "$record" | jq -r --slurpfile f_d <(printf '%s' "$doc") '$f_d[0] as $d | .milestone.id as $m | [.phases[] | select(.milestone == $m)] as $old
    | [.plans[] | select(.status != "planned") | .phase] as $began
    | [$d.phases[] | . as $n | ([$old[] | select(.id == $n.id)][0]) as $o | select($o != null)
        | select(($o.escalations // []) != [] or any($began[]; . == $o.id))
        | select((($n | has("goal")) and $o.goal != null and $o.goal != $n.goal) or (($n | has("criteria")) and $o.criteria != null and $o.criteria != $n.criteria))
        | "\($n.id) has work started: its goal and criteria stay as they are; add a new phase for the further work"]
    | .[0] // empty')
  [ -z "$problem" ] || apply_refuse "$problem"
  problem=$(printf '%s' "$record" | jq -r --slurpfile f_d <(printf '%s' "$doc") '$f_d[0] as $d | .milestone.id as $m | [.phases[] | select(.milestone == $m)] as $old
    | select(any(.plans[]; .status != "planned" and (.phase as $p | any($old[]; .id == $p))))
    | [($d.phases[] | . as $n | ([$old[] | select(.id == $n.id)][0]) as $o | select($o != null)
        | if $o.title != $n.title then "\($n.id) has work started: its title stays \"\($o.title)\" (a phase is not renamed once planned work has started)"
          elif ($o.reqs | sort) != ($n.reqs | sort) then "\($n.id) has work started: its requirements stay \($o.reqs | join(", "))" else empty end)
      ] | .[0] // empty')
  [ -z "$problem" ] || apply_refuse "$problem"
  # A requirement's rules in the record count when live: not retired, nor retired by this patch (T168).
  problem=$(printf '%s' "$record" | jq -r --slurpfile f_d <(printf '%s' "$doc") --slurpfile f_p <(printf '%s' "$pdoc") --slurpfile f_o <(printf '%s' "$ops") --argjson add "$add" "$VBW_JQ_DEFS$RULES_JQ"'$f_d[0] as $d | select($d | has("rules"))
    | . as $r | $d.rules as $rules | $f_o[0] as $ops | ([$f_p[0].phases[]?.reqs[]] | unique) as $newreqs
    | [($rules[] | . as $x | select(any($r.requirements[]; .id == $x.req and .proof == "human"))
        | "the rule \"\($x.text)\" is for \($x.req), a [human] requirement: only [auto] requirements list rules"),
       ($rules[] | . as $x | select(any($d.checks[]; .id == $x.check and .req == $x.req) | not)
        | "the rule \"\($x.text)\" names \($x.check), which is not a check of \($x.req) in this plan"),
       ($r.requirements[] | . as $q | select(.proof == "auto" and .status != "proven" and ($q | doc_only($d.plans; $d.checks) | not)
          and any($d.phases[].reqs[]; . == $q.id) and (($add | not) or ($newreqs | index($q.id) != null))
          and ($r.phases | any(.milestone == $r.milestone.id and any(.reqs[]; . == $q.id)
                and (((.escalations // []) != []) or (.id as $i | $r.plans | any(.phase == $i and .status != "planned")))) | not)
          and ((($rules | any(.req == $q.id))
                or ([(.rules // []) | to_entries[] | .key as $k | .value | rule_edit($ops; "\($q.id).\($k + 1)") | select(has("retired") | not)] | length > 0)) | not))
        | "\(.id) lists no rules: list each condition, edge and error case its text states, with the check that tests it (rules)")]
    | .[0] // empty')
  [ -z "$problem" ] || apply_refuse "$problem"
  hypo=$(printf '%s' "$record" | jq -c --slurpfile f_d <(printf '%s' "$doc") '$f_d[0] as $d | .milestone.id as $m
    | .phases = [(.phases[] | select(.milestone != $m)), ($d.phases[] | {id, title, reqs, milestone: $m} + (with_entries(select(.key | IN("goal", "tier")))))]
    | .plans = [.plans[] | select(.phase as $p | $d.phases | any(.id == $p) | not)] + [$d.plans[] | {id, phase, title, reqs, files, after: (.after // [])}]')
  # The phases judged: with --add only the ones it brings, else every phase of the doc.
  judged=$doc
  [ "$add" = false ] || judged=$pdoc
  # A phase that has started (a plan no longer planned, or an escalation) or finished keeps
  # its tier, reasons and predicted tier: only the phases that have not started are judged (R159).
  ids=()
  while IFS= read -r p; do
    ids+=("$p")
  done < <(printf '%s' "$record" | jq -r --slurpfile f_j <(printf '%s' "$judged") '.milestone.id as $m
    | [.plans[] | select(.status != "planned") | .phase] as $began
    | [.phases[] | select(.milestone == $m and ((.escalations // []) != [])) | .id] as $esc
    | $f_j[0].phases[].id | select(. as $i | (($began + $esc) | index($i)) | not)')
  tiers='[]'
  if [ ${#ids[@]} -gt 0 ]; then
    tiers=$(printf '%s' "$hypo" | rigor_assess "${ids[@]}" 2> /dev/null) \
      || apply_internal "cannot compute the rigor tiers"
  fi
  problem=$(printf '%s' "$tiers" | jq -r --slurpfile f_d <(printf '%s' "$doc") '$f_d[0] as $d | [.[] | . as $a | ([$d.phases[] | select(.id == $a.id)][0].tier) as $s
      | select($s != null and ($s | IN("express", "standard", "deep")) and (["express", "standard", "deep"] | index($s)) < (["express", "standard", "deep"] | index($a.floor)))
      | "\($a.id) is planned at \($s) but its signals set the floor at \($a.floor) (\($a.reasons | map(select(test("^(requirements|files|risk|breaks|tests): ") and (test(": none$") | not))) | join("; "))): the Architect may only raise a tier"]
    | .[0] // empty')
  if [ -n "$problem" ] && [ "$(printf '%s' "$record" | jq -r '.settings.rigor // "auto"')" = auto ]; then
    apply_refuse "$problem"
  fi
  one=$(printf '%s' "$record" | jq -r --slurpfile f_d <(printf '%s' "$doc") --slurpfile f_tiers <(printf '%s' "$tiers") --arg mode "$(printf '%s' "$record" | jq -r '.settings.rigor // "auto"')" '$f_d[0] as $d | $f_tiers[0] as $tiers |
      [$tiers[] | . as $a | (if $mode | IN("express", "standard", "deep") then $mode else $a.tier end) as $t
        | select($t == "express" and ([$d.plans[] | select(.phase == $a.id)] | length) > 1)
        | "\($a.id) is express: one plan, merge its plans or raise its tier"] | .[0] // empty')
  [ -z "$one" ] || apply_refuse "$one"
  vbw_scratch df "$doc"
  vbw_scratch tf "$tiers"
  vbw_scratch pf "$pdoc"
  vbw_scratch of "$ops"
  filter="$RULES_JQ"'$f_d[0] as $d | $f_tiers[0] as $tiers | $f_pd[0] as $pd | $f_ops[0] as $ops | .milestone.id as $m
    | ([.phases[] | select(.milestone == $m) | .id]) as $mine
    | ([.requirements[] | select(.milestone == $m) | .id]) as $myreqs
    | (.plans | map({key: .id, value: .status}) | from_entries) as $status
    | [.phases[] | select(.milestone == $m)] as $old
    | [.plans[] | select(.status != "planned") | .phase] as $started
    | .checks as $c0
    | .phases = (if $patch then .phases else [(.phases[] | select($add or .milestone != $m)), ((if $add then $pd.phases else $d.phases end)[] | . as $np | ([$old[] | select(.id == $np.id)][0]) as $o
                  | ([$tiers[] | select(.id == $np.id)][0]) as $a
                  | (.tier // null) as $sub
                  | ($mode | IN("express", "standard", "deep")) as $forced
                  | (($o != null) and (($o.escalations // []) != [] or any($started[]; . == $np.id))) as $locked
                  | (if $forced then $mode else $a.tier end) as $want
                  | ($locked and ($o.tier != null)) as $keep
                  | (if $keep then $o.tier else $want end) as $tier
                  | {id, title, reqs, milestone: $m}
                    # A started phase keeps its goal and criteria when the document leaves them out (R158).
                    + (if $locked then ($o | with_entries(select(.key | IN("goal", "criteria")))) else {} end)
                    + (with_entries(select(.key | IN("goal", "criteria"))))
                    + (if $keep then ($o | with_entries(select(.key == "proposed")))
                       elif $sub != null then {proposed: $sub} else {} end)
                    + {tier: $tier,
                       reasons: (if $keep then ($o.reasons // [])
                         else ($a.reasons | map(select(startswith("Architect raised") | not))
                           + (if $forced then ["forced: vbw config rigor \($mode)"]
                              elif ($sub != null and $tier == $sub and $tier != $a.floor) then ["raised by the Architect"]
                              else [] end)) end),
                       predicted: (if $locked then ($o.predicted // $tier) else $tier end)}
                    + ($o // {} | with_entries(select(.key | IN("escalations", "outcome", "qa")))))] end)
    # A plan keeps the breaks its mutation check recorded: kernel evidence, like its status (T154).
    | ([.plans[] | select(has("mutations")) | {key: .id, value: .mutations}] | from_entries) as $mut
    # and its note, the blocked reason, the same way (R213).
    | ([.plans[] | select(has("note")) | {key: .id, value: .note}] | from_entries) as $note
    # and its amendments and awaited checks, and the amendments of a check (R250): history the Lead never re-sends.
    | ([.plans[] | select(has("amendments") or has("awaits")) | {key: .id, value: with_entries(select(.key | IN("amendments", "awaits")))}] | from_entries) as $kept
    | ([.checks[] | select(has("amendments")) | {key: .id, value: .amendments}] | from_entries) as $camd
    | ([($pd.plans // $d.plans)[] | {id, phase, title, reqs, files, after: (.after // []), status: ($status[.id] // "planned")}
          + (with_entries(select(.key | IN("tasks", "role"))))
          + (if $mut[.id] then {mutations: $mut[.id]} else {} end)
          + (if $note[.id] then {note: $note[.id]} else {} end)
          + ($kept[.id] // {})]) as $np
    | .plans = (if $patch or $add then [.plans[] | . as $o | ([$np[] | select(.id == $o.id)][0]) // $o] + [$np[] | select($status[.id] == null)]
        else [(.plans[] | select(.phase as $p | any($mine[]; . == $p) | not)), $np[]] end)
    | .checks = (if $patch or $add then [$c0[] | . as $o | ([$pd.checks[] | select(.id == $o.id)][0]) // $o] + [$pd.checks[] | select(.id as $i | $c0 | any(.id == $i) | not)]
        else [($c0[] | select(.req as $q | any($myreqs[]; . == $q) | not)), $d.checks[]] end)
    | .checks |= map(if $camd[.id] then . + {amendments: $camd[.id]} else . end)
    # The rules named by address first (T168), then the live rules laid around the retired ones.
    | .requirements |= map(.id as $q | if (.rules | type) == "array"
        then .rules = [.rules | to_entries[] | .key as $k | .value | rule_edit($ops; "\($q).\($k + 1)")] else . end)
    | if $d | has("rules") then .requirements |= map(. as $q
        | if any($d.rules[]; .req == $q.id) then .rules = place($q.rules // []; [$d.rules[] | select(.req == $q.id) | {text, check} + (if has("plan") then {plan} else {} end)]) else . end)
      else . end'
  # The merged record is checked here, so a violation names the mode too; record_update checks it again.
  merged=$(mktemp "$VBW_RUNTIME/apply.XXXXXX") || vbw_die "cannot create a temporary file in $VBW_RUNTIME"$'\n'"Next: check that $VBW_RUNTIME exists and can be written to, then run vbw apply again"
  vbw_guard_add file "$merged"
  jq "$filter | .protected = ([(.checks // [])[]? | objects | .files? | arrays | .[] | strings] | unique)" --slurpfile f_d "$df" --slurpfile f_tiers "$tf" --slurpfile f_pd "$pf" --slurpfile f_ops "$of" --argjson patch "$patch" --argjson add "$add" --arg mode "$(printf '%s' "$record" | jq -r '.settings.rigor // "auto"')" "$VBW_RECORD" > "$merged" 2> /dev/null \
    || apply_internal "cannot merge the plan into the record"
  # Judged on the merged record: a mixed requirement (R212) and a check owned by two plans not yet
  # built, one after the other (R211) or beside each other in a wave (R215); all leave the record unchanged.
  problem=$(jq -r "$VBW_JQ_DEFS"'.milestone.id as $m
    | ([.phases[] | select(.milestone == $m) | .id]) as $mine
    | [.plans[] | select(.phase as $p | any($mine[]; . == $p))] as $plans
    | ([.requirements[] | select(.milestone == $m) | . as $q | ([(.rules // [])[] | select(has("retired") | not)]) as $live
        | ([$live[] | select(has("plan"))] | length) as $n | select($n > 0 and $n < ($live | length))
        | "\($q.id): \($n) of \($live | length) rules name a plan: name one on every rule or on none"][0]) as $mixed
    # up($id): the plans $id builds after, directly or through a chain.
    | def up($id): reduce range(0; $plans | length) as $_ ([$id]; . + [.[] | . as $i | $plans[] | select(.id == $i) | (.after // [])[]] | unique) | map(select(. != $id));
    # The waves of the merged record as vbw next would place them with no plan blocked: a blocked plan builds again.
    ((.plans |= map(if .status == "blocked" then .status = "planned" else . end)) | waves($m)) as $wv
    | def widx($i): [range(0; $wv | length) | select(any($wv[.][]; . == $i))][0];
    ([.requirements[] | select(.milestone == $m) | (.rules // [])[] | select((has("retired") | not) and has("plan")) | {check, plan}] | unique) as $owned
    | ([[$owned[].check] | unique | .[] | . as $c
        | ([$owned[] | select(.check == $c) | .plan] | unique | map(. as $i | select(any($plans[]; .id == $i and .status != "done")))) as $ps
        | range(0; $ps | length) as $x | range($x + 1; $ps | length) as $y | $ps[$x] as $a | $ps[$y] as $b
        | ([$plans[] | select(.id == $a)][0]) as $pa | ([$plans[] | select(.id == $b)][0]) as $pb
        | (widx($a)) as $wa | (widx($b)) as $wb
        | (if (up($b) | index($a)) != null then "\($b) builds after \($a)"
           elif (up($a) | index($b)) != null then "\($a) builds after \($b)"
           elif overlaps($pa.files; $pb.files) then "\($a) and \($b) share a file"
           elif $wa == null or $wb == null or $wa == $wb then null
           elif $wa < $wb then "\($a) builds in an earlier wave than \($b)"
           else "\($b) builds in an earlier wave than \($a)" end) as $why
        | if $why != null then "\($c) is owned by two plans that build one after the other (\($why)): \($a) and \($b); the earlier plan'"'"'s mutation step would find \($c) red on unbroken code"
          elif $wa != null and $wa == $wb then "\($c) is owned by two plans that build beside each other (a shared wave): \($a) and \($b); the first Dev'"'"'s mutation step would run \($c) before the other Dev committed, a race that fails only sometimes"
          else empty end][0]) as $order
    | $mixed // $order // empty' "$merged" 2> /dev/null | head -n 1) || true
  [ -n "$problem" ] || problem=$(apply_empty_filter "$df" | head -n 1) || true
  [ -n "$problem" ] || problem=$(record_violation "$merged") || true
  rm -f "$merged"
  vbw_guard_drop "$merged"
  [ -z "$problem" ] || apply_refuse "$problem"
  record_update "$filter" --slurpfile f_d "$df" --slurpfile f_tiers "$tf" --slurpfile f_pd "$pf" --slurpfile f_ops "$of" --argjson patch "$patch" --argjson add "$add" --arg mode "$(printf '%s' "$record" | jq -r '.settings.rigor // "auto"')"
  vbw_guard_drop "$df"
  vbw_guard_drop "$tf"
  vbw_guard_drop "$pf"
  vbw_guard_drop "$of"
  jq -r '.milestone.id as $m | ([.phases[] | select(.milestone == $m) | .id]) as $mine
    | "applied \($mine | length) phases, \([.plans[] | select(.phase as $p | any($mine[]; . == $p))] | length) plans, \(.checks | length) checks in all"' "$VBW_RECORD"
  [ "$form" = null ] || apply_write_test_files
}
