#!/usr/bin/env bats
# R31: the Lead and the express router write rules with the "rules" key of vbw apply.
# R211, R212, R215: the Lead's brief states the rules vbw apply enforces on the plan's
# checks and rules. R220: its Lean checks line says the failing cases a case filter
# names are written at planning, before vbw apply.

load helper

setup() { vbw_setup; }
teardown() { vbw_teardown; }

@test "the Lead writes rules through the \"rules\" key of vbw apply" {
  grep -q '"rules"' "$PLUGIN_ROOT/agents/lead.md"
}

@test "the router's express apply example carries rules" {
  grep -q '"rules":\[{"req"' "$PLUGIN_ROOT/skills/vibe/SKILL.md"
}

# R211 and R212 (T187, T191): the Lead's brief states the two rules vbw apply enforces.

@test "R211 R215: the Lead's brief says a check's rules belong to one plan: several open plans of a requirement, whatever their order and the same wave included, each get a check of their own" {
  grep -q "check's rules belong to one plan" "$PLUGIN_ROOT/agents/lead.md" || { echo "no sentence saying a check's rules belong to one plan"; false; }
  grep "check's rules belong to one plan" "$PLUGIN_ROOT/agents/lead.md" | grep -q 'whatever their order' || { echo "the sentence does not cover plans whatever their order"; false; }
  grep "check's rules belong to one plan" "$PLUGIN_ROOT/agents/lead.md" | grep -q 'same wave included' || { echo "the sentence does not name the same wave"; false; }
  grep 'check of their own' "$PLUGIN_ROOT/agents/lead.md" | grep -qi 'case filter' || { echo "the sentence does not offer the same file with a case filter as a distinct check"; false; }
  grep "check's rules belong to one plan" "$PLUGIN_ROOT/agents/lead.md" | grep -q 'vbw apply. refuses' || { echo "the sentence does not say vbw apply refuses it"; false; }
}

@test "R212: the Lead's brief rule 7 (Rules) says the plan is named on every rule of the requirement or on none" {
  grep -E '^7\. \*\*Rules' "$PLUGIN_ROOT/agents/lead.md" | grep -q 'every rule' || { echo "rule 7 does not say every rule"; false; }
  grep -E '^7\. \*\*Rules' "$PLUGIN_ROOT/agents/lead.md" | grep -q 'or on none' || { echo "rule 7 does not say or on none"; false; }
}

@test "R220: the Lead's brief Lean checks line says the filter names cases the file already holds, written at planning before vbw apply, because vbw apply refuses an empty match and a Dev cannot add them later" {
  local line
  line=$(grep -E '^[[:space:]]*- \*\*Lean checks' "$PLUGIN_ROOT/agents/lead.md")
  [ -n "$line" ] || { echo "no Lean checks line in rule 6"; false; }
  printf '%s\n' "$line" | grep -q 'already holds' || { echo "the line does not say the filter names cases the file already holds"; false; }
  printf '%s\n' "$line" | grep -q 'at planning' || { echo "the line does not say the cases are written at planning"; false; }
  printf '%s\n' "$line" | grep -Eq 'before .?.?vbw apply' || { echo "the line does not say before vbw apply"; false; }
  printf '%s\n' "$line" | grep -Eq 'refuses[^.]*case filter[^.]*no case' || { echo "the line does not say vbw apply refuses a case filter matching no case name"; false; }
  printf '%s\n' "$line" | grep -q 'protected' || { echo "the line does not say a Dev cannot add the cases later (check files are protected during the build)"; false; }
}

# R259 (T235): a requirement reworded with its rules kept is reviewed by the Lead at the
# next plan step: the router passes vbw next's detail.reworded to the planning workflow,
# the workflow names those requirements in the Lead's prompt, and the Lead's
# specification says to keep a rule that still holds, reword one whose words are now
# wrong, or retire one, each through vbw apply --patch; a rule is removed only so.

@test "R259: the router passes detail.reworded to the planning workflow, which names the reworded requirements in the Lead's plan prompt" {
  local p="$PLUGIN_ROOT/workflows/planning.js"
  grep -q 'reworded' "$PLUGIN_ROOT/skills/vibe/SKILL.md" || { echo "the router does not pass detail.reworded"; false; }
  grep -E 'vbw:planning|"requirements": <requirements>' "$PLUGIN_ROOT/skills/vibe/SKILL.md" | grep -q 'reworded' || { echo "the planning workflow's args do not carry reworded"; false; }
  grep -q 'args.reworded\|args && args.reworded\|reworded' "$p" || { echo "planning.js never reads args.reworded"; false; }
  grep -E 'Plan these phases' "$p" | grep -q 'reworded' || { echo "the Lead's plan prompt does not name the reworded requirements"; false; }
}

@test "R259: the Lead's specification says to review a reworded requirement's kept rules: keep, reword or retire each through vbw apply --patch, never removed by sync" {
  local lead="$PLUGIN_ROOT/agents/lead.md"
  grep -qi 'reworded' "$lead" || { echo "the Lead's brief never mentions a reworded requirement"; false; }
  grep -iE 'reworded' "$lead" | grep -qiE 'rules' || { echo "the brief does not tie a reworded requirement to its kept rules"; false; }
  grep -iE 'reworded|kept' "$lead" | grep -qiE 'retire' || { echo "the brief does not offer retiring a kept rule"; false; }
  grep -iE 'reworded|kept' "$lead" | grep -qF -- '--patch' || { echo "the brief does not route the review through vbw apply --patch"; false; }
  grep -qiE 'never by (a )?(spec )?sync|sync never removes|only (by|through) an explicit' "$lead" || { echo "the brief does not say a rule is removed only by an explicit retire"; false; }
}
