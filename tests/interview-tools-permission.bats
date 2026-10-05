#!/usr/bin/env bats
# R62 (F35): on yes, the interview carries on as /vbw:skills does, so it may run
# what /vbw:skills runs: the tooling workflow and npx skills. Without them the
# yes path stops on a permission prompt (L1: the skills' front matter).

load helper

tools_of() { sed -n 's/^allowed-tools: //p' "$PLUGIN_ROOT/skills/$1/SKILL.md"; }

@test "R62: the interview may run the tooling workflow and npx skills, like /vbw:skills" {
  local interview skills
  interview=$(tools_of interview)
  skills=$(tools_of skills)
  for t in 'Workflow(vbw:tooling)' 'Bash(npx skills *)'; do
    [[ "$skills" == *"$t"* ]] || { echo "/vbw:skills lacks $t"; false; }
    [[ "$interview" == *"$t"* ]] || { echo "the interview lacks $t"; false; }
  done
}
