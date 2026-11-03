# The road (R191, docs/next.md): one jq program adds up everything still ahead in
# the milestone: the build waves still to build, the proofs, QA and the usual fix
# rounds. lib/road.sh builds the program: VBW_JQ_DEFS, VBW_STEP_DEFS, then
# `def expect($kind; $size)` (lib/steps-expect.jq, the one ladder of expected
# seconds for every piece), then this file.
#
# Interface: jq -n --slurpfile rec RECORD --slurpfile h HISTORY --slurpfile runs RUN_TIMES
#   --slurpfile next NEXT --slurpfile note NOTE
#   $rec[0]  the record; $h[0] / $runs[0] the step history and the run times
#            (run-times.json; null when missing or damaged); $next[0] vbw next's answer
#            (action, qa.standing); $note[0] the live step's note, or null
# Output: null, or {seconds, end, rounds, basis, say}; seconds and end are null
# when a piece has no basis, and basis then names the first kind missing.

def median: sort | length as $n
  | if $n == 0 then null
    elif $n % 2 == 1 then .[($n - 1) / 2 | floor]
    else (.[$n / 2 - 1] + .[$n / 2]) / 2 end;
def first_of(f): [f] | first;
def dur($s): ($s / 60 | round | if . < 1 then 1 else . end) as $m
  | if $m < 60 then "about \($m) min"
    else ($m / 60 | floor) as $h | ($m % 60) as $mm | "about \($h) h" + (if $mm == 0 then "" else " \($mm) min" end) end;
def tier_name: .tier // "standard";
def plural($n; $one; $many): if $n == 1 then "\($n) \($one)" else "\($n) \($many)" end;
# A glob of a git pathspec as a regular expression (* crosses /, as git's does).
def globre: gsub("(?<c>[.+^$()|{}\\[\\]\\\\])"; "\\\(.c)") | gsub("\\*"; ".*") | gsub("\\?"; ".");

$rec[0] as $r
| ($next[0] // {}) as $next
| ($note[0] // null) as $note
| (now | floor) as $t
| ($r.milestone // null) as $ms
| if $ms == null or $ms.status == "shipped" or $ms.status == "parked" then null else
  $ms.id as $m
  | [$r.requirements[] | select(.milestone == $m)] as $current
  | [$r.phases[] | select(.milestone == $m)] as $phases
  | ($next.qa.standing // []) as $standing
  | def passing($c): ([$r.requirements[] | select(.id == $c.req)][0].status | IN("proven", "accepted"))
      and ($r.evidence.checks[$c.id].status? == "pass");
    def checks_of($ph): [$r.checks[] | select(.req as $q | any($ph.reqs[]; . == $q))];
    # The units a proof of these checks runs: each check and, with approved
    # single-file forms, the test files of the checks that a form names.
    def units($cs):
      [$cs[] | "check:\(.id)"]
      + (if $r.test_files == null then [] else
           [$r.checks[].run[]] as $ran
           | [($r.test_files | if type == "array" then .[] else . end) as $tf
               | ([$tf.files[] | select(pathspec_path == .) | globre | "^\(.)$"]) as $inc
               | ([$tf.files[] | pathspec_path as $p | select($p != .) | $p | globre | "^\(.)$"]) as $exc
               | $cs[].files[]? | select(. as $f | any($inc[]; . as $p | $f | test($p)) and (any($exc[]; . as $p | $f | test($p)) | not)
                   and (any($ran[]; . == $f) | not)) | "file:\(.)"] | unique
         end);
    def finished($tier): [$r.phases[] | select((.outcome | type) == "object" and ((.outcome.tier // .tier // "standard") == $tier)
        and (.outcome.fix_rounds | type) == "number")] | .[-10:] | map(.outcome.fix_rounds);
    def usual($tier): finished($tier) | if length >= 3 then median | round else null end;
    ($phases | map(
        . as $ph | tier_name as $tier
        | (needs_qa($tier; $current)) as $nq
        | checks_of($ph) as $cs
        | ([$r.plans[] | select(.phase == $ph.id)]) as $ps
        | {ph: $ph, tier: $tier, nq: $nq, cs: $cs, bad: [$cs[] | select(passing(.) | not)],
           built: (($ps | length) > 0 and all($ps[]; .status == "done")),
           qa_ok: (($nq | not) or ($standing | index($ph.id)) != null)})
      | map(select((.built and (.bad | length) == 0 and .qa_ok) | not))) as $left
    # Everything ahead, in road order, each piece {kind, size, mult, ids?, label}.
    | ( if ($phases | length) == 0 or $next.action == "spec" or $next.action == "convert" then
          ([$r.requirements[] | select(.milestone == $m and .status != "proven" and .status != "accepted")] | length) as $n
          | if ($phases | length) == 0 and $n == 0 and $next.action != "spec" and $next.action != "convert" then []
            else [{kind: "plan", size: {reqs: $n}, mult: 1, label: "planning steps"}] end
        else
          ($r | waves($m)) as $waves
            | [$waves[] | . as $ids | {kind: "build", ids: $ids, mult: 1, label: "plans",
                size: [$ids[] as $i | ([$r.plans[] | select(.id == $i)][0]) as $p
                  | {id: $i, tier: ([$phases[] | select(.id == $p.phase)][0] | tier_name), tasks: (($p.tasks // []) | length),
                     breaks: ($r | owed_rules($i) | length)}]}] as $wp
          | ( [ $left[] | . as $l
                | ([$waves[] | select(any(.[]; . as $i | any($r.plans[]; .id == $i and .phase == $l.ph.id)))] | length) as $nw
                | (if ($l.bad | length) > 0 then $l.bad else $l.cs end) as $us
                | (if ($l.bad | length) > 0 then ([$nw, 1] | max) else $nw end) as $n
                | select($n > 0 and ($us | length) > 0)
                | {kind: "proof", size: {units: units($us)}, mult: $n, label: "proofs"}] ) as $pp
          | [ [$left[] | select(.nq and (.qa_ok | not))] | select(length > 0)
              | {kind: "qa", size: [.[] | {id: .ph.id, tier: .tier}], mult: 1, label: "QA checks"} ] as $qp
          | [ $left[] | . as $l | (usual($l.tier) // 0) as $n | select($n > 0)
              | {kind: "fix", size: {tier: $l.tier}, mult: $n, label: "fix rounds"},
                (select(($l.cs | length) > 0) | {kind: "proof", size: {units: units($l.cs)}, mult: $n, label: "proofs", fixr: true}),
                (select($l.nq) | {kind: "qa", size: [{id: $l.ph.id, tier: $l.tier}], mult: $n, label: "QA checks", fixr: true}) ] as $fp
          | $wp + $pp + $qp + $fp
        end
      ) as $pieces
    # The live step's note: what is left of it replaces its own piece's first estimate.
    | (if $note == null then null else
        {kind: ($note.kind), ids: ($note.ids // []),
         seconds: (if $note.end == null then null else ((($note.end | fromdateiso8601) - $t) | if . < 0 then 0 else . end) end)} end) as $live
    # A piece whose time cannot be worked out (T174) has no time and says so; the road stays.
    | ($pieces | map(. as $p | (try {v: first_of(expect($p.kind; $p.size))} catch {v: null, unread: true}) as $x
        | . + {seconds: ($x.v | if . == null then null else . * $p.mult end)} + (if $x.unread then {unread: true} else {} end))) as $timed
    | (if $live == null then $timed else
        ( [ $timed | to_entries[] | select(.value.kind == $live.kind)
            | select($live.kind == "plan" or $live.kind == "proof" and (.value.label == "proofs") and (.value.fixr | not)
                     or $live.kind == "build" and any(.value.ids[]?; . as $i | any($live.ids[]; . == $i))
                     or $live.kind == "qa" and .value.label == "QA checks" and (.value.fixr | not) and ((.value.size | map(.id)) as $q | any($live.ids[]; . as $i | any($q[]; . == $i)))) | .key ] | first) as $k
        | if $k != null then ($timed | .[$k] |= (.seconds = $live.seconds | .mult = 1)) else
            $timed + [{kind: $live.kind, size: null, mult: 1, label: (if $live.kind == "build" then "plans" elif $live.kind == "fix" then "fix rounds" elif $live.kind == "qa" then "QA checks" elif $live.kind == "proof" then "proofs" else "planning steps" end), seconds: $live.seconds}] end
      end) as $all
    | if ($all | length) == 0 then null else
      ([$all[] | select(.seconds == null)][0]) as $miss
      | (["deep", "standard", "express"] | map(select(. as $x | any($left[]; .tier == $x)))) as $tiers
      | ($tiers | map({t: ., n: usual(.)})) as $ru
      | {seconds: ($all | if any(.[]; .seconds == null) then null else map(.seconds) | add end)} as $tot
      | ($tot.seconds) as $sec
      | (if $sec == null then null else $t + $sec | todateiso8601 end) as $end
      | ($ru | map(select(.n != null)) | map("\(if .n == 0 then "no fix rounds" else plural(.n; "fix round"; "fix rounds") end) per \(.t) phase") | step_and) as $known
      | ($ru | map(select(.n == null) | .t)) as $lack
      | ([ (if ($known | length) > 0 then "\($known) (the usual here)" else empty end),
           (if ($lack | length) > 0 then "no fix rounds: fewer than 3 finished \($lack | step_and) phases here" else empty end) ] | join("; ")) as $counting
      | (if $miss != null and $miss.unread == true then "VBW could not time the \($miss.label) here from its step history"
         elif $miss != null then "VBW has timed fewer than 3 \($miss.label) here"
         else
           ([$all[] | select(.kind == "plan")] | length) as $np
           | if $np > 0 then "the planning step, sized by the open requirements"
             else ([ ($all | map(select(.kind == "build")) | length | select(. > 0) | plural(.; "build wave"; "build waves")),
                     ($all | map(select(.label == "proofs" and (.fixr | not))) | length | select(. > 0) | plural(.; "proof"; "proofs")),
                     ($all | map(select(.label == "QA checks" and (.fixr | not)) | (.size // []) | length) | add // 0 | select(. > 0) | plural(.; "QA check"; "QA checks")),
                     ($all | map(select(.kind == "fix" and .label == "fix rounds")) | map(select(true) | .mult) | add // 0 | select(. > 0)
                        | "\(plural(.; "usual fix round"; "usual fix rounds")) (median of the latest 10 finished phases of each tier)") ] | step_and) end
         end) as $basis
      | {seconds: $sec, end: $end,
         rounds: (if $all[0].kind == "plan" and ($all | length) == 1 then {} else ($ru | map({key: .t, value: (.n // 0)}) | from_entries) end),
         basis: $basis}
      | . + {say: (
          if .end == null then "no milestone end time yet (\(.basis))"
          elif $all[0].kind == "plan" and ($all | length) == 1 then
            "Milestone end: planning \(dur(.seconds)), until around \(step_clock(.end; $t)); the rest follows once the work is planned"
          else "Milestone end: \(dur(.seconds)), until around \(step_clock(.end; $t))\(if ($counting | length) > 0 then ", counting \($counting)" else "" end)" end)}
      end
  end
