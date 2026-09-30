# vbw prove: fold one run into the record (docs/proof.md). Input: the record.
# Args: $ev (the evidence object), $cap (fix attempt cap). VBW_JQ_DEFS prepended.

def ok: .status == "pass";

. as $r
| ($ev.checks) as $checks
| [ .requirements[] | select(.proof == "auto") | .id as $id
    | [$r.checks[] | select(.req == $id) | .id] as $ids
    | select($ids | length > 0)
    | { key: "req", target: $id,
        pass: all($ids[]; $checks[.] | ok),
        note: ([$ids[] | select($checks[.] | ok | not) | "\(.) \($checks[.].status)\(if $checks[.].exit != null then " (exit \($checks[.].exit))" else "" end)"] | join(", ")) } ]
  as $req_results
| [ $ev.commands | to_entries[] | select(.value.status != "skipped")
    | {key: "command", target: .key, pass: (.value | ok), note: "\(.key) \(.value.status)"} ]
  as $cmd_results

# Requirements: proven when all their checks pass.
| .requirements |= map(. as $q
    | ([$req_results[] | select(.target == $q.id)][0]) as $res
    | if $res == null then . else .status = (if $res.pass then "proven" else "failing" end) end)

# Fixes: close on pass; open on first failure; count a failed attempt after work.
| reduce ($req_results + $cmd_results)[] as $t (.;
    ([.fixes | to_entries[] | select(.value[$t.key] == $t.target and (.value.status | IN("open","fixed","escalated"))) | .key][0]) as $i
    | if $t.pass then
        (if $i != null then .fixes[$i].status = "closed" else . end)
      elif $i == null then
        .fixes += [{id: (.fixes | next_id("F")), ($t.key): $t.target, attempts: 0, status: "open", note: $t.note}]
      elif .fixes[$i].status == "fixed" then
        .fixes[$i].attempts += 1
        | .fixes[$i].note = $t.note
        | .fixes[$i].status = (if .fixes[$i].attempts >= $cap then "escalated" else "open" end)
      else .fixes[$i].note = $t.note end)

| .evidence = $ev
