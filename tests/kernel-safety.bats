#!/usr/bin/env bats
# P1 / R1, R2: concurrent consent grants are never lost, and an interrupted
# vbw command leaves no debris and keeps its caller's own EXIT cleanup.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  git add .vbw && git commit -q -m "chore(vbw): init"
}

teardown() { vbw_teardown; }

# grants PREFIX N: N distinct consent grants, one process, this directory.
grants() {
  vbw_kernel "for i in \$(seq 1 $2); do consent_grant command $1\$i '{}'; done"
}

@test "R1: grants from two worktrees of one clone, started together, are all kept" {
  git worktree add -q "$TEST_ROOT/wt" -b other
  local round
  for round in 1 2 3; do
    rm -f .git/vbw/consent.json
    grants a 25 &
    local p1=$!
    (cd "$TEST_ROOT/wt" && grants b 25) &
    local p2=$!
    wait "$p1"; wait "$p2"
    [ "$(jq '.granted | length' .git/vbw/consent.json)" -eq 50 ]
  done
}

# An interrupted vbw commit: the plan's commit is held in a pre-commit hook,
# then the process gets SIGTERM.
commit_setup() {
  jq '.requirements = [{id:"R1", text:"Pay", proof:"auto", status:"open", milestone: "M1"}]
      | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone: "M1"}]
      | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["pay.txt"], after:[], status:"building"}]' \
    .vbw/record.json > "$TEST_ROOT/r.json" && cp "$TEST_ROOT/r.json" .vbw/record.json
  git add .vbw/record.json && git commit -q -m "chore(vbw): plan"
  printf 'pay\n' > pay.txt
  printf '#!/bin/sh\ntouch "%s/held"\nsleep 3\n' "$TEST_ROOT" > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
}

wait_for() {
  local i
  for i in $(seq 1 100); do [ -e "$1" ] && return 0; sleep 0.1; done
  return 1
}

@test "R2: an interrupted code fingerprint (prove, next) leaves no index file" {
  mkdir -p "$TEST_ROOT/bin"
  local real
  real=$(command -v git)
  printf '#!/bin/sh\nif [ "$1" = add ]; then touch "%s/held"; sleep 3; fi\nexec "%s" "$@"\n' "$TEST_ROOT" "$real" > "$TEST_ROOT/bin/git"
  chmod +x "$TEST_ROOT/bin/git"
  cat > "$TEST_ROOT/tree.sh" <<EOS
VBW_LIB="$PLUGIN_ROOT/lib"
for l in core record consent contract; do . "\$VBW_LIB/\$l.sh"; done
vbw_project; mkdir -p "\$VBW_RUNTIME"
vbw_code_tree
EOS
  PATH="$TEST_ROOT/bin:$PATH" bash "$TEST_ROOT/tree.sh" < /dev/null > /dev/null 2>&1 &
  local pid=$!
  wait_for "$TEST_ROOT/held"
  kill -TERM "$pid"
  wait "$pid" || true
  [ -z "$(find .vbw/runtime -name 'index.*' 2> /dev/null)" ]
}

@test "R2: the caller's EXIT trap still runs when vbw code is interrupted" {
  commit_setup
  cat > "$TEST_ROOT/caller.sh" <<EOS
VBW_LIB="$PLUGIN_ROOT/lib"
for l in core record consent contract; do . "\$VBW_LIB/\$l.sh"; done
VBW_PLUGIN="$PLUGIN_ROOT"; export VBW_LIB VBW_PLUGIN
vbw_project
trap 'touch "$TEST_ROOT/caller-ran"' EXIT
. "\$VBW_LIB/cmd-commit.sh"
cmd_commit P1.1 "feat(pay): pay"
EOS
  bash "$TEST_ROOT/caller.sh" < /dev/null > /dev/null 2>&1 &
  local pid=$!
  wait_for "$TEST_ROOT/held"
  kill -TERM "$pid"
  wait "$pid" || true
  [ -e "$TEST_ROOT/caller-ran" ]
  [ ! -d .vbw/runtime/lock ]
}

@test "R2: the caller's EXIT trap survives a vbw write that completes" {
  vbw_kernel 'trap "echo caller" EXIT; record_update ".milestone.title = \"X\""; trap -p EXIT' > "$TEST_ROOT/out"
  grep -q "caller" "$TEST_ROOT/out"
}

@test "the kernel stays within 3,000 lines" {
  [ "$(cat "$PLUGIN_ROOT"/bin/vbw "$PLUGIN_ROOT"/lib/*.sh | wc -l)" -le 3000 ]
}
