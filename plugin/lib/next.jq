# vbw next: the lifecycle decision table (docs/next.md). Input: a valid record.
# Args: $approved (the current contract hash has consent), $contract (that hash),
# $code_changed (the project differs from the commit the evidence proved), $legacy (a
# VBW 1 plan, .vbw-planning/, is not converted yet), $session (the caller's session, "" when unknown).
# $waiting: the check files edited since the approval, newline-separated ("" when none).
# $tracked (the number of files git tracks, for the early tier).
# $profile: interview_effective (lib/interview.sh); next fills unanswered ones with the neutral middle choice.
# $tiers (slurped: [table]; lib/tiers.json: profile -> tier -> cell).
# Output: {action, gate, instruction, detail, requirements (the active milestone's: id, text, proof), rigor, profile}; profile.ask is true only
# at the spec or convert step with no completed interview (once per project).
# First matching row wins.

def result($action; $gate; $instruction; $detail):
  {action: $action, gate: $gate, instruction: $instruction, detail: $detail};

# QA ranks, lowest first.
def qa_rank: {quick: 0, standard: 1, deep: 2}[.];

# Builders share one working tree, so work that touches the same file never runs
# at the same time. "*" stands for any file.
# A plan file entry covers PATH: the same path, or a directory entry (ending
# in /) with PATH under it. Two file lists overlap when either covers the other.
def covers($p): . as $e | $e == $p or (($e | endswith("/")) and ($p | startswith($e)));
def overlaps($a; $b): any($a[], $b[]; . == "*")
  or any($a[]; . as $x | any($b[]; . as $y | ($x | covers($y)) or ($y | covers($x))));

# The files a fix may touch (as in vbw run start fix): the files of the plans
# serving its requirement; any file for a project command.
def fix_files($r): if .command then ["*"]
  else (.req as $q | [$r.plans[] | select(any(.reqs[]; . == $q)) | .files[]] | unique)
       | if length == 0 then ["*"] else . end end;

.milestone.id as $m
| ([.requirements[] | select(.milestone == null) | .id]) as $unassigned
| (if ($unassigned | length) > 0 then error("requirements with no milestone: \($unassigned | join(", "))") else . end)
| [.requirements[] | select(.milestone == $m)] as $current
| (.plans | map(select(.status == "done") | .id)) as $done
| . as $r
| ([.plans[] | select(.status != "done" and .status != "blocked")
             | select(all((.after // [])[]; . as $a | any($done[]; . == $a)))]
   | reduce .[] as $p ({ids: [], files: []};
       if overlaps(.files; $p.files) then . else .ids += [$p.id] | .files += $p.files end)
   | .ids) as $ready
| ([.plans[] | select(.status == "blocked") | .id]) as $blocked
| ([.plans[] | select(.status == "blocked") | {id, note: (.note // "")}]) as $blocked_why
| ($blocked_why | map(if .note == "" then .id else "\(.id) (\(.note))" end) | join(", ")) as $blocked_text
| ([.fixes[] | select(.status == "escalated") | .id]) as $escalated
| ([.fixes[] | select(.status == "open") | .id]) as $open_fixes
# Open fixes that share files form one group, worked by one Dev.
| ([.fixes[] | select(.status == "open")]
   | reduce .[] as $f ([]; ($f | fix_files($r)) as $ff
       | map(select(overlaps(.files; $ff))) as $hit
       | map(select(overlaps(.files; $ff) | not))
         + [{ids: ([$hit[].ids[]] + [$f.id]), files: ([$hit[].files[]] + $ff | unique)}])
   | map(.ids)) as $fix_groups
| (.evidence == null or .evidence.contract != $contract or $code_changed) as $stale
| ([.requirements[] | select(.proof == "auto" and (.status != "proven" or $stale)) | .id]) as $unproven
| ([$current[] | select(.proof == "human" and .status == "open") | .id]) as $to_accept
# Rigor: each current phase's tier (standard when it has none) with its cell of
# the profile (lib/tiers.json); the user's model overrides win over the cell's.
| ((.settings.models // {}) | {dev, qa} | with_entries(select(.value != null))) as $override
| ([.phases[] | select(.milestone == $m) | . as $ph | ($ph.tier // "standard") as $t
    | {key: $ph.id, value: ({tier: $t} + $tiers[0][$r.settings.profile][$t] | .models += $override | .models |= (if ((.qa // "" | ascii_downcase | contains("haiku"))) then .qa = "sonnet" else . end))}]
   | from_entries) as $rigor
# Built phases QA must check again (VBW 1's QA mandate; lib/qa.jq): failed,
# never passed, their inputs changed, or building on a phase that was. A built phase needs QA
# unless it is express with only [auto] requirements and no escalations.
| ([.phases[] | select(.milestone == $m and $qa.recheck[.id] != null and needs_qa($rigor[.id].tier; $current)) | .id]) as $to_verify
# The QA tier is the highest among the phases to verify.
| ([$to_verify[] | $rigor[.].qa] | max_by(qa_rank) // "standard") as $tier
# QA depth by the size and risk of the change (R71): at most two files and no risk
# path is quick; three to nine files and no risk at most standard; else the cell's.
# A phase with no recorded reasons is not small.
| (. as $rec | [$to_verify[] | . as $id | ($rec.phases[] | select(.id == $id)) as $ph
    | ($rec.plans | map(select(.phase == $id) | .files // []) | add // [] | unique | length) as $nf
    | ($ph.reasons // []) as $why
    | $rigor[$id].qa as $cell
    | {key: $id, value: (if ($why | index("risk: none")) == null then $cell
        elif $nf <= 2 then "quick"
        elif $nf <= 9 then ([$cell, "standard"] | min_by(qa_rank))
        else $cell end)}] | from_entries) as $tiers_qa
| (if .lease != null and .lease.session != null and .lease.session != $session then
    result("run"; false; "A VBW \(.lease.kind) run (\(.lease.run)) belongs to another session: wait for it, or check vbw status"; {lease: .lease})
  elif .lease != null then
    result("run"; false; "A VBW \(.lease.kind) run (\(.lease.run)) is open: if its workflow is still running in this session, wait for it; otherwise run vbw run end"; {lease: .lease})
  elif .milestone.status == "shipped" then
    result("milestone"; true; "Milestone \(.milestone.id) is shipped: start the next milestone (vbw milestone start TITLE)"; {})
  elif ($current | length) == 0 and $legacy then
    result("convert"; true; "This project has a VBW 1 plan (.vbw-planning/): bring it into VBW 2 (/vbw:convert), or start fresh"; {})
  elif ($current | length) == 0 then
    result("spec"; true; "Write the requirements for \(.milestone.id) \(.milestone.title) in .vbw/spec.md"; {})
  elif ([.phases[] | select(.milestone == $m)] | length) == 0
       or (. as $r | any(.requirements[]; .proof == "auto" and (.id as $id | any($r.checks[]; .req == $id) | not) and (doc_only($r) | not)))
       or (.plans as $p | any($current[]; .proof == "auto" and (.id as $id | any($p[]; any(.reqs[]; . == $id)) | not))) then
    result("plan"; false; "Run the plan workflow: phases, plans and contract checks"; {tier: early_tier($tracked), small: small_change})
  elif $approved | not then
    result("approve"; true; "Review and approve the contract (requirements, plans and checks)"; {})
  elif ($ready | length) > 0 then
    result("build"; false; "Run the build workflow for \($ready | join(", "))\(if ($blocked | length) > 0 then ". Blocked meanwhile, with their dependents waiting: \($blocked_text)" else "" end)"; {plans: $ready,
      docs: [.plans[] | select(.role == "docs" and (.id as $i | any($ready[]; . == $i))) | .id]}
      + (if ($blocked | length) > 0 then {blocked: $blocked_why} else {} end))
  elif ($blocked | length) > 0 then
    result("unblock"; true; "Resolve the blocker reported for \($blocked_text)"; {plans: $blocked, blocked: $blocked_why})
  elif ($escalated | length) > 0 then
    result("escalate"; true; "The fix cap was reached for \($escalated | join(", ")): decide how to proceed"; {fixes: $escalated})
  elif ($stale | not) and (.evidence.scope | length) > 0 then
    result("scope"; true; "Commits changed files outside their plans: review them (vbw show evidence)"; {violations: .evidence.scope})
  elif ($open_fixes | length) > 0 then
    result("fix"; false; "Run the fix workflow for \($open_fixes | join(", "))"; {fixes: $open_fixes, groups: $fix_groups})
  elif ($waiting | length) > 0 and ($unproven | length) > 0 then
    ([$waiting | split("\n")[] | select(length > 0)] | sort) as $wf
    | result("approve"; true; "Approve the test files edited since the approval, once, before they are proved: \($wf | join(", "))"; {files: $wf})
  elif ($unproven | length) > 0 then
    result("prove"; false; "Run vbw prove for \($unproven | join(", "))"; {requirements: $unproven})
  elif ($to_verify | length) > 0 then
    result("qa"; false; "Run the QA workflow (\($tier)) for \($to_verify | join(", ")): goal-backward verification of the built work. Checked again: \([$to_verify[] | "\(.) (\($qa.recheck[.] | join("; ")))"] | join(", "))\(if ($qa.standing | length) > 0 then ". Keeping their pass: \($qa.standing | join(", "))" else "" end)"; {phases: $to_verify, tier: $tier})
  elif ($to_accept | length) > 0 then
    result("accept"; true; "Accept or reject \($to_accept | join(", ")), one scenario at a time"; {requirements: $to_accept})
  else
    result("ship"; true; "Everything is proven and accepted: ship milestone \(.milestone.id)"; {})
  end) as $n | $n + (if $n.action == "qa" then {round: {tiers: $tiers_qa, suite: (if (.commands.test // null) == null then null else (.evidence.commands.test // {command: "test", status: "not run"}) end)}} else {} end) + {requirements: [$current[] | {id, text, proof}], rigor: $rigor, qa: ($qa | {recheck, standing, problems}), declined: [(.project.declined // [])[].text], profile: ({level: "small scripts or no-code", depth: "plain with technical terms explained", involvement: "options with a recommendation"} + ($profile | with_entries(select(.value != null or .key == "kept" or .key == "pending"))) + {ask: ([$n.action] | inside(["spec","convert"]) and ($profile.interviewed | not))})}
