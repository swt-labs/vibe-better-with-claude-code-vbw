#!/usr/bin/env bats
# R167: the Lead proposes the single-file test form through vbw apply
# ("test_files", with the {file} placeholder). docs/proof.md shows the Test
# files section with its run and files lines and the count line; docs/workflows.md
# names test_files. L1.

load helper

DOC="$REPO_ROOT/docs/proof.md"
FLOW="$REPO_ROOT/docs/workflows.md"
LEAD="$PLUGIN_ROOT/agents/lead.md"

@test "R167: the Lead proposes the single-file form through vbw apply: test_files and {file}" {
  grep -qF 'test_files' "$LEAD"
  grep -qF '{file}' "$LEAD"
}

@test "R167: docs/proof.md shows the Test files section with its run and files lines" {
  grep -qx '## Test files' "$DOC"
  grep -qF -- '- run: ' "$DOC"
  grep -qF -- '- files: ' "$DOC"
  grep -qF '{file}' "$DOC"
}

@test "R167: docs/proof.md shows the test files count line" {
  grep -qE 'test files: N ran, M reused' "$DOC"
}

@test "R167: docs/workflows.md names test_files" {
  grep -qF 'test_files' "$FLOW"
}

@test "R167 (#721): the map's tests scout finds the command that runs one test file, runs it once, and says what a new test file needs" {
  command -v node > /dev/null 2>&1 || skip "node not installed"
  local prompt
  prompt=$(node "$BATS_TEST_DIRNAME/helpers/run-workflow-all.js" "$PLUGIN_ROOT/workflows/mapping.js" '{}' '{}' | jq -r '.calls[] | select(.opts.label == "scout tests") | .prompt')
  printf '%s' "$prompt" | grep -q 'one test file' || { echo "the tests scout is not asked for the one-file command"; false; }
  printf '%s' "$prompt" | grep -q 'run it once' || { echo "the one-file command is not run"; false; }
  printf '%s' "$prompt" | grep -q 'new test file' || { echo "what a new test file needs is not asked"; false; }
  printf '%s' "$prompt" | grep -q 'each subproject' || { echo "the command is not asked per subproject"; false; }
  printf '%s' "$prompt" | grep -q 'Never guess' || { echo "the scout may guess a form"; false; }
}

@test "R167 (#721): the Lead takes the one-file form from the map before working one out, and the docs say the map records it" {
  grep -E '^8\. \*\*One-file test form' "$LEAD" | grep -qF '.vbw/map.md'
  grep -E '^\| `vbw:mapping`' "$FLOW" | grep -q 'one test file'
}

# R228 (#733): the map's Tests section marks every test or lint command as run and dated
# ("ran as of <short commit>, <date>: ...") or as "Not run", so the router can choose
# the spec's ## Commands from what the map verified; the map skill says what the marks
# mean, and the docs say so too. L1: the merge prompt's text, the skill and the docs.

MAPSKILL="$PLUGIN_ROOT/skills/map/SKILL.md"

# merge_prompt: the mapping workflow's merge prompt, as the scout receives it.
merge_prompt() {
  node "$BATS_TEST_DIRNAME/helpers/run-workflow-all.js" "$PLUGIN_ROOT/workflows/mapping.js" '{}' '{}' | jq -r '.calls[] | select(.opts.label == "scout merge") | .prompt'
}

@test "R228: the merge prompt tells the Lead to mark each test or lint command ran and dated, or Not run, in these words" {
  command -v node > /dev/null 2>&1 || skip "node not installed"
  local prompt
  prompt=$(merge_prompt)
  [ -n "$prompt" ] || { echo "no merge prompt"; false; }
  printf '%s' "$prompt" | grep -qF 'ran as of <short commit>, <date>: <what happened, how long it took>' || { echo "the ran mark is not in the merge prompt"; false; }
  printf '%s' "$prompt" | grep -qF 'Not run' || { echo "the Not run mark is not in the merge prompt"; false; }
  printf '%s' "$prompt" | grep -qi 'Tests section' || { echo "the marks are not tied to the Tests section"; false; }
}

@test "R228: the map skill says what the two marks mean and that the router chooses ## Commands from them, and still never writes the map itself" {
  grep -qF 'Not run' "$MAPSKILL"
  grep -qE 'ran as of' "$MAPSKILL"
  grep -qF '## Commands' "$MAPSKILL"
  grep -qF 'Never write `.vbw/map.md` yourself' "$MAPSKILL"
  grep -qF 'or `Not run` (no scout ran it' "$MAPSKILL"
  grep -qF '(a scout ran it' "$MAPSKILL"
  grep -qF '` from these marks' "$MAPSKILL"
}

@test "R228 docs: docs/workflows.md's mapping row names the two marks, and docs/proof.md's project commands say the router chooses them from the map's Tests section and asks before planning about a suite marked Not run" {
  grep -E '^\| `vbw:mapping`' "$FLOW" | grep -qF 'Not run'
  grep -E '^\| `vbw:mapping`' "$FLOW" | grep -qF 'ran as of'
  local section
  section=$(sed -n '/^## Project commands/,/^## /p' "$DOC" | tr '\n' ' ' | tr -s ' ')
  printf '%s' "$section" | grep -qi 'tests section' || { echo "docs/proof.md does not say ## Commands comes from the map's Tests section"; false; }
  printf '%s' "$section" | grep -qF 'Not run' || { echo "docs/proof.md does not name the Not run mark"; false; }
  printf '%s' "$section" | grep -qi 'unverified' || { echo "docs/proof.md does not say an unrun suite is offered as unverified"; false; }
  printf '%s' "$section" | grep -qi 'before planning' || { echo "docs/proof.md does not place the question before planning"; false; }
  printf '%s' "$section" | grep -qi 'run it now' || { echo "docs/proof.md does not name the run-it-now option"; false; }
}

# #735: several named forms, one per test runner, each with an optional dir.
@test "#735 docs: docs/proof.md shows named forms with dir, and says where a form runs, that a file belongs to one form and how the summary names them" {
  local section
  section=$(sed -n '/^## Test files/,/^## `vbw prove`/p' "$DOC" | tr '\n' ' ' | tr -s ' ')
  sed -n '/^## Test files/,/^## `vbw prove`/p' "$DOC" | grep -qE '^  - dir: ' || { echo "no nested dir line"; false; }
  printf '%s' "$section" | grep -qF 'relative to its dir' || { echo "{file} relative to dir not said"; false; }
  printf '%s' "$section" | grep -qF 'matched by two forms' || { echo "the overlap refusal is not said"; false; }
  printf '%s' "$section" | grep -qF '(webapp 2 ran, 30 reused; mobile 1 ran, 11 reused)' || { echo "the per-form count is not shown"; false; }
}

@test "#735 docs: docs/record.md and docs/workflows.md give both test_files shapes, and the Lead proposes one form per runner" {
  grep -qF '{name, dir, run, files}' "$REPO_ROOT/docs/record.md"
  grep -qF '"name"' "$FLOW"
  grep -E '^8\. \*\*One-file test form' "$LEAD" | grep -qF 'one form per test runner'
}

@test "R304 docs: docs/proof.md shows the filter, rest and join lines, says a file named only by filtered checks runs its other tests, and that a rest run must pass when nothing is left (bats --allow-empty-suite)" {
  grep -qF -- '- filter: ' "$DOC"
  grep -qF -- '- rest: ' "$DOC"
  grep -qF -- '- join: ' "$DOC"
  grep -qF '{filters}' "$DOC"
  grep -qF -- '--negative-filter' "$DOC"
  grep -qF -- '--allow-empty-suite' "$DOC"
}

@test "R304 docs: docs/record.md gives the form's filter, rest and join fields, and the Lead's instructions name the filter and rest lines" {
  grep -qF '"filter"' "$REPO_ROOT/docs/record.md"
  grep -qF '"rest"' "$REPO_ROOT/docs/record.md"
  grep -qF '{filters}' "$LEAD"
}
