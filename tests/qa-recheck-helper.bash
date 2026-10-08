# shellcheck shell=bash
# Shared fixtures for the QA re-check tests (M8: R47, R48, R49). Load after helper:
#   load helper
#   load qa-recheck-helper
# A phase Pn serves requirement Rn with one plan Pn.1 that writes src/pn.txt,
# checked by tests/pn.sh. Every phase is standard, so QA applies to each.

edit_record() {
  jq "$1" .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
}

# qa_base N: a git project with requirements R1..RN synced into the record.
qa_base() {
  local i
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  {
    printf '# Shop\n\n## Requirements\n\n'
    for ((i = 1; i <= $1; i++)); do printf -- '- R%d [auto] Part %d works\n' "$i" "$i"; done
  } > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  for ((i = 1; i <= $1; i++)); do printf 'grep -qx part%d src/p%d.txt\n' "$i" "$i" > "tests/p$i.sh"; done
}

# qa_doc N [chain]: the vbw apply document for phases P1..PN; with "chain",
# plan Pn.1 comes after P(n-1).1 (phase n builds on phase n-1).
qa_doc() {
  jq -nc --argjson n "$1" --arg chain "${2:-}" '
    [range(1; $n + 1)] as $r
    | {phases: [$r[] | {id: "P\(.)", title: "Part \(.)", reqs: ["R\(.)"], goal: "Part \(.) works", criteria: ["src/p\(.).txt says part\(.)"], tier: "standard"}],
       plans: [$r[] | {id: "P\(.).1", phase: "P\(.)", title: "Write part \(.)", reqs: ["R\(.)"], files: ["src/p\(.).txt"],
                       after: (if $chain == "chain" and . > 1 then ["P\(. - 1).1"] else [] end), tasks: ["write part \(.)"]}],
       checks: [$r[] | {id: "C\(.)", req: "R\(.)", run: ["sh", "tests/p\(.).sh"], files: ["tests/p\(.).sh"]}]}'
}

# qa_build N: approve the contract, build every plan, commit and prove.
qa_build() {
  local i
  "$VBW" approve > /dev/null
  for ((i = 1; i <= $1; i++)); do
    printf 'part%d\n' "$i" > "src/p$i.txt"
    "$VBW" commit "P$i.1" "feat(p$i): part $i" > /dev/null
    # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
    "$VBW" plan done "P$i.1" > /dev/null
  done
  "$VBW" prove --full > /dev/null
}

# qa_project N [chain]: N built and proven phases, none checked by QA yet.
qa_project() {
  qa_base "$1"
  qa_doc "$@" | "$VBW" apply > /dev/null
  qa_build "$1"
}

# qa_pass PHASE...: QA records a pass for each phase.
qa_pass() {
  local p
  for p in "$@"; do "$VBW" qa record "$p" pass standard > /dev/null || return 1; done
}

# qa_touch N: a user commit that changes phase N's file but keeps its check passing; then prove.
qa_touch() {
  printf 'extra\n' >> "src/p$1.txt"
  git add "src/p$1.txt" && git commit -q -m "fix(p$1): touch"
  "$VBW" prove --full > /dev/null
}

# next_json: vbw next --json on the current project.
next_json() { "$VBW" next --json < /dev/null; }

# listed: the phases vbw next sends to QA, as a compact JSON array.
listed() { next_json | jq -c '.detail.phases // []'; }
