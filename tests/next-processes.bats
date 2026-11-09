#!/usr/bin/env bats
# R282 (measured at 2.1.28 on the big-milestone fixture: 1279 processes, 599 jq, 478
# sha256sum and 158 awk for one vbw next): vbw next starts a number of processes that
# does not grow with the milestone's plans. QA's per-plan and per-phase fingerprints
# (plugin/lib/qa-inputs.sh) are built in one jq pass and one batch hash call, as the
# proof's reuse already hashes in one call. A fixture with twice the plans (the
# big-milestone fixture of tests/big-milestone-helper.bash, its 79 phases copied once more
# as P80 to P158) starts exactly as many jq, git, awk, sha256sum and shasum processes.
# The fingerprints stay stable for unchanged inputs, and a change to one plan's file moves
# only that phase's and those of the phases that build on it. L1.

load helper
load big-milestone-helper
load fixture-helper

# The fixture's document, doubled when BIG_DOUBLE is 1: every phase, plan, check and rule
# again, numbered 79 higher (P1.2 -> P80.2, R1 -> R80, C1 -> C80, src/p1-2.txt -> src/p80-2.txt).
source <(declare -f big_milestone_doc | sed '1s/^big_milestone_doc /big_doc_single /')
big_milestone_doc() {
  if [ "${BIG_DOUBLE:-0}" = 1 ]; then
    BIG_PHASES=79 big_doc_single | jq -c 'def shift: if type == "string" then gsub("(?<a>[PRCpc])(?<n>[0-9]+)"; "\(.a)\(.n | tonumber + 79)") else . end;
      . as $d | with_entries(.value += ($d[.key] | map(walk(shift)))) | .rules = ($d.rules + ($d.rules | map(walk(shift))))'
  else
    big_doc_single
  fi
}
big_double_fixture() {
  vbw_setup
  BIG_DOUBLE=1 BIG_PHASES=158 BIG_PLANS=516 BIG_LINKS=1136 big_milestone_project
}

setup_file() {
  fixture_build big big_milestone_fixture
  fixture_build big2 big_double_fixture
}
setup() {
  mkdir -p "$BATS_TEST_TMPDIR/shim"
  SHIM="$BATS_TEST_TMPDIR/shim"
  local p real
  for p in jq git awk sha256sum shasum; do
    real=$(command -v "$p") || continue
    printf '#!/bin/sh\necho %s >> "$PROC_LOG"\nexec "%s" "$@"\n' "$p" "$real" > "$SHIM/$p"
    chmod +x "$SHIM/$p"
  done
}
teardown() { vbw_teardown; }
teardown_file() { fixture_teardown; }

# starts FIXTURE: the jq, git, awk, sha256sum and shasum processes one vbw next --json starts on a copy of FIXTURE, as "name count" lines.
starts() {
  fixture_copy "$1"
  "$VBW" next --json < /dev/null > /dev/null
  export PROC_LOG="$TEST_ROOT/proc.log"
  : > "$PROC_LOG"
  PATH="$SHIM:$PATH" "$VBW" next --json < /dev/null > /dev/null
  sort "$PROC_LOG" | uniq -c | awk '{print $2, $1}'
}

@test "R282 processes: vbw next on a milestone with twice the plans starts exactly as many processes, jq, git, awk and hashing included" {
  local one two
  jq -e '(.plans | length) == 258' "$(fixture_root big)/project with space/.vbw/record.json" > /dev/null
  jq -e '(.plans | length) == 516' "$(fixture_root big2)/project with space/.vbw/record.json" > /dev/null
  one=$(starts big)
  two=$(starts big2)
  [ -n "$one" ] || { echo "no process was counted"; false; }
  [ "$one" = "$two" ] || { echo "258 plans:"; echo "$one"; echo "516 plans:"; echo "$two"; false; }
}

@test "R282 fingerprints: QA's fingerprints are stable for unchanged inputs, and a change to one plan's file moves only its phase's, and a change to its check file also those of the phases that build on it" {
  fixture_copy big
  local a b c changed
  a=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"' | jq -cS .)
  b=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"' | jq -cS .)
  [ "$a" = "$b" ] || { echo "two runs on unchanged inputs differ"; false; }
  # The values themselves are those the R268 identity recorded, while QA_FP_VERSION stays 2: a change of values raises it.
  if grep -qx 'QA_FP_VERSION=2' "$PLUGIN_ROOT/lib/qa-inputs.sh"; then
    [ "$a" = "$(jq -cS . "$BATS_TEST_DIRNAME/big-milestone-expected/digests.json")" ] || { echo "the fingerprints changed while QA_FP_VERSION stayed 2"; false; }
  fi
  printf 'part78 changed\n' > src/p78-1.txt
  git add src/p78-1.txt && git commit -q -m "chore(test): change P78.1's file"
  c=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"' | jq -cS .)
  changed=$(jq -nc --argjson a "$a" --argjson c "$c" '[$a | keys[] | select($a[.].combined != $c[.].combined)] | sort')
  # A phase relies on what the phases it builds on promise (their checks), not on their code: only P78 moves.
  [ "$changed" = '["P78"]' ] || { echo "changed: $changed"; false; }
  [ "$(jq -nc --argjson a "$a" --argjson c "$c" '$a.P78.files != $c.P78.files')" = true ]
  [ "$(jq -nc --argjson a "$a" --argjson c "$c" '$a.P1.files == $c.P1.files and $a.P1.combined == $c.P1.combined')" = true ]
  # Its check file: P78 and every phase that builds on it.
  printf 'grep -qx "part78 changed" src/p78-1.txt\n' > tests/c78.sh
  git add tests/c78.sh && git commit -q -m "chore(test): change C78"
  b=$(vbw_kernel '. "$VBW_LIB/qa-inputs.sh"; qa_digests "$(cat "$VBW_RECORD")"' | jq -cS .)
  changed=$(jq -nc --argjson c "$c" --argjson b "$b" '[$c | keys[] | select($c[.].combined != $b[.].combined)] | sort')
  [ "$changed" = "$(jq -nc --argjson c "$c" '["P78"] + [$c | keys[] | select(. != "P78" and (($c[.].deps // []) | index("P78")))] | sort')" ] && [ "$changed" != '["P78"]' ] || { echo "changed: $changed"; false; }
  grep -qE '^QA_FP_VERSION=[0-9]+$' "$PLUGIN_ROOT/lib/qa-inputs.sh"
}
