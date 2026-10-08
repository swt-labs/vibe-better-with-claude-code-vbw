#!/usr/bin/env bats
# R115 (docs/proof.md): a passed phase is not checked by QA again when the only
# files that changed since its pass are documentation (.md, .markdown, .rst;
# plain .txt is data, D144) or saved test results inside the folders the
# spec's "## Test results" section names (approved like any spec change; none
# named, no exemption: D195). A file one of the phase's checks runs or lists
# counts as a test; a phase whose every plan changes only documents keeps them
# as its code; a change to code, tests, goal or plans still lists the phase,
# with the reason. L1.

load helper
load qa-recheck-helper

teardown() { vbw_teardown; }

# docs_project [results]: R1..R3 synced; with "results", the spec names the
# folder results/ as saved test results before the contract is approved.
#   P1 (R1): code src/p1.txt, documents docs/p1.md, docs/p1.markdown,
#     docs/p1.rst, data data/words.txt, saved results results/run.json, and
#     two documents its check C1 uses: tests/p1-cases.md (in C1's files) and
#     results/expected.md (in C1's argv).
#   P2 (R2): documentation only, docs/guide.md.
#   P3 (R3): src/p3.txt; its plan comes after P1.1, so P3 builds on P1.
# Every plan is built and committed, the proof passes, QA passes all three.
docs_project() {
  qa_base 3
  if [ "${1:-}" = results ]; then
    printf '\n## Test results\n\n- results/\n' >> .vbw/spec.md
    "$VBW" spec sync > /dev/null
  fi
  printf 'grep -q guide docs/guide.md\n' > tests/p2.sh
  printf '# cases\n' > tests/p1-cases.md
  jq -nc '{phases: [
      {id: "P1", title: "Part 1", reqs: ["R1"], goal: "Part 1 works", criteria: ["src/p1.txt says part1"]},
      {id: "P2", title: "Guide", reqs: ["R2"], goal: "The guide exists", criteria: ["docs/guide.md has a guide"]},
      {id: "P3", title: "Part 3", reqs: ["R3"], goal: "Part 3 works", criteria: ["src/p3.txt says part3"]}],
    plans: [
      {id: "P1.1", phase: "P1", title: "Part 1", reqs: ["R1"], after: [], tasks: ["write part 1"],
       files: ["src/p1.txt", "docs/p1.md", "docs/p1.markdown", "docs/p1.rst", "data/words.txt", "results/run.json", "results/expected.md", "tests/p1-cases.md"]},
      {id: "P2.1", phase: "P2", title: "Guide", reqs: ["R2"], after: [], tasks: ["write the guide"], files: ["docs/guide.md"]},
      {id: "P3.1", phase: "P3", title: "Part 3", reqs: ["R3"], after: ["P1.1"], tasks: ["write part 3"], files: ["src/p3.txt"]}],
    checks: [
      {id: "C1", req: "R1", run: ["sh", "tests/p1.sh", "results/expected.md"], files: ["tests/p1.sh", "tests/p1-cases.md"]},
      {id: "C2", req: "R2", run: ["sh", "tests/p2.sh"], files: ["tests/p2.sh"]},
      {id: "C3", req: "R3", run: ["sh", "tests/p3.sh"], files: ["tests/p3.sh"]}],
    rules: [{req: "R1", text: "part 1", check: "C1"}, {req: "R2", text: "guide", check: "C2"}, {req: "R3", text: "part 3", check: "C3"}]}' \
    | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  mkdir -p docs data results
  printf 'part1\n' > src/p1.txt
  printf '# p1\n' > docs/p1.md
  printf '# p1\n' > docs/p1.markdown
  printf 'p1\n==\n' > docs/p1.rst
  printf 'apple\n' > data/words.txt
  printf '{"run": 1}\n' > results/run.json
  printf '# expected\n' > results/expected.md
  "$VBW" commit P1.1 "feat(p1): part 1" > /dev/null
  printf '# guide\n' > docs/guide.md
  "$VBW" commit P2.1 "docs(p2): guide" > /dev/null
  printf 'part3\n' > src/p3.txt
  "$VBW" commit P3.1 "feat(p3): part 3" > /dev/null
  local p
  # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
  for p in P1.1 P2.1 P3.1; do "$VBW" plan done "$p" > /dev/null; done
  "$VBW" prove --full > /dev/null
  qa_pass P1 P2 P3
  [ "$(rechecked)" = '[]' ] || { echo "not standing after the passes: $(rechecked)"; false; }
}

# change MESSAGE FILE...: a user commit that appends a line to each FILE.
change() {
  local msg="$1" f
  shift
  for f in "$@"; do printf 'more\n' >> "$f"; done
  git add -- "$@" && git commit -q -m "$msg"
}

# rechecked: the phases vbw next --json puts on QA's re-check list, sorted.
rechecked() { next_json | jq -c '.qa.recheck | keys'; }

@test "R115: a commit of only .md, .markdown and .rst files the phase lists leaves it off the list, in vbw next and vbw show qa" {
  docs_project
  change "docs: reword" docs/p1.md docs/p1.markdown docs/p1.rst
  [ "$(rechecked)" = '[]' ] || { rechecked; false; }
  vbw_run show qa
  [[ "$output" == *"Nothing needs checking again"* ]] || { echo "$output"; false; }
  [[ "$output" == *"P1 keeps its pass"* ]] || { echo "$output"; false; }
}

@test "R115: a plain .txt file the phase lists is data: changing it lists the phase again" {
  docs_project
  change "chore: words" data/words.txt
  next_json | jq -e '.qa.recheck.P1 | index("its files changed")' || { next_json | jq -c .qa; false; }
}

@test "R115: naming a results folder in the spec makes the contract wait for approval, and vbw show contract shows it" {
  docs_project
  printf '\n## Test results\n\n- results/\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  next_json | jq -e '.action == "approve"' || { next_json | jq -c '{action, instruction}'; false; }
  vbw_run show contract
  [[ "$output" == *"NOT APPROVED"* ]] || { echo "$output"; false; }
  [[ "$output" == *"results/"* ]] || { echo "$output"; false; }
  "$VBW" approve > /dev/null
  next_json | jq -e '.action != "approve"' || { next_json | jq -c '{action, instruction}'; false; }
  # Changing the list waits for approval again.
  printf -- '- reports/\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  next_json | jq -e '.action == "approve"' || { next_json | jq -c '{action, instruction}'; false; }
}

@test "R115: with the results folder approved, a commit of only files inside it leaves the phase off the list" {
  docs_project results
  change "test: save results" results/run.json
  [ "$(rechecked)" = '[]' ] || { next_json | jq -c .qa; false; }
}

@test "R115: a spec that names no results folder gives no exemption: a saved result is a file like any other" {
  docs_project
  change "test: save results" results/run.json
  next_json | jq -e '.qa.recheck.P1 | index("its files changed")' || { next_json | jq -c .qa; false; }
}

@test "R115: until a changed results-folder list is approved, a change inside the new folder still lists the phase" {
  docs_project
  printf '\n## Test results\n\n- results/\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  change "test: save results" results/run.json
  next_json | jq -e '.action == "approve" and (.qa.recheck | has("P1"))' || { next_json | jq -c '{action, qa}'; false; }
  vbw_run show qa
  [[ "$output" == *"P1 is checked again"* ]] || { echo "$output"; false; }
}

@test "R115: a file the phase's check runs or lists is a test, even as Markdown or inside a results folder" {
  docs_project results
  change "test: cases" tests/p1-cases.md
  next_json | jq -e '.qa.recheck | has("P1")' || { next_json | jq -c .qa; false; }
  # A check file changed: the contract waits for approval; then QA passes P1 and P3 (which builds on it) again.
  "$VBW" approve > /dev/null
  "$VBW" prove --full > /dev/null
  qa_pass P1 P3
  [ "$(rechecked)" = '[]' ] || { next_json | jq -c .qa; false; }
  change "test: expected" results/expected.md
  next_json | jq -e '.qa.recheck | has("P1")' || { next_json | jq -c .qa; false; }
}

@test "R115: a commit of documentation and one code file lists the phase again" {
  docs_project
  change "feat(p1): more" docs/p1.md src/p1.txt
  next_json | jq -e '.qa.recheck.P1 | index("its files changed")' || { next_json | jq -c .qa; false; }
}

@test "R115: a change to the phase's goal, success criteria or plans still lists it again" {
  docs_project
  local doc
  doc=$(jq -c '.milestone.id as $m | {phases: [.phases[] | select(.milestone == $m) | {id, title, reqs, goal, criteria}],
      plans: [.plans[] | {id, phase, title, reqs, files, after, tasks}], checks: .checks,
      rules: [.requirements[] | .id as $q | (.rules // [])[] | {req: $q, text, check}]}' .vbw/record.json)
  printf '%s' "$doc" | jq -c '(.phases[] | select(.id == "P1")).criteria += ["src/p1.txt ends with a newline"]' | "$VBW" apply > /dev/null
  next_json | jq -e '.qa.recheck.P1 | index("its goal or plan changed")' || { next_json | jq -c .qa; false; }
}

@test "R115: a phase built on another stays off the list when that phase changed only documentation or results, and is listed when its code changed" {
  docs_project results
  change "docs: reword" docs/p1.md
  change "test: save results" results/run.json
  [ "$(rechecked)" = '[]' ] || { next_json | jq -c .qa; false; }
  change "feat(p1): more" src/p1.txt
  next_json | jq -e '(.qa.recheck.P1 | index("its files changed")) and (.qa.recheck.P3 | index("builds on P1, which changed"))' || { next_json | jq -c .qa; false; }
}

@test "R115: a phase whose every plan changes only documents is listed again when those documents change" {
  docs_project
  change "docs: guide" docs/guide.md
  next_json | jq -e '.qa.recheck.P2 | index("its files changed")' || { next_json | jq -c .qa; false; }
  vbw_run show qa
  [[ "$output" == *"P2 is checked again: its files changed"* ]] || { echo "$output"; false; }
}

@test "R115: docs/proof.md and docs/record.md describe the documentation and saved-results rule" {
  grep -qi 'Test results' "$REPO_ROOT/docs/proof.md"
  grep -qiE 'saved test results|saved results' "$REPO_ROOT/docs/proof.md"
  grep -qE '\.markdown' "$REPO_ROOT/docs/proof.md"
  grep -qE 'project\.results' "$REPO_ROOT/docs/record.md"
}
