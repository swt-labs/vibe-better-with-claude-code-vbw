#!/usr/bin/env bats
# R202 (docs/next.md, plugin/lib/steps.sh): vbw next does not redo the proof's
# reuse planning when nothing it depends on changed. The planned unit list is
# cached in .vbw/runtime/proof-units.json, keyed on the committed tree, the git
# index's digest (the test files are listed from the index), the record's
# fingerprint and the run store's digest, and reused only while all four match;
# any change recomputes it. L1: a counting stand-in git on PATH
# shows whether the planning ran (it is the only caller of git diff-tree in
# vbw next); the answer's step is compared without its clock fields.

load helper
load fixture-helper

built_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'a\n' > src/a.txt
  printf 'b\n' > src/b.txt
  printf 'c\n' > src/c.txt
  printf 'grep -q . src/a.txt\n' > tests/c1.sh
  printf 'grep -q . src/b.txt\n' > tests/c2.sh
  printf 'grep -q . src/c.txt\n' > tests/c3.sh
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/c1.sh"], files:["tests/c1.sh"]},
      {id:"C2", req:"R1", run:["sh","tests/c2.sh"], files:["tests/c2.sh"]},
      {id:"C3", req:"R1", run:["sh","tests/c3.sh"], files:["tests/c3.sh"]}]
    | .phases = [{id:"P1", title:"Shop", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Shop", reqs:["R1"], files:["src/a.txt","src/b.txt","src/c.txt"], after:[], status:"done"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' \
    .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null
  # One unit's file changes: the next proof runs C1 and reuses the rest.
  printf 'more\n' >> src/a.txt
  git add -A && git commit -q -m "feat: a"
  REAL_GIT=$(command -v git)
  mkdir -p "$TEST_ROOT/standin"
  cat > "$TEST_ROOT/standin/git" << SH
#!/bin/sh
case " \$* " in *" diff-tree "*) printf 'x\\n' >> "\$DIFFTREE" ;; esac
exec "$REAL_GIT" "\$@"
SH
  chmod +x "$TEST_ROOT/standin/git"
  export DIFFTREE="$TEST_ROOT/difftree"
}

setup_file() { fixture_build built built_project; }
setup() {
  fixture_copy built
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# next: vbw next --json with the counting git; DIFF is how many diff-tree calls it made, STEP its step without clock fields.
next() {
  : > "$DIFFTREE"
  PATH="$TEST_ROOT/standin:$PATH" "$VBW" next --json < /dev/null > "$TEST_ROOT/next.json" || { cat "$TEST_ROOT/next.json"; return 1; }
  DIFF=$(wc -l < "$DIFFTREE" | tr -d ' ')
  STEP=$(jq -c '.step | if . == null then null else del(.seconds, .low, .high, .end, .end_low, .end_high, .say) end' "$TEST_ROOT/next.json")
}

store_file() { printf '%s/vbw/runs.json' "$(git rev-parse --path-format=absolute --git-common-dir)"; }

@test "R202: the second of two consecutive vbw next --json calls reads the cache: no diff-tree, the same step" {
  next
  local first="$STEP" d1="$DIFF"
  [ "$d1" -gt 0 ] || { echo "the first call planned nothing (no diff-tree): $(cat "$TEST_ROOT/next.json")"; false; }
  jq -e '.action == "prove" and .step.kind == "proof" and .step.parts == 1' "$TEST_ROOT/next.json" || { cat "$TEST_ROOT/next.json"; false; }
  [ -f .vbw/runtime/proof-units.json ] || { echo "no cache at .vbw/runtime/proof-units.json"; ls .vbw/runtime; false; }
  next
  [ "$DIFF" -eq 0 ] || { echo "the second call ran git diff-tree $DIFF times"; false; }
  [ "$STEP" = "$first" ] || { echo "first: $first"; echo "second: $STEP"; false; }
}

@test "R202: a changed run store recomputes the list" {
  next
  next
  [ "$DIFF" -eq 0 ]
  jq 'del(.runs["check:C2"])' "$(store_file)" > "$TEST_ROOT/store.json" && cp "$TEST_ROOT/store.json" "$(store_file)"
  next
  [ "$DIFF" -gt 0 ] || { echo "the store changed and the cache was still used"; false; }
  jq -e '.step.parts == 2' "$TEST_ROOT/next.json" || { cat "$TEST_ROOT/next.json"; false; }
}

@test "R202: a changed record recomputes the list" {
  next
  next
  [ "$DIFF" -eq 0 ]
  "$VBW" decide "a note" > /dev/null
  next
  [ "$DIFF" -gt 0 ] || { echo "the record changed and the cache was still used"; false; }
}

@test "R202: a new commit recomputes the list" {
  next
  next
  [ "$DIFF" -eq 0 ]
  printf 'more\n' >> src/c.txt
  git add -A && git commit -q -m "feat: c"
  next
  [ "$DIFF" -gt 0 ] || { echo "the committed tree changed and the cache was still used"; false; }
  jq -e '.step.parts == 2' "$TEST_ROOT/next.json" || { cat "$TEST_ROOT/next.json"; false; }
}

@test "R202: a staged new test file recomputes the list: the test files are listed from the git index" {
  # A single-file form, proved; then a committed change makes C1 the one unit to run.
  printf 'grep -q . src/b.txt\n' > tests/t_a.sh
  printf 'true\n' > tests/all.sh
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n\n## Commands\n\n- test: sh tests/all.sh\n\n## Test files\n\n- run: sh {file}\n- files: tests/t_*.sh\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "test: a single-file form"
  "$VBW" approve > /dev/null
  "$VBW" prove > /dev/null || { echo "the proof with the form failed"; false; }
  printf 'again\n' >> src/a.txt
  git add -A && git commit -q -m "feat: a again"
  next
  jq -e '.step.parts == 1' "$TEST_ROOT/next.json" || { cat "$TEST_ROOT/next.json"; false; }
  next
  [ "$DIFF" -eq 0 ]
  # Staged, not committed: no commit, no record or store change; only the index moved.
  printf 'true\n' > tests/t_b.sh
  git add tests/t_b.sh
  next
  [ "$DIFF" -gt 0 ] || { echo "a test file was staged and the cache was still used"; false; }
  jq -e '.step.parts == 2' "$TEST_ROOT/next.json" || { cat "$TEST_ROOT/next.json"; false; }
}
