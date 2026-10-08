# vbw prove: fold one run into the record (docs/proof.md). Input: the record.
# Args: $ev (the evidence object), $cap (fix attempt cap), $cur (qa_combined), $at (the time). VBW_JQ_DEFS prepended.

def ok: .status == "pass";

. as $r
| ($ev.checks) as $checks
| ([ .requirements[] | select(.proof == "auto") | .id as $id
    | [$r.checks[] | select(.req == $id) | .id] as $ids
    | select($ids | length > 0)
    | { key: "req", target: $id,
        pass: all($ids[]; $checks[.] | ok),
        built: all($r.plans[]; .status == "done" or (any(.reqs[]; . == $id) | not)),
        note: ([$ids[] | select($checks[.] | ok | not) | "\(.) \($checks[.].status)\(if $checks[.].exit != null then " (exit \($checks[.].exit))" else "" end)"] | join(", ")) } ]
  # A documentation-only requirement has no check: it is proven once its plans are done.
  + [ .requirements[] | select(.proof == "auto" and doc_only($r)) | .id as $id
      | select(all($r.plans[]; .status == "done" or (any(.reqs[]; . == $id) | not)))
      | {key: "req", target: $id, pass: true, built: true, note: ""} ])
  as $req_results
| [ $ev.commands | to_entries[] | select(.value.status != "skipped")
    | {key: "command", target: .key, pass: (.value | ok), built: all($r.plans[]; .status == "done"), note: "\(.key) \(.value.status)"} ]
  as $cmd_results

# A requirement that was proven and now fails raises its phases one step.
| [ .requirements[] | select(.status == "proven") | .id ] as $was_proven
| reduce ($req_results[] | select(.pass | not) | select(.target as $t | $was_proven | index($t))) as $t (.;
    escalate_phases([.phases[] | select(.reqs | index($t.target)) | .id]; null; "proven requirement \($t.target) failed"; $at))

# Requirements: proven when all their checks pass.
| .requirements |= map(. as $q
    | ([$req_results[] | select(.target == $q.id)][0]) as $res
    | if $res == null then . else .status = (if $res.pass then "proven" else "failing" end) end)

# Fixes: close on pass; open on a failure once the work is built (every plan
# serving the requirement, or every plan for a project command, is done: before
# that a failure is work in progress, not a defect); count a failed attempt
# after work.
| reduce ($req_results + $cmd_results)[] as $t (.;
    # QA's findings (source "qa") are QA's to close: passing checks do not settle
    # a deviation from the plan.
    ([.fixes | to_entries[] | select(.value[$t.key] == $t.target and (.value.source // "") != "qa"
        and (.value.status | IN("open","fixed","escalated"))) | .key][0]) as $i
    | if $t.pass then
        (if $i != null then .fixes[$i].status = "closed" else . end)
      elif $i == null and ($t.built | not) then .
      elif $i == null then
        .fixes += [{id: (.fixes | next_id("F")), ($t.key): $t.target, attempts: 0, status: "open", note: $t.note}]
      elif .fixes[$i].status == "fixed" then
        .fixes[$i].attempts += 1
        | .fixes[$i].note = $t.note
        | .fixes[$i].status = (if .fixes[$i].attempts >= $cap then "escalated" else "open" end)
        | .fixes[$i] as $fx
        | escalate_phases([.phases[] | select($fx.req != null and (.reqs | index($fx.req))) | .id]; null; "fix \($fx.id) needs a second round"; $at)
      else .fixes[$i].note = $t.note end)

# A passing full test command settles a fix opened for a failing quick command.
| if $ev.full == true and (($ev.commands.test // {}) | ok) then
    .fixes |= map(if .command == "quick" and (.status | IN("open","fixed","escalated")) then .status = "closed" else . end)
  else . end

| .evidence = $ev
| finish_phases($cur)
