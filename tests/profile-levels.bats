#!/usr/bin/env bats
# R39 (docs/interview.md): every VBW step that talks to the user, and every agent
# whose words reach the user, receives the user's level, explanation depth and
# involvement and writes at that level. The kernel hands the three values over
# (vbw next --json, with a neutral default); skills, agents and workflow calls
# carry them. The prompts are text, so the proof is structural (L1): a list of
# every such file that fails when one lacks the three values.

load helper

setup() { vbw_setup; vbw_git_project; "$VBW" init > /dev/null; }
teardown() { vbw_teardown; }

skills() { find "$PLUGIN_ROOT/skills" -name SKILL.md | LC_ALL=C sort; }
agents() { find "$PLUGIN_ROOT/agents" -name '*.md' | LC_ALL=C sort; }
workflows() { find "$PLUGIN_ROOT/workflows" -name '*.js' | LC_ALL=C sort; }

# carries_profile FILE: the prompt names all three values it must apply.
carries_profile() {
  grep -qi 'level' "$1" && grep -qi 'explanation depth' "$1" && grep -qi 'involvement' "$1"
}

@test "R39: vbw next --json carries the user's level, explanation depth and involvement" {
  "$VBW" interview set level "senior engineer" > /dev/null
  "$VBW" interview set depth "technical and brief" > /dev/null
  "$VBW" interview set involvement "I make the calls" > /dev/null
  "$VBW" interview keep private > /dev/null
  run "$VBW" next --json < /dev/null
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.profile.level == "senior engineer" and .profile.depth == "technical and brief"
    and .profile.involvement == "I make the calls" and .profile.interviewed == true'
}

@test "R39: with no answers it carries an explicit neutral default" {
  run "$VBW" next --json < /dev/null
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.profile.interviewed == false
    and .profile.depth == "plain with technical terms explained"
    and .profile.involvement == "options with a recommendation"
    and (.profile.level | type == "string" and length > 0)'
}

@test "R39: a partly answered interview fills the gaps with the neutral default" {
  "$VBW" interview set depth "plain words" > /dev/null
  run "$VBW" next --json < /dev/null
  printf '%s' "$output" | jq -e '.profile.depth == "plain words" and .profile.involvement == "options with a recommendation"'
}

@test "R39: machine-read output does not change with the level: only the profile field differs" {
  local a b c
  a=$("$VBW" next --json < /dev/null | jq -S 'del(.profile)')
  "$VBW" interview set level "never" > /dev/null
  "$VBW" interview set depth "plain words" > /dev/null
  "$VBW" interview set involvement "decide and tell me" > /dev/null
  b=$("$VBW" next --json < /dev/null | jq -S 'del(.profile)')
  "$VBW" interview set level "senior engineer" > /dev/null
  "$VBW" interview set depth "technical and brief" > /dev/null
  "$VBW" interview set involvement "I make the calls" > /dev/null
  c=$("$VBW" next --json < /dev/null | jq -S 'del(.profile)')
  [ "$a" = "$b" ]
  [ "$b" = "$c" ]
  "$VBW" next --json < /dev/null | jq -e '.profile | has("level") and has("depth") and has("involvement")'
}

@test "R39: every skill hands the user's three values to its prompt, and none is skipped" {
  local f n=0
  while IFS= read -r f; do
    n=$((n + 1))
    carries_profile "$f" || { echo "does not carry level, explanation depth and involvement: $f"; false; }
    case "$f" in
      */skills/vibe/SKILL.md) grep -qF 'profile' "$f" ;;
      *) grep -qF 'bin/vbw" interview' "$f" || { echo "does not read the answers (vbw interview): $f"; false; } ;;
    esac
  done < <(skills)
  [ "$n" -ge 26 ] || { echo "only $n skills found: the scan is broken"; false; }
}

@test "R39: every agent that can reach the user receives and applies the three values" {
  local f n=0 role
  while IFS= read -r f; do
    n=$((n + 1))
    carries_profile "$f" || { echo "does not carry level, explanation depth and involvement: $f"; false; }
  done < <(agents)
  [ "$n" -eq 7 ]
  for role in architect lead qa docs debugger scout dev; do
    carries_profile "$PLUGIN_ROOT/agents/$role.md"
  done
}

@test "R39: involvement is honored: the three settings each name what VBW does with a decision" {
  local f s
  for f in "$PLUGIN_ROOT/skills/vibe/SKILL.md" "$PLUGIN_ROOT/agents/architect.md"; do
    for s in "decide and tell me" "options with a recommendation" "I make the calls"; do
      grep -qF -- "$s" "$f" || { echo "$f does not handle involvement '$s'"; false; }
    done
  done
  # Architect Job 1 (the decision boundary) is written against each setting.
  awk '/^## Job 1/ { on = 1; next } /^## Job 2/ { on = 0 } on' "$PLUGIN_ROOT/agents/architect.md" > "$TEST_ROOT/job1.txt"
  for s in "decide and tell me" "options with a recommendation" "I make the calls"; do
    grep -qF -- "$s" "$TEST_ROOT/job1.txt" || { echo "Job 1 ignores involvement '$s'"; false; }
  done
  # The router puts decisions to the user before proceeding for 'I make the calls'.
  grep -iE 'I make the calls' "$PLUGIN_ROOT/skills/vibe/SKILL.md" | grep -qiE 'before|ask|put'
  grep -iE 'decide and tell me' "$PLUGIN_ROOT/skills/vibe/SKILL.md" | grep -qiE 'vbw decide|decid'
}

@test "R39: every workflow agent call carries the profile in its task text and still passes a schema" {
  local f calls voices schemas n=0
  while IFS= read -r f; do
    n=$((n + 1))
    grep -qF 'args.profile' "$f" || { echo "does not read args.profile: $f"; false; }
    calls=$(grep -cE '(^|[^A-Za-z_])agent\(' "$f" || true)
    # shellcheck disable=SC2016 # the literal JavaScript placeholder
    voices=$(grep -cF '${voice}' "$f" || true)
    schemas=$(grep -cE 'schema' "$f" || true)
    [ "$calls" -ge 1 ] || { echo "no agent call found: $f"; false; }
    [ "$voices" -ge "$calls" ] || { echo "$f: $calls agent calls but the profile is in $voices task texts"; false; }
    [ "$schemas" -ge "$calls" ] || { echo "$f: an agent call without a schema"; false; }
  done < <(workflows)
  # Every workflow was checked: at least the seven core ones, and any added since.
  [ "$n" -ge 7 ] && [ "$n" -eq "$(workflows | wc -l | tr -d ' ')" ]
}

@test "R39: the router hands the profile to every workflow it starts" {
  local r="$PLUGIN_ROOT/skills/vibe/SKILL.md"
  grep -iE 'profile' "$r" | grep -qiE 'workflow|args'
}

@test "R39: prompts stay within their budgets: agents 1.5k tokens, mode prompts 3k, router 2k, all prompts 16k (owner raised it from 15k on 2026-10-04)" {
  local f total=0 w
  while IFS= read -r f; do
    w=$(wc -w < "$f"); total=$((total + w))
    [ "$w" -le 900 ] || { echo "$f has $w words"; false; }
  done < <(agents)
  while IFS= read -r f; do
    w=$(wc -w < "$f"); total=$((total + w))
    case "$f" in */skills/vibe/SKILL.md) [ "$w" -le 1400 ] ;; *) [ "$w" -le 2000 ] ;; esac || { echo "$f has $w words"; false; }
  done < <(skills)
  echo "all prompts: $total words"
  # About 1.4 tokens a word: the owner doubled 11,400 words to 22,800 on 2026-10-07.
  [ "$total" -le 22800 ]
}

@test "R39: the workflows stay within 1,500 lines of JavaScript" {
  local total=0 f n
  while IFS= read -r f; do
    n=$(grep -cvE '^[[:space:]]*(//|$)' "$f" || true)
    total=$((total + n))
  done < <(workflows)
  [ "$total" -le 1500 ]
}
