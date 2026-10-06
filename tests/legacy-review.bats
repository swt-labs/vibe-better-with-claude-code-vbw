#!/usr/bin/env bats
# R65 (docs/convert.md): `vbw legacy review` reviews a VBW 1 folder
# (.vbw-planning/) from the folder and the repo, by the kernel's own code, and
# recommends converting or starting fresh with reasons that name its numbers.
# It reads files only. Hermetic projects (L1); the model's wording and the
# real-app run are other checks.

load helper

setup() {
  vbw_setup
  vbw_git_project
  export GIT_CEILING_DIRECTORIES="$TEST_ROOT"
}

teardown() { vbw_teardown; }

# plan DIR NAME [FILE...]: a VBW 1 plan that names FILEs (front matter and prose).
plan() {
  local dir=$1 name=$2 f
  shift 2
  mkdir -p ".vbw-planning/phases/$dir"
  {
    printf -- '---\nphase: 1\nfiles_modified:\n'
    for f in "$@"; do printf '  - %s\n' "$f"; done
    printf -- '---\n# Plan\nChange `%s` as described.\n' "${1:-nothing}"
  } > ".vbw-planning/phases/$dir/$name-PLAN.md"
}
summary() { printf '# Done\n' > ".vbw-planning/phases/$1/$2-SUMMARY.md"; }

# healthy: phase 01 finished (2 plans), phase 02 half done (2 plans, 1 summary);
# the plans name 3 paths, all present in the repo.
healthy() {
  mkdir -p src lib
  printf 'x\n' > src/app.js
  printf 'x\n' > src/util.js
  printf 'x\n' > lib/keep.js
  mkdir -p .vbw-planning
  printf '# Project\n' > .vbw-planning/PROJECT.md
  printf '# State\n' > .vbw-planning/STATE.md
  plan 01-core 01-01 src/app.js
  plan 01-core 01-02 src/util.js
  plan 02-more 02-01 lib/
  plan 02-more 02-02 src/app.js
  summary 01-core 01-01
  summary 01-core 01-02
  summary 02-more 02-01
}

# stale: one of four plans done, every path the plans name is gone, last
# touched on 2024-10-01 (committed on that date).
stale() {
  mkdir -p .vbw-planning
  printf '# Project\n' > .vbw-planning/PROJECT.md
  printf '# State\n' > .vbw-planning/STATE.md
  plan 01-old 01-01 src/gone1.js
  plan 01-old 01-02 src/gone2.js
  plan 02-old 02-01 src/gone3.js
  plan 02-old 02-02 src/gone1.js
  summary 01-old 01-01
  git add -A
  GIT_AUTHOR_DATE="2024-10-01T12:00:00Z" GIT_COMMITTER_DATE="2024-10-01T12:00:00Z" git commit -q -m "chore: VBW 1 plan"
}

review() { "$VBW" legacy review < /dev/null; }

@test "R65: a project without a VBW 1 folder: legacy false, one line of JSON, exit 0, nothing else printed" {
  run "$VBW" legacy review
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.legacy == false'
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  [ ! -e .vbw ]
}

@test "R65: the review works before VBW 2 is set up and reports no choice yet" {
  healthy
  run "$VBW" legacy review
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.legacy == true and .choice == null and .asked == false'
  [ ! -e .vbw ]
}

@test "R65: how much was finished: plans with a summary against all readable plans" {
  healthy
  run "$VBW" legacy review
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.finished == {done: 3, total: 4} and .readable == true'
}

@test "R65: how recently it was used: the date and the days, from the commit that touched the folder" {
  stale
  run "$VBW" legacy review
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.last_used == "2024-10-01" and .days_ago > 700'
}

@test "R65: an untracked folder's last use comes from its newest file" {
  healthy
  run "$VBW" legacy review
  printf '%s' "$output" | jq -e '(.last_used | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) and .days_ago <= 1'
}

@test "R65: whether the plans still match the code: the files and folders they name that still exist" {
  healthy
  run "$VBW" legacy review
  printf '%s' "$output" | jq -e '.match == {named: 3, found: 3}'
  rm src/util.js
  run "$VBW" legacy review
  printf '%s' "$output" | jq -e '.match == {named: 3, found: 2}'
}

@test "R65: a path that climbs out of the project or is absolute is never looked up" {
  healthy
  plan 03-odd 03-01 ../outside.txt /etc/hosts src/app.js
  run "$VBW" legacy review
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.match.found == 3 and .match.named >= 3'
}

@test "R65: work half done: a phase started but not finished, and an unfinished build marker" {
  healthy
  printf '{"status":"running","phase":2}\n' > .vbw-planning/.execution-state.json
  run "$VBW" legacy review
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '(.half_done | map(test("02-more")) | any) and (.half_done | map(test("build"; "i")) | any)'
}

@test "R65: a finished build marker is not half done work" {
  healthy
  printf '{"status":"complete"}\n' > .vbw-planning/.execution-state.json
  run "$VBW" legacy review
  printf '%s' "$output" | jq -e '(.half_done | map(test("build"; "i")) | any) | not'
}

@test "R65: a healthy folder is recommended for conversion, and the reasons name the numbers behind it" {
  healthy
  git add -A && git commit -q -m "chore: VBW 1 plan"
  run "$VBW" legacy review
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.recommendation == "convert" and (.reasons | length) >= 1'
  [[ "$(printf '%s' "$output" | jq -r '.reasons | join(" ")')" == *"3 of 4"* ]]
  [[ "$(printf '%s' "$output" | jq -r '.reasons | join(" ")')" == *"3 of 3"* ]]
}

@test "R65: an old folder whose plans name files that are gone is recommended to start fresh, with the numbers" {
  stale
  run "$VBW" legacy review
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.recommendation == "fresh" and .match == {named: 3, found: 0}'
  [[ "$(printf '%s' "$output" | jq -r '.reasons | join(" ")')" == *"0 of 3"* ]]
  [[ "$(printf '%s' "$output" | jq -r '.reasons | join(" ")')" == *"2024-10-01"* ]]
}

@test "R65: the same folder always gives the same review and recommendation" {
  healthy
  git add -A && git commit -q -m "chore: VBW 1 plan"
  review > "$TEST_ROOT/one.json"
  review > "$TEST_ROOT/two.json"
  cmp "$TEST_ROOT/one.json" "$TEST_ROOT/two.json"
}

@test "R65: an empty folder: exit 0, valid JSON, says what could not be read, recommends fresh" {
  mkdir .vbw-planning
  run "$VBW" legacy review
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.legacy == true and .readable == false and .finished == {done: 0, total: 0}
    and .recommendation == "fresh" and (.notes | length) >= 1 and (.reasons | length) >= 1'
  [[ "$(printf '%s' "$output" | jq -r '.notes | join(" ")')" == *"plan"* ]]
}

@test "R65: plans that cannot be read (empty files) are named, never counted, and never recommended for conversion" {
  mkdir -p .vbw-planning/phases/01-a
  : > .vbw-planning/phases/01-a/01-01-PLAN.md
  : > .vbw-planning/phases/01-a/01-02-PLAN.md
  printf '{oops\n' > .vbw-planning/.execution-state.json
  run "$VBW" legacy review
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.readable == false and .finished.total == 0 and .recommendation == "fresh"'
  [[ "$(printf '%s' "$output" | jq -r '.notes | join(" ")')" == *"01-01-PLAN.md"* ]]
  [[ "$(printf '%s' "$output" | jq -r '.notes | join(" ")')" == *".execution-state.json"* ]]
}

@test "R65: a corrupt build marker and a missing project file are reported, the readable plans still count" {
  healthy
  rm .vbw-planning/PROJECT.md
  printf '{oops\n' > .vbw-planning/.execution-state.json
  run "$VBW" legacy review
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.finished == {done: 3, total: 4}'
  [[ "$(printf '%s' "$output" | jq -r '.notes | join(" ")')" == *".execution-state.json"* ]]
  [[ "$(printf '%s' "$output" | jq -r '.notes | join(" ")')" == *"PROJECT.md"* ]]
}

@test "R65: a folder not in a git repository: exit 0, the last use from file times, the lack of git is said" {
  local dir="$TEST_ROOT/nogit"
  mkdir -p "$dir/.vbw-planning/phases/01-a" "$dir/src"
  cd "$dir"
  printf 'x\n' > src/app.js
  printf -- '---\nfiles_modified:\n  - src/app.js\n---\n' > .vbw-planning/phases/01-a/01-01-PLAN.md
  printf 'done\n' > .vbw-planning/phases/01-a/01-01-SUMMARY.md
  touch -t 202401151200 .vbw-planning/phases/01-a/01-01-PLAN.md .vbw-planning/phases/01-a/01-01-SUMMARY.md \
    .vbw-planning/phases/01-a .vbw-planning src/app.js "$dir"
  run "$VBW" legacy review
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.legacy == true and (.last_used | startswith("2024-01-1")) and .days_ago > 600
    and .finished == {done: 1, total: 1} and (.notes | map(test("git"; "i")) | any)'
}

@test "R65: the review writes nothing, runs nothing it finds in the folder, and changes no file" {
  healthy
  printf '# Plan\n$(touch %s/pwned-by-plan)\n`touch %s/pwned-by-tick`\n' "$PROJECT" "$PROJECT" > .vbw-planning/phases/01-core/01-03-PLAN.md
  printf '#!/bin/sh\ntouch "%s/pwned-by-script"\n' "$PROJECT" > .vbw-planning/hook.sh
  chmod +x .vbw-planning/hook.sh
  printf '{"status":"running","command":"touch %s/pwned-by-state"}\n' "$PROJECT" > .vbw-planning/.execution-state.json
  git add -A && git commit -q -m "chore: VBW 1 plan"
  local before after
  before=$(find . -path ./.git -prune -o -print | LC_ALL=C sort; find . -path ./.git -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 cat | git hash-object --stdin)
  review > /dev/null
  after=$(find . -path ./.git -prune -o -print | LC_ALL=C sort; find . -path ./.git -prune -o -type f -print0 | LC_ALL=C sort -z | xargs -0 cat | git hash-object --stdin)
  [ "$before" = "$after" ]
  [ -z "$(git status --porcelain)" ]
  [ ! -e pwned-by-plan ] && [ ! -e pwned-by-tick ] && [ ! -e pwned-by-script ] && [ ! -e pwned-by-state ]
  [ ! -e .vbw ]
  # No network tool in the review's code.
  [ -f "$PLUGIN_ROOT/lib/legacy-review.sh" ] || [ -f "$PLUGIN_ROOT/lib/cmd-legacy.sh" ]
  if grep -hE '(^|[^a-z])(curl|wget|nc|ssh|eval)([^a-z]|$)' "$PLUGIN_ROOT/lib/cmd-legacy.sh" "$PLUGIN_ROOT"/lib/legacy-review.sh 2> /dev/null | grep -qvE '^[[:space:]]*#'; then false; fi
}

@test "R65: the recommended option comes first: recommendation is convert or fresh and the reasons are plain sentences" {
  stale
  run "$VBW" legacy review
  printf '%s' "$output" | jq -e '(.recommendation | . == "convert" or . == "fresh")
    and (.reasons | all(type == "string" and length > 10))'
}

@test "R65: usage: review takes no argument and the help lists it" {
  healthy
  run "$VBW" legacy review extra
  [ "$status" -ne 0 ]
  run "$VBW" --help
  [[ "$output" == *"legacy"*"review"* ]]
}

@test "R65: the kernel with the review stays within its budget (kept in one place: tests/standards.bats)" {
  grep -q 'review' "$PLUGIN_ROOT/lib/cmd-legacy.sh"
  run bats --filter 'kernel stays within' "$REPO_ROOT/tests/standards.bats"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
