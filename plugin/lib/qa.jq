# What QA must check again (R47, R49; docs/proof.md). Input: the record.
# Arguments: $inputs (null, or the current digests of every phase of the active
# milestone: {Pn: {files, tests, plan, reqs, combined}}, from lib/qa-inputs.sh) and
# $cache (null, or what each phase's last pass covered: {Pn: {files, tests,
# plan, reqs, deps: {Pm: {files, tests, plan, reqs}}}}; this clone's file, so anything may
# be wrong with it). Output: {closure, recheck, standing, problems}. closure
# maps a phase to every phase it builds on, directly or not (a phase builds on
# another when one of its plans comes after a plan of the other).
# recheck maps each built phase that needs checking again to its reasons, in
# plain words; standing lists the built phases whose pass stands.
. as $r
| ([$r.phases[].id]) as $all
| ([$r.phases[] | select(.milestone == $r.milestone.id) | .id]) as $ids
| ([$r.plans[] | {key: .id, value: .phase}] | from_entries) as $owner
# Edges and problems.
| ([$r.plans[] | select(.phase | IN($all[]) | not) | "plan \(.id) belongs to \(.phase), which does not exist"]
   + [$r.plans[] | select(.phase | IN($ids[])) | .id as $p | (.after // [])[] | select($owner[.] == null) | "plan \($p) comes after \(.), which does not exist"]) as $missing
| ([$r.plans[] | select(.phase | IN($ids[])) | .phase as $ph | (.after // [])[] | $owner[.] | select(. != null and . != $ph and IN($ids[])) | {from: $ph, to: .}]) as $edges
| ([$ids[] | . as $i | {key: $i, value: ([$edges[] | select(.from == $i) | .to] | unique)}] | from_entries) as $direct
# Transitive closure by repeated expansion: terminates on cycles.
| (reduce range(0; $ids | length) as $_ ($direct; . as $c | with_entries(.value |= (. + [.[] | $c[.][]] | unique)))) as $full
| ([$ids[] | select(. as $i | $full[$i] | index($i))]) as $cyclic
| ($full | with_entries(.key as $k | .value -= [$k])) as $closure
| ($missing + (if ($cyclic | length) > 0 then ["phases \($cyclic | join(", ")) build on each other (a cycle)"] else [] end)) as $problems
| ([$r.phases[] | select(.id | IN($ids[]))
    | select(.id as $i | [$r.plans[] | select(.phase == $i)] | length > 0 and all(.[]; .status == "done"))]) as $built
| (def own: {files, tests, plan, reqs};
   def plain: "its files, tests or plan changed";
   # A cache written before the [auto] requirements digest existed has no reqs: compare what it has.
   def same($o; $n): $o != null and $o.files == $n.files and $o.tests == $n.tests and $o.plan == $n.plan and ($o.reqs == null or $o.reqs == $n.reqs);
   ($cache | if type == "object" then . else {} end) as $c
   | [$built[] | . as $ph | ($inputs[$ph.id]) as $cur | ($c[$ph.id]) as $old
     | (if $ph.qa == null then ["not checked yet"]
        else (if $ph.qa.result != "pass" then ["failed last time"] else [] end)
          + (if $ph.qa.tree == $cur.combined then []
             else (if ($old | type == "object" and (.files | type == "string") and (.tests | type == "string") and (.plan | type == "string") and (.reqs | type == "string" or . == null) and (.deps | type == "object"))
                   then ([if $old.files != $cur.files then "its files changed" else empty end,
                          if $old.tests != $cur.tests then "its tests changed" else empty end,
                          if $old.plan != $cur.plan then "its goal or plan changed" else empty end,
                          if $old.reqs != null and $old.reqs != $cur.reqs then "an [auto] requirement changed" else empty end]
                         + [$closure[$ph.id][] as $d | select(same($old.deps[$d]; $inputs[$d] | own) | not) | "builds on \($d), which changed"])
                   else [] end) | if length > 0 then . else [plain] end
             end)
        end) as $why
     | {id: $ph.id, why: $why}]) as $judged
| {closure: $closure,
   recheck: (if $inputs == null then {} else [$judged[] | select(.why | length > 0) | {key: .id, value: .why}] | from_entries end),
   standing: (if $inputs == null then [] else [$judged[] | select(.why | length == 0) | .id] end),
   problems: $problems}
