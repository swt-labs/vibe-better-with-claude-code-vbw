#!/usr/bin/env bash
# Real-user scenarios before a release (AGENTS.md: evidence level L3). Each
# scenario sets up a project, drives the real Claude Code TUI through
# tools/l3.sh as a user would (typing, answering questions, approving), and
# then checks the outcome in the plan of record and in git, never on screen
# text. Costs model usage: about $1-3 per scenario.
#
#   tools/l3-suite.sh [SCENARIO...]     (default: all)
#
# Scenarios: greenfield, reject, resume, change, convert, balanced. A user answers every
# question with VBW's recommendation unless the scenario says otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
l3() { bash "$ROOT/tools/l3.sh" "$@"; }
VBW="$ROOT/plugin/bin/vbw"
ALL="greenfield reject resume change convert balanced"
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
session_cost() {
  local out
  l3 type "$scenario" "/cost"; sleep 3
  out=$(screen)
  l3 keys "$scenario" Escape
  printf '%s' "$out" | grep -oE '\$[0-9]+\.[0-9]+' | head -1 | tr -d '$'
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
  checks
  l3 stop "$scenario"
done
[ "$failed" -eq 0 ] && echo "L3 suite: all checks passed" || { echo "L3 suite: FAILED"; exit 1; }
