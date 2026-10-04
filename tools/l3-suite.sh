#!/usr/bin/env bash
# Real-user scenarios before a release (AGENTS.md: evidence level L3). Each
# scenario sets up a project, drives the real Claude Code TUI through
# tools/l3.sh as a user would (typing, answering questions, approving), and
# then checks the outcome in the plan of record and in git, never on screen
# text. Costs model usage: about $1-3 per scenario.
#
#   tools/l3-suite.sh [SCENARIO...]     (default: all)
#
# Scenarios are independent (own project, own Claude Code session), so they run
# L3_JOBS at a time (default 4); each one's lines print together when it ends.
#
# Scenarios: greenfield, reject, resume, change, convert, balanced, docs, qafix,
# decision, debug, research, edgecase, leftover, newcomer, senior. A user answers
# every question with VBW's recommendation unless the scenario says otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
l3() { bash "$ROOT/tools/l3.sh" "$@"; }
VBW="$ROOT/plugin/bin/vbw"
ALL="greenfield reject resume change convert balanced docs qafix decision debug research edgecase leftover newcomer senior"
RESULTS="$ROOT/tools/l3-results"
STEPS=60

say() { printf '[%s] %s\n' "$scenario" "$*"; }

# A fresh git repository for one scenario, in the system temp directory.
new_project() {
  dir=$(mktemp -d "${TMPDIR:-/tmp}/vbw-l3-$scenario.XXXXXX")
  git -C "$dir" init -q
  git -C "$dir" config user.email l3@vbw.local
  git -C "$dir" config user.name "VBW L3"
  # A neutral title: the scenario's name ("reject", "leftover") read by a
  # planner as project content once led to an unrequested task.
  printf '# Demo project\n' > "$dir/README.md"
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
# expect DESCRIPTION COMMAND...: assert that COMMAND succeeds (run as argv, in $dir).
expect() {
  local d="$1"; shift
  if (cd "$dir" && "$@") > /dev/null 2>&1; then say "ok   $d"; else say "FAIL $d"; failed=1; fi
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
  # session can be closed while its workflow is still working. VBW's state is
  # read every 3 s: an express build is short, and a 30 s screen wait missed it.
  idle() {
    local waited=0 last="" now steady=0
    while [ "$waited" -lt 1500 ]; do
      [ "$killed" -eq 0 ] && [ "$(next_action)" = run ] && return 0
      now=$(screen)
      if [ "$now" = "$last" ] && ! printf '%s' "$now" | grep -q 'esc to interrupt'; then
        steady=$((steady + 3))
      else
        steady=0
      fi
      last=$now
      [ "$steady" -ge 15 ] && return 0
      sleep 3
      waited=$((waited + 3))
    done
  }
  # Back in a new session, VBW asks whether the closed session is still open:
  # the user closed it, and says so.
  on_question() {
    [ "$killed" -eq 1 ] && screen | grep -q 'That session is closed' || return 1
    local n i
    n=$(screen | grep -E '[0-9]+\. That session is closed' | grep -oE '[0-9]+' | head -1)
    for ((i = 1; i < n; i++)); do l3 keys "$scenario" Down; done
    l3 keys "$scenario" Enter
    return 0
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
    expect "no Stop-hook errors in the transcript ($te) or the debug log ($dl)" [ "$te" -eq 0 -a "$dl" -eq 0 ]
    expect "QA ran in the background (a vbw:verifying workflow)" [ "$qa_bg" = true ]
    expect "VBW's next step is accept ($stopped)" [ "$stopped" = accept ]
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
    # Each condition prints its own line, so a failed one is never silent.
    expect "docs/USAGE.md was written" [ -f "$dir/docs/USAGE.md" ]
    expect "the Docs agent built it (agents: $agents)" [ "$by" = docs ]
    expect "an approved check proves the documentation requirement (check status: $cst)" [ "$cst" = pass ]
    expect "the documentation requirement is proven, not only accepted ($rst)" [ "$rst" = proven ]
    expect "the docs plan's commits carry provenance" [ "$prov" = true ]
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
    expect "QA's first verdict was fail ($fv)" [ "$fv" = fail ]
    expect "at least one fix round ran ($rounds)" [ "$rounds" -ge 1 ]
    expect "QA's final verdict is pass ($final)" [ "$final" = pass ]
    expect "every requirement is proven or accepted" [ "$proved" = true ]
    [ "$failed" -eq 0 ] && [ "$fv" = fail ] && [ "$rounds" -ge 1 ] && [ "$final" = pass ] && [ "$proved" = true ] || { passed=false; failed=1; }
    result_write qafix "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg d "${deviation:-}" --arg fv "$fv" --arg n "$note" --argjson r "$rounds" --arg fin "$final" --argjson p "$proved" \
        '{deviation: $d, first_qa_verdict: $fv, first_qa_note: $n, fix_rounds: $r, final_qa_verdict: $fin, phase_proved: $p}')" \
      '["a deviation other than one missing file","a deviation the Dev introduces itself (the seed is played by the scenario)","the fix cap (three failed rounds) and its escalation","a project larger than the greet.sh fixture"]'
  }
}

# Agent types of every subagent the session ran (their .meta.json), one per line.
agent_types() {
  local f
  while IFS= read -r f; do
    jq -r '.agentType // empty' "${f%.jsonl}.meta.json" 2> /dev/null
  done < <(transcripts | grep '/subagents/')
}

# The session's own transcript (not its subagents').
main_transcript() { transcripts | grep -v '/subagents/' | head -1; }

# The text of the session's last reply to the user.
last_reply() {
  local f
  f=$(main_transcript)
  [ -n "$f" ] || return 0
  jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // ""' "$f" 2> /dev/null
}

# workflow_started NAME: the session started the VBW workflow NAME.
workflow_started() {
  local f
  f=$(main_transcript)
  [ -n "$f" ] && jq -e --arg n "$1" 'select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use" and .name == "Workflow" and ((.input | tostring) | contains($n)))' "$f" > /dev/null 2>&1
}

# A decision recorded by the user justifies a deviation from the plan text:
# QA loads the decisions and does not fail the phase for it. The mirror of
# qafix: the same file is dropped after the build, with a recorded decision.
scenario_decision() {
  new_project
  dropped=""
  start="Use guided autonomy for this project. $GREET Also add NOTES.md with one sentence on what greet.sh is for. Nothing automated needs to test NOTES.md: a person reads it."
  seed_decision() {
    [ -z "$dropped" ] || return 1
    case "$(next_action)" in prove | qa) ;; *) return 1 ;; esac
    [ -f "$dir/NOTES.md" ] || return 1
    git -C "$dir" rm -q -- NOTES.md && git -C "$dir" commit -qm "chore: drop NOTES.md" -- NOTES.md || return 1
    dropped=NOTES.md
    say "dropped NOTES.md after the build; telling the session it is a decision"
    l3 keys "$scenario" Escape; sleep 2
    l3 type "$scenario" "I deleted NOTES.md myself: I don't want it, the README says enough. Please record that as my decision and carry on."
    return 0
  }
  on_question() { seed_decision; }
  on_idle() { seed_decision; }
  done_yet() { [ -n "$dropped" ] && shipped; }
  checks() {
    common_checks
    local after qa_read=false f
    # QA after the user's decision: its first verdict, and fixes it opened since.
    after=$(record_history | jq -sr '. as $h
      | ([$h[] | .decisions[]? | select(.text | test("NOTES"; "i")) | .at] | first) as $d
      | if $d == null then "no decision" else
          ([$h[] | .phases[]? | .qa | select(. != null and .at > $d)] | first // {} | .result // "none") + " "
          + ([$h[] | select(any(.decisions[]?; .at == $d)) | [.fixes[]? | select(.source == "qa")] | length] | (last - first) | tostring)
        end')
    while IFS= read -r f; do
      [ "$(jq -r '.agentType // empty' "${f%.jsonl}.meta.json" 2> /dev/null)" = vbw:qa ] || continue
      jq -se 'any(.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use");
        (.input.command // "") | contains("show decisions"))' "$f" > /dev/null 2>&1 && qa_read=true
    done < <(transcripts | grep '/subagents/')
    [ -n "$dropped" ] || { say "FAIL the deviation was never seeded"; failed=1; }
    check "the user's decision is recorded" 'any(.decisions[]; .text | test("NOTES"; "i"))'
    expect "QA loaded the recorded decisions" [ "$qa_read" = true ]
    expect "after the decision, QA passed the phase first time and opened no fix ($after)" [ "$after" = "pass 0" ]
  }
}

# /vbw:debug on a seeded bug: Debuggers find the root cause, and with the
# user's yes one fixes it with a regression test that fails on the old code.
scenario_debug() {
  new_project
  printf '#!/bin/sh\nname="$1"\necho "Hello, $name!"\n' > "$dir/greet.sh"
  chmod +x "$dir/greet.sh"
  git -C "$dir" add -A && git -C "$dir" commit -qm "feat: greet.sh"
  seed=$(git -C "$dir" rev-parse HEAD)
  start='/vbw:debug ./greet.sh with no name prints "Hello, !" but it should print "Hello, world!" (with a name it works: "./greet.sh Ana" prints "Hello, Ana!")'
  said_yes=0
  # After the diagnosis the session asks whether to fix it now; the user says yes.
  on_idle() {
    [ "$said_yes" -eq 0 ] && workflow_started investigating && last_reply | grep -qi 'fix' || return 0
    said_yes=1
    l3 type "$scenario" "Yes, fix it now, with the regression test."
    return 0
  }
  done_yet() { [ -n "$(git -C "$dir" log --format=%H "$seed..HEAD" -- greet.sh)" ]; }
  checks() {
    local added t old new fails_before=false passes_now=false run
    expect "the root cause (greet.sh) was fixed" [ -n "$(git -C "$dir" log --format=%H "$seed..HEAD" -- greet.sh)" ]
    check_sh "./greet.sh prints Hello, world! now" '[ "$(./greet.sh)" = "Hello, world!" ] && [ "$(./greet.sh Ana)" = "Hello, Ana!" ]'
    added=$(git -C "$dir" diff --name-only --diff-filter=A "$seed" HEAD | grep -v '^\.vbw/' || true)
    expect "a regression test was committed" [ -n "$added" ]
    # Each added file is run as a test on the fixed code and on the seeded greet.sh.
    old=$(mktemp -d "${TMPDIR:-/tmp}/vbw-l3-debug-old.XXXXXX"); new=$(mktemp -d "${TMPDIR:-/tmp}/vbw-l3-debug-new.XXXXXX")
    git -C "$dir" archive HEAD | tar -x -C "$new"; git -C "$dir" archive HEAD | tar -x -C "$old"
    git -C "$dir" show "$seed:greet.sh" > "$old/greet.sh"; chmod +x "$old/greet.sh"
    for t in $added; do
      case "$t" in *.bats) run=(bats "$t") ;; *) run=(sh "$t") ;; esac
      (cd "$new" && "${run[@]}" > /dev/null 2>&1) && passes_now=true
      (cd "$old" && "${run[@]}" > /dev/null 2>&1) || fails_before=true
    done
    rm -rf "$old" "$new"
    expect "the regression test passes on the fix" [ "$passes_now" = true ]
    expect "the regression test fails on the seeded bug" [ "$fails_before" = true ]
    expect "Debuggers did the work" [ "$(agent_types | grep -c '^vbw:debugger$')" -ge 2 ]
  }
}

# /vbw:research on a question with a known answer (git switch arrived in Git
# 2.23): Scouts research it in parallel and the answer names it with a link.
scenario_research() {
  new_project
  start="/vbw:research Which Git release first added the git switch command? Give the version number and a link to its release notes."
  on_idle() { return 0; }
  done_yet() { workflow_started researching && last_reply | grep -q '2\.23'; }
  checks() {
    local reply
    reply=$(last_reply)
    expect "the researching workflow ran" workflow_started researching
    expect "Scouts did the research" [ "$(agent_types | grep -c '^vbw:scout$')" -ge 2 ]
    case "$reply" in *2.23*) say "ok   the answer names Git 2.23" ;; *) say "FAIL the answer names Git 2.23"; failed=1 ;; esac
    case "$reply" in *https://*) say "ok   the answer gives a link" ;; *) say "FAIL the answer gives a link"; failed=1 ;; esac
  }
}

# run_check_in DIR CHECK_ID: run the approved check's argv in DIR (as argv).
run_check_in() {
  local a argv=()
  while IFS= read -r -d '' a; do argv+=("$a"); done \
    < <(jq -j --arg c "$2" 'first(.checks[] | select(.id == $c)) | .run[] + "\u0000"' "$dir/.vbw/record.json")
  [ "${#argv[@]}" -gt 0 ] || return 1
  (cd "$1" && "${argv[@]}") > /dev/null 2>&1
}

# A request that states an edge case (R34): the Lead lists a rule for it, with
# its check, before the user approves; the check passes on the solution and
# fails on a copy that ignores the edge.
scenario_edgecase() {
  new_project
  fixture="greet.sh from scratch; the request states one edge case (several words as separate arguments)"
  edge='./greet.sh Ana Maria (two arguments) prints "Hello, Ana Maria!"'
  start="$GREET Edge case to handle: $edge."
  checks() {
    common_checks
    local rule="" rc="" listed=false appr=false sol=false nof=false passed=true h v tmp pat
    pat='maria|several|multiple|more than one|separate|words|two arg'
    # The record as it was when the user approved: the commit that approves.
    h=$(git -C "$dir" log --reverse --format='%H %s' -- .vbw/record.json | grep -m1 'chore(vbw): approve contract' | cut -d' ' -f1 || true)
    if [ -n "$h" ]; then
      v=$(git -C "$dir" show "$h^:.vbw/record.json" 2> /dev/null || true)
      rule=$(printf '%s' "$v" | jq -r --arg p "$pat" 'first(.requirements[]?.rules[]? | select(.text | test($p; "i"))) | .text // empty' 2> /dev/null || true)
      rc=$(printf '%s' "$v" | jq -r --arg p "$pat" 'first(.requirements[]?.rules[]? | select(.text | test($p; "i"))) | .check // empty' 2> /dev/null || true)
      [ -n "$rule" ] && [ -n "$rc" ] && printf '%s' "$v" | jq -e --arg c "$rc" 'any(.checks[]; .id == $c)' > /dev/null 2>&1 && listed=true
      appr=true
    fi
    if [ -n "$rc" ]; then
      jq -e --arg c "$rc" '.evidence.checks[$c].status == "pass"' "$dir/.vbw/record.json" > /dev/null 2>&1 || appr=false
      tmp=$(mktemp -d "${TMPDIR:-/tmp}/vbw-l3-edge.XXXXXX")
      git -C "$dir" archive HEAD | tar -x -C "$tmp"
      run_check_in "$tmp" "$rc" && sol=true
      # The same project with a greet.sh that ignores the edge case.
      printf '#!/bin/sh\necho "Hello, ${1:-world}!"\n' > "$tmp/greet.sh"
      run_check_in "$tmp" "$rc" || nof=true
      rm -rf "$tmp"
    fi
    expect "a rule for the edge case was listed before approval, with its check" [ "$listed" = true ]
    expect "the contract was approved with that check passing" [ "$appr" = true ]
    expect "the check passes on the solution" [ "$sol" = true ]
    expect "the check fails on a copy that ignores the edge" [ "$nof" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write edgecase "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg e "$edge" --arg r "$rule" --arg c "$rc" --argjson l "$listed" --argjson a "$appr" --argjson s "$sol" --argjson n "$nof" \
        '{edge_case: $e, rule_text: $r, rule_check: $c, rule_listed_before_approval: $l, check_approved: $a, check_passes_on_solution: $s, check_fails_without_edge: $n}')" \
      '["an edge case the user states only in a later answer","an error case (a rule for a refusal)","a rule listed for a [human] requirement","a project larger than the greet.sh fixture"]'
  }
}

# A leftover untracked file in the working folder (R34): the project command
# fails on it when run in the working folder, and the proof (run on a clean
# copy) is unchanged and passes. lint.sh records where it ran and whether the
# file was there.
scenario_leftover() {
  new_project
  fixture="greet.sh from scratch plus a committed lint.sh that fails when todos.txt exists; project command lint: sh lint.sh"
  printf '#!/bin/sh\n[ -z "${LEFTOVER_PROBE:-}" ] || { pwd -P; [ -e todos.txt ] && echo yes || echo no; } > "$LEFTOVER_PROBE"\n[ ! -e todos.txt ]\n' > "$dir/lint.sh"
  git -C "$dir" add -A && git -C "$dir" commit -qm "chore: lint.sh"
  start="$GREET Also make the project command lint (sh lint.sh) part of the project's commands; it is already in the repository."
  checks() {
    common_checks
    local probe before after f=todos.txt flips=false same=false pp=false inc=true gone=false passed=true where a argv=()
    jq -e '.commands.lint' "$dir/.vbw/record.json" > /dev/null 2>&1 || { say "FAIL no lint command in the record"; failed=1; }
    before=$(jq -c '.evidence | {passed, checks: (.checks | map_values(.status)), commands: (.commands | map_values(.status))}' "$dir/.vbw/record.json" 2> /dev/null)
    printf 'buy milk\n' > "$dir/$f"
    while IFS= read -r -d '' a; do argv+=("$a"); done < <(jq -j '.commands.lint[] + "\u0000"' "$dir/.vbw/record.json" 2> /dev/null)
    (cd "$dir" && [ "${#argv[@]}" -gt 0 ] && ! "${argv[@]}" > /dev/null 2>&1) && flips=true
    probe=$(mktemp "${TMPDIR:-/tmp}/vbw-l3-probe.XXXXXX")
    (cd "$dir" && LEFTOVER_PROBE="$probe" "$VBW" prove > /dev/null 2>&1) || true
    after=$(jq -c '.evidence | {passed, checks: (.checks | map_values(.status)), commands: (.commands | map_values(.status))}' "$dir/.vbw/record.json" 2> /dev/null)
    [ -n "$before" ] && [ "$before" = "$after" ] && same=true
    jq -e '.evidence.passed == true' "$dir/.vbw/record.json" > /dev/null 2>&1 && pp=true
    where=$(sed -n 1p "$probe"); [ "$(sed -n 2p "$probe")" = no ] && inc=false
    rm -f "$probe"
    [ -n "$where" ] && [ "$where" != "$(cd "$dir" && pwd -P)" ] && [ ! -e "$where" ] \
      && ! git -C "$dir" worktree list --porcelain | grep -qF "$where" && gone=true
    rm -f "$dir/$f"
    expect "the check flips in the working folder with the leftover file" [ "$flips" = true ]
    expect "the proof is unchanged by the leftover file" [ "$same" = true ]
    expect "the proof passed" [ "$pp" = true ]
    expect "the file was not in the proof copy" [ "$inc" = false ]
    expect "the proof copy is gone" [ "$gone" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write leftover "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg f "$f" --argjson fl "$flips" --argjson s "$same" --argjson p "$pp" --argjson i "$inc" --argjson g "$gone" \
        '{leftover_file: $f, check_flips_in_working_folder: $fl, proof_unchanged: $s, proof_passed: $p, file_in_proof_copy: $i, copy_removed: $g}')" \
      '["a leftover modified tracked file","a git-ignored leftover (linked into the copy by design)","a project command other than a shell script","a project larger than the greet.sh fixture"]'
  }
}

# --- The interview (R42): a newcomer and a senior engineer answer it in the real
# app, in their own words. Each answer is recorded, the interview is not asked
# again in a new session, and the milestone ships. The transcript is saved for a
# person to read (R41, human). Facts come from `vbw interview`, the record, the
# spec Goals and git, never from screen text.

interview_pending() { (cd "$dir" && "$VBW" interview --json 2> /dev/null | jq -r '.pending // "none"') || echo none; }

# The open question as it shows: from the separator above its tab line to the
# end (the scrollback still shows the questions answered before).
current_question() {
  local s start
  s=$(screen)
  start=$(printf '%s\n' "$s" | grep -n '^──' | tail -2 | head -1 | cut -d: -f1)
  printf '%s\n' "$s" | tail -n +"${start:-1}"
}

# pick_label REGEX: choose the option on screen whose label starts with REGEX
# (the model may reorder options; the cursor's marker is not always a plain space).
pick_label() {
  local n i
  n=$(current_question | grep -iE "^[^0-9]*[0-9]+\. $1" | head -1 | grep -oE '[0-9]+' | head -1)
  [ -n "$n" ] || { say "no option matching '$1' on screen"; return 1; }
  for ((i = 1; i < n; i++)); do l3 keys "$scenario" Down; done
  l3 keys "$scenario" Enter
}

# Render the project's main session transcripts (what VBW said and asked, what
# the user answered) as Markdown, in time order, to $1.
transcript_write() {
  local f
  mkdir -p "$RESULTS"
  {
    printf '# %s: transcript of the real Claude Code session\n\n' "$scenario"
    while IFS= read -r f; do
      jq -r 'if .type == "assistant" then
          (.message.content[]? | if .type == "text" then "**VBW:** " + .text + "\n"
            elif .type == "tool_use" and .name == "AskUserQuestion" then
              "**VBW asks:**\n" + ([.input.questions[]? | "- " + .question + " (options: " + ([.options[]?.label] | join(" / ")) + ")"] | join("\n")) + "\n"
            else empty end)
        elif .type == "user" then
          # Claude Code marks the text it injects (skill bodies, tool references) isMeta;
          # background-task notifications are not marked. Neither is the conversation.
          if .isMeta == true then empty else
          (.message.content | if type == "string" then (select(startswith("<task-notification>") | not) | "**User:** " + . + "\n")
            else (.[]? | if .type == "text" and (.text | startswith("<task-notification>") | not) then "**User:** " + .text + "\n"
              elif .type == "tool_result" then ((.content | if type == "array" then map(.text? // "") | join(" ") else (. // "") end)
                | select(startswith("Your questions have been answered")) | "**User answers:** " + . + "\n")
              else empty end) end) end
        else empty end' "$f" 2> /dev/null
    done < <(transcripts | grep -v '/subagents/' | sort)
  } > "$1"
}

# interview_options_fixed: every time the main session asked one of the three
# baseline interview questions, it offered exactly the skill's options, in its
# order, none marked Recommended (read from the session, not the screen).
interview_options_fixed() {
  local t
  t=$(transcripts | grep -v '/subagents/')
  [ -n "$t" ] || return 1
  printf '%s\n' "$t" | xargs cat 2> /dev/null | jq -s -e '
    {"^How much software have you built": ["never", "small scripts or no-code", "professionally", "senior engineer"],
     "^How should I explain things": ["plain words", "plain with technical terms explained", "technical and brief"],
     "^How involved do you want to be": ["decide and tell me", "options with a recommendation", "I make the calls"]} as $want
    | [.[] | select(.type == "assistant") | .message.content[]?
       | select(.type == "tool_use" and .name == "AskUserQuestion") | .input.questions[]?
       | . as $q | $want | to_entries[] | .key as $k | select($q.question | test($k; "i"))
       | ([$q.options[]?.label] == .value)]
    | length > 0 and all' > /dev/null
}

# transcript_clean FILE: no text Claude Code injected (isMeta) reached FILE.
transcript_clean() {
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && grep -qF -- "$line" "$1" && return 1
  done < <(transcripts | grep -v '/subagents/' | xargs cat 2> /dev/null | jq -r 'select(.type == "user" and .isMeta == true)
    | .message.content | if type == "string" then . else ([.[]? | .text? // empty] | join("\n")) end
    | split("\n") | map(select(length >= 20)) | .[0] // empty')
  return 0
}

# scenario_interview LEVEL DEPTH INVOLVEMENT KEEP_REGEX PURPOSE KEYWORD: sets up
# a project whose user answers the interview as given (drive handlers) and
# defines checks() to read the outcome. The caller's checks() writes the result.
scenario_interview() {
  a_level=$1 a_depth=$2 a_inv=$3 a_keep=$4 a_purpose=$5 a_word=$6
  new_project
  start="/vbw:vibe I want to build a small greeting tool. One small milestone."
  purpose_done=0 followups=0
  # The question on screen decides the answer (the model may put several
  # questions in one form, so the recorded state is not a guide).
  on_question() {
    local p scr
    p=$(interview_pending)
    scr=$(current_question)
    if printf '%s' "$scr" | grep -qi 'how much software'; then pick_label "$a_level"
    elif printf '%s' "$scr" | grep -qi 'explain things'; then pick_label "$a_depth"
    elif printf '%s' "$scr" | grep -qi 'how involved'; then pick_label "$a_inv"
    elif printf '%s' "$scr" | grep -qi 'private on this machine'; then pick_label "$a_keep"
    elif [ "$p" = none ] || printf '%s' "$scr" | grep -q 'Ready to submit'; then return 1
    elif [ "$purpose_done" -eq 0 ]; then
      purpose_done=1; answer_other "$a_purpose"
    else
      followups=$((followups + 1))
      if printf '%s' "$scr" | grep -q 'Type something'; then answer_other "Keep it as simple as that."; else answer_recommended; fi
    fi
  }
  # The question "what and for whom" may arrive as a plain message, not a menu.
  on_idle() {
    [ "$(interview_pending)" = keep ] && [ "$purpose_done" -eq 0 ] || return 1
    last_reply | grep -qiE 'building|for whom|who.*(for|use)' || return 1
    purpose_done=1
    l3 type "$scenario" "$a_purpose"
  }
}

# interview_outcome: reads the outcome and sets $passed and $facts. Also runs a
# second request in a new session and checks the interview is not asked again.
interview_outcome() {
  local rec before after files new asked=false ask_after=true goals="" in_goals=false shipped_ok=false ship_commit=false match=false keptw n fixed=false clean=false
  passed=true
  common_checks
  rec=$(cd "$dir" && "$VBW" interview --json 2> /dev/null || echo '{}')
  keptw=$(printf '%s' "$rec" | jq -r '.kept // "none"')
  goals=$(sed -n '/^## Goals/,/^## /p' "$dir/.vbw/spec.md" 2> /dev/null || true)
  printf '%s' "$goals" | grep -qi "$a_word" && in_goals=true
  shipped && shipped_ok=true
  [ "$(git -C "$dir" log --format=%s | grep -c '^chore(vbw): ship')" -gt 0 ] && ship_commit=true
  printf '%s' "$rec" | jq -e --arg l "$a_level" --arg d "$a_depth" --arg i "$a_inv" '.level == $l and .depth == $d and .involvement == $i' > /dev/null && match=true
  [ "$keptw" = private ] || [ "$keptw" = project ] || match=false
  transcript_write "$RESULTS/$scenario.transcript.md"
  interview_options_fixed && fixed=true
  transcript_clean "$RESULTS/$scenario.transcript.md" && clean=true
  # A second request in a new session.
  files=$(transcripts | sort); before=$rec
  l3 start "$scenario" "$dir" > /dev/null
  if screen | grep -q "Type \/reload-skills"; then l3 type "$scenario" "/reload-skills"; sleep 5; fi
  l3 type "$scenario" "/vbw:vibe Also let greet.sh take --shout, printing the greeting in capital letters."
  default_idle
  l3 keys "$scenario" Escape; sleep 2; default_idle
  l3 stop "$scenario"
  after=$(cd "$dir" && "$VBW" interview --json 2> /dev/null || echo '{}')
  new=$(comm -13 <(printf '%s\n' "$files") <(transcripts | sort) | grep -v '/subagents/' || true)
  if [ -n "$new" ] && printf '%s\n' "$new" | xargs cat 2> /dev/null | jq -e 'select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use" and (((.input | tostring) | test("interview (set|keep)|How much software")) or (.name == "Skill" and ((.input | tostring) | test("interview")))))' > /dev/null 2>&1; then asked=true; fi
  [ "$(cd "$dir" && "$VBW" next --json 2> /dev/null | jq -r '.profile.ask')" = false ] && ask_after=false || ask_after=true
  [ "$before" = "$after" ] || asked=true
  n=$followups
  expect "the answers were recorded as given, kept $keptw" [ "$match" = true ]
  expect "what was being built is in the spec Goals" [ "$in_goals" = true ]
  expect "the second session did not ask the interview again" [ "$asked" = false ]
  expect "the profile no longer asks" [ "$ask_after" = false ]
  expect "the milestone shipped, with a ship commit" [ "$shipped_ok$ship_commit" = truetrue ]
  expect "at most three follow-ups ($n)" [ "$n" -le 3 ]
  expect "the baseline options came in the skill's order, none marked Recommended" [ "$fixed" = true ]
  expect "the transcript holds the conversation only, no injected text" [ "$clean" = true ]
  [ "$failed" -eq 0 ] || passed=false
  facts=$(jq -n --arg l "$a_level" --arg d "$a_depth" --arg i "$a_inv" --arg k "$keptw" --arg p "$a_purpose" --argjson f "$n" \
    --argjson rec "$rec" --argjson m "$match" --argjson g "$in_goals" --argjson a "$asked" --argjson aa "$ask_after" \
    --argjson s "$shipped_ok" --argjson sc "$ship_commit" --argjson fx "$fixed" --argjson cl "$clean" --arg t "tools/l3-results/$scenario.transcript.md" \
    '{answered: {level: $l, depth: $d, involvement: $i, purpose: $p, follow_ups: $f, keep: $k},
      recorded: {level: $rec.level, depth: $rec.depth, involvement: $rec.involvement, kept: $rec.kept},
      recorded_matches_answered: $m, purpose_in_spec_goals: $g,
      second_session_asked_interview: $a, next_profile_ask_after: $aa,
      milestone_shipped: $s, reached_ship: ($s and $sc), transcript: $t,
      baseline_options_fixed: $fx, transcript_clean: $cl}')
}

# interview_not_tested LIST: LIST, plus the follow-up answering path when the
# session asked no follow-up question.
interview_not_tested() {
  printf '%s' "$facts" | jq -c --argjson l "$1" 'if .answered.follow_ups == 0
    then $l + ["answering an interview follow-up question (none was asked)"] else $l end'
}

scenario_newcomer() {
  fixture="greet.sh from scratch; a user who has never built software answers in plain words and lets VBW decide"
  scenario_interview "never" "plain words" "decide and tell me" "private" \
    "a script greet.sh: ./greet.sh Ana prints Hello, Ana! and ./greet.sh alone prints Hello, world!. It is for my grandmother, who is learning English." grandmother
  checks() {
    interview_outcome
    result_write newcomer "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      "$(interview_not_tested '["a person judging the wording (R41, human)","the other two level answers","a project larger than the greet.sh fixture","a second request carried through to the end"]')"
  }
}

scenario_senior() {
  fixture="greet.sh from scratch; a senior engineer answers technically and briefly and makes the calls; answers kept in the project"
  scenario_interview "senior engineer" "technical and brief" "I make the calls" "saved" \
    "a CLI greeter, greet.sh: ./greet.sh Ana prints Hello, Ana!, no argument prints Hello, world!. Our team calls it from onboarding scripts; users are platform engineers." onboarding
  checks() {
    interview_outcome
    result_write senior "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      "$(interview_not_tested '["a person judging the wording (R41, human)","the middle level answers","a project larger than the greet.sh fixture","a second request carried through to the end"]')"
  }
}

failed=0
# shellcheck disable=SC2086 # the default list splits on purpose
[ $# -gt 0 ] || set -- $ALL

# Several scenarios: run each in its own process, L3_JOBS at a time, then
# print each one's lines in the order asked; the exit reflects all of them.
if [ $# -gt 1 ] && [ "${L3_JOBS:-4}" -gt 1 ] && [ -z "${L3_CHILD:-}" ]; then
  logs=$(mktemp -d "${TMPDIR:-/tmp}/vbw-l3-logs.XXXXXX")
  pids=() names=() status=0 running=0
  for scenario in "$@"; do
    case " $ALL " in *" $scenario "*) ;; *) echo "unknown scenario $scenario (one of: $ALL)" >&2; exit 2 ;; esac
  done
  for scenario in "$@"; do
    L3_CHILD=1 bash "$0" "$scenario" > "$logs/$scenario.log" 2>&1 &
    pids+=("$!") names+=("$scenario") running=$((running + 1))
    if [ "$running" -ge "${L3_JOBS:-4}" ]; then wait "${pids[$((${#pids[@]} - running))]}" || status=1; running=$((running - 1)); fi
  done
  for ((i = ${#pids[@]} - running; i < ${#pids[@]}; i++)); do wait "${pids[$i]}" || status=1; done
  for scenario in "${names[@]}"; do grep -v '^L3 suite:' "$logs/$scenario.log"; done
  rm -rf "$logs"
  [ "$status" -eq 0 ] && echo "L3 suite: all checks passed" || { echo "L3 suite: FAILED"; exit 1; }
  exit 0
fi
for scenario in "$@"; do
  case " $ALL " in *" $scenario "*) ;; *) echo "unknown scenario $scenario (one of: $ALL)" >&2; exit 2 ;; esac
  # Each scenario's result reflects its own checks; the suite's exit, all of them.
  suite_failed=$failed failed=0
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
  [ "$suite_failed" -eq 0 ] || failed=1
done
[ "$failed" -eq 0 ] && echo "L3 suite: all checks passed" || { echo "L3 suite: FAILED"; exit 1; }
