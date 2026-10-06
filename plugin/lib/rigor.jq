# Adaptive rigor: the tier floor of each phase, from measured signals.
# Input: the record. Args: $facts (object: planned path -> bytes, for the
# existing regular files only), $ids (array of phase ids, or null = the
# current milestone's phases).
# Output: [{id, tier, floor, reasons}]. The floor comes from the signals alone;
# tier is the phase's own tier when it is higher (the Architect may only raise).

# The tier, risk and escalate definitions are in rigor-defs.jq (loaded first).

# A plan file entry and a path overlap: equal, or one is a directory entry
# (ending in /) holding the other.
def overlaps($b): . as $a
  | $a == $b or (($a | endswith("/")) and ($b | startswith($a))) or (($b | endswith("/")) and ($a | startswith($b)));

def rid: ltrimstr("R") | tonumber? // 0;

. as $r
| ($ids // [$r.phases[] | select(.milestone == $r.milestone.id) | .id]) as $want
| [ $r.phases[] | select(.id as $i | $want | index($i)) | . as $ph
    | ([$r.plans[] | select(.phase == $ph.id) | .files[]] | unique) as $files
    | ($ph.reqs | length) as $nreqs
    | ([$files[] | $facts[.] // empty] | add // 0) as $bytes
    | ($files | any(.[]; $facts[.] != null and (is_doc | not))) as $existing
    | ($r | has_tests) as $has_tests
    | ([$r.requirements[] | select(.id as $q | $ph.reqs | index($q))] ) as $mine
    | ([ $files[] | select(is_doc | not) | {src: ., text: .} ]
       + [{src: "phase title", text: $ph.title}]
       + [{src: "phase goal", text: ($ph.goal // "")}]
       + [$mine[] | {src: .id, text: .text}]) as $haystack
    | [ risks[] | . as $c
        | ([$haystack[] | select(.text | test($c.re; "i")) | .src] | .[0]) as $hit
        | select($hit != null) | {name: $c.name, src: $hit} ] as $risk
    | ($ph.reqs) as $own
    | ([$r.requirements[] | select(.status == "proven" and (.id as $q | $own | index($q) | not)) | .id as $q
        | select([$r.plans[] | select(.phase != $ph.id and (.reqs | index($q))) | .files[]
                  | . as $f | select($files | any(.[]; overlaps($f)))] | length > 0) | $q]
       | sort_by(rid)) as $breaks
    | ( [ ($nreqs | sig_reqs),
          ($files | length | sig_files),
          ($bytes | sig_bytes),
          (if ($risk | length) > 0 then "deep" else "express" end),
          ($breaks | length | sig_breaks),
          sig_tests($existing; $has_tests)
        ] | reduce .[] as $t ("express"; max_tier($t))) as $floor
    | (if ($ph.tier // $floor) | tier_rank > ($floor | tier_rank) then $ph.tier else $floor end) as $tier
    | { id: $ph.id, tier: $tier, floor: $floor,
        reasons: ([ "requirements: \($nreqs)",
                    "files: \($files | length) (\($bytes) bytes)",
                    (if ($risk | length) == 0 then "risk: none"
                     else "risk: " + ([$risk[] | "\(.name) (\(.src))"] | join(", ")) end),
                    (if ($breaks | length) == 0 then "breaks: none" else "breaks: " + ($breaks | join(", ")) end),
                    (if $has_tests then "tests: project test command" else "tests: no project test command" end)
                  ] + (if $tier != $floor then ["Architect raised the tier to \($tier)"] else [] end)) }
  ]
