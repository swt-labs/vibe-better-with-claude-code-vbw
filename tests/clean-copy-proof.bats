#!/usr/bin/env bats
# R205 (docs/proof.md): every clean copy VBW makes (vbw prove, vbw fix done, vbw
# mutate in its single form, --run and the one run of Rn.k --none) skips a path
# the spec's `## Clean copy` section lists, and everything under it, while every
# other git-ignored path is still copied in: with two ignored folders and one
# listed, the copy holds the other one whole and nothing of the listed one, also
# when only files inside the listed path are ignored (git lists them one by one).
# Build folders are left out as before. A listed path that no longer exists at
# copy time changes nothing (the next sync accepts it). The proof's results do
# not change because a path was left out: verdict, reuse decisions and read lists
# are the same with the list and without it for checks that never read the
# left-out data. L1: the kernel on a fixture project whose check lists the copy
# it runs in (PROBE, as tests/proof-build-dirs.bats does).

load helper
load fixture-helper

# shop LISTED: an approved project with two ignored folders (data/ with a nested
# folder, cache/), an ignored build folder (target/) and one check of R1 that
# reads src/pay.txt and, with PROBE set, lists the copy's files into it. With
# LISTED, the spec leaves data/ out of the clean copy.
shop() {
  vbw_setup
  vbw_git_project
  "$VBW" init > /dev/null
  printf 'data/\ncache/\ntarget/\n' > .gitignore
  mkdir -p data/sub cache target src tests
  printf 'big\n' > data/a.bin
  printf 'bigger\n' > data/sub/b.bin
  printf 'c\n' > cache/c.txt
  printf 'stale\n' > target/out
  printf 'paid\n' > src/pay.txt
  cat > tests/pay.sh << 'SH'
if [ -n "${PROBE:-}" ]; then
  find . -path ./.git -prune -o -print | sort > "$PROBE"
fi
grep -qx paid src/pay.txt
SH
  printf '# Shop\n\n## Requirements\n\n- R1 [auto] A customer can pay\n' > .vbw/spec.md
  [ "$1" != listed ] || printf '\n## Clean copy\n\n- data/\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  jq -nc '{phases: [{id: "P1", title: "Shop", reqs: ["R1"], goal: "g", criteria: ["c"], tier: "standard"}],
    plans: [{id: "P1.1", phase: "P1", title: "Pay", reqs: ["R1"], files: ["src/pay.txt"], after: [], role: "dev", tasks: ["pay"]}],
    checks: [{id: "C1", req: "R1", run: ["sh", "tests/pay.sh"], files: ["tests/pay.sh"]}],
    rules: [{req: "R1", text: "paying works", check: "C1"}]}' | "$VBW" apply > /dev/null
  # The plan is built, so vbw prove and vbw fix done judge its check.
  jq '.plans[0].status = "done"' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
  git add -A && git commit -q -m "feat(shop): start"
  "$VBW" approve > /dev/null
}

setup_file() {
  fixture_build listed shop listed
  fixture_build plain shop plain
}
setup() {
  fixture_copy listed
  export PROBE="$TEST_ROOT/probe"
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# probe_ok: the listing shows cache/ whole, no build folder and nothing of data/.
probe_ok() {
  [ -f "$PROBE" ] || { echo "the check did not run in a copy: no listing"; return 1; }
  grep -qx './cache' "$PROBE" && grep -qx './cache/c.txt' "$PROBE" || { echo "cache/ is not whole in the copy:"; cat "$PROBE"; return 1; }
  grep -qx './src/pay.txt' "$PROBE" || { echo "the committed code is missing:"; cat "$PROBE"; return 1; }
  if grep -q '^\./data' "$PROBE"; then echo "something of data/ is in the copy:"; cat "$PROBE"; return 1; fi
  if grep -q '^\./target' "$PROBE"; then echo "the build folder is in the copy:"; cat "$PROBE"; return 1; fi
}

store_reads() { jq -c '.runs["check:C1"].reads' "$(git rev-parse --git-common-dir)/vbw/runs.json"; }

@test "R205: vbw prove copies the other ignored folder whole and nothing of the listed one; build folders stay out" {
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.passed == true and .evidence.checks.C1.status == "pass"' .vbw/record.json
  probe_ok
  [ -f data/a.bin ] && [ -f data/sub/b.bin ]
}

@test "R205: when only files inside the listed path are ignored, none of them enters the copy either" {
  # The list and the contract are unchanged: only the ignore rule moves from the folder to its files.
  printf 'cache/\ntarget/\n*.bin\n' > .gitignore
  git add .gitignore && git commit -q -m "chore: ignore by file"
  [ "$(git ls-files --others --ignored --exclude-standard | grep -c '^data/')" -ge 2 ] || { git ls-files --others --ignored --exclude-standard; false; }
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  probe_ok
}

@test "R205: vbw fix done makes its copies without the listed path" {
  jq '.fixes = [{id: "F1", req: "R1", attempts: 0, status: "open", note: "a"}]' .vbw/record.json > "$TEST_ROOT/edit.json" && cp "$TEST_ROOT/edit.json" .vbw/record.json
  rm -f .vbw/runtime/glance.json
  vbw_run fix done F1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  probe_ok
}

@test "R205: vbw mutate's single form runs its checks in a copy without the listed path" {
  printf 'unpaid\n' > src/pay.txt
  vbw_run mutate P1.1 R1.1 "unpaid" src/pay.txt
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *red* ]] || { echo "$output"; false; }
  probe_ok
}

@test "R205: vbw mutate --run runs the queued breaks in copies without the listed path" {
  printf 'unpaid\n' > src/pay.txt
  "$VBW" mutate P1.1 R1.1 --queue "unpaid" src/pay.txt > /dev/null
  vbw_run mutate P1.1 --run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  probe_ok
}

@test "R205: the one run of vbw mutate Rn.k --none is made in a copy without the listed path" {
  vbw_run mutate P1.1 R1.1 --none "the check judges the record alone"
  [[ "$output" == *"ran C1 once"* ]] || { echo "$output"; false; }
  probe_ok
}

@test "R205: a listed path that no longer exists at copy time changes nothing; the next sync accepts it" {
  rm -rf data
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.evidence.passed == true' .vbw/record.json
  probe_ok
  run "$VBW" spec sync
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"does not exist"* ]] || { echo "$output"; false; }
  [ "$(jq -c '.project.leave_out' .vbw/record.json)" = '["data/"]' ] || { jq .project .vbw/record.json; false; }
}

@test "R205: a spec without the section copies every ignored folder in, as today" {
  fixture_copy plain
  export PROBE="$TEST_ROOT/probe"
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx './data/a.bin' "$PROBE" && grep -qx './data/sub/b.bin' "$PROBE" && grep -qx './cache/c.txt' "$PROBE" || { cat "$PROBE"; false; }
  if grep -q '^\./target' "$PROBE"; then cat "$PROBE"; false; fi
}

@test "R205: leaving a path out changes no result: the next proof reuses every unit and the read list is the same" {
  fixture_copy plain
  "$VBW" prove > /dev/null
  local before reads
  before=$(jq -c '.evidence | {passed, checks: (.checks | map_values(.status))}' .vbw/record.json)
  reads=$(store_reads)
  [ "$reads" != null ] || { echo "no read list recorded"; false; }
  printf '\n## Clean copy\n\n- data/\n' >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore(vbw): leave data/ out"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -c '.evidence | {passed, checks: (.checks | map_values(.status))}' .vbw/record.json)" = "$before" ] || { jq .evidence .vbw/record.json; false; }
  jq -e '.evidence.checks.C1.reused == true' .vbw/record.json || { jq .evidence.checks .vbw/record.json; false; }
  [ "$(store_reads)" = "$reads" ] || { echo "before: $reads"; echo "after: $(store_reads)"; false; }
  printf '%s\n' "$output" | grep -q '^ran again: 0 of 1 units; top reasons: none$' || { echo "$output"; false; }
}

@test "R205: a listed path under a folder git ignores as a whole is left out; the rest of that folder is copied" {
  printf '\n## Clean copy\n\n- data/sub/\n' > "$TEST_ROOT/tail"
  sed -i.bak '/^## Clean copy/,$d' .vbw/spec.md && rm -f .vbw/spec.md.bak
  cat "$TEST_ROOT/tail" >> .vbw/spec.md
  "$VBW" spec sync > /dev/null
  git add -A && git commit -q -m "chore: list data/sub"
  "$VBW" approve > /dev/null
  vbw_run prove
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$PROBE" ] || { echo "no listing"; false; }
  grep -qx './data/a.bin' "$PROBE" || { echo "data/a.bin is not in the copy:"; cat "$PROBE"; false; }
  if grep -q '^\./data/sub' "$PROBE"; then echo "something of data/sub is in the copy:"; cat "$PROBE"; false; fi
  [ -f data/sub/b.bin ]
}

# R214: the leave-out list is parsed once per copy (proofcopy_make fills the bash
# array PROOFCOPY_LEFT, the listed paths without their trailing slash), and
# proofcopy_entry reads only that array: no here-string over a raw list, no jq
# call and no record read per ignored entry.
lib() { vbw_kernel '. "$VBW_LIB/proofcopy.sh"; '"$1"; }

@test "R214: proofcopy_entry reads the parsed list only: with PROOFCOPY_LEFT set, no raw list text and no record, the listed path is skipped and its sibling listed to copy; an empty list under set -u lists as well" {
  run lib 'set -u
    unset VBW_RECORD left
    PROOFCOPY_LEFT=(data)
    got=$({ proofcopy_entry data; proofcopy_entry cache; proofcopy_entry data/sub; } | tr "\0" "\n")
    [ "$got" = cache ] || { echo "listed to copy: $got (only cache, nothing of the listed data/)"; exit 1; }
    PROOFCOPY_LEFT=()
    got=$(proofcopy_entry target | tr "\0" "\n")
    [ "$got" = target ] || { echo "target/ was not listed with an empty list: $got"; exit 1; }
    echo done'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | tail -n 1)" = done ] || { echo "$output"; false; }
}
