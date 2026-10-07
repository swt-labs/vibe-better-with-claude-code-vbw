#!/usr/bin/env bats
# R92 (docs/proof.md): the proof copy shares no writable folder with the working
# folder. Git-ignored files and folders (dependencies, env files) are copied in,
# as a copy-on-write clone where the file system offers one and as a plain copy
# where it does not, never linked; so a tool that refuses linked folders
# (pnpm 11 recursive runs) or writes into its dependency folders behaves in the
# proof as in place, and nothing a proof does changes the working folder.
# L1: a project script drives vbw prove on a fixture; the fixture's check
# scripts first fail when node_modules is a link (the pnpm 11 refusal).

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests packages/a
  printf 'paid\n' > src/pay.txt
  printf 'pkg a\n' > packages/a/x.txt
  cat > .gitignore << 'GI'
node_modules/
.env.local
dist/
.next/
target/
locked/
.vbw/runtime/
.vbw/local.txt
GI
  mkdir -p node_modules/pkg node_modules/dep/dist node_modules/ro/sub dist .next target
  printf 'dep\n' > node_modules/pkg/index.txt
  printf 'nested dist\n' > node_modules/dep/dist/x.js
  printf 'ro\n' > node_modules/ro/sub/f.txt
  chmod 555 node_modules/ro/sub
  printf 'secret\n' > .env.local
  printf 'local\n' > .vbw/local.txt
  printf 'stale\n' > dist/bundle.js
  printf 'stale\n' > .next/b
  printf 'stale\n' > target/t
  ln -s ../packages/a node_modules/rel
  ln -s "$PROJECT/packages/a" node_modules/abs
  OUTSIDE="$TEST_ROOT/outside"
  mkdir -p "$OUTSIDE"
  printf 'keep\n' > "$OUTSIDE/keep.txt"
  ln -s "$OUTSIDE" node_modules/outside
  export OUTSIDE ROOT="$PROJECT" MARK="$TEST_ROOT/mark"
  mkdir -p "$MARK"
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | del(.requirements[]?.rules)' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  use_check ''
}

teardown() {
  chmod -R u+rwx "$PROJECT" 2> /dev/null || true
  vbw_teardown
}

# use_check BODY: the check script; it first fails when node_modules or the env
# file is a link (the pnpm 11 task-run-state refusal), then runs BODY.
use_check() {
  {
    cat << 'SH'
grep -qx paid src/pay.txt || exit 1
if [ -L node_modules ] || [ ! -d node_modules ]; then echo "ERR_PNPM_UNSAFE_TASK_RUN_STATE_PATH node_modules is a link"; exit 41; fi
if [ -L .env.local ] || [ ! -f .env.local ]; then echo ".env.local is a link"; exit 42; fi
SH
    printf '%s\n' "$1"
  } > tests/pay.sh
  git add -A > /dev/null
  git commit -q -m "chore(vbw): check" --allow-empty
  "$VBW" approve > /dev/null
}

# snap: every file (checksum), link (target) and folder of the working folder
# outside .git and .vbw, git-ignored ones included.
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

@test "R92: no git-ignored path of the copy is a link, and each has the working folder's content" {
  use_check '
[ ! -L node_modules/pkg ] && [ "$(cat node_modules/pkg/index.txt)" = dep ] || exit 43
[ "$(cat .env.local)" = secret ] || exit 44
[ "$(cat node_modules/dep/dist/x.js)" = "nested dist" ] || exit 45'
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.checks.C1.status == "pass"' .vbw/record.json
}

@test "R92: a write inside node_modules passes in the proof and never reaches the working folder" {
  use_check '
printf "made by the proof\n" > node_modules/written.txt || exit 46
printf "more\n" >> .env.local || exit 47'
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e node_modules/written.txt ]
  [ "$(cat .env.local)" = secret ]
}

@test "R92: a check that fails when node_modules is a link (the pnpm 11 refusal) passes in vbw prove as in vbw check" {
  use_check 'mkdir -p node_modules/.pnpm-task-run-state-v1 || exit 48'
  vbw_run check C1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  rm -rf node_modules/.pnpm-task-run-state-v1
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.checks.C1.status == "pass"' .vbw/record.json
  [ ! -e node_modules/.pnpm-task-run-state-v1 ]
}

@test "R92: after a proof every file and link of the working folder is byte-identical, workspace links in node_modules included" {
  use_check '
rm node_modules/rel && ln -s "$PWD/packages/a" node_modules/rel || exit 49
printf "changed\n" > node_modules/pkg/index.txt
rm -rf node_modules/dep
mkdir -p node_modules/new && printf "x\n" > node_modules/new/y.txt'
  snap > "$TEST_ROOT/before"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  snap > "$TEST_ROOT/after"
  diff "$TEST_ROOT/before" "$TEST_ROOT/after"
  [ "$(readlink node_modules/rel)" = ../packages/a ]
}

@test "R92: links inside a copied folder stay links: a relative one resolves in the copy, an absolute one into the working folder is reported with its path" {
  use_check '
[ -L node_modules/rel ] && [ "$(readlink node_modules/rel)" = ../packages/a ] || exit 50
[ "$(cat node_modules/rel/x.txt)" = "pkg a" ] || exit 51
[ -L node_modules/abs ] && [ "$(readlink node_modules/abs)" = "$ROOT/packages/a" ] || exit 52'
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"node_modules/abs"* ]]
  [[ "$output" != *"node_modules/outside"* ]]
  [[ "$output" != *"node_modules/rel"* ]]
}

@test "R92: the copy uses a copy-on-write clone first, and falls back to a plain copy where it is refused" {
  local stub="$TEST_ROOT/stub" real
  real=$(command -v cp)
  mkdir -p "$stub"
  cat > "$stub/cp" << 'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$CP_LOG"
if [ -n "${CP_REFUSE_CLONE:-}" ]; then
  for a in "$@"; do
    case "$a" in
      --reflink*) exit 1 ;;
      --) break ;;
      -[!-]*c*) exit 1 ;;
    esac
  done
fi
exec "$REAL_CP" "$@"
SH
  chmod +x "$stub/cp"
  export REAL_CP="$real" CP_LOG="$TEST_ROOT/cp.log"
  use_check '[ "$(cat node_modules/pkg/index.txt)" = dep ] || exit 53'
  : > "$CP_LOG"
  PATH="$stub:$PATH" vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -E -- '(^| )(--reflink|-[A-Za-z]*c[A-Za-z]*)( |$)' "$CP_LOG" || { cat "$CP_LOG"; false; }
  : > "$CP_LOG"
  CP_REFUSE_CLONE=1 PATH="$stub:$PATH" vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.checks.C1.status == "pass"' .vbw/record.json
  [ -s "$CP_LOG" ]
}

@test "R92: build output is not brought in, but a dist folder inside a copied folder is; .git and .vbw are never copied" {
  use_check '
for p in dist .next target; do [ ! -e "$p" ] && [ ! -L "$p" ] || { echo "build output visible: $p"; exit 54; }; done
[ -f node_modules/dep/dist/x.js ] || exit 55
[ -f .git ] || exit 56
[ ! -e .vbw/local.txt ] && [ ! -e .vbw/runtime ] || exit 57'
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.checks.C1.status == "pass"' .vbw/record.json
}

@test "R92: an ignored folder that cannot be read fails the proof before any check runs, naming it, with no copy left" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  use_check 'touch "$MARK/ran"'
  mkdir locked
  printf 'x\n' > locked/f.txt
  chmod 000 locked
  vbw_run prove
  [ "$status" -ne 0 ]
  [[ "$output" == *"locked"* ]]
  [ ! -e "$MARK/ran" ]
  [ -z "$(find .vbw/runtime -maxdepth 1 -name 'proof.*' 2> /dev/null)" ]
  [ "$(git worktree list | wc -l | tr -d ' ')" = 1 ]
}

@test "R92: the copy is removed after a proof, read-only folders included, and nothing outside it is touched" {
  use_check '[ -d node_modules/ro/sub ] || exit 58'
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$(find .vbw/runtime -maxdepth 1 -name 'proof.*' 2> /dev/null)" ]
  [ "$(git worktree list | wc -l | tr -d ' ')" = 1 ]
  [ "$(cat "$OUTSIDE/keep.txt")" = keep ]
  [ -L node_modules/outside ]
  [ "$(cat node_modules/ro/sub/f.txt)" = ro ]
}

@test "R92: an interrupted proof removes the whole copy and never deletes outside it" {
  use_check '
touch "$MARK/started"
sleep 4'
  "$VBW" prove > "$TEST_ROOT/out" 2>&1 &
  local pid=$! i
  for i in $(seq 1 100); do [ -e "$MARK/started" ] && break; sleep 0.1; done
  [ -e "$MARK/started" ]
  kill -TERM "$pid"
  wait "$pid" || true
  [ -z "$(find .vbw/runtime -maxdepth 1 -name 'proof.*' 2> /dev/null)" ]
  [ "$(cat "$OUTSIDE/keep.txt")" = keep ]
  [ "$(cat node_modules/pkg/index.txt)" = dep ]
}
