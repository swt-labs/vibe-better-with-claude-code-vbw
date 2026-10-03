# Adaptive rigor: the tier floor of each phase, from measured signals.
# Input: the record. Args: $facts (object: planned path -> bytes, for the
# existing regular files only), $ids (array of phase ids, or null = the
# current milestone's phases).
# Output: [{id, tier, floor, reasons}]. The floor comes from the signals alone;
# tier is the phase's own tier when it is higher (the Architect may only raise).

def tiers: ["express", "standard", "deep"];
def rank: . as $t | tiers | index($t);
def at_least($a; $b): if ($a | rank) >= ($b | rank) then $a else $b end;

# Risk categories, matched case-insensitively, in the order they are reported.
def risks: [
  {name: "sign-in", re: "(^|[^a-z])(sign[ _-]?in|log[ _-]?in|auth)([^a-z]|$)|authenticat|authoriz|oauth|password"},
  {name: "payments", re: "payment|billing|invoice|stripe|purchase"},
  {name: "data migration", re: "migration|migrate"},
  {name: "secrets", re: "secret|credential|api[ _-]?key|private[ _-]?key|(^|[^a-z])\\.env([^a-z]|$)"},
  {name: "deletion", re: "delet|destroy|purge|drop[ _-]?table"},
  {name: "CI", re: "\\.github/workflows|\\.gitlab-ci|circleci|jenkins|(^|[^a-z])ci([^a-z]|$)"}
];

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
    | ($files | any(.[]; $facts[.] != null)) as $existing
    | ($r.commands.test != null) as $has_tests
    | ([$r.requirements[] | select(.id as $q | $ph.reqs | index($q))] ) as $mine
    | ([ $files[] | {src: ., text: .} ]
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
    | ( [ (if $nreqs >= 6 then "deep" elif $nreqs >= 3 then "standard" else "express" end),
          (if ($files | length) >= 10 then "deep" elif ($files | length) >= 5 then "standard" else "express" end),
          (if $bytes >= 500000 then "deep" elif $bytes >= 100000 then "standard" else "express" end),
          (if ($risk | length) > 0 then "deep" else "express" end),
          (if ($breaks | length) >= 4 then "deep" elif ($breaks | length) >= 1 then "standard" else "express" end),
          (if $existing and ($has_tests | not) then "standard" else "express" end)
        ] | reduce .[] as $t ("express"; at_least(.; $t))) as $floor
    | (if ($ph.tier // $floor) | rank > ($floor | rank) then $ph.tier else $floor end) as $tier
    | { id: $ph.id, tier: $tier, floor: $floor,
        reasons: ([ "requirements: \($nreqs)",
                    "files: \($files | length) (\($bytes) bytes)",
                    (if ($risk | length) == 0 then "risk: none"
                     else "risk: " + ([$risk[] | "\(.name) (\(.src))"] | join(", ")) end),
                    (if ($breaks | length) == 0 then "breaks: none" else "breaks: " + ($breaks | join(", ")) end),
                    (if $has_tests then "tests: project test command" else "tests: no project test command" end)
                  ] + (if $tier != $floor then ["Architect raised the tier to \($tier)"] else [] end)) }
  ]
