# vbw next: the lifecycle decision table (docs/next.md). Input: a valid record.
# Args: $approved (the current contract hash has consent), $contract (that hash),
# $code_changed (the project differs from the commit the evidence proved), $legacy (a
# VBW 1 plan, .vbw-planning/, is not converted yet), $session (the caller's session, "" when unknown).
# $waiting: the check files edited since the approval, newline-separated ("" when none).
# $added_to: [{file, lines}], the check files that only had lines added since the approval (R269); carried as added_to when any.
# $problems: why the contract cannot be approved yet, one per line ("" when it can; lib/cmd-approve.sh).
# $tracked (the number of files git tracks, for the early tier).
# $profile: interview_effective (lib/interview.sh); next fills unanswered ones with the neutral middle choice.
# $qa (slurped: [state]; lib/qa.jq's answer, handed over a file so the command line stays short).
# $tiers (slurped: [table]; lib/tiers.json: profile -> tier -> cell).
# $next_phase: the next free phase number (next_phase_number, lib/cmd-next.sh, worked out from the whole record, decision texts included).
# $effort: the current profile's effort table (lib/effort.sh), passed through as `effort`.
# $approved_doc (slurped: [] or [doc]): the last approved contract of this clone, read only while the
# current one is not approved (lib/cmd-approve.sh writes it). $prev: the last answer's text (runtime/next.json, "" when none).
# Output: {action, gate, instruction, detail, requirements (the active milestone's: id, text, proof), rigor, profile}, and on a gate
# since (R189): when VBW first reached it, kept from $prev while the same action and detail stand. profile.ask is true only
# at the spec or convert step with no completed interview (once per project). Every answer also carries
# next_phase (one after the highest phase number the record knows: phase and plan ids, plan phases and the
# P-numbers decisions name; P65.1 counts as 65; letters before the P do not) and effort.
# First matching row wins.

def result($action; $gate; $instruction; $detail):
  {action: $action, gate: $gate, instruction: $instruction, detail: $detail};

# QA ranks, lowest first.
def qa_rank: {quick: 0, standard: 1, deep: 2}[.];

# Builders share one working tree, so work that touches the same file never runs
# at the same time. "*" stands for any file.
# covers, overlaps and wave come with VBW_JQ_DEFS (record.sh).

# The files a fix may touch (as in vbw run start fix): the files of the plans
# serving its requirement; any file for a project command.
def fix_files($r): if .command then ["*"]
  else (.req as $q | [$r.plans[] | select(any(.reqs[]; . == $q)) | .files[]] | unique)
       | if length == 0 then ["*"] else . end end;

.milestone.id as $m
| $qa[0] as $qa
| ([.requirements[] | select(.milestone == null) | .id]) as $unassigned
| (if ($unassigned | length) > 0 then error("requirements with no milestone: \($unassigned | join(", "))") else . end)
| [.requirements[] | select(.milestone == $m)] as $current
| (.plans | map(select(.status == "done") | .id)) as $done
| . as $r
| ([.plans[] | select(.status != "done" and .status != "blocked")] | wave($done)) as $ready
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
# Delivered files changed outside any plan that the user has not settled yet (lib/qa.jq):
# no decision covers the change and no restore (vbw fix restore) is under way for the file.
| ([.fixes[] | select(has("restore") and (.status | IN("open","fixed"))) | .restore]) as $restoring
| ([($qa.deviations // {}) | to_entries[] | .key as $p | .value[] | select(.decision == null and (.file | IN($restoring[]) | not))
    | {phase: $p, file, plan, change, commit, by}]) as $unsettled
| (.evidence == null or .evidence.contract != $contract or $code_changed) as $stale
| ([.requirements[] | select(.proof == "auto" and (.status != "proven" or $stale)) | .id]) as $unproven
# #706: open fixes whose failures a proof writes (an [auto] requirement's or a project command's;
# not QA's, a restore's or a rejection's). On stale evidence they wait for a proof of the current code.
| ([.requirements[] | select(.proof == "auto") | .id]) as $auto
| ([.fixes[] | select(.status == "open" and (.source // "") != "qa" and (has("restore") | not)
    and (has("command") or (.req as $q | $auto | index($q) != null))) | .id]) as $proof_fixes
| ($stale and ($proof_fixes | length) > 0) as $reprove
| ([$current[] | select(.proof == "human" and .status == "open" and .skipped != true) | .id]) as $to_accept
# [human] requirements the user skipped (vbw req skip): the ship offers to move them on.
| ([$current[] | select(.proof == "human" and .status == "open" and .skipped == true) | .id]) as $later
# A moved requirement (vbw milestone start) was built in an earlier milestone: it only awaits its verdict.
| ([.phases[] | select(.milestone != $m) | .reqs[]?] | unique) as $built_before
| (all($current[]; .proof == "human" and (.id as $i | $built_before | index($i) != null))) as $only_moved
# Rigor: each current phase's tier (standard when it has none) with its cell of
# the profile (lib/tiers.json); the user's model overrides win over the cell's.
| ((.settings.models // {}) | {dev, qa} | with_entries(select(.value != null))) as $override
| ([.phases[] | select(.milestone == $m) | . as $ph | ($ph.tier // "standard") as $t
    | {key: $ph.id, value: ({tier: $t} + $tiers[0][$r.settings.profile][$t] | .models += $override | .models |= (if ((.qa // "" | ascii_downcase | contains("haiku"))) then .qa = "sonnet" else . end))}]
   | from_entries) as $rigor
# Built phases QA must check again (VBW 1's QA mandate; lib/qa.jq): failed,
# never passed, their inputs changed, or building on a phase that was. A built phase needs QA
# unless it is express with only [auto] requirements and no escalations, and no file
# its plans delivered changed outside any plan without a decision of the user (lib/qa.jq deviations).
| ([.phases[] | select(.milestone == $m and $qa.recheck[.id] != null
    and (needs_qa($rigor[.id].tier; $current) or any((($qa.deviations // {})[.id] // [])[]; .decision == null))) | .id]) as $to_verify
# The QA tier is the highest among the phases to verify.
| ([$to_verify[] | $rigor[.].qa] | max_by(qa_rank) // "standard") as $tier
# A phase in a re-check round (lib/qa.jq focus, T131) goes to QA with the fixes since its
# failed verdict and that verdict's commit (round.focus): QA verifies those, not the whole phase.
# QA depth by the size and risk of the change (R71): at most two files and no risk
# path is quick; three to nine files and no risk at most standard; else the cell's.
# A phase with no recorded reasons is not small. A phase with a recorded escalation (R145)
# keeps its cell's depth whatever its size; a tier forced with vbw config rigor records none.
| (. as $rec | [$to_verify[] | . as $id | ($rec.phases[] | select(.id == $id)) as $ph
    | ($rec.plans | map(select(.phase == $id) | .files // []) | add // [] | unique | length) as $nf
    | ($ph.reasons // []) as $why
    | $rigor[$id].qa as $cell
    | {key: $id, value: (if ($why | index("risk: none")) == null or (($ph.escalations // []) | length) > 0 then $cell
        elif $nf <= 2 then "quick"
        elif $nf <= 9 then ([$cell, "standard"] | min_by(qa_rank))
        else $cell end)}] | from_entries) as $tiers_qa
| (if .lease != null and .lease.session != null and .lease.session != $session then
    result("run"; false; "A VBW \(.lease.kind) run (\(.lease.run)) belongs to another session, \($holder): wait for it, or check vbw status"; {lease: .lease})
  elif .lease != null then
    result("run"; false; "A VBW \(.lease.kind) run (\(.lease.run)) is open: if its workflow is still running in this session, wait for it; otherwise run vbw run end"; {lease: .lease})
  elif .milestone.status == "parked" then
    result("milestone"; true; "Milestone \(.milestone.id) is parked (\([.parked[]? | select(.id == $m) | .reason] | first // "")): start the next milestone (vbw milestone start TITLE)"; {})
  elif .milestone.status == "shipped" then
    result("milestone"; true; "Milestone \(.milestone.id) is shipped: start the next milestone (vbw milestone start TITLE)"; {})
  elif ($current | length) == 0 and $legacy then
    result("convert"; true; "This project has a VBW 1 plan (.vbw-planning/): bring it into VBW 2 (/vbw:convert), or start fresh"; {})
  elif ($current | length) == 0 then
    result("spec"; true; "Write the requirements for \(.milestone.id) \(.milestone.title) in .vbw/spec.md"; {})
  elif (([.phases[] | select(.milestone == $m)] | length) == 0 and ($only_moved | not))
       or (. as $r | any(.requirements[]; .proof == "auto" and (.id as $id | any($r.checks[]; .req == $id) | not) and (doc_only($r) | not)))
       or (.plans as $p | any($current[]; .proof == "auto" and (.id as $id | any($p[]; any(.reqs[]; . == $id)) | not))) then
    ([$current[] | select(.reworded == true) | .id]) as $rw
    | result("plan"; false; "Run the plan workflow: phases, plans and contract checks\(if ($rw | length) > 0 then ". \($rw | join(", ")) reworded: its rules were kept, so the Lead reviews them (keep, reword or retire each with vbw apply --patch)" else "" end)"; {tier: early_tier($tracked), small: small_change} + (if ($rw | length) > 0 then {reworded: $rw} else {} end))
  elif ($approved | not) and ($problems | length) > 0 then
    ([$problems | split("\n")[] | select(length > 0)]) as $pl
    | result("contract"; false; "The contract is not ready for approval, so there is no approval question yet: \($pl | join("; ")). Fix each (write a missing check file and see it fail first with vbw check --expect-red; vbw spec sync when the spec and the record differ; add missing rules with vbw apply --patch), then run vbw next again"; {problems: $pl})
  elif $approved | not then
    # A re-approval (R61): the last approved contract already held this milestone's requirements.
    ((($approved_doc[0] // {}).requirements // {}) as $old | any(.requirements[]; .milestone == $m and $old[.id] != null)) as $changed
    | result("approve"; true; "Review and approve the contract (requirements, plans and checks)"; (if $changed then {changed: true} else {} end))
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
  # #706: a fix round works from the last proof's failures, so stale evidence (a round's
  # refused fix done, an interrupted Dev, a user commit) is proved again first.
  elif ($open_fixes | length) > 0 and ($reprove | not) then
    result("fix"; false; "Run the fix workflow for \($open_fixes | join(", "))"; {fixes: $open_fixes, groups: $fix_groups})
  # Waiting files belong to checks, and checks only to [auto] requirements, which stale
  # evidence puts in $unproven: a $reprove with waiting files is always caught here.
  elif ($waiting | length) > 0 and ($unproven | length) > 0 then
    ([$waiting | split("\n")[] | select(length > 0)] | sort) as $wf
    | result("approve"; true; "Approve the test files new or edited since the approval (a fix may add or change them), once, before they are proved: \($wf | join(", "))"; {files: $wf})
  elif ($unproven | length) > 0 or $reprove then
    result("prove"; false; "Run vbw prove for \(if ($unproven | length) > 0 then $unproven else $proof_fixes end | join(", "))"; {requirements: $unproven})
  # The gate after the proof for check files that only had lines added (R269, F414): nothing is
  # failing or unproven, so the added lines are asked once, with their diff, before QA and shipping.
  elif ($added_to | length) > 0 then
    ([$added_to[].file] | sort) as $af
    | result("approve"; true; "Approve the lines added to the test files since the approval, once; the proof judged them with the approved content, and approved they count from the next proof: \($af | join(", "))"; {files: $af, added_to: $added_to})
  elif ($unsettled | length) > 0 then
    result("deviations"; true; "Files the plans delivered changed outside any plan: ask the user whether to keep each change (vbw decide naming the file) or restore it (vbw fix restore FILE): \([$unsettled[] | "\(.file) (\(.plan)) \(.change)"] | join(", "))"; {deviations: $unsettled})
  elif (proof_complete | not) and (($to_verify | length) > 0 or ($to_accept | length) == 0) then
    result("prove"; false; "Run vbw prove --full: QA and shipping need a proof in which no quick command stood in for the test command and no approved full command was skipped"; {full: true})
  elif ($to_verify | length) > 0 then
    result("qa"; false; "Run the QA workflow (\($tier)) for \($to_verify | join(", ")): goal-backward verification of the built work. Checked again: \([$to_verify[] | "\(.) (\($qa.recheck[.] | join("; ")))"] | join(", "))\(if ($qa.standing | length) > 0 then ". Keeping their pass: \($qa.standing | join(", "))" else "" end)"; {phases: $to_verify, tier: $tier})
  elif ($to_accept | length) > 0 then
    result("accept"; true; "Accept or reject \($to_accept | join(", ")), one scenario at a time"; {requirements: $to_accept})
  elif ($later | length) > 0 then
    result("ship"; true; "Everything else is proven and accepted; you skipped \($later | join(", ")). Choose: ship milestone \(.milestone.id) now and judge \($later | join(", ")) in the next milestone, or judge \($later | join(", ")) now (vbw req accept or vbw req reject)"; {later: $later})
  else
    result("ship"; true; "Everything is proven and accepted: ship milestone \(.milestone.id)"; {})
  end) as $n0
| ($n0 + (if ($added_to | length) > 0 then {added_to: $added_to} else {} end)) as $n
# The round (QA depth, the proof's test run, re-check focus, the deviations of the phases to
# verify, lib/qa.jq: those a decision covers too, with it) is the qa answer's. The router
# opens the QA run first, which turns the answer into run, so the round stays on it while the
# caller's own QA run is open: the router may read it on either side of vbw run start qa (T178).
| ($n.action == "qa" or ($n.action == "run" and .lease.kind == "qa" and (.lease.session == null or .lease.session == $session))) as $with_round
| $n + (if $with_round then {round: {tiers: $tiers_qa, focus: ([$to_verify[] | select(($qa.focus // {})[.] != null) | {key: ., value: $qa.focus[.]}] | from_entries),
    deviations: ([$to_verify[] | select(($qa.deviations // {})[.] != null) | {key: ., value: $qa.deviations[.]}] | from_entries), suite: (if (.commands.test // null) == null then null else (.commands.test) as $cmd | (if .evidence.commands.test == null then {command: "test", status: "not run"} else .evidence.commands.test | (if (.command // "") == "" then .command = ($cmd | join(" ")) else . end) end) end)}} else {} end) + {next_phase: $next_phase, effort: $effort, requirements: [$current[] | {id, text, proof}], rigor: $rigor, qa: ($qa | {recheck, standing, interleaved, problems}), declined: [(.project.declined // [])[].text], profile: ({level: "small scripts or no-code", depth: "plain with technical terms explained", involvement: "options with a recommendation"} + ($profile | with_entries(select(.value != null or .key == "kept" or .key == "pending"))) + {ask: ([$n.action] | inside(["spec","convert"]) and ($profile.interviewed | not))})}
# When VBW first reached this gate (R189): the last answer's since while the same action and
# detail stand, so a restart or another session never moves it; a new gate starts now.
| if .gate then . + {since: (($prev | try fromjson catch null) as $p
    | if ($p | type) == "object" and $p.gate == true and $p.action == .action and $p.detail == .detail and ($p.since | type) == "string"
      then $p.since else (now | todate) end)} else . end
# The amendments recorded since the previous answer (R250, D586), told once: amendments_seen
# is every amendment the record holds now ("id at what"), kept in the answer file; the ones the
# previous answer did not hold are carried as amendments [{id, what}].
| ([($r.plans[]?, $r.checks[]?) | .id as $i | (.amendments // [])[] | {key: "\($i) \(.at) \(.what)", id: $i, what: .what}]) as $am
| (($prev | try fromjson catch null) as $p | if ($p | type) == "object" then ($p.amendments_seen // []) else [] end) as $seen
| . + {amendments: [$am[] | select(.key as $k | $seen | index($k) | not) | {id, what}], amendments_seen: [$am[].key]}
