#!/usr/bin/env bats
# #738 (docs/proof.md, "Kept copies"): measured in the release run
# (tests/timed-*.bats), never in vbw prove: on a project with a 50 MB ignored
# folder of 5,000 files, a second proof that claims the kept copy spends less
# time bringing it up to date (evidence.own.copy_slots.refresh) than half the
# time the first proof spent making it. The copies step (evidence.own.copies)
# also counts work no copy changes (checking the committed check files against
# the approved ones, the step bookkeeping): the second proof's copies less its
# refresh is that work, taken off the first proof's copies to leave the making
# alone. The figures come from the proof's own clock.

load helper

setup() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  mkdir -p src tests node_modules
  printf 'paid\n' > src/pay.txt
  printf 'grep -qx paid src/pay.txt\n' > tests/pay.sh
  printf 'node_modules/\n' > .gitignore
  # 50 packages of 100 files of 10 KB: 50 MB in 5,000 files.
  local p f
  head -c 10240 /dev/zero > "$TEST_ROOT/blob"
  for p in $(seq 1 50); do
    mkdir -p "node_modules/p$p"
    for f in $(seq 1 100); do cp "$TEST_ROOT/blob" "node_modules/p$p/f$f.js"; done
  done
  jq '.checks = [{id:"C1", req:"R1", run:["sh","tests/pay.sh"], files:["tests/pay.sh"]}]
    | .phases = [{id:"P1", title:"Pay", reqs:["R1"], milestone:"M1"}]
    | .plans = [{id:"P1.1", phase:"P1", title:"Pay", reqs:["R1"], files:["src/pay.txt"], after:[], status:"done"}]
    | del(.requirements[]?.rules) | if has("protected") then .protected = ([.checks[]?.files // [] | .[]] | unique) | .schema = ([.schema, 4] | max) else . end' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  git add -A > /dev/null
  git commit -q -m "chore(vbw): plan"
  "$VBW" approve > /dev/null
}

teardown() { vbw_teardown; }

@test "#738: a second proof claiming the kept copy of a 50 MB ignored folder is brought up to date in less than half the time the first proof spent making it" {
  local first second rest make
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.own.copy_slots.made == 1' .vbw/record.json > /dev/null || { jq .evidence.own .vbw/record.json; false; }
  first=$(jq '.evidence.own.copies' .vbw/record.json)
  printf 'paid\ntwo\n' > src/pay.txt
  git commit -q -am "feat: two"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.own.copy_slots | .claimed == 1 and .made == 0' .vbw/record.json > /dev/null || { jq .evidence.own .vbw/record.json; false; }
  second=$(jq '.evidence.own.copy_slots.refresh' .vbw/record.json)
  rest=$(jq '.evidence.own.copies - .evidence.own.copy_slots.refresh' .vbw/record.json)
  make=$(awk -v a="$first" -v r="$rest" 'BEGIN { printf "%.3f", a - r }')
  echo "first proof: $first s in copies, about $make s of it making the copy; second proof: $second s bringing it up to date"
  awk -v m="$make" -v b="$second" 'BEGIN { exit !(m > 0 && b < m / 2) }' || { echo "the kept copy saved too little"; false; }
}
