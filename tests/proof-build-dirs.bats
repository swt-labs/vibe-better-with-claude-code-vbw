#!/usr/bin/env bats
# R73 (docs/proof.md): a proof never reuses build output from the working
# folder. The clean copy links the project's environment (dependency folders,
# env files) in from the working folder, but its build folders (Node, Python,
# Rust and Go style) are its own: nothing in the copy is a link to build output
# in the working folder or any other copy. L1: a project script drives vbw
# prove on a fixture.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  # Build output of four ecosystems, all git-ignored, as a long-lived working
  # folder holds it; node_modules and .venv are the environment, not build output.
  cat > .gitignore << 'EOF'
target/
dist/
build/
bin/
__pycache__/
.pytest_cache/
node_modules/
.venv/
.env.local
EOF
  mkdir -p target/debug dist src/__pycache__ .pytest_cache bin build node_modules/pkg .venv/lib
  printf 'stale rust\n' > target/debug/app
  printf 'stale node\n' > dist/bundle.js
  printf 'stale python\n' > src/__pycache__/pay.pyc
  printf 'stale pytest\n' > .pytest_cache/v
  printf 'stale go\n' > bin/app
  printf 'stale build\n' > build/out.txt
  printf 'dep\n' > node_modules/pkg/index.txt
  printf 'venv\n' > .venv/lib/site.txt
  printf 'secret\n' > .env.local
  # The check runs inside the clean copy. It fails while any build output of the
  # working folder is visible there, and lists every link in the copy to PROBE.
  cat > tests/pay.sh << 'SH'
fail=0
for p in target dist build bin src/__pycache__ .pytest_cache; do
  if [ -e "$p" ] || [ -L "$p" ]; then echo "build output visible in the clean copy: $p"; fail=1; fi
done
if [ -n "${PROBE:-}" ]; then
  find . -path ./.git -prune -o -type l -print | sort > "$PROBE"
fi
grep -qx paid src/pay.txt || exit 1
exit "$fail"
SH
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | del(.requirements[]?.rules)' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

@test "R73: the build folders of Node, Python, Rust and Go style projects are not linked into the clean copy" {
  export PROBE="$TEST_ROOT/links"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.checks.C1.status == "pass"' .vbw/record.json
  [ -f "$PROBE" ]
  # No link in the copy leads to build output: not target, dist, build, bin,
  # a __pycache__ or .pytest_cache.
  ! grep -E '(^|/)(target|dist|build|bin|__pycache__|\.pytest_cache)$' "$PROBE" || { cat "$PROBE"; false; }
}

@test "R73: the project's environment (dependency folders, env files) is still linked in" {
  cat > tests/pay.sh << 'SH'
grep -qx paid src/pay.txt || exit 1
grep -qx dep node_modules/pkg/index.txt || exit 1
grep -qx venv .venv/lib/site.txt || exit 1
grep -qx secret .env.local || exit 1
SH
  git add tests/pay.sh && git commit -q -m "test(pay): needs the environment"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.checks.C1.status == "pass"' .vbw/record.json
  [ "$(cat node_modules/pkg/index.txt)" = dep ]
  [ "$(cat .env.local)" = secret ]
}

@test "R73: a proof never reads build output left in the working folder: deleting those folders does not change the result" {
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local with
  with=$(jq -c '.evidence | {passed, checks: (.checks | map_values(.status))}' .vbw/record.json)
  rm -rf target dist build bin src/__pycache__ .pytest_cache
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -c '.evidence | {passed, checks: (.checks | map_values(.status))}' .vbw/record.json)" = "$with" ]
  [ "$with" = '{"passed":true,"checks":{"C1":"pass"}}' ]
}

@test "R73: build output the copy makes stays in the copy and the working folder's build output is untouched" {
  cat > tests/pay.sh << 'SH'
grep -qx paid src/pay.txt || exit 1
mkdir -p target && printf 'made by the proof\n' > target/made.txt
printf 'made by the proof\n' > dist/made.txt 2> /dev/null || true
SH
  git add tests/pay.sh && git commit -q -m "test(pay): writes build output"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e target/made.txt ]
  [ ! -e dist/made.txt ]
  [ "$(cat target/debug/app)" = "stale rust" ]
}
