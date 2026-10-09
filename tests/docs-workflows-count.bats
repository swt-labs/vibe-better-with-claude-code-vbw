#!/usr/bin/env bats
# R134 (L1): docs/workflows.md lists every workflow VBW ships
# (plugin/workflows/*.js, vbw:tooling included) by its vbw:<name>, and every
# place that says how many there are gives that count; docs/proof.md says, in
# its Test results section, that a folder name cannot contain spaces, which is
# what vbw spec sync does with such a folder. The list and the count come from
# the directory, so a new workflow without its docs fails here.

load helper

DOC="$REPO_ROOT/docs/workflows.md"
PROOF="$REPO_ROOT/docs/proof.md"

# workflow_names: the name of each shipped workflow file, one per line.
workflow_names() { find "$PLUGIN_ROOT/workflows" -maxdepth 1 -name '*.js' -type f | sed 's|.*/||; s|\.js$||' | LC_ALL=C sort; }

# number_word N: N in words (1 to 20), as the docs write counts.
number_word() {
  local words=(zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty)
  printf '%s\n' "${words[$1]}"
}

@test "R134: docs/workflows.md lists every workflow file by its vbw:<name>, vbw:tooling included" {
  local name missing=""
  [ -n "$(workflow_names)" ]
  workflow_names | grep -qx tooling
  while IFS= read -r name; do
    grep -qE "^\| \`vbw:$name\` \|" "$DOC" || missing="$missing vbw:$name"
  done < <(workflow_names)
  [ -z "$missing" ] || { echo "docs/workflows.md has no table row for:$missing"; false; }
}

@test "R134: every count of workflows in docs/workflows.md equals the number of workflow files" {
  local n word found
  n=$(workflow_names | wc -l | tr -d ' ')
  word=$(number_word "$n")
  found=$(grep -oiE "\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|[0-9]+) (Claude Code )?workflows\b" "$DOC" || true)
  [ -n "$found" ] || { echo "docs/workflows.md never says how many workflows there are"; false; }
  if printf '%s\n' "$found" | grep -viE "^($word|$n) "; then
    echo "the count is $n ($word)"
    false
  fi
  grep -qiE "\b$word (Claude Code )?workflows\b" "$DOC" || { echo "docs/workflows.md never says $word workflows"; false; }
}

@test "R134: docs/proof.md says in its Test results section that a folder name cannot contain spaces" {
  local section
  section=$(awk '/^### Saved test results/ { on = 1; next } on && /^##/ { exit } on' "$PROOF")
  [ -n "$section" ] || { echo "no Saved test results section in docs/proof.md"; false; }
  printf '%s' "$section" | tr '\n' ' ' | grep -qiE "(cannot|can't|must not|may not|no) [^.]{0,60}spaces?|spaces?[^.]{0,60}(cannot|not allowed|refused|an error)" \
    || { echo "$section"; false; }
}

@test "R134: vbw spec sync refuses a Test results folder whose name contains a space, and changes nothing" {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Test results\n\n- my results/\n' > .vbw/spec.md
  local before
  before=$(cksum < .vbw/record.json)
  run "$VBW" spec sync < /dev/null
  [ "$status" -ne 0 ] || { echo "accepted: $output"; vbw_teardown; false; }
  [[ "$output" == *"my results/"* ]] || { echo "$output"; vbw_teardown; false; }
  [ "$(cksum < .vbw/record.json)" = "$before" ] || { vbw_teardown; false; }
  vbw_teardown
}
