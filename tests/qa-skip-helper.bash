# shellcheck shell=bash
# Shared fixture for the QA skip tests (R104). Load after helper and qa-recheck-helper:
#   load helper
#   load qa-recheck-helper
#   load qa-skip-helper
# One standard phase P1 serves R1 and R3 ([auto], each with a check) and R2
# ([human], accepted). It is built, proved, and has passed QA.

qa_skip_project() {
  qa_base 1
  printf -- '- R2 [human] Part two feels right\n- R3 [auto] Part three works\n' >> .vbw/spec.md
  printf 'grep -qx part3 src/p3.txt\n' > tests/p3.sh
  "$VBW" spec sync > /dev/null
  jq -nc '{phases: [{id: "P1", title: "Parts", reqs: ["R1", "R2", "R3"], goal: "The parts work", criteria: ["each part file says its name"], tier: "standard"}],
           plans: [{id: "P1.1", phase: "P1", title: "Write the parts", reqs: ["R1", "R3"], files: ["src/p1.txt", "src/p3.txt"], after: [], tasks: ["write parts one and three"]}],
           checks: [{id: "C1", req: "R1", run: ["sh", "tests/p1.sh"], files: ["tests/p1.sh"]},
                    {id: "C3", req: "R3", run: ["sh", "tests/p3.sh"], files: ["tests/p3.sh"]}]}' | "$VBW" apply > /dev/null
  "$VBW" approve > /dev/null
  printf 'part1\n' > src/p1.txt
  printf 'part3\n' > src/p3.txt
  "$VBW" commit P1.1 "feat(parts): parts one and three" > /dev/null
  # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null
  "$VBW" prove --full > /dev/null
  "$VBW" req accept R2 > /dev/null
  "$VBW" qa record P1 pass standard > /dev/null
}

# rechecked: the phases QA must check again, as JSON; standing: those whose pass stands.
rechecked() { next_json | jq -c '.qa.recheck | keys'; }
standing() { next_json | jq -c '.qa.standing'; }

# spec_drop PATTERN: remove the spec lines containing PATTERN (a fixed string), then sync, approve and prove.
spec_drop() {
  grep -vF -- "$1" .vbw/spec.md > "$TEST_ROOT/spec.md"
  cp "$TEST_ROOT/spec.md" .vbw/spec.md
  "$VBW" spec sync > /dev/null
  "$VBW" approve > /dev/null
  "$VBW" prove --full > /dev/null
}

# spec_reword FROM TO: change requirement wording in the spec, then sync, approve and prove.
spec_reword() {
  local spec from=$1 to=$2
  spec=$(cat .vbw/spec.md)
  # The words are plain text (no pattern characters): kept unquoted for bash 3.2.
  printf '%s\n' "${spec/$from/$to}" > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  "$VBW" approve > /dev/null
  "$VBW" prove --full > /dev/null
}

# change_test: a stricter test for part one, committed, approved and proved.
change_test() {
  printf '# stricter\n' >> tests/p1.sh
  git add tests/p1.sh && git commit -q -m "test(p1): stricter"
  "$VBW" approve > /dev/null
  "$VBW" prove --full > /dev/null
}
