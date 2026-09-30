# vbw next: the lifecycle decision table (docs/next.md). Input: a valid record.
# Args: $approved (the current contract hash has consent), $contract (that hash).
# Output: {action, gate, instruction, detail}. First matching row wins.

def result($action; $gate; $instruction; $detail):
  {action: $action, gate: $gate, instruction: $instruction, detail: $detail};

(.plans | map(select(.status == "done") | .id)) as $done
| ([.plans[] | select(.status != "done" and .status != "blocked")
             | select(all((.after // [])[]; . as $a | any($done[]; . == $a)))
             | .id]) as $ready
| ([.plans[] | select(.status == "blocked") | .id]) as $blocked
| ([.fixes[] | select(.status == "escalated") | .id]) as $escalated
| ([.fixes[] | select(.status == "open") | .id]) as $open_fixes
| (.evidence == null or .evidence.contract != $contract) as $stale
| ([.requirements[] | select(.proof == "auto" and (.status != "proven" or $stale)) | .id]) as $unproven
| ([.requirements[] | select(.proof == "human" and .status == "open") | .id]) as $to_accept
| ([.requirements[] | select(.proof == "human" and .status == "rejected") | .id]) as $rejected
| if .milestone.status == "shipped" then
    result("milestone"; true; "Milestone \(.milestone.id) is shipped: start the next milestone"; {})
  elif (.requirements | length) == 0 then
    result("spec"; true; "Write the goals and requirements in .vbw/spec.md"; {})
  elif (.phases | length) == 0 or (.checks as $c | any(.requirements[]; .proof == "auto" and (.id as $id | any($c[]; .req == $id) | not))) then
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
    result("fix"; false; "Run the fix workflow for \($open_fixes | join(", "))"; {fixes: $open_fixes})
  elif ($unproven | length) > 0 then
    result("prove"; false; "Run vbw prove for \($unproven | join(", "))"; {requirements: $unproven})
  elif ($to_accept | length) > 0 then
    result("accept"; true; "Accept or reject \($to_accept | join(", ")), one scenario at a time"; {requirements: $to_accept})
  elif ($rejected | length) > 0 then
    result("fix"; false; "Turn the rejection of \($rejected | join(", ")) into a fix"; {requirements: $rejected})
  else
    result("ship"; true; "Everything is proven and accepted: ship milestone \(.milestone.id)"; {})
  end
