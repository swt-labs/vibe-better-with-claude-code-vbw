# Definitions of adaptive rigor shared by every record update (record.sh loads
# this file into VBW_JQ_DEFS) and by the assessment program (rigor.jq).

def tiers: ["express", "standard", "deep"];
def tier_rank: . as $t | tiers | index($t);
def max_tier($b): if tier_rank >= ($b | tier_rank) then . else $b end;

# Risk categories, matched case-insensitively, in the order they are reported.
def risks: [
  {name: "sign-in", re: "(^|[^a-z])(sign[ _-]?in|log[ _-]?in|auth)([^a-z]|$)|authenticat|authoriz|oauth|password"},
  {name: "payments", re: "payment|billing|invoice|stripe|purchase"},
  {name: "data migration", re: "migration|migrate"},
  {name: "secrets", re: "secret|credential|api[ _-]?key|private[ _-]?key|(^|[^a-z])\\.env([^a-z]|$)"},
  {name: "deletion", re: "delet|destroy|purge|drop[ _-]?table"},
  {name: "CI", re: "\\.github/workflows|\\.gitlab-ci|circleci|jenkins|(^|[^a-z])ci([^a-z]|$)"}
];

# risk_name: on a text, the name of the first risk category it matches, or null.
def risk_name: . as $t | ([risks[] | select(. as $c | $t | test($c.re; "i")) | .name] | .[0]);

# escalate($to; $reason; $at): on a phase object, inside a record update. Raises
# the tier to $to (null = one step up; deep stays deep) and appends {at, from,
# to, reason} to escalations. A reason already recorded is not recorded twice,
# and an explicit target that is not higher is never applied.
def escalate($to; $reason; $at):
  (.tier // "express") as $from
  | (if $to == null then tiers[([($from | tier_rank) + 1, 2] | min)] else $to end) as $target
  | if (($to != null) and (($target | tier_rank) <= ($from | tier_rank))) or (((.escalations // []) | any(.[]; .reason == $reason)))
    then .
    else .tier = $target | .escalations = ((.escalations // []) + [{at: $at, from: $from, to: $target, reason: $reason}])
    end;

# escalate_phases($ids; $to; $reason; $at): escalate the phases with these ids.
def escalate_phases($ids; $to; $reason; $at):
  .phases |= map(if .id as $i | $ids | index($i) then escalate($to; $reason; $at) else . end);
