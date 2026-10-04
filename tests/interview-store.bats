#!/usr/bin/env bats
# R38 (docs/interview.md): the interview's answers (level, explanation depth,
# involvement) are kept private in the clone's git directory or shared in the
# project record, shown by vbw status, changed one at a time (/vbw:profile), and
# an older record or answers file without them reads as "not yet interviewed".
# Run through the kernel on hermetic projects (L1).

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  git add -A && git commit -q -m "chore: init"
  COMMON=$(git rev-parse --path-format=absolute --git-common-dir)
  PRIVATE="$COMMON/vbw/profile.json"
  LEVELS=("never" "small scripts or no-code" "professionally" "senior engineer")
  DEPTHS=("plain words" "plain with technical terms explained" "technical and brief")
  INVOLVEMENTS=("decide and tell me" "options with a recommendation" "I make the calls")
}

teardown() { vbw_teardown; }

# answer LEVEL DEPTH INVOLVEMENT: record the three answers.
answer() {
  "$VBW" interview set level "$1" > /dev/null
  "$VBW" interview set depth "$2" > /dev/null
  "$VBW" interview set involvement "$3" > /dev/null
}

kept() { "$VBW" interview --json | jq -r '.kept'; }

# no_private_copy: the private answers file holds no answers (or does not exist).
no_private_copy() {
  if [ -f "$PRIVATE" ] && jq -e 'has("level") or has("depth") or has("involvement")' "$PRIVATE" > /dev/null; then
    echo "a private copy of the answers is left in $PRIVATE"
    return 1
  fi
}

@test "R38: a kernel command records the three answers and refuses any other value, naming the allowed ones" {
  local v
  for v in "${LEVELS[@]}"; do vbw_run interview set level "$v"; [ "$status" -eq 0 ]; done
  for v in "${DEPTHS[@]}"; do vbw_run interview set depth "$v"; [ "$status" -eq 0 ]; done
  for v in "${INVOLVEMENTS[@]}"; do vbw_run interview set involvement "$v"; [ "$status" -eq 0 ]; done
  vbw_run interview set level "wizard"
  [ "$status" -ne 0 ]
  for v in "${LEVELS[@]}"; do [[ "$output" == *"$v"* ]]; done
  vbw_run interview set depth "verbose"
  [ "$status" -ne 0 ]
  for v in "${DEPTHS[@]}"; do [[ "$output" == *"$v"* ]]; done
  vbw_run interview set involvement "whatever"
  [ "$status" -ne 0 ]
  for v in "${INVOLVEMENTS[@]}"; do [[ "$output" == *"$v"* ]]; done
  vbw_run interview set colour "blue"
  [ "$status" -ne 0 ]
  # The last valid values stand: a refused value writes nothing.
  [ "$("$VBW" interview --json | jq -r '.level + "|" + .depth + "|" + .involvement')" = "senior engineer|technical and brief|I make the calls" ]
}

@test "R38: private answers live in the clone's git directory beside consent.json and never touch the project" {
  local before
  before=$(cksum < .vbw/record.json)
  answer "never" "plain words" "decide and tell me"
  vbw_run interview keep private
  [ "$status" -eq 0 ]
  [ -f "$PRIVATE" ]
  jq -e '.level == "never" and .depth == "plain words" and .involvement == "decide and tell me"' "$PRIVATE"
  [ "$(kept)" = "private" ]
  [ "$(cksum < .vbw/record.json)" = "$before" ]
  jq -e '.project | has("interview") | not' .vbw/record.json
  [ "$(git ls-files | grep -ci profile || true)" -eq 0 ]
  [ -z "$(git status --porcelain)" ]
}

@test "R38: shared answers are written to the project record by the kernel, valid at schema 1, with no private copy" {
  answer "senior engineer" "technical and brief" "I make the calls"
  vbw_run interview keep project
  [ "$status" -eq 0 ]
  jq -e '.schema == 1 and .project.interview.level == "senior engineer"
    and .project.interview.depth == "technical and brief"
    and .project.interview.involvement == "I make the calls"' .vbw/record.json
  [ "$(kept)" = "project" ]
  no_private_copy
  vbw_run status
  [ "$status" -eq 0 ]
}

@test "R38: choosing the other location moves the answers and leaves no copy behind" {
  answer "professionally" "plain with technical terms explained" "options with a recommendation"
  "$VBW" interview keep project
  "$VBW" interview keep private
  [ "$(kept)" = "private" ]
  jq -e '.project | has("interview") | not' .vbw/record.json
  jq -e '.level == "professionally"' "$PRIVATE"
  "$VBW" interview keep project
  [ "$(kept)" = "project" ]
  no_private_copy
  jq -e '.project.interview.depth == "plain with technical terms explained"' .vbw/record.json
}

@test "R38: private answers made in one worktree are read in another worktree of the clone" {
  git worktree add -q "$TEST_ROOT/wt" -b other
  answer "never" "plain words" "I make the calls"
  "$VBW" interview keep private
  run bash -c 'cd "$1" && "$2" interview --json' _ "$TEST_ROOT/wt" "$VBW"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.kept == "private" and .level == "never" and .involvement == "I make the calls" and .interviewed == true'
}

@test "R38: concurrent writes from two worktrees are both kept" {
  git worktree add -q "$TEST_ROOT/wt" -b other
  for _ in 1 2 3 4 5; do
    rm -f "$PRIVATE"
    (cd "$TEST_ROOT/wt" && "$VBW" interview set level "senior engineer" > /dev/null) &
    "$VBW" interview set depth "technical and brief" > /dev/null &
    (cd "$TEST_ROOT/wt" && "$VBW" interview set involvement "I make the calls" > /dev/null) &
    wait
    jq -e '.level == "senior engineer" and .depth == "technical and brief" and .involvement == "I make the calls"' "$PRIVATE"
  done
}

@test "R38: answers shared by choice are seen by a second worktree once the project record is committed" {
  answer "small scripts or no-code" "plain words" "options with a recommendation"
  "$VBW" interview keep project
  git add .vbw/record.json && git commit -q -m "chore(vbw): share the interview answers"
  git worktree add -q "$TEST_ROOT/wt" -b other
  run bash -c 'cd "$1" && "$2" interview --json' _ "$TEST_ROOT/wt" "$VBW"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.kept == "project" and .level == "small scripts or no-code" and .depth == "plain words" and .interviewed == true'
}

@test "R38: vbw status shows the three answers and where they are kept; with none it says the interview has not been done" {
  vbw_run status
  [ "$status" -eq 0 ]
  [[ "$output" == *"the interview has not been done"* ]]
  answer "senior engineer" "technical and brief" "I make the calls"
  "$VBW" interview keep private
  vbw_run status
  [ "$status" -eq 0 ]
  [[ "$output" == *"senior engineer"* && "$output" == *"technical and brief"* && "$output" == *"I make the calls"* ]]
  [[ "$output" == *"private"* ]]
  vbw_run status --json
  printf '%s' "$output" | jq -e '.interview.kept == "private" and .interview.level == "senior engineer" and .interview.interviewed == true'
  "$VBW" interview keep project
  vbw_run status
  [[ "$output" == *"project"* && "$output" == *"technical and brief"* ]]
  vbw_run status --json
  printf '%s' "$output" | jq -e '.interview.kept == "project"'
}

@test "R38: changing one answer later leaves the other two untouched, in either location" {
  answer "never" "plain words" "decide and tell me"
  "$VBW" interview keep private
  vbw_run interview set depth "technical and brief"
  [ "$status" -eq 0 ]
  "$VBW" interview --json | jq -e '.level == "never" and .depth == "technical and brief" and .involvement == "decide and tell me" and .kept == "private"'
  vbw_run status
  [[ "$output" == *"technical and brief"* ]]
  "$VBW" interview keep project
  vbw_run interview set involvement "I make the calls"
  [ "$status" -eq 0 ]
  "$VBW" interview --json | jq -e '.level == "never" and .depth == "technical and brief" and .involvement == "I make the calls" and .kept == "project"'
  jq -e '.project.interview.involvement == "I make the calls" and .project.interview.level == "never"' .vbw/record.json
  no_private_copy
}

@test "R38: a record or answers file from an older VBW (no answers) reads without error as not yet interviewed" {
  cp "$BATS_TEST_DIRNAME/fixtures/records/v1.json" .vbw/record.json
  vbw_run interview --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.interviewed == false and .kept == null and .level == null'
  vbw_run status
  [ "$status" -eq 0 ]
  [[ "$output" == *"the interview has not been done"* ]]
  mkdir -p "$COMMON/vbw"
  printf '{}\n' > "$PRIVATE"
  vbw_run interview --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.interviewed == false'
  printf '{"granted":[]}\n' > "$COMMON/vbw/consent.json"
  vbw_run status
  [ "$status" -eq 0 ]
}

@test "R38: the record change is additive under project: schema stays 1, older VBWs read it, and a bad value is corrupt" {
  answer "never" "plain words" "decide and tell me"
  "$VBW" interview keep project
  jq -e '.schema == 1 and (keys - ["schema","project","milestone","requirements","checks","phases","plans","fixes","todos","decisions","commands","settings","evidence","lease","shipped","converted"] == [])' .vbw/record.json
  jq -e '(.project | keys | sort) == ["interview","name"]' .vbw/record.json
  jq '.project.interview.level = "wizard"' .vbw/record.json > "$TEST_ROOT/bad.json"
  cp "$TEST_ROOT/bad.json" .vbw/record.json
  vbw_run status
  [ "$status" -eq 3 ]
  [[ "$output" == *"corrupt"* ]]
}

@test "R38: what is being built and for whom is not a personal answer: it is refused and never stored" {
  vbw_run interview set purpose "a shop for my aunt"
  [ "$status" -ne 0 ]
  answer "never" "plain words" "decide and tell me"
  "$VBW" interview keep private
  [ "$(jq -r 'del(.done) | keys | join(",")' "$PRIVATE")" = "depth,involvement,level" ]
  if grep -rq "aunt" "$COMMON/vbw" .vbw; then echo "the purpose was stored"; false; fi
  "$VBW" interview keep project
  [ "$(jq -r '.project.interview | del(.at) | keys | join(",")' .vbw/record.json)" = "depth,involvement,level" ]
}

@test "R38: keep refuses until all three answers exist, naming the first unanswered one" {
  "$VBW" interview set level "never" > /dev/null
  vbw_run interview keep private
  [ "$status" -ne 0 ]
  [[ "$output" == *"depth"* ]]
  vbw_run interview keep project
  [ "$status" -ne 0 ]
  jq -e '.project | has("interview") | not' .vbw/record.json
  vbw_run interview keep nowhere
  [ "$status" -eq 2 ]
}

@test "R38: /vbw:profile changes any one answer with the kernel command and shows the answers first" {
  local f="$PLUGIN_ROOT/skills/profile/SKILL.md"
  grep -qF 'vbw interview set level' "$f"
  grep -qF 'vbw interview set depth' "$f"
  grep -qF 'vbw interview set involvement' "$f"
  # shellcheck disable=SC2016 # the literal skill text
  grep -q '^"${CLAUDE_PLUGIN_ROOT}/bin/vbw" interview' "$f"
  grep -qi 'one answer' "$f"
}
