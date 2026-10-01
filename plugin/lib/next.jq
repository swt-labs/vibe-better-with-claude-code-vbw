# vbw next: the lifecycle decision table (docs/next.md). Input: a valid record.
# Args: $approved (the current contract hash has consent), $contract (that hash),
# $code_changed (the project differs from the commit the evidence proved), $legacy (a
# VBW 1 plan, .vbw-planning/, is not converted yet).
# Output: {action, gate, instruction, detail}. First matching row wins.

def result($action; $gate; $instruction; $detail):
  {action: $action, gate: $gate, instruction: $instruction, detail: $detail};

# Builders share one working tree, so work that touches the same file never runs
# at the same time. "*" stands for any file.
def overlaps($a; $b): any($a[], $b[]; . == "*") or any($a[]; . as $x | any($b[]; . == $x));

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
# Open fixes that share files form one group, worked by one builder.
| ([.fixes[] | select(.status == "open")]
   | reduce .[] as $f ([]; ($f | fix_files($r)) as $ff
       | map(select(overlaps(.files; $ff))) as $hit
       | map(select(overlaps(.files; $ff) | not))
         + [{ids: ([$hit[].ids[]] + [$f.id]), files: ([$hit[].files[]] + $ff | unique)}])
   | map(.ids)) as $fix_groups
| (.evidence == null or .evidence.contract != $contract or $code_changed) as $stale
| ([.requirements[] | select(.proof == "auto" and (.status != "proven" or $stale)) | .id]) as $unproven
| ([$current[] | select(.proof == "human" and .status == "open") | .id]) as $to_accept
| if .lease != null then
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
    result("plan"; false; "Run the plan workflow: phases, plans and contract checks"; {})
  elif $approved | not then
    result("approve"; true; "Review and approve the contract (requirements, plans and checks)"; {})
  elif ($blocked | length) > 0 then
    result("unblock"; true; "Resolve the blocker reported for \($blocked | join(", "))"; {plans: $blocked})
  elif ($ready | length) > 0 then
    result("build"; false; "Run the build workflow for \($ready | join(", "))"; {plans: $ready})
  elif ($escalated | length) > 0 then
    result("escalate"; true; "The fix cap was reached for \($escalated | join(", ")): decide how to proceed"; {fixes: $escalated})
  elif ($stale | not) and (.evidence.scope | length) > 0 then
    result("scope"; true; "Commits changed files outside their plans: review them (vbw show evidence)"; {violations: .evidence.scope})
  elif ($open_fixes | length) > 0 then
    result("fix"; false; "Run the fix workflow for \($open_fixes | join(", "))"; {fixes: $open_fixes, groups: $fix_groups})
  elif ($unproven | length) > 0 then
    result("prove"; false; "Run vbw prove for \($unproven | join(", "))"; {requirements: $unproven})
  elif ($to_accept | length) > 0 then
    result("accept"; true; "Accept or reject \($to_accept | join(", ")), one scenario at a time"; {requirements: $to_accept})
  else
    result("ship"; true; "Everything is proven and accepted: ship milestone \(.milestone.id)"; {})
  end
