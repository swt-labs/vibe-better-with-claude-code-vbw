# What QA must check again (R47, R49; docs/proof.md). Input: the record.
# Arguments: $fpv (optional: the version of how the digests are computed, QA_FP_VERSION; absent, versions are not compared), $inputs (null, or the current digests of every phase of the active
# milestone: {Pn: {files, tests, plan, reqs, combined}}, from lib/qa-inputs.sh) and
# $cache (null, or what each phase's last pass covered: {Pn: {files, tests,
# plan, reqs, combined, version, tree, deps: {Pm: {files, tests, plan, reqs}}}}; this clone's
# file, so anything may be wrong with it). Output: {closure, recheck, standing, focus, deviations, interleaved, problems}. closure
# maps a phase to every phase it builds on, directly or not (a phase builds on
# another when one of its plans comes after a plan of the other). interleaved lists
# the phases that build on each other that way (a note: the plans stay acyclic).
# recheck maps each built phase that needs checking again to its reasons, in
# plain words; standing lists the built phases whose pass stands; focus maps each
# re-checked phase in a re-check round to {since: the commit of its failed verdict,
# round, fixes: the QA fixes since}. A phase is checked again for one it builds on
# only when that one's tests changed (its checks or their files), whatever else did.
# deviations maps each phase of the active milestone to the files its plans
# delivered that the last proof found changed outside any plan (evidence.deviations,
# lib/delivered.sh), each {file, plan, change, commit, by, decision}: decision is
# the user's decision that covers it, or null. One that no decision covers sends
# a built phase to QA again, whatever else changed. It does not depend on $inputs.
. as $r
| ([$r.phases[].id]) as $all
| ([$r.phases[] | select(.milestone == $r.milestone.id) | .id]) as $ids
| ([$r.plans[] | {key: .id, value: .phase}] | from_entries) as $owner
# Edges and problems.
| ([$r.plans[] | select(.phase | IN($all[]) | not) | "plan \(.id) belongs to \(.phase), which does not exist"]
   + [$r.plans[] | select(.phase | IN($ids[])) | .id as $p | (.after // [])[] | select($owner[.] == null) | "plan \($p) comes after \(.), which does not exist"]) as $missing
| ([$r.plans[] | select(.phase | IN($ids[])) | .phase as $ph | (.after // [])[] | $owner[.] | select(. != null and . != $ph and IN($ids[])) | {from: $ph, to: .}]) as $edges
| ([$ids[] | . as $i | {key: $i, value: ([$edges[] | select(.from == $i) | .to] | unique)}] | from_entries) as $direct
# Transitive closure by one walk per node over the direct links, a visited set stopping on loops.
| (def reach($g; $s): {seen: {}, todo: ($g[$s] // [])} | until(.todo | length == 0; .todo[-1] as $n | .todo |= .[:-1] | if .seen[$n] then . else .seen[$n] = true | .todo += ($g[$n] // []) end) | .seen | keys;
   [$ids[] | {key: ., value: reach($direct; .)}] | from_entries) as $full
# Phases on such a loop interleave: a plan of each comes after a plan of the other. That
# is a note, not a problem, and the closure still lets each be checked again for the
# other's tests. Only a loop among the plans themselves is a problem (the record refuses
# one; this program still names it): looked for among the interleaved phases' plans only.
| ([$ids[] | select(. as $i | $full[$i] | index($i))]) as $interleaved
| ($full | with_entries(.key as $k | .value -= [$k])) as $closure
| (if ($interleaved | length) == 0 then [] else
    ([$r.plans[] | select(.phase | IN($interleaved[])) | .id]) as $pids
    | ([$r.plans[] | select(.id | IN($pids[])) | {key: .id, value: ([(.after // [])[] | select(IN($pids[]))] | unique)}] | from_entries) as $pd
    | (def reach($g; $s): {seen: {}, todo: ($g[$s] // [])} | until(.todo | length == 0; .todo[-1] as $n | .todo |= .[:-1] | if .seen[$n] then . else .seen[$n] = true | .todo += ($g[$n] // []) end) | .seen | keys;
       [$pids[] | select(. as $i | reach($pd; $i) | index($i))])
  end) as $loop
| ($missing + (if ($loop | length) > 0 then ["plans \($loop | join(", ")) come after each other (a cycle)"] else [] end)) as $problems
| ([$r.phases[] | select(.id | IN($ids[]))
    | select(.id as $i | [$r.plans[] | select(.phase == $i)] | length > 0 and all(.[]; .status == "done"))]) as $built
| ($ARGS.named.fpv) as $fpv
# A decision covers a deviation when it was recorded at or after the commit that
# delivered the file and its text or reason names the file's path: as a word of
# its own (a sentence's closing dot, or a leading ./, does not hide it; NOTES.md
# names neither NOTES.md.bak nor docs/NOTES.md).
| ([($r.evidence.deviations // [])[] | . as $d | ($owner[.plan]) as $p | select($p != null and ($p | IN($ids[])))
    | {phase: $p, d: ({file, plan, change, commit, by}
        + {decision: (first($r.decisions[]? | select(.at >= $d.at and ([.text, (.why // empty)] | join("\n") | names($d.file))) | .id) // null)})}]
   | group_by(.phase) | map({key: .[0].phase, value: map(.d)}) | from_entries) as $deviations
| (def plain: "its files, tests or plan changed";
   ($cache | if type == "object" then . else {} end) as $c
   | [$built[] | . as $ph | ($inputs[$ph.id]) as $cur | ($c[$ph.id]) as $old
     | ((if $ph.qa == null then ["not checked yet"]
        else (if $ph.qa.result != "pass" then ["failed last time"] else [] end)
          + (if $ph.qa.tree == $cur.combined
                or ($old | type == "object" and .version == $fpv and .tree == $ph.qa.tree and .combined == $cur.combined) then []
             else (if ($old | type == "object" and ($fpv == null or (.version // 0) == $fpv) and (.files | type == "string") and (.tests | type == "string") and (.plan | type == "string") and (.reqs | type == "string" or . == null) and (.deps | type == "object"))
                   then ([if $old.files != $cur.files then "its files changed" else empty end,
                          if $old.tests != $cur.tests then "its tests changed" else empty end,
                          if $old.plan != $cur.plan then "its goal or plan changed" else empty end,
                          if $old.reqs != null and $old.reqs != $cur.reqs then "an [auto] requirement changed" else empty end]
                         + [$closure[$ph.id][] as $d | select(($old.deps[$d].tests // null) != $inputs[$d].tests) | "builds on \($d), whose tests changed"])
                   else [] end) | if length > 0 then . else [plain] end
             end)
        end)
        + [($deviations[$ph.id] // [])[] | select(.decision == null) | "\(.file), delivered by \(.plan), was \(.change) outside any plan"]) as $why
     # A re-check round (T131): the last verdict failed and this clone's cache, of this
     # method, shows the goal, criteria, plans and [auto] requirements unchanged since.
     | (if $ph.qa.result == "fail" and ($old | type == "object" and ($fpv == null or (.version // 0) == $fpv) and (.commit | type == "string")
             and .plan == $cur.plan and (.reqs == null or .reqs == $cur.reqs))
        then {since: $old.commit, round: (($ph.qa.rounds // 1) + 1),
              fixes: [$r.fixes[] | select(.source == "qa" and (.status | IN("open", "fixed")) and (.req as $q | $ph.reqs | index($q)) and ((has("phase") | not) or .phase == $ph.id)) | {id, req, note}]}
        else null end) as $focus
     | {id: $ph.id, why: $why, focus: $focus}]) as $judged
| {closure: $closure,
   recheck: (if $inputs == null then {} else [$judged[] | select(.why | length > 0) | {key: .id, value: .why}] | from_entries end),
   standing: (if $inputs == null then [] else [$judged[] | select(.why | length == 0) | .id] end),
   focus: (if $inputs == null then {} else [$judged[] | select((.why | length > 0) and .focus != null) | {key: .id, value: .focus}] | from_entries end),
   deviations: $deviations,
   interleaved: $interleaved,
   problems: $problems}
