#!/usr/bin/env bats
# R239 (T209, D557, L1): the vibe skill says the chat never commits plan work by hand and
# follows the proof's Next line; docs/guards.md and the refusal table in docs/workflows.md
# name the new refusals (commit-tree for an agent under a lease; the chat's git history
# changes while an autonomous run or loop is armed), when they apply, and that the user's
# own commands are never checked.

load helper

SKILL="$PLUGIN_ROOT/skills/vibe/SKILL.md"
GUARDS="$REPO_ROOT/docs/guards.md"
WORKFLOWS="$REPO_ROOT/docs/workflows.md"

@test "R239: the vibe skill states that the chat never commits plan work by hand, naming every git history command, that commits go through vbw commit inside the run, and that it follows the proof's Next line" {
  grep -qi 'never commits plan work by hand' "$SKILL" || { echo "the skill does not say the chat never commits plan work by hand"; false; }
  local line cmd
  line=$(grep -i 'never commits plan work by hand' "$SKILL")
  for cmd in 'git commit' 'commit-tree' 'merge' 'rebase' 'cherry-pick' 'revert' 'am'; do
    [[ "$line" == *"$cmd"* ]] || { echo "the hand-commit sentence does not name $cmd: $line"; false; }
  done
  grep -q 'vbw commit' "$SKILL" && grep -qiE 'commits? go(es)? through `?vbw commit`? inside the run' "$SKILL" \
    || { echo "the skill does not say commits go through vbw commit inside the run"; false; }
  grep -qiE "follow(s)? the proof'?s `?Next`? line" "$SKILL" || { echo "the skill does not say the chat follows the proof's Next line"; false; }
}

@test "R239: docs/guards.md's refusal table names commit-tree beside commit, the chat's refusal while armed or in a loop, and that the user's own commands are never checked" {
  grep -E '^\|.*`commit`' "$GUARDS" | grep -q 'commit-tree' || { echo "the guards table row for git commit does not name commit-tree"; false; }
  grep -qiE '^\|.*(armed|autonomous run).*loop' "$GUARDS" || { echo "no table row for the chat's git commands while an autonomous run or loop is armed"; false; }
  grep -qi "user's own commands are never checked" "$GUARDS" || { echo "docs/guards.md does not say the user's own commands are never checked"; false; }
}

@test "R239: docs/workflows.md's 'Every refusal and its next step' table has the two refusals with vbw commit as the next step" {
  local table
  table=$(sed -n '/^### Every refusal and its next step/,/^### Refusals reach the user/p' "$WORKFLOWS")
  printf '%s\n' "$table" | grep -E '^\| Guards:' | grep -i 'commit-tree' | grep -qi 'lease' || { echo "no row for an agent's commit-tree under a lease"; false; }
  printf '%s\n' "$table" | grep -E '^\| Guards:' | grep -iE 'armed|autonomous' | grep -qi 'loop' || { echo "no row for the chat's git history change while armed or in a loop"; false; }
  printf '%s\n' "$table" | grep -E '^\| Guards:' | grep -iE 'commit-tree|armed' | grep -vq 'vbw commit' && { echo "a new refusal row does not name vbw commit as the next step"; false; }
  printf '%s\n' "$table" | grep -qi "user's own commands are never checked" || { echo "the refusal table does not say the user's own commands are never checked"; false; }
}
