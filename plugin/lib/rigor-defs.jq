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

# phase_finished($r): on a phase object, with the whole record as $r. A phase is
# finished when its plans are done, its requirements are proven (accepted, for
# [human] ones), no fix on them is still open, fixed or escalated, and, when its
# tier calls for QA (not express) or it has a [human] requirement, QA passed on
# the code that was proven.
def phase_finished($r):
  . as $ph
  | [$r.plans[] | select(.phase == $ph.id)] as $plans
  | [$r.requirements[] | select(.id as $q | $ph.reqs | index($q))] as $reqs
  | ($plans | length > 0 and all(.[]; .status == "done"))
    and all($reqs[]; .status | IN("proven", "accepted"))
    and ([$r.fixes[] | select(.req as $q | $q != null and ($ph.reqs | index($q))) | select(.status != "closed")] | length == 0)
    and ((($ph.tier // "express") == "express" and all($reqs[]; .proof == "auto"))
         or (($ph.qa.result // "") == "pass" and $ph.qa.tree == ($r.evidence.tree // "")));

# finish_phases: on the record. Writes outcome {tier, predicted, held,
# fix_rounds, qa_findings, escalations} once (predicted: the tier the work began
# at, which is the first escalation's from; a re-tier before any work is no miss) on every tiered phase that has just
# finished; an outcome already written is never rewritten.
def finish_phases:
  . as $r
  | .phases |= map(
      if has("outcome") or (has("tier") | not) or (phase_finished($r) | not) then .
      else . as $ph
        | [$r.fixes[] | select(.req as $q | $q != null and ($ph.reqs | index($q)))] as $fx
        | ((.escalations // [])[0].from // .tier) as $predicted
        | .outcome = {tier: .tier, predicted: $predicted, held: (.tier == $predicted),
                      fix_rounds: ([$fx[] | .attempts + 1] | add // 0),
                      qa_findings: ([$fx[] | select(.source == "qa")] | length),
                      escalations: ((.escalations // []) | length)}
      end);
