#!/usr/bin/env bash
# Real-user scenarios before a release (AGENTS.md: evidence level L3). Each
# scenario sets up a project, drives the real Claude Code TUI through
# tools/l3.sh as a user would (typing, answering questions, approving), and
# then checks the outcome in the plan of record and in git, never on screen
# text. Costs model usage: about $1-3 per scenario.
#
#   tools/l3-suite.sh [SCENARIO...]     (default: all)
#
# Scenarios: greenfield, reject, resume, change, convert, balanced, docs, qafix. A user answers every
# question with VBW's recommendation unless the scenario says otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
l3() { bash "$ROOT/tools/l3.sh" "$@"; }
VBW="$ROOT/plugin/bin/vbw"
ALL="greenfield reject resume change convert balanced docs qafix"
RESULTS="$ROOT/tools/l3-results"
STEPS=60

say() { printf '[%s] %s\n' "$scenario" "$*"; }

# A fresh git repository for one scenario, in the system temp directory.
new_project() {
  dir=$(mktemp -d "${TMPDIR:-/tmp}/vbw-l3-$scenario.XXXXXX")
  git -C "$dir" init -q
  git -C "$dir" config user.email l3@vbw.local
  git -C "$dir" config user.name "VBW L3"
  printf '# %s\n' "$scenario" > "$dir/README.md"
  git -C "$dir" add -A && git -C "$dir" commit -qm "chore: seed"
}

next_action() { (cd "$dir" && "$VBW" next --json 2> /dev/null | jq -r '.action // "none"') || echo none; }
screen() { l3 screen "$scenario"; }
default_idle() { l3 wait "$scenario" 1500 > /dev/null 2>&1 || true; }

# Answer the question on screen with the first (recommended) option. A
# multi-select question needs the option ticked, then Submit.
answer_recommended() {
  if screen | grep -q 'Ready to submit'; then
    l3 keys "$scenario" Enter
  elif screen | grep -q '\[ \]'; then
    l3 keys "$scenario" Enter; sleep 1; l3 keys "$scenario" Right; sleep 2; l3 keys "$scenario" Enter
  else
    l3 keys "$scenario" Enter
  fi
}

# answer_other TEXT: pick "Type something." and type TEXT.
answer_other() {
  local n
  n=$(screen | grep -E '^\s*(❯ )?[0-9]+\. Type something' | grep -oE '[0-9]+' | head -1)
  [ -n "$n" ] || { l3 keys "$scenario" Escape; sleep 1; l3 type "$scenario" "$1"; return; }
  local i
  for ((i = 1; i < n; i++)); do l3 keys "$scenario" Down; done
  l3 keys "$scenario" Enter; sleep 1
  l3 type "$scenario" "$1"
}

# drive: play the user until done() or STEPS turns. A scenario may define
# on_question (return 0 when it answered) and on_idle (return 0 when it acted).
drive() {
  local turn action
  for ((turn = 1; turn <= STEPS; turn++)); do
    idle
    screen > /dev/null 2>&1 || { say "the Claude Code session is gone"; return 1; }
    done_yet && return 0
    if screen | grep -q 'Enter to select\|Ready to submit'; then
      on_question || answer_recommended
      continue
    fi
    on_idle && continue
    action=$(next_action)
    case "$action" in
      approve) l3 type "$scenario" "/vbw:approve" ;;
      *) l3 type "$scenario" "/vbw:vibe" ;;
    esac
  done
  say "gave up after $STEPS turns (next: $(next_action))"
  return 1
}

# Defaults; scenarios override what they need.
on_question() { return 1; }
on_idle() { return 1; }
shipped() { jq -e '.milestone.status == "shipped"' "$dir/.vbw/record.json" > /dev/null 2>&1; }
done_yet() { shipped; }

# check DESCRIPTION JQ: assert on the record.
check() {
  if jq -e "$2" "$dir/.vbw/record.json" > /dev/null 2>&1; then say "ok   $1"; else say "FAIL $1"; failed=1; fi
}
check_sh() {
  if (cd "$dir" && eval "$2") > /dev/null 2>&1; then say "ok   $1"; else say "FAIL $1"; failed=1; fi
}

common_checks() {
  check "milestone shipped" '.milestone.status == "shipped"'
  check "every requirement proven or accepted" 'all(.requirements[]; .status == "proven" or .status == "accepted")'
  check "no open fixes, no lease" '(all(.fixes[]; .status == "closed")) and .lease == null'
  # grep -c reads everything: grep -q would close the pipe early, and under
  # pipefail the SIGPIPE in git log fails the check.
  check_sh "plan work committed with provenance" '[ "$(git log --format=%B | grep -c "^VBW-Plan: ")" -gt 0 ]'
  check_sh "no stray changes outside .vbw/runtime" '[ -z "$(git status --porcelain -- . ":(exclude).vbw/runtime")" ]'
}

# --- Results (docs/proof.md, D2): a scenario that proves a requirement writes
# tools/l3-results/NAME.json from the record, git and the session logs, never
# from screen text. tests/l3-results.bats holds the committed file to its facts.

claude_dir() { printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }

# Session transcripts of the project in $dir, the main one and its subagents'.
transcripts() {
  local real enc
  real=$(cd "$dir" && pwd -P)
  enc=$(printf '%s' "$real" | sed 's/[^A-Za-z0-9]/-/g')
  find "$(claude_dir)/projects/$enc" -name '*.jsonl' 2> /dev/null
}

# Stop hooks that reported an error in the transcript: hook errors on a
# stop_hook_summary entry, or a hook that did not complete.
stop_hook_errors_transcript() {
  local f n=0 c
  while IFS= read -r f; do
    c=$(jq -s '[.[] | select(.type == "system" and .subtype == "stop_hook_summary")
      | select((.hookErrors | length) > 0)] | length' "$f" 2> /dev/null || echo 0)
    n=$((n + c))
  done < <(transcripts)
  echo "$n"
}

# Stop-hook error lines in the session's debug log (--debug-file).
stop_hook_errors_debug_log() {
  local log
  log=$(l3 debuglog "$dir")
  [ -f "$log" ] || { echo "-1"; return; }
  grep -ciE 'stop.{0,40}hook.{0,80}(error|fail)|hook.{0,40}stop.{0,80}(error|fail)' "$log" || true
}

# Session cost in USD, from the TUI's /cost.
# Read once, before the session ends (see the main loop); checks reuse it.
session_cost() { printf '%s' "${cost_usd:-}"; }
read_session_cost() {
  local out
  l3 type "$scenario" "/cost"; sleep 3
  out=$(screen)
  l3 keys "$scenario" Escape
  printf '%s' "$out" | grep -oE '\$[0-9]+\.[0-9]+' | head -1 | tr -d '$'
}

# Agent types of the subagents the building workflow ran (their .meta.json),
# one per line, sorted and unique.
build_agent_types() {
  local f
  while IFS= read -r f; do
    jq -r 'select(.workflowPhase == "Build") | .agentType' "${f%.jsonl}.meta.json" 2> /dev/null
  done < <(transcripts | grep '/subagents/') | sort -u
}

# result_write NAME FIXTURE COST PASSED FACTS_JSON NOT_TESTED_JSON
result_write() {
  mkdir -p "$RESULTS"
  jq -n --arg n "$1" --arg fx "$2" --arg cost "${3:-0}" --argjson passed "$4" \
    --argjson facts "$5" --argjson nt "$6" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{scenario: $n, fixture: $fx, cost_usd: ($cost | tonumber), evidence_level: "L3",
      at: $at, passed: $passed, facts: $facts, not_tested: $nt}' > "$RESULTS/$1.json"
  say "result written: tools/l3-results/$1.json"
}

GREET='/vbw:vibe a command-line script greet.sh: "./greet.sh Ana" prints "Hello, Ana!" and without a name prints "Hello, world!". One small milestone.'

scenario_greenfield() {
  new_project
  start=$GREET
  checks() { common_checks; }
}

scenario_reject() {
  new_project
  start="$GREET Also, the wording should feel warm and friendly; I will judge that myself."
  rejected=0
  on_question() {
    [ "$(next_action)" = accept ] && [ "$rejected" -eq 0 ] || return 1
    screen | grep -q "Something's wrong" || return 1
    rejected=1
    local n
    n=$(screen | grep -E "[0-9]+\. Something's wrong" | grep -oE '[0-9]+' | head -1)
    local i
    for ((i = 1; i < n; i++)); do l3 keys "$scenario" Down; done
    l3 keys "$scenario" Enter; sleep 2
    idle
    answer_other "Too plain. Add a friendly touch, like a wave emoji after the greeting."
    return 0
  }
  checks() {
    common_checks
    check "the rejection opened a fix that was worked and closed" 'any(.fixes[]; .status == "closed" and (.note | test("friendly|emoji|plain"; "i")))'
  }
}

scenario_resume() {
  new_project
  start=$GREET
  killed=0
  # Wait like the others, but come back as soon as a run is open, so the
  # session can be closed while its workflow is still working.
  idle() {
    local waited=0
    while [ "$waited" -lt 1500 ]; do
      [ "$killed" -eq 0 ] && [ "$(next_action)" = run ] && return 0
      # l3 wait needs 15 s of a steady screen, so a 30 s limit can succeed.
      l3 wait "$scenario" 30 > /dev/null 2>&1 && return 0
      waited=$((waited + 30))
    done
  }
  done_yet() {
    if [ "$killed" -eq 0 ] && [ "$(next_action)" = run ]; then
      killed=1
      say "closing Claude Code mid-run, then starting it again"
      l3 stop "$scenario"
      l3 start "$scenario" "$dir" > /dev/null
      if screen | grep -q "Type \/reload-skills"; then l3 type "$scenario" "/reload-skills"; sleep 5; fi
      l3 type "$scenario" "/vbw:vibe"
    fi
    shipped
  }
  checks() {
    common_checks
    check_sh "the session was really closed mid-run" "[ $killed -eq 1 ]"
  }
}

scenario_change() {
  new_project
  start=$GREET
  changed=0
  on_question() {
    [ "$changed" -eq 0 ] && [ "$(next_action)" = ship ] || return 1
    changed=1
    answer_other "Not yet: also add a --shout flag that prints the greeting in capitals."
    return 0
  }
  checks() {
    common_checks
    check "a requirement was added before shipping" '(.requirements | length) >= 2 and any(.requirements[]; .text | test("shout|capital|upper"; "i"))'
  }
}

scenario_convert() {
  new_project
  mkdir -p "$dir/.vbw-planning/phases/01-greeting"
  printf '# Greeter\n\nA tiny command-line greeter.\n' > "$dir/.vbw-planning/PROJECT.md"
  printf '# Requirements\n\n### REQ-01: ./greet.sh NAME prints "Hello, NAME!"\n**Must-have**\n\n### REQ-02: A --version flag\n**Nice-to-have**\n' > "$dir/.vbw-planning/REQUIREMENTS.md"
  printf '# State\n\n## Key Decisions\n| Decision | Date | Rationale |\n|---|---|---|\n| Plain POSIX shell | 2026-01-01 | runs everywhere |\n' > "$dir/.vbw-planning/STATE.md"
  printf 'plan\n' > "$dir/.vbw-planning/phases/01-greeting/01-01-PLAN.md"
  git -C "$dir" add -A && git -C "$dir" commit -qm "chore: VBW 1 plan"
  base=$(git -C "$dir" rev-parse HEAD)
  start="/vbw:vibe"
  done_yet() { jq -e 'has("converted") and (.requirements | length) > 0 and (.plans | length) > 0' "$dir/.vbw/record.json" > /dev/null 2>&1; }
  checks() {
    check "converted, with requirements and a plan" 'has("converted") and (.requirements | length) > 0 and (.plans | length) > 0'
    check "the VBW 1 decision was carried over" 'any(.decisions[]; .text | test("POSIX|shell"; "i"))'
    # Tracked VBW 1 files only: on a machine that still shows VBW 1's status line,
    # that status line itself adds untracked cost files to .vbw-planning/.
    check_sh "the VBW 1 folder is unchanged" "git diff --quiet $base -- .vbw-planning"
  }
}

# Balanced autonomy with QA in the background (R8): the session runs on its
# own (auto armed by /vbw:vibe), QA runs as a background workflow, and the
# session stops at accept without a Stop-hook error.
scenario_balanced() {
  new_project
  fixture="greet.sh, one auto requirement and one human requirement"
  start="$GREET Also, the wording should feel warm and friendly; I will judge that myself."
  done_yet() { [ "$(next_action)" = accept ]; }
  checks() {
    check "QA recorded on the built phase" 'any(.phases[]; .qa.result == "pass")'
    check "stopped at accept, not shipped" '.milestone.status != "shipped"'
    check "no human requirement accepted for the user" 'all(.requirements[]; .status != "accepted")'
    local te dl cost passed=true autonomy qa_bg=false stopped=none
    te=$(stop_hook_errors_transcript); dl=$(stop_hook_errors_debug_log)
    autonomy=$(cd "$dir" && "$VBW" config autonomy 2> /dev/null)
    # QA ran as a Workflow call of vbw:verifying in the session transcript.
    if transcripts | xargs cat 2> /dev/null | jq -e 'select(.type == "assistant") | .message.content[]?
      | select(.type == "tool_use" and .name == "Workflow" and ((.input | tostring) | test("verifying")))' > /dev/null 2>&1; then qa_bg=true; fi
    [ "$(next_action)" = accept ] && stopped=accept
    [ "$failed" -eq 0 ] && [ "$te" -eq 0 ] && [ "$dl" -eq 0 ] && [ "$stopped" = accept ] && [ "$qa_bg" = true ] || passed=false
    cost=$(session_cost)
    result_write balanced "$fixture" "${cost:-0}" "$passed" \
      "$(jq -n --arg a "$autonomy" --argjson q "$qa_bg" --argjson t "$te" --argjson d "$dl" --arg s "$stopped" \
        '{autonomy: $a, qa_background: $q, stop_hook_errors_transcript: $t, stop_hook_errors_debug_log: $d, stopped_at: $s}')" \
      '["acceptance itself (the run stops at accept)","hands-off and guided autonomy","a project larger than the greet.sh fixture"]'
  }
}

# A documentation requirement (R4): the Lead marks its plan as documentation,
# the Docs agent builds it, and the approved check proves it.
scenario_docs() {
  new_project
  fixture="greet.sh already in the repo; one auto requirement: docs/USAGE.md documents it"
  printf '#!/bin/sh\necho "Hello, ${1:-world}!"\n' > "$dir/greet.sh"
  chmod +x "$dir/greet.sh"
  git -C "$dir" add -A && git -C "$dir" commit -qm "feat: greet.sh"
  start="/vbw:vibe Documentation only, no code changes: write docs/USAGE.md for the existing greet.sh, with how to run it with a name and without one, and one example of each. One small milestone."
  checks() {
    common_checks
    local plan req agents passed=true by=none appr=false cst=none prov=false rst=none
    plan=$(jq -r 'first(.plans[] | select(.role == "docs")) | .id // empty' "$dir/.vbw/record.json" 2> /dev/null)
    req=$(jq -r --arg p "$plan" 'first(.plans[] | select(.id == $p)) | .reqs[0] // empty' "$dir/.vbw/record.json" 2> /dev/null)
    agents=$(build_agent_types | tr '\n' ' ')
    [ "$agents" = "vbw:docs " ] && by=docs
    # Only approved checks ever run: a passing result in the evidence means approved.
    cst=$(jq -r --arg r "$req" '. as $x | first($x.checks[] | select(.req == $r)) | .id as $c | $x.evidence.checks[$c].status // "none"' "$dir/.vbw/record.json" 2> /dev/null)
    [ "$cst" = pass ] && appr=true
    rst=$(jq -r --arg r "$req" 'first(.requirements[] | select(.id == $r)) | .status // "none"' "$dir/.vbw/record.json" 2> /dev/null)
    [ -n "$plan" ] && [ "$(cd "$dir" && git log --format=%B | grep -c "^VBW-Plan: $plan\$")" -gt 0 ] && prov=true
    [ -f "$dir/docs/USAGE.md" ] || failed=1
    [ "$failed" -eq 0 ] && [ "$by" = docs ] && [ "$appr" = true ] && [ "$cst" = pass ] && [ "$prov" = true ] && [ "$rst" = proven ] || passed=false
    result_write docs "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg b "$by" --argjson a "$appr" --arg c "$cst" --argjson p "$prov" --arg r "$rst" --arg pl "$plan" --arg ag "$agents" \
        '{built_by_agent_type: $b, check_approved: $a, check_status: $c, commit_has_provenance: $p, requirement_status: $r, docs_plan: $pl, build_agents: $ag}')" \
      '["acceptance by a person of the documentation quality","a documentation plan mixed with code plans in one wave","a project larger than the greet.sh fixture"]'
  }
}

# Every committed version of the record, oldest first, one JSON document per
# line: the history QA verdicts and fix rounds are read from (the record keeps
# only the latest verdict).
record_history() {
  local h
  while IFS= read -r h; do
    git -C "$dir" show "$h:.vbw/record.json" 2> /dev/null | jq -c .
  done < <(git -C "$dir" log --reverse --format=%H -- .vbw/record.json)
}

# QA fails a build that deviates from its plan (R5): checks cannot see the
# deviation, QA must, and the fix loop must close it. The scenario plays the
# deviation: once the build is proven it deletes a file its plan lists that no
# check names (a commit by the "user"), the way a build that skipped a task
# would look.
scenario_qafix() {
  new_project
  fixture="greet.sh plus NOTES.md (no check names it); the built NOTES.md is deleted after the build, so only QA can see the deviation"
  deviation=""
  # Guided autonomy: the session asks before each step, which is where a user
  # (and this scenario) can act between the build and QA.
  start="Use guided autonomy for this project. $GREET Also add NOTES.md with one sentence on what greet.sh is for. Nothing automated needs to test NOTES.md: a person reads it."
  seed_deviation() {
    [ -z "$deviation" ] || return 1
    case "$(next_action)" in prove | qa) ;; *) return 1 ;; esac
    local f
    f=$(jq -r '. as $r | [$r.plans[] | .files[]] | unique[]
      | select(. as $f | ([$r.checks[] | (.run + .files)[]] | any(contains($f))) | not)' "$dir/.vbw/record.json" 2> /dev/null \
      | while IFS= read -r f; do [ -f "$dir/$f" ] && { echo "$f"; break; }; done)
    [ -n "$f" ] || return 1
    git -C "$dir" rm -q -- "$f" && git -C "$dir" commit -qm "chore: drop $f" -- "$f" || return 1
    deviation="$f"
    # The user's commit changed the code: prove it again, so the evidence (and
    # the tree QA is given) is the deviating build.
    (cd "$dir" && "$VBW" prove > /dev/null 2>&1) || true
    say "seeded the deviation: $f deleted after the build"
    return 0
  }
  # Seed, then answer the question as a user would (the recommended option).
  on_question() { seed_deviation || true; return 1; }
  on_idle() { seed_deviation; }
  done_yet() { [ -n "$deviation" ] && shipped; }
  # Human requirements (NOTES.md wording) are accepted as a user would.
  checks() {
    common_checks
    local hist first note rounds=0 final=none proved=false passed=true fv=none
    hist=$(record_history)
    first=$(printf '%s\n' "$hist" | jq -sr '[.[] | .phases[]? | select(.qa != null) | .qa] | first // {} | .result // "none"')
    fv=$first
    note=$(printf '%s\n' "$hist" | jq -sr '[.[] | select(any(.phases[]?; .qa.result == "fail"))] | first // {}
      | ([.phases[]? | .qa.note // empty] + [.fixes[]? | select(.source == "qa") | .note]) | join(" ")')
    # A fix round is one fix run (the kernel commits the record after each run).
    rounds=$(git -C "$dir" log --format=%s | grep -c '^chore(vbw): record after fix-' || true)
    final=$(jq -r '[.phases[] | .qa.result // "none"] | last // "none"' "$dir/.vbw/record.json" 2> /dev/null)
    jq -e 'all(.requirements[]; .status == "proven" or .status == "accepted")' "$dir/.vbw/record.json" > /dev/null 2>&1 && proved=true
    say "QA rounds: first verdict $fv, fix rounds $rounds, final $final"
    [ -n "$deviation" ] || { say "FAIL the deviation was never seeded"; failed=1; }
    case "$note" in *"$deviation"*) ;; *) say "FAIL the first QA note does not name the deviation"; failed=1 ;; esac
    [ "$failed" -eq 0 ] && [ "$fv" = fail ] && [ "$rounds" -ge 1 ] && [ "$final" = pass ] && [ "$proved" = true ] || { passed=false; failed=1; }
    result_write qafix "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg d "${deviation:-}" --arg fv "$fv" --arg n "$note" --argjson r "$rounds" --arg fin "$final" --argjson p "$proved" \
        '{deviation: $d, first_qa_verdict: $fv, first_qa_note: $n, fix_rounds: $r, final_qa_verdict: $fin, phase_proved: $p}')" \
      '["a deviation other than one missing file","a deviation the Dev introduces itself (the seed is played by the scenario)","the fix cap (three failed rounds) and its escalation","a project larger than the greet.sh fixture"]'
  }
}

failed=0
# shellcheck disable=SC2086 # the default list splits on purpose
[ $# -gt 0 ] || set -- $ALL
for scenario in "$@"; do
  case " $ALL " in *" $scenario "*) ;; *) echo "unknown scenario $scenario (one of: $ALL)" >&2; exit 2 ;; esac
  unset -f on_question on_idle done_yet checks idle
  idle() { default_idle; }
  on_question() { return 1; }
  on_idle() { return 1; }
  done_yet() { shipped; }
  "scenario_$scenario"
  say "project: $dir"
  if ! l3 start "$scenario" "$dir" > /dev/null; then say "could not start Claude Code"; failed=1; continue; fi
  # As a user would: VBW 2 asks for a reload when it removed VBW 1 command copies.
  if screen | grep -q "Type \/reload-skills"; then l3 type "$scenario" "/reload-skills"; sleep 5; fi
  l3 type "$scenario" "$start"
  drive || failed=1
  # Dismiss a pending question with Escape (never answer it), let the session
  # settle, read its cost, then stop. Stop first, then read the state: the result records where the session
  # actually ended, and a stop that acted for the user would show.
  l3 keys "$scenario" Escape; sleep 2; default_idle
  cost_usd=$(read_session_cost)
  l3 stop "$scenario"
  checks
done
[ "$failed" -eq 0 ] && echo "L3 suite: all checks passed" || { echo "L3 suite: FAILED"; exit 1; }
