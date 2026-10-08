#!/usr/bin/env bats
# R48 (docs/proof.md): when QA runs, VBW says for each phase why it is checked
# again (failed last time, or which of its inputs changed, or which phase it
# builds on) and lists the phases whose pass still stands. The reasons ride in
# vbw next --json (.qa), in its instruction line, in vbw show qa, and in the qa
# skill, in plain words.

load helper
load qa-recheck-helper

teardown() { vbw_teardown; }

# jargon: words a beginner would not know; none may reach the reasons.
JARGON='fingerprint|hash|sha|digest|checksum|tree|blob|inputs'

@test "R48: a phase that failed last time is named with that reason, and the phase that passed is listed as standing" {
  qa_project 2
  qa_pass P2
  "$VBW" qa finding R1 "part 1 deviates from its plan" > /dev/null
  "$VBW" qa record P1 fail standard "1 deviation" > /dev/null
  "$VBW" fix done F1 > /dev/null
  "$VBW" prove --full > /dev/null
  next_json | jq -e '.qa.recheck.P1 | any(.[]; test("failed last time"))'
  next_json | jq -e '.qa.standing == ["P2"]'
}

@test "R48: a phase that was never checked is named with that reason" {
  qa_project 1
  next_json | jq -e '.qa.recheck.P1 | any(.[]; test("not checked yet"))'
}

@test "R48: each changed input is named: files, tests, goal or plan" {
  qa_project 3
  qa_pass P1 P2 P3
  printf 'extra\n' >> src/p1.txt
  printf '# stricter\n' >> tests/p2.sh
  git add src/p1.txt tests/p2.sh && git commit -q -m "change"
  "$VBW" approve > /dev/null
  edit_record '(.phases[] | select(.id == "P3")).goal = "Part 3 works for everyone"'
  "$VBW" prove --full > /dev/null
  next_json | jq -e '.qa.recheck.P1 | any(.[]; test("files changed"))'
  next_json | jq -e '.qa.recheck.P2 | any(.[]; test("tests changed"))'
  next_json | jq -e '.qa.recheck.P3 | any(.[]; test("goal or plan changed"))'
}

@test "R48: a phase that builds on a re-checked phase names it" {
  qa_project 2 chain
  qa_pass P1 P2
  qa_touch 1
  next_json | jq -e '.qa.recheck.P2 | any(.[]; test("builds on P1"))'
}

@test "R48: a phase with several reasons shows all of them" {
  qa_project 2 chain
  qa_pass P1 P2
  printf 'extra\n' >> src/p2.txt
  printf 'extra\n' >> src/p1.txt
  printf '# stricter\n' >> tests/p2.sh
  git add -A && git commit -q -m "change"
  "$VBW" approve > /dev/null
  "$VBW" prove --full > /dev/null
  next_json | jq -e '.qa.recheck.P2 | length >= 3
    and any(.[]; test("files changed")) and any(.[]; test("tests changed")) and any(.[]; test("builds on P1"))'
}

@test "R48: the reasons list is exactly the list of phases sent to QA, and the instruction states each reason" {
  qa_project 3 chain
  qa_pass P1 P2 P3
  qa_touch 2
  local json out
  json=$(next_json)
  printf '%s' "$json" | jq -e '(.qa.recheck | keys) == (.detail.phases | sort) and .action == "qa"'
  printf '%s' "$json" | jq -e '.instruction as $i | all(.qa.recheck | to_entries[]; .key as $k | ($i | contains($k)) and (.value | all(.[]; . as $r | $i | contains($r))))'
  printf '%s' "$json" | jq -e '.instruction | contains("P1")'
  [ "$(printf '%s' "$json" | jq -c '.qa.standing')" = '["P1"]' ]
  out=$(node "$REPO_ROOT/tests/helpers/run-workflow.js" "$PLUGIN_ROOT/workflows/verifying.js" \
    "$(printf '%s' "$json" | jq -c '{phases: .detail.phases, tier: .detail.tier}')" '{}')
  [ "$(printf '%s' "$out" | jq -c '[.calls[].opts.label | ltrimstr("qa ")] | sort')" = "$(printf '%s' "$json" | jq -c '.qa.recheck | keys')" ]
}

@test "R48: when nothing needs checking again, the output says so and lists every phase as standing" {
  qa_project 2
  qa_pass P1 P2
  next_json | jq -e '.qa.recheck == {} and .qa.standing == ["P1","P2"]'
  vbw_run show qa
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing needs checking again"* ]]
  [[ "$output" == *"P1"* && "$output" == *"P2"* ]]
}

@test "R48: vbw show qa reports each reason in text and each phase whose pass stands" {
  qa_project 2
  qa_pass P1 P2
  qa_touch 1
  vbw_run show qa
  [ "$status" -eq 0 ]
  [[ "$output" == *"P1 is checked again: its files changed"* ]]
  [[ "$output" == *"P2 keeps its pass"* ]]
}

@test "R48: the answer the status line reads carries the reasons" {
  qa_project 2
  qa_pass P1 P2
  qa_touch 2
  next_json > /dev/null
  jq -e '.qa.recheck.P2 | length > 0' .vbw/runtime/next.json
  jq -e '.qa.standing == ["P1"]' .vbw/runtime/next.json
}

@test "R48: for a user at 'never' and 'plain with terms explained', the reasons carry no unexplained jargon" {
  qa_project 3 chain
  "$VBW" interview set level "never" > /dev/null
  "$VBW" interview set depth "plain with technical terms explained" > /dev/null
  "$VBW" interview set involvement "options with a recommendation" > /dev/null
  qa_pass P1 P2
  qa_touch 1
  local text
  text=$(next_json | jq -r '.instruction, (.qa.recheck[][])')
  text="$text $("$VBW" show qa)"
  echo "$text"
  if printf '%s' "$text" | grep -qiwE "($JARGON)"; then false; fi
}

@test "R48: the qa skill reads the reasons, tells the user at their level which phases are checked again and why, and which keep their pass" {
  local f="$PLUGIN_ROOT/skills/qa/SKILL.md"
  grep -q 'vbw show qa' "$f"
  grep -qi 'checked again' "$f"
  grep -qiE 'keeps? its pass|pass still stands|keep their pass' "$f"
  grep -qi 'level' "$f"
  grep -qi 'explanation depth' "$f"
  grep -qi 'involvement' "$f"
  if grep -qiwE "($JARGON)" "$f"; then false; fi
}

@test "R48: the docs describe the re-check rule and where the reasons appear" {
  grep -qi 'checked again' "$REPO_ROOT/docs/proof.md"
  grep -qiE 'standing|keeps its pass' "$REPO_ROOT/docs/proof.md"
  grep -q 'recheck' "$REPO_ROOT/docs/next.md"
  grep -q 'vbw show qa' "$REPO_ROOT/docs/proof.md"
}

@test "R48: on a clone without the cache of what each pass covered, a re-checked phase still gets a plain reason" {
  qa_project 2
  qa_pass P1 P2
  rm -f "$(git rev-parse --git-common-dir)/vbw/qa.json"
  qa_touch 1
  next_json | jq -e '.qa.recheck.P1 == ["its files, tests or plan changed"] and .qa.standing == ["P2"]'
}
