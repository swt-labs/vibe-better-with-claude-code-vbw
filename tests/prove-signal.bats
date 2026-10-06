#!/usr/bin/env bats
# R69 (F40, D145): when vbw prove is stopped by a signal sent to it alone, it
# never kills its checks (no process killing): it waits for the checks already
# running to finish within their own timeout, then cleans up and exits, so no
# check outlives it or writes into a removed directory. L1: a fixture whose
# checks mark when they start and end.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  mkdir -p src tests
  printf 'paid\n' > src/pay.txt
  MARK="$TEST_ROOT/mark"
  mkdir -p "$MARK"
  export MARK
  cat > tests/slow.sh << 'SH'
touch "$MARK/start.$$"
sleep 5
touch "$MARK/end.$$"
SH
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/slow.sh"], files:["tests/slow.sh"]},
                 {id:"C2", req:"R1", run:["sh","tests/slow.sh"], files:["tests/slow.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | del(.requirements[]?.rules)' .vbw/record.json > "$TEST_ROOT/e.json" && cp "$TEST_ROOT/e.json" .vbw/record.json
  git add -A && git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

count() { ls "$MARK" | grep -c "^$1\." || true; }

@test "R69: a TERM sent to vbw prove alone waits for its running checks, then cleans up; nothing outlives it" {
  "$VBW" prove > "$TEST_ROOT/out" 2>&1 &
  local pid=$! i
  for i in $(seq 1 100); do [ "$(count start)" -ge 2 ] && break; sleep 0.1; done
  [ "$(count start)" -ge 2 ]
  kill -TERM "$pid"
  local code=0
  wait "$pid" || code=$?
  echo "vbw exited $code; started $(count start), ended $(count end)" >&3
  # When vbw has exited, every check it started has ended: none was orphaned.
  [ "$(count end)" -eq "$(count start)" ] || { echo "started $(count start), ended $(count end) when vbw exited"; false; }
  # Its run directories are gone and stay gone.
  sleep 1
  [ -z "$(find .vbw/runtime -maxdepth 1 \( -name 'run.*' -o -name 'proof.*' \) 2> /dev/null)" ]
}
