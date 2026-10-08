#!/usr/bin/env bats
# R93 (docs/proof.md): after a proof, VBW looks in the working folder (git-ignored
# folders such as node_modules included) for symbolic links whose target is
# inside a proof copy (.vbw/runtime/proof.*, absolute or relative) and names each
# one with how to repair it, so damage left by an earlier VBW is found; with none
# it says nothing. The scan only reads: it does not follow links, skips .git, and
# never turns a passing proof into a failing one. L1: stale links planted by hand
# in a fixture.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'node_modules/\ntarget/\n.vbw/runtime/\n' > .gitignore
  mkdir -p node_modules/@kit node_modules/pkg target
  printf 'dep\n' > node_modules/pkg/index.txt
  OUTSIDE="$TEST_ROOT/outside"
  mkdir -p "$OUTSIDE/inner"
  export OUTSIDE
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | del(.requirements[]?.rules)' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A > /dev/null
  git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

# plant: a stale absolute and a stale relative link, as an earlier VBW's proof copy left them.
plant() {
  ln -s "$PROJECT/.vbw/runtime/proof.OLDabs1/tree/packages/ui" node_modules/@kit/ui
  ln -s ../.vbw/runtime/proof.OLDrel2/tree/packages/core node_modules/core
}

# snap: every file (checksum), link (target) and folder outside .git and .vbw.
snap() {
  local p
  find . \( -path ./.git -o -path ./.vbw \) -prune -o -print | LC_ALL=C sort | while IFS= read -r p; do
    if [ -L "$p" ]; then
      printf 'L %s -> %s\n' "$p" "$(readlink "$p")"
    elif [ -f "$p" ]; then
      printf 'F %s %s\n' "$p" "$(cksum < "$p")"
    else
      printf 'D %s\n' "$p"
    fi
  done
}

@test "R93: each stale link, absolute or relative, in a git-ignored folder is named on its own line with its target and the pnpm repair" {
  printf 'lockfileVersion: 9\n' > pnpm-lock.yaml
  git add pnpm-lock.yaml && git commit -q -m "chore: lockfile"
  "$VBW" approve > /dev/null
  plant
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'proof\.OLD')" -eq 2 ]
  printf '%s\n' "$output" | grep 'node_modules/@kit/ui' | grep 'proof.OLDabs1' | grep -q 'pnpm install'
  printf '%s\n' "$output" | grep 'node_modules/core' | grep 'proof.OLDrel2' | grep -q 'pnpm install'
  printf '%s\n' "$output" | grep 'node_modules/@kit/ui' | grep -qi 'delete node_modules'
}

@test "R93: a project that is not pnpm is told to re-run its install command" {
  plant
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'proof\.OLD')" -eq 2 ]
  printf '%s\n' "$output" | grep 'node_modules/core' | grep -q "install command"
  ! printf '%s\n' "$output" | grep 'node_modules/core' | grep -q 'pnpm install'
}

@test "R93: with no such link a proof prints nothing but its own summary" {
  ln -s ../.vbw/record.json node_modules/other-in-vbw
  ln -s "$OUTSIDE/.vbw/runtime/proof.NOTMINE/tree" node_modules/elsewhere
  ln -s ../.vbw/runtime/other/tree node_modules/near
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"proof.NOTMINE"* ]]
  [[ "$output" != *"other-in-vbw"* ]]
  [[ "$output" != *"node_modules/near"* ]]
  # Every line is the proof's own summary.
  ! printf '%s\n' "$output" | grep -vE '^(  C1 pass [0-9]+s|  checks: [0-9]+ ran, [0-9]+ reused|  proof: (full|partial.*)|  scope ok|R1 [a-z]+|proved)$'
}

@test "R93: the scan changes nothing in the working folder, does not follow links, and skips .git" {
  plant
  ln -s "$OUTSIDE" node_modules/ext
  ln -s "$PROJECT/.vbw/runtime/proof.INSIDEOUT/tree" "$OUTSIDE/inner/stale"
  ln -s . node_modules/loop
  ln -s "$PROJECT/.vbw/runtime/proof.INGIT/tree" .git/hooks/stale
  snap > "$TEST_ROOT/before"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"proof.OLDabs1"* ]]
  [[ "$output" != *"proof.INSIDEOUT"* ]]
  [[ "$output" != *"proof.INGIT"* ]]
  snap > "$TEST_ROOT/after"
  diff "$TEST_ROOT/before" "$TEST_ROOT/after"
}

@test "R93: the scan runs when the proof stops early with an error, and a failing proof still fails the same way" {
  plant
  printf 'grep -qx paid src/pay.txt\n# edited\n' > tests/pay.sh
  vbw_run prove
  [ "$status" -ne 0 ]
  [[ "$output" == *"waiting for approval"* ]]
  [[ "$output" == *"proof.OLDabs1"* ]]
  git checkout -q tests/pay.sh
  printf 'broken\n' > src/pay.txt
  git add src/pay.txt && git commit -q -m "feat(pay): break it"
  vbw_run prove
  [ "$status" -eq 1 ]
  [[ "$output" == *"C1 fail"* ]]
  [[ "$output" == *"proof.OLDrel2"* ]]
}

@test "R93: a stale link never turns a passing proof into a failing one" {
  plant
  vbw_run prove
  [ "$status" -eq 0 ]
  jq -e '.evidence.passed == true' .vbw/record.json
}

@test "R93: the scan of a working folder with 50,000 files adds little time (measured)" {
  local d i t0 t1 t2
  for d in $(seq 1 50); do
    mkdir -p "target/d$d"
    (cd "target/d$d" && seq 1 1000 | sed 's/^/f/' | xargs touch)
  done
  [ "$(find target -type f | wc -l | tr -d ' ')" -eq 50000 ]
  now() { perl -MTime::HiRes=time -e 'printf "%.2f", time'; }
  t0=$(now)
  vbw_run prove
  t1=$(now)
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  plant
  vbw_run prove
  t2=$(now)
  [ "$status" -eq 0 ]
  [[ "$output" == *"proof.OLDabs1"* ]]
  i=$(perl -e 'printf "%.2f", $ARGV[0] - $ARGV[1]' "$t2" "$t1")
  echo "50,000 files in the working folder: proof without a stale link $(perl -e 'printf "%.2f", $ARGV[0] - $ARGV[1]' "$t1" "$t0")s, with one $i s" >&3
  perl -e 'exit($ARGV[0] < 30 ? 0 : 1)' "$i"
}
