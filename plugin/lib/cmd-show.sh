#!/usr/bin/env bash
# vbw show roadmap | phase ID | req ID | plan ID [--json] | fix ID [--json] |
# contract | evidence | decisions [--since-approval [PLAN|FIX...]] | requirements | rigor | qa: views rendered from the record
# and git trailers. Nothing is stored in rendered form. plan and fix are the
# context a Dev works from.

cmd_show() {
  local view="${1:-}" record cf
  [ $# -gt 0 ] && shift
  case "$view" in roadmap|phase|req|plan|fix|contract|evidence|decisions|requirements|rigor|qa|costs) ;; *) vbw_usage_error "usage: vbw show roadmap | phase ID | req ID | plan ID [--json] | fix ID [--json] | contract [--changes] | evidence | decisions [--since-approval [PLAN|FIX...]] | requirements | rigor | qa | costs [--json | --ceiling USD]" ;; esac
  vbw_require_project
  if [ "$view" = costs ]; then
    show_costs "$@"
    return
  fi
  # shellcheck source=cmd-next.sh
  . "$VBW_LIB/cmd-next.sh"
  record=$(record_read)
  case "$view" in
    roadmap)
      printf '%s' "$record" | jq -r "$SHOW_JQ_DEFS"'
        . as $r
        | ([.shipped[] | {id, title, at, line: "\(.id) \(.title) [shipped \(.at[0:10])]"}]
           + [(.parked // [])[] | {id, title, at, line: "\(.id) \(.title) [parked \(.at[0:10]): \(.reason)]"}]
           | sort_by(.id[1:] | tonumber) | .[].line),
          (if .milestone.status == "shipped" or .milestone.status == "parked" then empty else
             "\(.milestone.id) \(.milestone.title) [\(.milestone.status)]",
             ((.phases[] | select(.milestone == $r.milestone.id)) as $ph
               | "  \($ph.id) \($ph.title) [\($ph | phase_status($r))]",
                 ($r.plans[] | select(.phase == $ph.id)
                   | "    \(.id) \(.title) [\(.status)]\(if (.after | length) > 0 then " after \(.after | join(", "))" else "" end)\(if .status == "blocked" and .note then ": " + .note else "" end)"))
           end)'
      ;;
    phase)
      [ $# -eq 1 ] || vbw_usage_error "usage: vbw show phase ID"
      printf '%s' "$record" | jq -e --arg p "$1" 'any(.phases[]; .id == $p)' > /dev/null || vbw_die "unknown phase $1"
      vbw_scratch_json cf "$(qa_combined "$record")"
      # shellcheck source=delivered.sh
      . "$VBW_LIB/delivered.sh"
      printf '%s' "$record" | jq -r --arg p "$1" --slurpfile cf "$cf" --slurpfile dv <(qa_deviations "$record") "$SHOW_JQ_DEFS$DELIVERED_DEFS"'
        $cf[0] as $cur | . as $r | (.phases[] | select(.id == $p)) as $ph
        | "\($ph.id) \($ph.title) [\($ph | phase_status($r))]",
          (if $ph.goal then "goal: \($ph.goal)" else empty end),
          (if $ph.criteria then "criteria:", ($ph.criteria[] | "  - " + .) else empty end),
          (if $ph.qa then "qa: \($ph.qa.result) (\($ph.qa.tier), \($ph.qa.at))\(if $ph.qa.note then ": " + $ph.qa.note else "" end)"
             + (if $ph.qa.result == "pass" and $ph.qa.tree != ($cur[$ph.id] // "") then " [on older code]" else "" end) else empty end),
          (if $ph.tier then "tier: \($ph.tier) (predicted \($ph.predicted // $ph.tier))", ($ph.reasons // [] | map("  - " + .)[]) else empty end),
          (($ph.escalations // [])[] | "escalated \(.from) -> \(.to) (\(.at)): \(.reason)"),
          (($dv[0][$p] // [])[] | "deviation: \(deviation_line)\(if .decision then ", covered by \(.decision)" else "" end)"),
          "requirements:",
          ($ph.reqs[] as $q | $r.requirements[] | select(.id == $q) | "  \(.id) [\(.proof), \(.status)] \(.text)"),
          "plans:",
          ($r.plans[] | select(.phase == $p) | "  \(.id) \(.title) [\(.status)\(if .role == "docs" then ", docs" else "" end)]: \(.files | join(", "))",
            ((.tasks // [])[] | "    - " + .))'
      ;;
    qa)
      qa_state "$record" | jq -r '(if (.recheck | length) == 0 then "Nothing needs checking again" else
          (.recheck | to_entries[] | "\(.key) is checked again: \(.value | join("; "))") end),
        (.standing[] | "\(.) keeps its pass"),
        (if (.interleaved | length) > 0 then "note: phases \(.interleaved | if length < 2 then join("") else (.[:-1] | join(", ")) + " and " + .[-1] end) build on each other through their plans; each is checked again when the other'"'"'s tests change" else empty end),
        (.problems[] | "problem: " + .)'
      ;;
    req)
      [ $# -eq 1 ] || vbw_usage_error "usage: vbw show req ID"
      printf '%s' "$record" | jq -e --arg q "$1" 'any(.requirements[]; .id == $q)' > /dev/null || vbw_die "unknown requirement $1"
      printf '%s' "$record" | jq -r --arg q "$1" "$SHOW_JQ_DEFS"'
        . as $r | (.requirements[] | select(.id == $q)) as $req
        | "\($req.id) [\($req.proof), \($req.status)] \($req.text)",
          ($req | rule_lines),
          "checks:", ($r.checks[] | select(.req == $q) | "  \(.id) " + check_line + (if .fix then " (added by \(.fix))" else "" end)),
          "plans:", ($r.plans[] | select(any(.reqs[]; . == $q)) | "  \(.id) \(.title) [\(.status)]")'
      printf 'commits:\n'
      show_commits_for_req "$1"
      ;;
    plan|fix)
      [ $# -ge 1 ] && [ $# -le 2 ] && { [ $# -eq 1 ] || [ "$2" = --json ]; } || vbw_usage_error "usage: vbw show $view ID [--json]"
      show_work "$record" "$view" "$1" "${2:-}"
      ;;
    contract)
      if [ "${1:-}" = --changes ]; then
        show_contract_changes "$record"
        return 0
      fi
      [ $# -eq 0 ] || vbw_usage_error "usage: vbw show contract [--changes]"
      local hash state="NOT APPROVED"
      hash=$(contract_hash "$record")
      contract_approved "$hash" && state="approved"
      printf 'contract %s (%s)\n' "${hash:0:12}" "$state"
      printf '%s' "$record" | jq -r "$VBW_JQ_DEFS$SHOW_JQ_DEFS"'
        def express_line($r): $r.phases[] | select(.milestone == $r.milestone.id and .tier == "express") | .id as $p | .reqs as $q
          | "express: \($p) (\(([$q[], ($r.checks[] | select(.req as $c | any($q[]; . == $c)) | .id), ($r.plans[] | select(.phase == $p) | .id)]) | join(", ")))";
        # shared_file($a; $b): the file two plans would both change, the more specific
        # entry where a directory covers a file; "*" when either may change any file.
        def shared_file($a; $b): first(($a[], $b[] | select(. == "*")),
          ($a[] as $x | $b[] as $y | if ($x | covers($y)) then $y elif ($y | covers($x)) then $x else empty end));
        # wait_lines($r; $w): one line per plan after the first wave, naming the plans of
        # the wave before it that hold it back and why (the wave rule in record.sh).
        def wait_lines($r; $w): range(1; $w | length) as $k | $w[$k][] as $id
          | ([$r.plans[] | select(.id == $id)][0]) as $p
          | [$w[$k - 1][] as $q | ([$r.plans[] | select(.id == $q)][0]) as $o
              | [if any(($p.after // [])[]; . == $q) then "planned after it" else empty end,
                 (shared_file($p.files; $o.files) | if . == "*" then "either may change any file" else "both change \(.)" end)]
              | select(length > 0) | "\($q) (\(join(", ")))"]
          | select(length > 0) | "  \($id) waits for \(join(", "))";
        . as $r
        | "requirements:",
          (.requirements[] | . as $q | "  \(.id) [\(.proof)] \(.text)",
            (rule_lines | "    " + .),
            ($r.checks[] | select(.req == $q.id) | "    \(.id) " + check_line)),
          (([.phases[] | select(.milestone == $r.milestone.id and .tier)]) as $tp
            | if ($tp | length) > 0 then "phases:", ($tp[] | "  \(.id) \(.tier): \(.reasons | join("; "))") else empty end),
          (express_line($r) | "  " + .),
          "plans:",
          (.plans[] | "  \(.id) \(.title): \(.files | join(", "))\(if (.after | length) > 0 then " (after \(.after | join(", ")))" else "" end)"),
          (waves($r.milestone.id) as $w
            | ($w | map(length) | select(length > 0)
                | "build waves: \(length) (the widest runs \(max) plan\(if max == 1 then "" else "s" end) at once)"),
              wait_lines($r; $w)),
          "project commands:",
          (.commands | to_entries[] | "  \(.key): \(.value | argv_line)"),
          (.test_files // empty | "  test file form: \(.run | join(" ")) (one test file per run; test files: \(.files | join(" ")))"),
          (.project.results // empty | "saved test results folders: \(join(", "))"),
          (.project.leave_out // empty | "clean copy leaves out: \(join(", "))")'
      if [ "$state" != approved ]; then
        printf 'approval question: Approve contract %s?\napproval options: Approve, Not yet\n' "${hash:0:12}"
      fi
      ;;
    requirements)
      # Every requirement with its proof, status and milestone, and whether the
      # work for it is built (every plan serving it is done).
      printf '%s' "$record" | jq -r '. as $r | .requirements[]
        | . as $q | [$r.plans[] | select(any(.reqs[]; . == $q.id))] as $ps
        | "\(.id) [\(.proof), \(.status)] \(.text) (\(.milestone)\(if ($ps | length) > 0 and all($ps[]; .status == "done") then ", built" else "" end))"'
      ;;
    rigor)
      # Every phase's tier, the tier predicted for it and why, then how often the
      # prediction held among the finished phases (those with an outcome).
      printf '%s' "$record" | jq -r '
        (.phases[] | select(.tier) | "\(.id) \(.tier) (predicted \(.predicted // .tier))\(if .outcome then ", finished" else "" end): \((.reasons // []) | join("; "))"),
        ([.phases[] | select(.outcome)] as $f
          | if ($f | length) == 0 then "no finished phases yet"
            else "prediction held for \([$f[] | select(.outcome.held)] | length) of \($f | length) finished phases (\(([$f[] | select(.outcome.held)] | length) * 100 / ($f | length) | round)%)" end)'
      ;;
    decisions)
      # --since-approval: the decisions after the latest approval of the contract (T123), the ones a
      # Dev's plan may predate. With plan or fix ids (#705): after the latest approval that changed
      # one of their plans (a fix's are the plans of its requirement, or every plan for a project
      # command), the earliest of those, so an approval that left a plan as it was hides nothing
      # from its Dev. Every approval's decision starts "Contract approved" (lib/cmd-approve.sh,
      # lib/loop-step.sh) and names the plans it changed; one naming none changed every plan.
      local since="" ids='[]' unknown
      if [ $# -gt 0 ]; then
        [ "$1" = --since-approval ] || vbw_usage_error "usage: vbw show decisions [--since-approval [PLAN|FIX...]]"
        since=yes
        shift
        ids=$(jq -nc '$ARGS.positional' --args "$@")
        printf '%s' "$record" | jq -e 'any(.decisions[]; .text | startswith("Contract approved"))' > /dev/null \
          || vbw_die "the contract has not been approved yet: no decision follows an approval"
        unknown=$(printf '%s' "$record" | jq -r --argjson ids "$ids" '$ids - [.plans[].id, .fixes[].id] | join(", ")')
        [ -z "$unknown" ] || vbw_die "no plan or fix $unknown (vbw show roadmap)"
      fi
      printf '%s' "$record" | jq -r --arg since "$since" --argjson ids "$ids" '
        def line: "\(.id) \(.text)\(if .why then " (why: \(.why))" else "" end)";
        def approval: .text | startswith("Contract approved");
        if $since == "" then
          if (.decisions | length) == 0 then "no decisions recorded yet (vbw decide TEXT [WHY])" else .decisions[] | line end
        else
          . as $r
          | [.decisions | to_entries[] | select(.value | approval)] as $apps
          | [$ids[] as $i | if any($r.plans[]; .id == $i) then $i
              else $r.fixes[] | select(.id == $i)
                | if has("req") then .req as $q | $r.plans[] | select(.reqs | index($q)) | .id else $r.plans[].id end end] as $plans
          | (if ($plans | length) == 0 then $apps[-1].key
             else [$plans[] as $p | ([$apps[] | select((.value | has("plans") | not) or (.value.plans | index($p)))][-1].key // $apps[0].key)] | min end) as $a
          | [.decisions[$a + 1:][] | select(approval | not)] as $after
          | if ($after | length) == 0 then "no decisions since the contract was approved (\(.decisions[$a].id))"
            else $after[] | line end
        end'
      ;;
    evidence)
      # The unit-time block follows the own-work line (unittime.sh): every current unit as it last ran.
      # shellcheck source=unittime.sh
      . "$VBW_LIB/unittime.sh"
      # shellcheck source=delivered.sh
      . "$VBW_LIB/delivered.sh"
      printf '%s' "$record" | jq -r --argjson cb "$VBW_CHECK_BUDGET" "$UNITTIME_DEFS$DELIVERED_DEFS"'
        (.settings.check_budget // $cb) as $budget
        | if .evidence == null then "no proof run yet (vbw prove)" else .evidence
        | "proof run \(.at): \(if .passed then "passed" else "FAILED" end) (contract \(.contract[0:12]))",
          (if .own == null then "  own work: not recorded" else
             def s: (. * 100 | round) as $n | "\($n / 100 | floor).\(($n % 100) | tostring | if length < 2 then "0" + . else . end)";
             .own as $o | "  own work: \(($o.planning + $o.copies + $o.tracking + $o.saving + $o.record) | s) of \($o.wall | s) s: planning \($o.planning | s), copies \($o.copies | s), read tracking \($o.tracking | s), saving \($o.saving | s), record \($o.record | s)" end),
          evidence_block($budget),
          ((.checks + (.commands | map_values(select(.of_files | not))) + (.test_files // {})) | to_entries[]
            | "  \(.key) \(.value.status)\(if .value.exit != null then " exit \(.value.exit)" else "" end) \(.value.seconds | sec)s\(if .value.reused then " reused (proof of \(.value.at))" elif (.value.why // "") != "" then " ran: \(.value.why)" else " not recorded" end)",
              (.value.tail | select(length > 0) | split("\n")[] | "    | " + .)),
          (.scope[] | "  scope: " + .),
          ((.undone // [])[] | "  scope: \(.commit[0:12]) (\(.plan)) undone by \(.by[0:12]), not judged"),
          ((.deviations // [])[] | "  delivered: \(deviation_line): QA judges it")
        end'
      ;;
  esac
}

# show_costs [--json | --ceiling USD]: what each milestone and run cost (R173; docs/costs.md).
# What VBW did not see prints as unknown with the remedy, never as a guess and never as $0.00.
show_costs() {
  local mode=text ceiling='' ids m totals='{}' t doc
  case "${1:-}" in
    '') [ $# -eq 0 ] || vbw_usage_error "usage: vbw show costs [--json | --ceiling USD]" ;;
    --json) [ $# -eq 1 ] || vbw_usage_error "usage: vbw show costs [--json | --ceiling USD]"; mode=json ;;
    --ceiling)
      [ $# -eq 2 ] || vbw_usage_error "usage: vbw show costs --ceiling USD"
      printf '%s' "$2" | grep -E '^([0-9]+[.]?[0-9]*|[.][0-9]+)$' > /dev/null \
        && jq -ne --argjson c "$2" '$c > 0' > /dev/null 2>&1 \
        || vbw_usage_error "the ceiling must be a positive number of dollars (vbw show costs --ceiling USD)"
      mode=ceiling; ceiling=$2 ;;
    *) vbw_usage_error "usage: vbw show costs [--json | --ceiling USD]" ;;
  esac
  # shellcheck source=costs.sh
  . "$VBW_LIB/costs.sh"
  ids=$(jq -r '[(.shipped[].id), ((.parked // [])[].id), .milestone.id] | unique[]' "$VBW_RECORD")
  for m in $ids; do
    t=$(costs_milestone_total "$VBW_RECORD" "$m")
    totals=$(printf '%s' "$totals" | jq -c --arg m "$m" --argjson t "$t" '.[$m] = $t')
  done
  doc=$(jq -c --argjson totals "$totals" --arg remedy "$(costs_remedy)" '
    . as $r
    | ([.shipped[] | {id, title, status: "shipped"}] + [(.parked // [])[] | {id, title, status: "parked"}]
       + (if any(.shipped[], (.parked // [])[]; .id == $r.milestone.id) then [] else [{id: .milestone.id, title: .milestone.title, status: .milestone.status}] end)
       | map(. + ($totals[.id] // null | {usd: (.usd // null), sessions: (.sessions // 0)}))) as $ms
    | {milestones: $ms,
       runs: [(.costs.runs // [])[] | {id, kind, milestone, session: (.session // null), started, ended, cost: (if .cost == null then null else {usd: .cost.usd} end)}],
       remedy: $remedy}
    | .unknown = {runs: [.runs[] | select(.cost == null) | .id], milestones: [.milestones[] | select(.usd == null) | .id]}' "$VBW_RECORD")
  case "$mode" in
    json) printf '%s\n' "$doc" | jq '{milestones, runs, unknown, remedy}' ;;
    ceiling)
      t=$(printf '%s' "$doc" | jq -r --argjson c "$ceiling" --arg raw "$ceiling" --arg active "$(jq -r .milestone.id "$VBW_RECORD")" '
        def usd: ((. * 100 | round) as $n | "$\($n / 100 | floor).\(($n % 100) | tostring | if length < 2 then "0" + . else . end)");
        (.milestones[] | select(.id == $active)) as $m
        | if $m.usd == null then "cannot tell: no figure was seen for \($active) (\(.remedy))"
          elif $m.usd >= $c then "reached: \($m.usd | usd) spent of a $\($raw) ceiling (\($active))"
          else "under: \($m.usd | usd) spent of a $\($raw) ceiling (\($active))" end' ) || vbw_die "cannot read the costs"
      printf '%s\n' "$t"
      [ "${t%%:*}" = under ] ;;
    text)
      printf '%s' "$doc" | jq -r '
        def usd: ((. * 100 | round) as $n | "$\($n / 100 | floor).\(($n % 100) | tostring | if length < 2 then "0" + . else . end)");
        (.milestones[] | "\(.id) \(.title) (\(.status)): "
          + (if .usd == null then "unknown" else "\(.usd | usd), \(.sessions) session\(if .sessions == 1 then "" else "s" end) seen" end)),
        (if (.runs | length) > 0 then "runs:", (.runs[] | "  \(.id): \(if .cost == null then "unknown" else .cost.usd | usd end) (\(.milestone))") else empty end),
        (if (.unknown.runs | length) + (.unknown.milestones | length) > 0 then "unknown means VBW did not see the figures: " + .remedy else empty end)'
      ;;
  esac
}

# What changed in the contract since the last approval in this clone.
show_contract_changes() {
  local before="$VBW_RUNTIME/approved-contract.json"
  if [ ! -f "$before" ]; then
    printf 'no earlier approval in this clone: the whole contract is new (vbw show contract)\n'
    return 0
  fi
  local lines line f want h c diff g rel
  lines=$(contract_doc "$1" | jq -r --slurpfile old "$before" "$SHOW_JQ_DEFS"'
    . as $new | $old[0] as $old
    | [ ($new.requirements | to_entries[] | select($old.requirements[.key] == null)
          | "added requirement \(.key) [\(.value.proof)] \(.value.text)"),
        ($old.requirements | to_entries[] | select($new.requirements[.key] == null)
          | "removed requirement \(.key): \(.value.text)"),
        ($new.requirements | to_entries[] | select($old.requirements[.key] != null and ($old.requirements[.key] | del(.rules)) != (.value | del(.rules)))
          | "changed requirement \(.key): [\($old.requirements[.key].proof)] \($old.requirements[.key].text) -> [\(.value.proof)] \(.value.text)"),
        # Rules by address (T168): a rule is found again by its words wherever it now
        # stands (moved, retired, re-pointed); new words in the place of words that are
        # gone are a reworded rule; what is left was added or removed.
        ($new.requirements | to_entries[] | select($old.requirements[.key] != null) | .key as $q
          | ($old.requirements[$q].rules // []) as $o | (.value.rules // []) as $n
          | def at($l; $t): first($l | to_entries[] | select(.value.text == $t) | .key) // null;
            def retiring($w; $v): if ($v | has("retired")) and ($w | has("retired") | not) then $v.retired else null end;
            ($n | to_entries[] | .key as $k | .value as $v | at($o; $v.text) as $j
              | if $j == null then
                  $o[$k] as $w
                  | if $w != null and at($n; $w.text) == null
                    then "reworded rule \($q).\($k + 1): \($w.text) -> \($v.text)"
                      + (if $w.check != $v.check then " (check \($v.check), was \($w.check))" else "" end)
                      + (retiring($w; $v) | if . then ", retired (\(.))" else "" end)
                    else "added rule \($q).\($k + 1): \($v.text) -> \($v.check)" end
                else $o[$j] as $w
                  | (if $j != $k then "moved rule \($q).\($k + 1): \($v.text) (was \($q).\($j + 1))" else empty end),
                    (retiring($w; $v) | if . then "retired rule \($q).\($k + 1): \($v.text) (\(.))" else empty end),
                    (if $w.check != $v.check then "changed rule \($q).\($k + 1): \($v.text) -> \($v.check) (was \($w.check))" else empty end),
                    (if ($w.plan // null) != ($v.plan // null) then "changed rule \($q).\($k + 1): \($v.text) -> plan \($v.plan // "none") (was \($w.plan // "none"))" else empty end)
                end),
            ($o | to_entries[] | .key as $j | .value as $w | select(at($n; $w.text) == null)
              | select($n[$j] == null or at($o; $n[$j].text) != null)
              | "removed rule \($q).\($j + 1): \($w.text)")),
        ($new.checks | to_entries[] | select($old.checks[.key] == null)
          | "added check \(.key) (\(.value.req)): " + (.value | check_line)),
        ($old.checks | to_entries[] | select($new.checks[.key] == null)
          | "removed check \(.key) (\(.value.req))"),
        ($new.checks | to_entries[] | select($old.checks[.key] != null and $old.checks[.key] != .value)
          | "changed check \(.key) (\(.value.req)): " + (.value | check_line)
            + (if ($old.checks[.key].alone // false) and (.value.alone | not) then " [no longer alone]" else "" end)),
        ($new.files | to_entries[] | select($old.files[.key] != null and $old.files[.key] != .value)
          | "changed test file \(.key)"),
        ($new.plans | to_entries[] | select($old.plans[.key] == null)
          | "added plan \(.key) \(.value.title): \(.value.files | join(", "))"),
        ($old.plans | to_entries[] | select($new.plans[.key] == null)
          | "removed plan \(.key) \(.value.title)"),
        ($new.plans | to_entries[] | select($old.plans[.key] != null and $old.plans[.key] != .value)
          | "changed plan \(.key) \(.value.title): \(.value.files | join(", "))\(if (.value.after | length) > 0 then " (after \(.value.after | join(", ")))" else "" end)"),
        # Snapshots taken before commands were part of it list none.
        ($old | select(has("commands")) | .commands as $oc
          | ($new.commands | to_entries[] | select($oc[.key] != .value)
              | "\(if $oc[.key] == null then "added" else "changed" end) project command \(.key): \(.value | argv_line)"),
            ($oc | keys[] | select(. as $k | $new.commands | has($k) | not) | "removed project command \(.)")),
        (select(($old.test_files // null) != ($new.test_files // null))
          | "test file form: \(($new.test_files // null) | if . == null then "none" else "\(.run | join(" ")) (files \(.files | join(" ")))" end)"),
        (select($old.results != $new.results)
          | "saved test results folders: \(($new.results // []) | if length == 0 then "none" else join(", ") end) (was \(($old.results // []) | if length == 0 then "none" else join(", ") end))"),
        (select(($old.leave_out // []) != ($new.leave_out // []))
          | "clean copy leaves out: \(($new.leave_out // []) | if length == 0 then "none" else join(", ") end) (was \(($old.leave_out // []) | if length == 0 then "none" else join(", ") end))") ]
    | if length == 0 then "no changes since the last approval" else "changes since the last approval:", (.[] | "  " + .) end')
  # Under each changed test file: the whole diff between the approved content
  # (found by hash in the file's git history) and the file as it is now.
  while IFS= read -r line; do
    printf '%s\n' "$line"
    case "$line" in
      "  changed test file "*) ;;
      *) continue ;;
    esac
    f=${line#"  changed test file "}
    want=$(jq -r --arg f "$f" '.files[$f]' "$before")
    # In the repository that tracks it (a submodule's file in the submodule).
    vbw_repos "$f"
    g="$VBW_ROOT${VBW_REPO_OF[0]:+/${VBW_REPO_OF[0]}}"
    rel=$(vbw_rel "${VBW_REPO_OF[0]}" "$f")
    c=
    for h in $(git -C "$g" log --format=%H -- "$rel" 2> /dev/null); do
      if [ "$(git -C "$g" show "$h:$rel" 2> /dev/null | vbw_sha256)" = "$want" ]; then
        c=$h
        break
      fi
    done
    if [ -z "$c" ]; then
      printf "    the approved content of %s is not in the project's git history, so no diff can be shown\n" "$f"
    else
      diff=$(git -C "$g" -c color.ui=never diff --no-ext-diff "$c" -- "$rel")
      printf '%s\n' "$diff" | sed 's/^/    /'
    fi
  done <<< "$lines"
}

# jq helpers for rendering checks. An argv is shown shell-quoted where needed.
# shellcheck disable=SC2016 # jq text, not shell
SHOW_JQ_DEFS='
# The status of a phase is derived from its plans, never stored.
def phase_status($r): .id as $id | [$r.plans[] | select(.phase == $id) | .status] as $s
  | if ($s | length) > 0 and all($s[]; . == "done") then "built"
    elif any($s[]; . != "planned") then "building" else "planned" end;
def argv_line: map(if test("^[A-Za-z0-9_./:=@%+-]+$") then . else @sh end) | join(" ");
# A rule is shown by its address Rn.k, its place among the requirement'"'"'s rules (T168).
def rule_lines: if .proof == "auto" then .id as $q |
    (if (.rules // []) | length == 0 then "rules not listed" else (.rules | to_entries[]
      | if .value | has("retired") then "rule \($q).\(.key + 1) retired: \(.value.text) (\(.value.retired))"
        else "rule \($q).\(.key + 1): \(.value.text) -> \(.value.check)" end) end)
  else empty end;
def check_line: (.run | argv_line)
  + (if (.exit // 0) != 0 then " (exit \(.exit))" else "" end)
  + (if .output then " (output ~ /\(.output)/)" else "" end)
  + (if .files then " [protects \(.files | join(", "))]" else "" end)
  + (if .alone then " [alone]" else "" end);
'

# Commits of the record's own history (lib/history.sh) whose VBW-Req trailer
# lists REQ as an exact token (not a substring: R1 must not match R12). An older
# commit naming the same id is an old roadmap's, not this requirement's. The
# project's commits first, then each submodule's (history_repos), "(in SUB)" after each.
show_commits_for_req() {
  local req="$1" line subject reqs r q HISTORY_ARGS=() HISTORY_REPOS=()
  # shellcheck source=history.sh
  . "$VBW_LIB/history.sh"
  history_repos
  for q in "${HISTORY_REPOS[@]}"; do
    history_args_in "$q"
    while IFS= read -r line; do
      subject=${line%%$'\x1f'*}
      reqs=${line#*$'\x1f'}
      for r in $(printf '%s' "$reqs" | tr ',' ' '); do
        [ "$r" = "$req" ] && { vbw_out '  %s%s\n' "$subject" "${q:+ (in $q)}"; break; }
      done
    done < <(git -C "$VBW_ROOT${q:+/$q}" log --format='%h %s%x1f%(trailers:key=VBW-Req,valueonly,separator=%x2C)' "${HISTORY_ARGS[@]}" 2>/dev/null)
  done
}

# show_work RECORD plan|fix ID [--json]: what a Dev needs, and nothing else.
show_work() {
  # A fix names the kept output of each failing check and project command
  # (R118): its path when the file exists, else null.
  local json dir='' have='[]' names='{}' fids='{}' f
  if [ "$2" = fix ]; then
    # shellcheck source=checks.sh
    . "$VBW_LIB/checks.sh"
    # shellcheck source=testfiles.sh
    . "$VBW_LIB/testfiles.sh"
    # A test file's kept file is named by its path's id, which the evidence does not carry.
    while IFS= read -r -d '' f; do
      fids=$(printf '%s' "$fids" | jq -c --arg p "$f" --arg i "$(testfiles_id "$f")" '.[$p] = $i')
    done < <(printf '%s' "$1" | jq -j '(.evidence.test_files // {}) | keys[] + "\u0000"')
    dir=$(checks_kept check _)
    dir=${dir%/*}
    if [ -d "$VBW_ROOT/$dir" ]; then
      have=$(find "$VBW_ROOT/$dir" -maxdepth 1 -type f -name '*.log' -print0 \
        | jq -Rsc 'split("\u0000") | map(select(length > 0) | sub("^.*/"; ""))')
      # The failing test names are read here and nowhere else (R195.9).
      for f in $(printf '%s' "$have" | jq -r '.[]'); do
        names=$(printf '%s' "$names" | jq -c --arg f "$f" --argjson n "$(jq -Rs -c -f "$VBW_LIB/failing-tests.jq" < "$VBW_ROOT/$dir/$f")" '.[$f] = $n')
      done
    fi
  fi
  json=$(printf '%s' "$1" | jq -c --arg kind "$2" --arg id "$3" --arg dir "$dir" --argjson have "$have" --argjson names "$names" --argjson fids "$fids" "$VBW_JQ_DEFS"'
    . as $r
    | def kept($file): if any($have[]; . == $file) then "\($dir)/\($file)" else null end;
      def tests($file): $names[$file] // [];
      def failing: . != null and .status != "pass";
      # A skipped command was not approved: vbw prove counts it as passed (R118).
      def command_failing: .status == "fail" or .status == "timeout";
      def checks_for($reqs): [$r.checks[] | select(.req as $q | any($reqs[]; . == $q))
        | . + {last: ($r.evidence.checks[.id] // null)}];
      if $kind == "plan" then
        [.plans[] | select(.id == $id)][0] as $p
        | if $p == null then null else
          # A retired rule (T168) is not the plan'"'"'s: it is left out, the others keep their addresses.
          [$p.reqs[] as $q | $r.requirements[] | select(.id == $q and .proof == "auto") | (.rules // []) | to_entries[]
             | select(.value | has("retired") | not)
             | {n: "\($q).\(.key + 1)", text: .value.text, check: .value.check, plan: (.value.plan // null), q: $q, k: (.key + 1)}
             | . as $x | ($r | own_rules($p.id)) as $own
             | . + {own: (.plan == null or any($own[]; .req == $x.q and .n == $x.k))}
             | if .own then . else
                 ([$r.plans[] | select(.id == $x.plan)][0].status // "open") as $qs
                 | . + {order: (if $qs == "done" then "done" elif $qs == "blocked" then "blocked"
                     elif $p.status == "done" or $p.status == "blocked" then "after"
                     else ($r | waves([$r.phases[] | select(.id == $p.phase)][0].milestone)) as $w
                       | ([$w | to_entries[] | select(any(.value[]; . == $p.id)) | .key][0]) as $mine
                       | ([$w | to_entries[] | select(any(.value[]; . == $x.plan)) | .key][0]) as $theirs
                       | if $theirs == null or $mine == null or $theirs > $mine then "after"
                         elif $theirs < $mine then "before" else "beside" end end)} end
             | del(.q, .k)] as $rl
          | {plan: $p,
           requirements: [$p.reqs[] as $q | $r.requirements[] | select(.id == $q) | {id, text, proof,
             other_open_plans: [$r.plans[] | select(.id != $p.id and .status != "done" and any(.reqs[]; . == $q)) | .id]}],
           rules: $rl,
           tier: ([$r.phases[] | select(.id == $p.phase)][0].tier // null),
           checks: (checks_for($p.reqs) | map(.id as $c
             | ([$rl[] | select(.check == $c)]) as $pts
             | . + {own: (($pts | length) == 0 or any($pts[]; .own))}
             | if .own then . else . + {plans: ([$pts[] | select(.own | not) | .plan] | unique)} end)),
           commands: $r.commands} end
      else
        [.fixes[] | select(.id == $id)][0] as $f
        | if $f == null then null else
          {fix: $f,
           requirement: (if $f.req then [$r.requirements[] | select(.id == $f.req) | {id, text, proof}][0] else null end),
           checks: (if $f.req then checks_for([$f.req]) else [] end
             | map(. + {kept: (if .last | failing then kept("\(.id).log") else null end)}
                 | . + {failing_tests: (if .kept then tests("\(.id).log") else [] end)})),
           command: (if $f.command then {name: $f.command, argv: $r.commands[$f.command],
                                          last: ($r.evidence.commands[$f.command] // null)} else null end),
           commands: [($r.evidence.commands // {}) | to_entries[] | select(.value | command_failing)
             | {name: .key, status: .value.status, kept: kept("command-\(.key).log")}
             | . + {failing_tests: (if .kept then tests("command-\(.name).log") else [] end)}],
           test_files: [($r.evidence.test_files // {}) | to_entries[] | select(.value | command_failing)
             | "file-\($fids[.key] // "").log" as $file
             | {path: .key, status: .value.status, kept: kept($file)}
             | . + {failing_tests: (if .kept then tests($file) else [] end)}],
           plans: [$r.plans[] | select($f.req != null and any(.reqs[]; . == $f.req)) | {id, title, files}]} end
      end')
  [ "$json" != null ] || vbw_die "unknown $2 $3"
  if [ "${4:-}" = --json ]; then
    printf '%s\n' "$json"
    return 0
  fi
  printf '%s' "$json" | jq -r "$SHOW_JQ_DEFS"'
    def check_lines: .checks[] | "  \(.id) (\(.req)) " + check_line
      + (if .last then " — last: \(.last.status)" else "" end)
      + (if .own == false then " [\(.plans | map(. + "\u0027s") | join(" and ")): red until it is built, not this plan\u0027s to pass]" else "" end);
    def full_output: if .kept then "    full output: \(.kept)",
        (if (.failing_tests | length) > 0 then "    failing tests:", (.failing_tests[] | "      " + .)
         else "    failing tests: none recognised in the output; read the full output file" end)
      else "    full output not kept: run vbw prove again" end;
    if .plan then
      .rules as $rules |
      "\(.plan.id) \(.plan.title) [\(.plan.status)]\(if .plan.note then ": " + .plan.note else "" end)",
      "files: \(.plan.files | join(", "))",
      (if .plan.tasks then "tasks:", (.plan.tasks | to_entries[] | "  \(.key + 1). \(.value)") else empty end),
      (if (.plan.after | length) > 0 then "after: \(.plan.after | join(", "))" else empty end),
      "requirements:", (.requirements[] | "  \(.id) [\(.proof)] \(.text)"),
      (if (.rules | length) > 0 then "rules:", (.rules[] | "  \(.n) \(.text) -> \(.check)"
        + (if .own then "" else " [\(.plan)\u0027s, \({done: "done", blocked: "blocked", before: "built before this plan", after: "built after this plan", beside: "built beside this plan"}[.order])]" end)) else empty end),
      (if .tier == "standard" then "tier: standard (the mutation check asks one break per rule)"
       elif .tier == "deep" then "tier: deep (the mutation check asks one break per rule, plus one per task no rule covers)"
       elif .tier then "tier: \(.tier)" else empty end),
      "checks:", check_lines,
      (def tname: if .rule then (.rule.req as $q | .rule.text as $t | ($rules | map(select(.text == $t and (.n | startswith($q + "."))))[0].n // $q)) else "task\(.task)" end;
       if (.plan.mutations // [] | length) > 0 then "mutations:",
         (.plan.mutations as $ms | $ms | to_entries[] | .key as $i | .value as $e | $e | if .none then (if .rule then "  \(tname): no code could change its outcome: \(.none)" else "  task\(.task): no testable behaviour: \(.none)" end)
           else (if .pending then
               "  \(tname) \(if ([$ms[:$i][] | select(.result == "survivor" and .head != $e.head and (if $e.rule then .rule == $e.rule else .task == $e.task end)
                    and ((($e.checks | to_entries | map(select(.value == "red") | .key)) - (.checks | keys)) | length == 0))] | length) > 0
                 then "survives the approved check; caught by the pending one" else "caught by a check file waiting for approval" end): \(.pending | join(", ")) (\(.what))"
             else "  \(tname): \(.what): \(.result)"
               + (if .strengthened then " (strengthened: \(.strengthened | join(", ")))" else "" end) end),
             (.checks | to_entries[] | "    \(.key): \(.value)") end) else empty end)
    else
      "\(.fix.id) [\(.fix.status), attempts \(.fix.attempts)]: \(.fix.note)",
      (if .requirement then "requirement: \(.requirement.id) \(.requirement.text)" else empty end),
      (if .command then "command \(.command.name): \(.command.argv | argv_line)\(if .command.last then " — last: \(.command.last.status)" else "" end)",
         (.command.last.tail // "" | select(length > 0) | split("\n")[] | "    | " + .),
         (.command.name as $n | .commands[] | select(.name == $n) | full_output) else empty end),
      (if (.checks | length) > 0 then "checks:", check_lines else empty end),
      (.checks[] | select(.last and .last.status != "pass")
        | (.last.tail | select(length > 0) | split("\n")[] | "    | " + .), full_output),
      ((.command.name // null) as $n | [.commands[] | select(.name != $n)]
        | if length > 0 then "failing project commands:", (.[] | "  \(.name) — last: \(.status)", full_output) else empty end),
      (if (.test_files | length) > 0 then "failing test files:", (.test_files[] | "  \(.path) — last: \(.status)", full_output) else empty end),
      (if (.plans | length) > 0 then "files (plans serving the requirement):", (.plans[] | "  \(.id): \(.files | join(", "))") else empty end)
    end'
}
