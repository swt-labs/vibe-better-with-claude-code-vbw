#!/usr/bin/env bats
# R268: vbw next fast on a big milestone. The fixture (tests/big-milestone-helper.bash)
# has the field report's shape: 79 phases, 258 plans, 568 after-links, 47
# interleaved phases, P1 to P40 built. The fast path changes how the answers are
# worked out, never the answers: vbw next, vbw show qa, vbw status and the
# digests say what they said before (tests/big-milestone-expected/, recorded
# from the program before the change), and the tree of each repository is read
# once. The speed itself is tests/timed-big-milestone.bats (the release run);
# here only its shape is pinned. L1.

load helper
load big-milestone-helper
load fixture-helper

setup_file() { fixture_build big big_milestone_fixture; }
setup() {
  fixture_copy big
  EXPECTED="$BATS_TEST_DIRNAME/big-milestone-expected"
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# same FILE: stdin is byte for byte the expected FILE; the difference otherwise.
same() { diff -u "$EXPECTED/$1" - || { echo "$1 differs from what the program said before"; return 1; }; }

@test "R268 identity: vbw next, vbw show qa, the digests and vbw status answer as they did before" {
  "$VBW" next < /dev/null | same next.txt
  jq -e --argjson n "$BIG_INTERLEAVED" '(.qa.interleaved | length) == $n and .qa.problems == []' .vbw/runtime/next.json \
    || { echo "the answer does not name the $BIG_INTERLEAVED interleaved phases, or finds a problem"; jq -c '.qa | {interleaved, problems}' .vbw/runtime/next.json; false; }
  "$VBW" show qa < /dev/null | same show-qa.txt
  vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"' | jq -c . | same digests.json
  # The "what's next" line reads the answer file's age, not the record: left out.
  "$VBW" status < /dev/null | grep -v "^what's next" | same status.txt
}

@test "R268 identity: the digests of the 79 phases read the repository's tree once" {
  mkdir -p "$TEST_ROOT/shim"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$GIT_LOG"\nexec "%s" "$@"\n' "$(command -v git)" > "$TEST_ROOT/shim/git"
  chmod +x "$TEST_ROOT/shim/git"
  export GIT_LOG="$TEST_ROOT/git.log"
  : > "$GIT_LOG"
  PATH="$TEST_ROOT/shim:$PATH" run vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")" > /dev/null'
  [ "$status" -eq 0 ]
  run grep -c ' ls-tree ' "$GIT_LOG"
  [ "$output" = 1 ]
}

@test "R268 timed: tests/timed-big-milestone.bats times vbw next --json on this fixture, user and system CPU together, within 5 s scaled by the bench's reference, and skips on a busy machine" {
  local f="$BATS_TEST_DIRNAME/timed-big-milestone.bats"
  [ -f "$f" ] || { echo "no tests/timed-big-milestone.bats"; false; }
  grep -q '^load big-milestone-helper$' "$f"
  grep -q 'fixture_build .* big_milestone_fixture' "$f"
  grep -q 'next --json' "$f"
  grep -qE 'TIMEFORMAT|%U|/usr/bin/time|times' "$f" || { echo "the timed test does not measure CPU time (user and system)"; false; }
  grep -q 'NOMINAL_MS' "$f" || { echo "the timed test does not read the bench's NOMINAL_MS"; false; }
  grep -qi 'busy' "$f" || { echo "the timed test has no busy-machine rule"; false; }
  grep -qE '\b5000\b|\b5 ?s\b' "$f" || { echo "the timed test names no 5 s budget"; false; }
  bats --count "$f" > /dev/null
}
