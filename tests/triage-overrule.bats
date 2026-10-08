#!/usr/bin/env bats
# R122 (decision D207; L1): when the user picks a sort other than VBW's, VBW
# asks exactly one follow-up question that says plainly what the choice
# displaces and its risk, with ready reasons, the user's own words, or keeping
# VBW's sorting. An overrule with a reason is followed and recorded with vbw
# decide (the idea, VBW's sort, the user's sort, the reason); keeping VBW's
# sorting records nothing; the warning is said once per idea. The skill's text
# (plugin/skills/triage/SKILL.md) is what the main conversation follows (L1);
# the decision itself is written by the kernel, run for real below.

load helper

SKILL="$PLUGIN_ROOT/skills/triage/SKILL.md"

flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
has() { flat "$1" | grep -qE -- "$2" || { echo "the triage skill lacks: $2"; return 1; }; }

@test "R122: a sort other than VBW's gets exactly one follow-up question, in a menu" {
  [ -f "$SKILL" ]
  has "$SKILL" 'overrul'
  has "$SKILL" 'exactly one (follow-up )?question|one follow-up question'
  has "$SKILL" 'askuserquestion'
}

@test "R122: the question says plainly what the choice displaces and its risk, for 'now' and for 'later' instead of 'now'" {
  has "$SKILL" 'displace'
  has "$SKILL" 'risk'
  has "$SKILL" 'grows the milestone'
  has "$SKILL" '(new|another) approval'
  has "$SKILL" 'delay'
  has "$SKILL" 'urgent'
  has "$SKILL" 'unfixed|not fixed|stays broken'
}

@test "R122: the options are one or two ready reasons, the user's own words, or keep VBW's sorting" {
  has "$SKILL" '(one or two|1-2|two) ready reasons'
  has "$SKILL" 'own words'
  has "$SKILL" "keep vbw's sort"
}

@test "R122: an overrule with a reason is followed and recorded with vbw decide naming the idea, both sorts and the reason; keeping VBW's sorting records no overrule" {
  grep -qF 'vbw decide' "$SKILL"
  has "$SKILL" "vbw decide \"[^\"]*(idea|<)[^\"]*\" \"[^\"]*reason"
  has "$SKILL" "vbw's sort.{0,200}(user's sort|their sort|the user's choice)|(user's sort|their sort).{0,200}vbw's sort"
  has "$SKILL" "follow the user's sort|follow their (sort|choice)|apply the user's sort"
  has "$SKILL" "keep vbw's sorting.{0,200}(no overrule|nothing|no decision)|(records|record) no overrule"
}

@test "R122: the warning is said once per idea: never repeated, argued or asked again in that conversation" {
  has "$SKILL" 'once per idea'
  has "$SKILL" 'never (repeat|argue)|do not (repeat|argue)|no (repeat|arguing)'
  has "$SKILL" '(ask|asks) again'
}

@test "R122: the decision the skill records is kept by the kernel with the reason as its why" {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  run "$VBW" decide "Triage overrule: Dark mode: VBW sorted later, the user chose now" "a customer asked for it this week" < /dev/null
  [ "$status" -eq 0 ] || { echo "$output"; vbw_teardown; false; }
  jq -e '.decisions[-1] | (.text | test("VBW sorted later")) and (.text | test("chose now")) and .why == "a customer asked for it this week"' .vbw/record.json
  vbw_teardown
}
