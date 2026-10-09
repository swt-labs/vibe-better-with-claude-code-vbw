#!/usr/bin/env bats
# R132 (L1): the QA files fingerprint stored for a passed phase carries the
# version of how it was computed (QA_FP_VERSION in lib/qa-inputs.sh), kept in
# the clone's QA cache next to the digests (no new record field). After a VBW
# update that changes that version, a phase that passed QA and whose files,
# tests, plan and requirements have not changed still stands: vbw next does not
# send it to QA and vbw show calls its pass current. A fingerprint written by
# an older VBW, with no version, is an older version, not a change. A real
# change to the phase, made before or after the update, still sends it back.
# The update is simulated by a copy of the plugin whose QA_FP_VERSION is one
# higher, with the stored digests rewritten as a different method would have
# computed them; the pass's commit holds them, as a real pass's does.

load helper
load qa-recheck-helper

setup() {
  qa_project 1
  qa_pass P1
  NEWER="$TEST_ROOT/newer/bin/vbw"
}

teardown() { vbw_teardown; }

cache_file() { printf '%s/vbw/qa.json\n' "$(git rev-parse --path-format=absolute --git-common-dir)"; }

# version: the fingerprint version of this VBW (exactly one QA_FP_VERSION=N line).
version() {
  local lines
  lines=$(grep -cE '^QA_FP_VERSION=[0-9]+$' "$PLUGIN_ROOT/lib/qa-inputs.sh" || true)
  [ "$lines" -eq 1 ] || { echo "lib/qa-inputs.sh has $lines QA_FP_VERSION=N lines, not 1" >&2; return 1; }
  sed -n 's/^QA_FP_VERSION=\([0-9][0-9]*\)$/\1/p' "$PLUGIN_ROOT/lib/qa-inputs.sh"
}

# update: a copy of this VBW whose fingerprint version is one higher ($NEWER).
update() {
  local v
  v=$(version) || return 1
  cp -R "$PLUGIN_ROOT" "$TEST_ROOT/newer"
  sed "s/^QA_FP_VERSION=$v\$/QA_FP_VERSION=$((v + 1))/" "$PLUGIN_ROOT/lib/qa-inputs.sh" > "$TEST_ROOT/newer/lib/qa-inputs.sh"
}

# other_method [legacy]: the stored fingerprints as another method computes
# them: every digest in P1's qa.tree and in the cache becomes a different one.
# With "legacy", the cache entry has only what VBW before versions wrote
# ({files, tests, plan, reqs, deps}). The pass's own commit is amended to hold
# the rewritten record, as if that method had written it.
other_method() {
  local f
  f=$(cache_file)
  # shellcheck disable=SC2016 # jq program
  local flip='walk(if type == "string" and test("^[0-9a-f]{64}$") then (explode | reverse | implode) else . end)'
  git log -1 --format=%s | grep -qx 'chore(vbw): qa P1 pass' || { echo "HEAD is not the pass's commit" >&2; return 1; }
  edit_record "(.phases[] | select(.id == \"P1\") | .qa.tree) |= $flip"
  jq -c "$flip" "$f" > "$TEST_ROOT/qa.json" && cp "$TEST_ROOT/qa.json" "$f"
  if [ "${1:-}" = legacy ]; then
    jq -c '.P1 |= {files, tests, plan, reqs, deps: {}}' "$f" > "$TEST_ROOT/qa.json" && cp "$TEST_ROOT/qa.json" "$f"
  fi
  git add .vbw/record.json && git commit -q --amend --no-edit
}

# qa_of VBW: vbw next's QA judgment ({recheck, standing}) by the given kernel.
qa_of() { "$1" next --json < /dev/null | jq -c '.qa | {recheck, standing}'; }

# standing VBW: P1's pass stands for that kernel: not sent to QA, shown as current.
standing() {
  local out
  out=$("$1" next --json < /dev/null)
  printf '%s' "$out" | jq -e '.qa.recheck == {} and .qa.standing == ["P1"] and .action != "qa"' > /dev/null || { printf '%s\n' "$out" | jq -c '{action, qa}'; return 1; }
  out=$("$1" show qa < /dev/null)
  [[ "$out" == *"Nothing needs checking again"* ]] || { echo "$out"; return 1; }
  out=$("$1" show phase P1 < /dev/null)
  [[ "$out" == *"qa: pass"* && "$out" != *"[on older code]"* ]] || { echo "$out"; return 1; }
}

# rechecked VBW REASON: that kernel sends P1 to QA again, REASON among its reasons.
rechecked() {
  local out
  out=$(qa_of "$1")
  printf '%s' "$out" | jq -e --arg r "$2" '(.recheck.P1 // []) | any(.[]; contains($r))' > /dev/null || { echo "P1 not rechecked for '$2': $out"; return 1; }
}

# change_file VBW / change_test VBW: a committed change to P1's file or its check's file, then a full proof.
change_file() {
  printf 'more\n' >> src/p1.txt
  git add src/p1.txt && git commit -q -m "fix(p1): more"
  "$1" prove --full > /dev/null
}
change_test() {
  printf 'grep -q part1 src/p1.txt\n' > tests/p1.sh
  git add tests/p1.sh && git commit -q -m "test(p1): looser"
}

@test "R132: the fingerprint stored for a passed phase carries the version of how it was computed, in the clone's QA cache" {
  local v
  v=$(version)
  jq -e --argjson v "$v" '.P1.version == $v' "$(cache_file)" || { cat "$(cache_file)"; false; }
  # No new record field: the pass is the same shape, and the record keeps its schema.
  jq -e '(.phases[0].qa | keys - ["result", "tier", "tree", "at", "note", "rounds"]) == [] and .schema == 1' .vbw/record.json
}

@test "R132: after an update that changes the fingerprint's version, an unchanged passed phase still stands" {
  other_method
  update
  standing "$NEWER"
}

@test "R132: at the same version, a different stored fingerprint is a change, as today" {
  other_method
  rechecked "$VBW" "changed"
}

@test "R132: a fingerprint written by an older VBW with no version is an older version, not a change" {
  other_method legacy
  jq -e '.P1 | has("version") | not' "$(cache_file)"
  standing "$VBW"
}

@test "R132: after an update, a real change to the phase's files sends it back to QA" {
  other_method
  update
  standing "$NEWER"
  change_file "$NEWER"
  rechecked "$NEWER" "its files changed"
}

@test "R132: a change to the phase's files made before the update still sends it back to QA after it" {
  other_method
  change_file "$VBW"
  update
  rechecked "$NEWER" "its files changed"
}

@test "R132: after an update, a change to the phase's tests, plan or requirements sends it back to QA" {
  other_method
  update
  change_test
  rechecked "$NEWER" "its tests changed"
  git revert --no-edit HEAD > /dev/null
  standing "$NEWER"
  "$NEWER" apply --patch <<< '{"plans": [{"id": "P1.1", "phase": "P1", "title": "Write part 1", "reqs": ["R1"], "files": ["src/p1.txt"], "after": [], "tasks": ["write part 1", "and say so"]}]}' > /dev/null
  rechecked "$NEWER" "its goal or plan changed"
}

@test "R132: a change to the phase's requirement made before an update of a version-less fingerprint sends it back to QA" {
  other_method legacy
  local spec
  spec=$(cat .vbw/spec.md)
  printf '%s\n' "${spec/Part 1 works/Part 1 works for everyone}" > .vbw/spec.md
  "$VBW" spec sync > /dev/null
  rechecked "$VBW" "requirement changed"
}
