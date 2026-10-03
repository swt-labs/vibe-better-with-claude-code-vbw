# vbw next: the lifecycle decision table (docs/next.md). Input: a valid record.
# Args: $approved (the current contract hash has consent), $contract (that hash),
# $code_changed (the project differs from the commit the evidence proved), $legacy (a
# VBW 1 plan, .vbw-planning/, is not converted yet), $session (the caller's session, "" when unknown).
# $tracked (the number of files git tracks, for the early tier).
# $tiers (slurped: [table]; lib/tiers.json: profile -> tier -> cell).
# Output: {action, gate, instruction, detail, rigor}. First matching row wins.

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
| [.requirements[] | select(.milestone == $m)] as $current
| (.plans | map(select(.status == "done") | .id)) as $done
| . as $r
| ([.plans[] | select(.status != "done" and .status != "blocked")
             | select(all((.after // [])[]; . as $a | any($done[]; . == $a)))]
   | reduce .[] as $p ({ids: [], files: []};
       if overlaps(.files; $p.files) then . else .ids += [$p.id] | .files += $p.files end)
   | .ids) as $ready
| ([.plans[] | select(.status == "blocked") | .id]) as $blocked
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
    | {key: $ph.id, value: ({tier: $t} + $tiers[0][$r.settings.profile][$t] | .models += $override)}]
   | from_entries) as $rigor
# Built phases QA has not verified on the proven code (VBW 1's QA mandate):
# never verified, failed, or the code changed since. A built phase needs QA
# unless it is express with only [auto] requirements and no escalations.
| ([.phases[] | select(.milestone == $m) | .id as $ph | . as $p
    | select([$r.plans[] | select(.phase == $ph)] | length > 0 and all(.[]; .status == "done"))
    | select(($rigor[$ph].tier != "express") or (($p.escalations // []) | length > 0)
             or any($p.reqs[]; . as $q | any($current[]; .id == $q and .proof == "human")))
    | select(.qa == null or .qa.result != "pass" or .qa.tree != ($r.evidence.tree // "")) | .id]) as $to_verify
# The QA tier is the highest among the phases to verify.
| ([$to_verify[] | $rigor[.].qa] | max_by(qa_rank) // "standard") as $tier
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
       or (.checks as $c | any(.requirements[]; .proof == "auto" and (.id as $id | any($c[]; .req == $id) | not)))
       or (.plans as $p | any($current[]; .proof == "auto" and (.id as $id | any($p[]; any(.reqs[]; . == $id)) | not))) then
    result("plan"; false; "Run the plan workflow: phases, plans and contract checks"; {tier: early_tier($tracked)})
  elif $approved | not then
    result("approve"; true; "Review and approve the contract (requirements, plans and checks)"; {})
  elif ($blocked | length) > 0 then
    result("unblock"; true; "Resolve the blocker reported for \($blocked | join(", "))"; {plans: $blocked})
  elif ($ready | length) > 0 then
    result("build"; false; "Run the build workflow for \($ready | join(", "))"; {plans: $ready,
      docs: [.plans[] | select(.role == "docs" and (.id as $i | any($ready[]; . == $i))) | .id]})
  elif ($escalated | length) > 0 then
    result("escalate"; true; "The fix cap was reached for \($escalated | join(", ")): decide how to proceed"; {fixes: $escalated})
  elif ($stale | not) and (.evidence.scope | length) > 0 then
    result("scope"; true; "Commits changed files outside their plans: review them (vbw show evidence)"; {violations: .evidence.scope})
  elif ($open_fixes | length) > 0 then
    result("fix"; false; "Run the fix workflow for \($open_fixes | join(", "))"; {fixes: $open_fixes, groups: $fix_groups})
  elif ($unproven | length) > 0 then
    result("prove"; false; "Run vbw prove for \($unproven | join(", "))"; {requirements: $unproven})
  elif ($to_verify | length) > 0 then
    result("qa"; false; "Run the QA workflow (\($tier)) for \($to_verify | join(", ")): goal-backward verification of the built work"; {phases: $to_verify, tier: $tier})
  elif ($to_accept | length) > 0 then
    result("accept"; true; "Accept or reject \($to_accept | join(", ")), one scenario at a time"; {requirements: $to_accept})
  else
    result("ship"; true; "Everything is proven and accepted: ship milestone \(.milestone.id)"; {})
  end) + {rigor: $rigor}
