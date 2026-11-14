#!/usr/bin/env bats
# R183, #738: a proof's copy is a kept slot (.vbw/runtime/proof.keep.N) whose pid
# file names its owner while it runs, and a killed proof's slot is claimed by the
# next one. A copy of an older VBW (.vbw/runtime/proof.PID.XXXXXX) names its
# owner process in its folder name; the next vbw prove or vbw fix done removes every copy whose
# owner has ended (with its git worktree entry, read-only folders included,
# never following a link out), keeps a copy whose owner is alive, removes an
# owner-less copy of an older VBW only past 24 hours, and never lets the
# cleanup change a proof's result. L1: a fixture whose check can be held.

load helper
load fixture-helper

# The approved project with its holdable check, built once per file. LIVE is an
# array, which a builder may not set, so setup makes it after the copy.
setup_file() { fixture_build hold hold_project; }
setup() {
  fixture_copy hold
  LIVE=()
}

hold_project() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  MARK="$TEST_ROOT/mark"
  OUTSIDE="$TEST_ROOT/outside"
  mkdir -p "$MARK" "$OUTSIDE"
  printf 'keep\n' > "$OUTSIDE/keep.txt"
  export MARK
  # HOLD=1 keeps the check running until $MARK/release exists; FAIL=1 fails it.
  cat > tests/hold.sh << 'SH'
touch "$MARK/start.$$"
while [ -n "${HOLD:-}" ] && [ ! -e "$MARK/release" ]; do sleep 0.1; done
touch "$MARK/end.$$"
[ -z "${FAIL:-}" ]
SH
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/hold.sh"], files:["tests/hold.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' \
    .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

teardown() {
  local p
  for p in ${LIVE[@]+"${LIVE[@]}"}; do kill "$p" 2> /dev/null || true; done
  touch "$MARK/release" 2> /dev/null || true
  if command -v chflags > /dev/null 2>&1; then chflags -R nouchg "$TEST_ROOT" 2> /dev/null || true; fi
  chmod -R u+rwx "$TEST_ROOT" 2> /dev/null || true
  wait 2> /dev/null || true
  vbw_teardown
}

count() { find "$MARK" -name "$1.*" | wc -l | tr -d ' '; }

# A pid that no running process has.
dead_pid() {
  local p
  sh -c 'exit 0' &
  p=$!
  wait "$p" || true
  printf '%s\n' "$p"
}

# live_pid: start a process that stays alive for the test; sets PID_LIVE.
live_pid() {
  sleep 300 &
  PID_LIVE=$!
  LIVE+=("$PID_LIVE")
}

# mkcopy NAME: a proof copy at .vbw/runtime/NAME, holding a git worktree of HEAD.
mkcopy() {
  mkdir -p ".vbw/runtime/$1"
  git worktree add -q --detach ".vbw/runtime/$1/tree" HEAD > /dev/null 2>&1
  printf 'whole\n' > ".vbw/runtime/$1/tree/whole.txt"
}

# wt_listed NAME: git worktree list names the copy.
wt_listed() { git worktree list --porcelain | grep -qF "/$1/tree"; }

# wt_admin NAME: .git/worktrees holds an entry for the copy.
wt_admin() {
  local g
  for g in .git/worktrees/*/gitdir; do
    [ -f "$g" ] && grep -qF "/$1/tree" "$g" && return 0
  done
  return 1
}

gone() {
  [ ! -e ".vbw/runtime/$1" ] || { echo "$1 is still on disk"; return 1; }
  ! wt_listed "$1" || { echo "$1 is still listed by git worktree list"; return 1; }
  ! wt_admin "$1" || { echo "$1 still has an entry in .git/worktrees"; return 1; }
}

whole() {
  [ "$(cat ".vbw/runtime/$1/tree/whole.txt" 2> /dev/null)" = whole ] || { echo "$1 was changed or removed"; return 1; }
  [ -f ".vbw/runtime/$1/tree/src/pay.txt" ] || { echo "$1 lost its files"; return 1; }
  wt_listed "$1" || { echo "$1 lost its worktree entry"; return 1; }
}

# result: the proof's outcome and what ran, as one line.
result() { jq -c '{passed: .evidence.passed, checks: (.evidence.checks | map_values({status, reused}))}' .vbw/record.json; }

@test "R183 #738: a proof's copy is a kept slot whose pid file names its owner process while it runs" {
  HOLD=1 "$VBW" prove > "$TEST_ROOT/out" 2>&1 &
  local pid=$! i d n=0
  for i in $(seq 1 100); do [ "$(count start)" -ge 1 ] && break; sleep 0.1; done
  [ "$(count start)" -ge 1 ]
  for d in .vbw/runtime/proof.*; do
    [ -e "$d" ] || continue
    n=$((n + 1))
    [[ "${d##*/}" =~ ^proof\.keep\.[0-9]+$ ]] || { echo "copy ${d##*/} is not a kept slot"; false; }
    [ "$(cat "$d/pid")" = "$pid" ] || { echo "slot ${d##*/} does not name its owner $pid"; false; }
  done
  [ "$n" -ge 1 ]
  touch "$MARK/release"
  wait "$pid"
}

@test "R183 #738: after a proof killed with kill -9, the next proof claims its slot, whose copy is a repository of its own; a live process's copy stays whole" {
  HOLD=1 "$VBW" prove > "$TEST_ROOT/out" 2>&1 &
  local pid=$! i
  for i in $(seq 1 100); do [ "$(count start)" -ge 1 ] && break; sleep 0.1; done
  [ "$(count start)" -ge 1 ]
  kill -9 "$pid"
  wait "$pid" || true
  # The orphaned check finishes by itself.
  touch "$MARK/release"
  for i in $(seq 1 100); do [ "$(count end)" -ge "$(count start)" ] && break; sleep 0.1; done
  sleep 0.5
  [ "$(cat .vbw/runtime/proof.keep.1/pid)" = "$pid" ] || { echo "the killed proof left no owned slot"; false; }
  live_pid
  mkcopy "proof.$PID_LIVE.Live01"
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r .evidence.passed .vbw/record.json)" = true ]
  [ ! -e .vbw/runtime/proof.keep.1/pid ] || { echo "the dead owner's slot is still owned"; false; }
  [ ! -e .vbw/runtime/proof.keep.2 ] || { echo "a new slot was made beside the dead owner's"; false; }
  # The claimed slot holds one copy, a repository of its own whose git folder is in the slot (R309).
  [ -f .vbw/runtime/proof.keep.1/tree/.git ] || { ls -la .vbw/runtime/proof.keep.1/tree; false; }
  case "$(cd -P "$(git -C .vbw/runtime/proof.keep.1/tree rev-parse --absolute-git-dir)" && pwd -P)" in
    "$(cd -P .vbw/runtime/proof.keep.1 && pwd -P)"/tree/*) echo "the copy's git folder is in its tree"; false ;;
    "$(cd -P .vbw/runtime/proof.keep.1 && pwd -P)"/*) ;;
    *) echo "the copy's git folder is not in its slot"; false ;;
  esac
  ! git worktree list --porcelain | grep -qF '/proof.keep.1/tree' || { git worktree list; false; }
  whole "proof.$PID_LIVE.Live01"
}

@test "R183: vbw fix done removes a dead process's copy and keeps a live one" {
  jq '.fixes = [{id:"F1", req:"R1", attempts:0, status:"open", note:"a"}]' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): fix"
  "$VBW" approve > /dev/null
  local dead
  dead=$(dead_pid)
  live_pid
  mkcopy "proof.$dead.Dead01"
  mkcopy "proof.$PID_LIVE.Live01"
  vbw_run fix "done" F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(count end)" -ge 1 ]
  gone "proof.$dead.Dead01"
  whole "proof.$PID_LIVE.Live01"
}

@test "R183: a copy with no owner (an older VBW's) is removed past 24 hours and kept when newer" {
  mkcopy proof.Old123
  mkcopy proof.Fresh1
  # All digits, no owner part: still an owner-less copy, never read as a pid.
  mkcopy proof.204816
  touch -t 202001010000 .vbw/runtime/proof.Old123
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  gone proof.Old123
  whole proof.Fresh1
  whole proof.204816
}

@test "R183: removing a dead copy deletes read-only folders, never follows a link out, and finishes a half-removed copy" {
  local dead
  dead=$(dead_pid)
  mkcopy "proof.$dead.Ro0001"
  mkdir -p ".vbw/runtime/proof.$dead.Ro0001/tree/ro/sub"
  printf 'ro\n' > ".vbw/runtime/proof.$dead.Ro0001/tree/ro/sub/f.txt"
  ln -s "$OUTSIDE" ".vbw/runtime/proof.$dead.Ro0001/tree/out"
  chmod 555 ".vbw/runtime/proof.$dead.Ro0001/tree/ro/sub" ".vbw/runtime/proof.$dead.Ro0001/tree/ro"
  # Half removed: the worktree's own .git file and some files are gone, the folder and the entry are not.
  mkcopy "proof.$dead.Half01"
  rm -rf ".vbw/runtime/proof.$dead.Half01/tree/.git" ".vbw/runtime/proof.$dead.Half01/tree/src"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  gone "proof.$dead.Ro0001"
  gone "proof.$dead.Half01"
  [ "$(cat "$OUTSIDE/keep.txt")" = keep ]
}

@test "R183: two cleanups at once never fail or print an error, and a live copy stays whole" {
  local dead i a=0 b=0
  live_pid
  mkcopy "proof.$PID_LIVE.Live01"
  for i in 1 2 3 4 5 6; do
    dead=$(dead_pid)
    mkcopy "proof.$dead.Dd000$i"
    printf '%s\n' "proof.$dead.Dd000$i" >> "$TEST_ROOT/dead"
  done
  "$VBW" prove > "$TEST_ROOT/a.out" 2> "$TEST_ROOT/a.err" < /dev/null &
  local pa=$!
  "$VBW" prove > "$TEST_ROOT/b.out" 2> "$TEST_ROOT/b.err" < /dev/null &
  local pb=$!
  wait "$pa" || a=$?
  wait "$pb" || b=$?
  cat "$TEST_ROOT/a.err" "$TEST_ROOT/b.err"
  [ "$a" -eq 0 ] && [ "$b" -eq 0 ]
  if grep -iE 'error|fatal|cannot|no such|rm:|proof\.' "$TEST_ROOT/a.err" "$TEST_ROOT/b.err"; then false; fi
  while IFS= read -r i; do gone "$i"; done < "$TEST_ROOT/dead"
  whole "proof.$PID_LIVE.Live01"
}

@test "R183: a dead copy that cannot be removed leaves the proof's result unchanged and one warning naming the folder" {
  command -v chflags > /dev/null 2>&1 || skip "no chflags: no unremovable file can be made without root"
  local dead line path
  vbw_run prove --full
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local before
  before=$(result)
  dead=$(dead_pid)
  mkcopy "proof.$dead.Stuck1"
  chflags uchg ".vbw/runtime/proof.$dead.Stuck1/tree/whole.txt"
  "$VBW" prove --full > "$TEST_ROOT/out" 2> "$TEST_ROOT/err" < /dev/null
  cat "$TEST_ROOT/err"
  [ "$(result)" = "$before" ]
  [ "$(grep -c 'proof\.' "$TEST_ROOT/err")" -eq 1 ]
  line=$(grep 'proof\.' "$TEST_ROOT/err")
  [[ "$line" == vbw:* ]]
  path=$(printf '%s' "$line" | grep -oE '\.vbw/runtime/proof[^ :;,()]*' | head -1)
  [ -n "$path" ] && [ -e "$path" ]
}

@test "R183: the proof's result is the same with and without leftover copies, passing or failing" {
  local f dead before
  for f in "" 1; do
    export FAIL=$f
    "$VBW" prove --full > /dev/null 2>&1 < /dev/null || true
    before=$(result)
    dead=$(dead_pid)
    mkcopy "proof.$dead.Same0$f"
    mkcopy "proof.Old00$f"
    touch -t 202001010000 ".vbw/runtime/proof.Old00$f"
    "$VBW" prove --full > /dev/null 2>&1 < /dev/null || true
    [ "$(result)" = "$before" ] || { echo "FAIL=$f: $before became $(result)"; false; }
    gone "proof.$dead.Same0$f"
    gone "proof.Old00$f"
  done
  unset FAIL
}

@test "R183: docs/proof.md says copies record their owner and the next proof removes copies left by an ended process" {
  local doc="$BATS_TEST_DIRNAME/../docs/proof.md"
  grep -qi 'owner' "$doc"
  grep -qiE 'leftover|left behind|left over' "$doc"
  grep -qi '24 hours' "$doc"
}
