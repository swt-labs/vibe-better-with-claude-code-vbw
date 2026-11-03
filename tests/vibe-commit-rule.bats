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
  # Fixed strings: a backtick inside double quotes would run as a command and drop part of the pattern.
  [[ "$line" == *"follows the proof's Next line"* ]] || { echo "the hand-commit rule does not say the chat follows the proof's Next line: $line"; false; }
  local prove
  prove=$(grep '^\*\*prove\*\*:' "$SKILL")
  [[ "$prove" == *"follow the proof's Next line"* || "$prove" == *"follow the proof's line that starts with Next:"* ]] \
    || { echo "the prove step does not say to follow the proof's Next line: $prove"; false; }
  [[ "$prove" == *"never a commit of your own"* ]] || { echo "the prove step does not rule out a commit of the chat's own: $prove"; false; }
}

@test "R239: docs/guards.md's refusal table names commit-tree beside commit, the chat's refusal while armed or in a loop, and that the user's own commands are never checked" {
  grep -E '^\| `git commit`, ' "$GUARDS" | grep -qF '`commit-tree`' || { echo "the guards table row for git commit does not name commit-tree"; false; }
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

# R245 (T217): the chat commits nothing by hand, a ship refusal included, never touches the
# user's own uncommitted files (it asks the user what to do with them), and never attributes
# an instruction to the user that the user did not type; no kernel or skill message tells the
# chat to commit a file outside the milestone's work; docs/guards.md and docs/workflows.md say
# it where the R239 rows are.

@test "R245: the vibe skill says the chat commits nothing by hand, a ship refusal included (no git commit, add, stash, checkout or reset of files, no commit of a submodule pointer) and follows the refusal's Next line; and that a user's own uncommitted files are the user's: never committed, staged, stashed, discarded or named as blocking, the chat asks the user what to do and waits" {
  local line w
  line=$(grep -i 'commits nothing by hand' "$SKILL")
  [ -n "$line" ] || { echo "the skill does not say the chat commits nothing by hand"; false; }
  for w in 'ship refusal' 'git commit' 'add' 'stash' 'checkout' 'reset' 'submodule pointer' 'Next line'; do
    [[ "$line" == *"$w"* ]] || { echo "the commits-nothing sentence does not name $w: $line"; false; }
  done
  line=$(grep -i 'anything VBW did not write' "$SKILL")
  [ -n "$line" ] || { echo "the skill does not say a user's own uncommitted files (anything VBW did not write) are the user's"; false; }
  for w in "user's own uncommitted files" 'never commits' 'stages' 'stashes' 'discards' 'blocking' 'asks the user' 'waits'; do
    [[ "$line" == *"$w"* ]] || { echo "the user's-own-files sentence does not say $w: $line"; false; }
  done
}

@test "R245: the vibe skill says the chat never attributes an instruction the user did not type (no 'as you asked'), and that an empty or unclear /vbw:vibe turn runs vbw next and reports its action, never inferring a request from silence" {
  local line
  line=$(grep -i 'as you asked' "$SKILL")
  [ -n "$line" ] || { echo "the skill does not rule out 'as you asked' for an action the user did not request"; false; }
  [[ "$line" == *"did not type"* ]] || { echo "the attribution sentence does not say 'did not type': $line"; false; }
  line=$(grep -i 'from silence' "$SKILL")
  [ -n "$line" ] || { echo "the skill does not say the chat never infers a request from silence"; false; }
  [[ "$line" == *"vbw next"* && "$line" == *"reports its action"* ]] || { echo "the empty-turn sentence does not say the turn runs vbw next and reports its action: $line"; false; }
  [[ "$line" == *"empty"* ]] || { echo "the empty-turn sentence does not name an empty turn: $line"; false; }
}

@test "R245: no kernel or skill message tells the chat to commit a file outside the milestone's work: the old ship wording is gone, and every message telling to commit names vbw commit, check files or VBW's own files" {
  ! grep -rqF 'commit it, then vbw ship' "$PLUGIN_ROOT" || { echo "plugin/ still holds 'commit it, then vbw ship'"; false; }
  ! grep -rqF 'the proven work is not committed' "$PLUGIN_ROOT" || { echo "plugin/ still holds 'the proven work is not committed'"; false; }
  # A message telling to commit something, outside comment lines: it names what to commit
  # with (vbw commit) or whose files they are (check files, VBW files, the legacy folder).
  local bad
  bad=$(grep -nE 'commit (it|them|its work)\b' "$PLUGIN_ROOT"/lib/*.sh "$PLUGIN_ROOT"/skills/*/SKILL.md \
    | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' \
    | grep -vE 'vbw commit|check files|VBW files|VBW_LEGACY' || true)
  [ -z "$bad" ] || { printf 'a message tells the chat to commit without naming vbw commit or whose files they are:\n%s\n' "$bad"; false; }
}

@test "R245 docs: docs/guards.md and docs/workflows.md say, where the R239 rows are, that the rule also holds on a ship refusal and that the user's own files are never committed by VBW's chat" {
  grep -E '^\|.*(armed|autonomous run)' "$GUARDS" | grep -i 'ship refusal' | grep -qi "user's own files" || { echo "docs/guards.md's chat row does not say the rule holds on a ship refusal and that the user's own files are never committed"; false; }
  grep -E '^\|.*(armed|autonomous run)' "$GUARDS" | grep -i 'ship refusal' | grep -qi "never committed" || { echo "docs/guards.md's chat row does not say never committed"; false; }
  local table
  table=$(sed -n '/^### Every refusal and its next step/,/^### Refusals reach the user/p' "$WORKFLOWS")
  printf '%s\n' "$table" | grep -E '^\| Guards:' | grep -iE 'armed|autonomous' | grep -i 'ship refusal' | grep -qi "user's own files" || { echo "the refusal table's chat row does not say the rule holds on a ship refusal and that the user's own files are never committed"; false; }
}
