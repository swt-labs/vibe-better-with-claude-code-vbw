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
# L3_JOBS at a time (default 4), started L3_STAGGER seconds apart (default 10);
# each one's lines print together when it ends.
#
# Scenarios: greenfield, reject, resume, change, convert, balanced, docs, qafix,
# decision, debug, research, edgecase, leftover, recheck, approval, newcomer, senior, panel, steptime, road, pluginoff, tools, legacy, nolegacy, smallchange, costs, loop, plugindir, sessions, taskbreak, fixchecks, failoutput, leaveout, hiddenrecord, latedecision, ignoredplanning, stalefix, mapsnapshot, alreadyfixed, mapnotrun. A user
# answers every question with VBW's recommendation unless the scenario says otherwise.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
l3() { bash "$ROOT/tools/l3.sh" "$@"; }
VBW="$ROOT/plugin/bin/vbw"
ALL="greenfield reject resume change convert balanced docs qafix decision debug research edgecase leftover recheck approval newcomer senior panel steptime road pluginoff tools legacy nolegacy smallchange costs loop plugindir sessions taskbreak fixchecks failoutput leaveout hiddenrecord latedecision ignoredplanning stalefix mapsnapshot alreadyfixed mapnotrun"
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
  # Marks a VBW test session (R64): the panel plays no sound aloud here and keeps
  # its choices under its test.vbw-panel.* keys, never the user's own.
  mkdir -p "$dir/.vbw/runtime" && : > "$dir/.vbw/runtime/test-mode"
}

next_action() { (cd "$dir" && "$VBW" next --json 2> /dev/null | jq -r '.action // "none"') || echo none; }
screen() { l3 screen "$scenario"; }
default_idle() { l3 wait "$scenario" 1500 > /dev/null 2>&1 || true; }
# spec_section_lines SPEC SECTION: the '- ' lines of the '## SECTION' section, after dropping every
# <!-- ... --> block (one-line or multi-line; text outside a block on the same line is kept). One awk
# reads to the end of the file, so no quiet grep can end it early (tools/check-pipefail-grep.sh).
spec_section_lines() {
  awk -v sec="$2" '
    BEGIN { inc = 0; insec = 0 }
    {
      line = $0; out = ""
      while (length(line) > 0) {
        if (inc) {
          i = index(line, "-->")
          if (i == 0) { line = ""; break }
          line = substr(line, i + 3); inc = 0
        } else {
          i = index(line, "<!--")
          if (i == 0) { out = out line; line = ""; break }
          out = out substr(line, 1, i - 1); line = substr(line, i + 4); inc = 1
        }
      }
      if (out ~ /^## /) { insec = (out == "## " sec); next }
      if (insec && out ~ /^- /) print out
    }
  ' "$1" 2> /dev/null
}

# Answer the question on screen with the first (recommended) option. A
# multi-select question needs the option ticked, then Submit.
answer_recommended() {
  if screen | grep 'Ready to submit' > /dev/null; then
    l3 keys "$scenario" Enter
  elif screen | grep '\[ \]' > /dev/null; then
    l3 keys "$scenario" Enter; sleep 1; l3 keys "$scenario" Right; sleep 2; l3 keys "$scenario" Enter
  else
    l3 keys "$scenario" Enter
  fi
}

# answer_other TEXT: move to "Type something." and type TEXT.
# Options may still be rendering: it looks for up to 5 s before it escapes the
# menu and types (which Claude Code reports to the model as an interruption).
answer_other() {
  local n="" i
  for ((i = 0; i < 10; i++)); do
    n=$(screen | grep -E '^\s*(❯ )?[0-9]+\. Type something' | grep -oE '[0-9]+' | head -1)
    [ -n "$n" ] && break
    sleep 0.5
  done
  [ -n "$n" ] || { say "no 'Type something' option on screen; escaping the menu"; l3 keys "$scenario" Escape; sleep 1; l3 type "$scenario" "$1"; return; }
  # On "Type something." the user types at once; Enter there first would
  # submit it empty and send the text as a new prompt.
  for ((i = 1; i < n; i++)); do l3 keys "$scenario" Down; done
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
    if screen | grep 'Enter to select\|Ready to submit' > /dev/null; then
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
# Reads a session transcript on stdin and the record's path: succeeds only when the
# settings write (config set autonomy) is at or before the record's first
# 'Contract approved' decision and the first run lease. A record with no such
# decision, or a lookup that fails, is never 'before'. Timestamps are cut to the second.
autonomy_written_before_run() {
  local first_approval
  first_approval=$(jq -r '[.decisions[] | select(.text | startswith("Contract approved")) | .at[0:19]] | first // empty' "$1" 2> /dev/null)
  [ -n "$first_approval" ] || return 1
  jq -sre --arg a "$first_approval" '
    [.[] | select(.type == "assistant") | . as $m | .message.content[]?
      | select(.type == "tool_use") | {at: ($m.timestamp[0:19]), name: .name, cmd: (.input.command // "")}] as $u
    | ([$u[] | select(.cmd | contains("config set autonomy")) | .at] | first) as $w
    | ([$u[] | select((.cmd | contains("run start")) or .name == "Workflow") | .at] | first // "9999") as $r
    | $w != null and $w <= $a and $w <= $r' > /dev/null 2>&1
}

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
    # The run-closing agent (a Lead labelled "close run") confirms the record; it builds nothing.
    jq -r 'select(.workflowPhase == "Build" and (.description // "") != "close run") | .agentType' "${f%.jsonl}.meta.json" 2> /dev/null
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

# report_line_in_proof_output REGEX: succeeds when a tool result of a 'vbw prove'
# or 'vbw fix done' call in the session transcripts (main and subagents) carries
# a line matching REGEX. Read from the transcripts, never from screen text.
report_line_in_proof_output() {
  transcripts | xargs cat 2> /dev/null | jq -se --arg re "$1" '
    [.[] | select(.type == "assistant") | .message.content[]?
      | select(.type == "tool_use" and ((.input.command // "") | test("vbw[^|;&]* (prove|fix done)|bin/vbw[^|;&]* (prove|fix done)"))) | .id] as $ids
    | any(.[] | select(.type == "user") | .message.content[]?
        | select(.type == "tool_result" and ([.tool_use_id] | inside($ids)))
        | (if (.content | type) == "string" then .content else ([.content[]? | .text? // ""] | join("\n")) end)
        | split("\n")[]; test($re))' > /dev/null 2>&1
}

# transcript_tool_output COMMAND_REGEX RESULT_REGEX: reads transcript file names on
# stdin and succeeds when the result of a Bash call whose command matches
# COMMAND_REGEX has a line matching RESULT_REGEX. Read from the tool results in the
# transcripts, never from screen text.
transcript_tool_output() {
  xargs cat 2> /dev/null | jq -se --arg cmd "$1" --arg re "$2" '
    [.[] | select(.type == "assistant") | .message.content[]?
      | select(.type == "tool_use" and ((.input.command // "") | test($cmd))) | .id] as $ids
    | any(.[] | select(.type == "user") | .message.content[]?
        | select(.type == "tool_result" and ([.tool_use_id] | inside($ids)))
        | (if (.content | type) == "string" then .content else ([.content[]? | .text? // ""] | join("\n")) end)
        | split("\n")[]; test($re))' > /dev/null 2>&1
}

# transcript_tool_called COMMAND_REGEX: reads transcript file names on stdin and
# succeeds when a Bash tool call has a command matching COMMAND_REGEX. Read from the
# tool calls in the transcripts, never from screen text.
transcript_tool_called() {
  xargs cat 2> /dev/null | jq -se --arg cmd "$1" '
    any(.[] | select(.type == "assistant") | .message.content[]?
      | select(.type == "tool_use") | (.input.command // ""); test($cmd))' > /dev/null 2>&1
}

# unhide_lines_present DIR: succeeds when DIR/.vbw/.gitignore holds the four
# un-hide lines VBW keeps for its plan files (R208).
unhide_lines_present() {
  local l
  for l in '!record.json' '!spec.md' '!map.md' '!.gitignore'; do
    grep -qxF -- "$l" "$1/.vbw/.gitignore" 2> /dev/null || return 1
  done
}

scenario_greenfield() {
  new_project
  start=$GREET
  fixture="greet.sh from scratch; one small milestone; the user types /vbw:vibe and the build runs to the end"
  checks() {
    common_checks
    local own=false ran=false passed=true
    # The printed forms of the two proof report lines (docs/proof.md, R202).
    if report_line_in_proof_output "^VBW.s own work: [0-9]+\\.[0-9] of [0-9]+\\.[0-9] min"; then own=true; fi
    if report_line_in_proof_output "^ran again: [0-9]+ of [0-9]+ units; top reasons: "; then ran=true; fi
    expect "a proof's output in the session carried the own-work line ($own)" [ "$own" = true ]
    expect "a proof's output in the session carried the ran-again line ($ran)" [ "$ran" = true ]
    # R208: the un-hide lines are in VBW's own .vbw/.gitignore and the record is tracked.
    local unhidden=false
    if unhide_lines_present "$dir" && git -C "$dir" ls-files --error-unmatch .vbw/record.json > /dev/null 2>&1; then unhidden=true; fi
    expect "the project's .vbw/.gitignore holds the un-hide lines and the record is tracked ($unhidden)" [ "$unhidden" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write greenfield "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson o "$own" --argjson r "$ran" --argjson u "$unhidden" '{report_own_work_line: $o, report_ran_again_line: $r, plan_files_unhidden: $u}')" \
      '["acceptance by a human (greet.sh has only auto requirements)","a project larger than the greet.sh fixture, so the figures in the lines are small","the lines on screen: they are read from the tool results in the transcripts, not from what the window showed","a proof that reused units, so the top reasons are mostly never-passed","vbw fix done output (no fix round in this run)"]'
  }
}

# A project-wide *.json ignore rule (R208): the committed .gitignore would hide
# .vbw/record.json. The record is committed anyway, with the un-hide lines in
# .vbw/.gitignore, judged in git and the project's files, never on screen text.
scenario_hiddenrecord() {
  new_project
  printf '*.json\n' > "$dir/.gitignore"
  git -C "$dir" add .gitignore && git -C "$dir" commit -qm "chore: ignore json files"
  start=$GREET
  fixture="greet.sh from scratch in a project whose committed .gitignore holds '*.json'; the user types /vbw:vibe and the build runs to the end"
  checks() {
    common_checks
    local rule tracked=false unhide=false n=0 passed=true facts
    rule=$(grep -vE '^[[:space:]]*(#|$)' "$dir/.gitignore" 2> /dev/null | head -n 1)
    git -C "$dir" ls-files --error-unmatch .vbw/record.json > /dev/null 2>&1 && tracked=true
    unhide_lines_present "$dir" && unhide=true
    n=$(git -C "$dir" log --format=%H -- .vbw/record.json 2> /dev/null | wc -l | tr -d ' ')
    expect "the *.json rule is still in the project's .gitignore (${rule})" [ "$rule" = '*.json' ]
    expect "the record is committed despite the rule ($tracked)" [ "$tracked" = true ]
    expect "the un-hide lines are in .vbw/.gitignore ($unhide)" [ "$unhide" = true ]
    expect "the record has at least one commit ($n)" [ "${n:-0}" -ge 1 ]
    [ "$failed" -eq 0 ] || passed=false
    facts=$(jq -n --arg r "$rule" --argjson t "$tracked" --argjson u "$unhide" --argjson n "${n:-0}" \
      '{gitignore_rule: $r, record_committed: $t, unhide_lines: $u, record_commits: $n}')
    result_write hiddenrecord "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      '["a rule hiding the whole .vbw folder (covered by tests/hidden-record.bats, L1)","a rule in .git/info/exclude or a global excludes file","an existing project upgraded from an older .vbw/.gitignore","the spec file staying untracked until the first full commit"]'
  }
}

# kernel_trees: the kernel's own fingerprints of the project in $dir, the ones
# vbw next compares with the evidence: "CODE_TREE HEAD_TREE" (empty on failure).
kernel_trees() {
  (cd "$dir" && bash -c 'VBW_LIB="$1/plugin/lib"; for l in core record; do . "$VBW_LIB/$l.sh"; done
    vbw_project; printf "%s %s\n" "$(vbw_code_tree)" "$(vbw_head_tree)"' _ "$ROOT") 2> /dev/null
}

# A .gitignore that ignores .vbw-planning (#695), with the folder a VBW 1 leftover
# would leave: one file tracked from before the rule, one untracked. The code
# fingerprint must still work: the proof records a tree, after the session the
# kernel's fingerprints equal the evidence (vbw next sees no change), and a proof
# after an unrelated commit reuses results. Judged in the record and git, never
# on screen text.
scenario_ignoredplanning() {
  new_project
  mkdir -p "$dir/.vbw-planning"
  printf '# State\n\nPhase 1 in progress.\n' > "$dir/.vbw-planning/STATE.md"
  git -C "$dir" add .vbw-planning/STATE.md && git -C "$dir" commit -qm "chore: VBW 1 state"
  printf '.vbw-planning/\n' > "$dir/.gitignore"
  printf 'scratch\n' > "$dir/.vbw-planning/notes.md"
  git -C "$dir" add .gitignore && git -C "$dir" commit -qm "chore: ignore the planning folder"
  # A file no check will read, edited after the session: an edit keeps the root listing, which a
  # check that runs ./greet.sh has on its read list (macOS, 2026-10-29), where a new root file would not.
  printf '# Notes\n' > "$dir/NOTES.md"
  git -C "$dir" add NOTES.md && git -C "$dir" commit -qm "docs: notes"
  start=$GREET
  fixture="greet.sh from scratch in a project whose committed .gitignore holds '.vbw-planning/', with .vbw-planning/STATE.md tracked from before the rule and .vbw-planning/notes.md untracked; the user types /vbw:vibe and the build runs to the end; then the scenario commits an unrelated NOTES.md and runs vbw prove"
  checks() {
    common_checks
    local tree head now nowhead ignored=false proved=false unchanged=false tree2="" proved2=false reused=0 passed=true facts
    tree=$(jq -r '.evidence.tree // empty' "$dir/.vbw/record.json" 2> /dev/null)
    head=$(jq -r '.evidence.head // empty' "$dir/.vbw/record.json" 2> /dev/null)
    [ -n "$tree" ] && jq -e '.evidence.passed == true' "$dir/.vbw/record.json" > /dev/null 2>&1 && proved=true
    git -C "$dir" check-ignore -q .vbw-planning/notes.md && git -C "$dir" ls-files --error-unmatch .vbw-planning/STATE.md > /dev/null 2>&1 && ignored=true
    read -r now nowhead <<< "$(kernel_trees)"
    [ -n "$tree" ] && [ "$now" = "$tree" ] && { [ -z "$head" ] || [ "$nowhead" = "$head" ]; } && unchanged=true
    # A user commit no check reads (an edit of a seeded file), then a proof: the fingerprint moves
    # and results are reused.
    printf '# Notes\n\nMore notes.\n' > "$dir/NOTES.md"
    git -C "$dir" add NOTES.md && git -C "$dir" commit -qm "docs: more notes"
    (cd "$dir" && "$VBW" prove > /dev/null 2>&1) || true
    tree2=$(jq -r '.evidence.tree // empty' "$dir/.vbw/record.json" 2> /dev/null)
    [ -n "$tree2" ] && [ "$tree2" != "$tree" ] && jq -e '.evidence.passed == true' "$dir/.vbw/record.json" > /dev/null 2>&1 && proved2=true
    reused=$(jq '[.evidence | (.checks // {}), (.commands // {}), (.test_files // {}) | .[] | select(.reused == true)] | length' "$dir/.vbw/record.json" 2> /dev/null || echo 0)
    expect "the .vbw-planning rule holds: notes.md ignored, STATE.md tracked ($ignored)" [ "$ignored" = true ]
    expect "the session's proof passed and recorded a tree (${tree:-none})" [ "$proved" = true ]
    expect "the kernel's fingerprints equal the evidence after the session ($unchanged)" [ "$unchanged" = true ]
    expect "the proof after a new commit passed with a new tree (${tree2:-none})" [ "$proved2" = true ]
    expect "that proof reused results ($reused)" [ "${reused:-0}" -ge 1 ]
    [ "$failed" -eq 0 ] || passed=false
    facts=$(jq -n --argjson i "$ignored" --arg t "$tree" --argjson p "$proved" --argjson u "$unchanged" --arg t2 "$tree2" --argjson p2 "$proved2" --argjson r "${reused:-0}" \
      '{planning_ignored_tracked_and_untracked: $i, proof_passed: $p, evidence_tree: $t, fingerprints_match_evidence: $u, second_proof_passed: $p2, second_tree: $t2, reused_units: $r}')
    result_write ignoredplanning "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      '["a rule ignoring the .vbw folder itself","a rule in .git/info/exclude or a global excludes file","converting the VBW 1 folder (the review recommends Start fresh for a folder with no readable plan)","a real VBW 1 project: the folder holds two small files","vbw next run in the session at each step: the fingerprints are compared once, after the session"]'
  }
}

scenario_reject() {
  new_project
  start="$GREET Also, the wording should feel warm and friendly; I will judge that myself."
  rejected=0
  on_question() {
    [ "$(next_action)" = accept ] && [ "$rejected" -eq 0 ] || return 1
    screen | grep "Something's wrong" > /dev/null || return 1
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
      if [ "$now" = "$last" ] && ! printf '%s' "$now" | grep 'esc to interrupt' > /dev/null; then
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
    [ "$killed" -eq 1 ] && screen | grep 'That session is closed' > /dev/null || return 1
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
      if screen | grep "Type \/reload-skills" > /dev/null; then l3 type "$scenario" "/reload-skills"; sleep 5; fi
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
    local te dl passed=true autonomy qa_bg=false stopped=none
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
    result_write balanced "$fixture" "${cost_usd:-0}" "$passed" \
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
    # R71 (owner, 2026-10-06, kept 2026-10-21): a requirement whose plans change only
    # documentation needs no check. Then the plan's files must all be documentation.
    nock=false
    if { [ -z "$cst" ] || [ "$cst" = none ]; } && jq -e --arg r "$req" '([.checks[] | select(.req == $r)] | length == 0)
        and ([.plans[] | select(any(.reqs[]; . == $r)) | .files[]] | length > 0 and all(test("\\.(md|rst)$")))' "$dir/.vbw/record.json" > /dev/null 2>&1; then
      nock=true
    fi
    rst=$(jq -r --arg r "$req" 'first(.requirements[] | select(.id == $r)) | .status // "none"' "$dir/.vbw/record.json" 2> /dev/null)
    [ -n "$plan" ] && [ "$(cd "$dir" && git log --format=%B | grep -c "^VBW-Plan: $plan\$")" -gt 0 ] && prov=true
    # Each condition prints its own line, so a failed one is never silent.
    expect "docs/USAGE.md was written" [ -f "$dir/docs/USAGE.md" ]
    expect "the Docs agent built it (agents: $agents)" [ "$by" = docs ]
    expect "an approved check proves the documentation requirement, or its plans change documentation only (R71) (check status: $cst)" [ "$cst" = pass -o "$nock" = true ]
    expect "the documentation requirement is proven, not only accepted ($rst)" [ "$rst" = proven ]
    expect "the docs plan's commits carry provenance" [ "$prov" = true ]
    [ "$failed" -eq 0 ] && [ "$by" = docs ] && { [ "$appr" = true ] && [ "$cst" = pass ] || [ "$nock" = true ]; } && [ "$prov" = true ] && [ "$rst" = proven ] || passed=false
    result_write docs "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg b "$by" --argjson a "$appr" --arg c "$cst" --argjson p "$prov" --arg r "$rst" --arg pl "$plan" --arg ag "$agents" --argjson n "$nock" \
        '{built_by_agent_type: $b, check_approved: $a, check_status: $c, documentation_only_no_check: $n, commit_has_provenance: $p, requirement_status: $r, docs_plan: $pl, build_agents: $ag}')" \
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

# A build that deviates from its plan is brought back (R5): checks cannot see
# the deviation, the kernel's delivered-files check does, and the user is asked
# before QA whether to keep it or restore it. The scenario plays the deviation:
# once the build is proven it deletes a file its plan lists that no check names
# (a commit by the "user"), the way a build that skipped a task would look, then
# answers the question with "Restore them", and the fix loop must bring it back.
scenario_qafix() {
  new_project
  fixture="greet.sh plus NOTES.md (no check names it); guided autonomy stated in words; the built NOTES.md is deleted after the build, so only the delivered-files check can see the deviation; the user restores it"
  deviation=""
  restored=0
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
    # The user's commit changed the code: prove it again, so the evidence holds the deviation.
    (cd "$dir" && "$VBW" prove > /dev/null 2>&1) || true
    say "seeded the deviation: $f deleted after the build"
    return 0
  }
  # restore_answer: at the deviations question, pick "Restore them".
  restore_answer() {
    [ -n "$deviation" ] && [ "$restored" -eq 0 ] && [ "$(next_action)" = deviations ] || return 1
    local n i
    n=$(screen | grep -E '[0-9]+\. Restore' | grep -oE '[0-9]+' | head -1)
    [ -n "$n" ] || return 1
    for ((i = 1; i < n; i++)); do l3 keys "$scenario" Down; done
    l3 keys "$scenario" Enter
    restored=1
    say "answered the deviations question: Restore them"
    return 0
  }
  # Seed, then answer the question as a user would (the recommended option, or Restore at the deviations question).
  on_question() { seed_deviation || true; restore_answer; }
  on_idle() { seed_deviation; }
  done_yet() { [ -n "$deviation" ] && shipped; }
  # Human requirements (NOTES.md wording) are accepted as a user would.
  checks() {
    common_checks
    local hist asked restore_fix=false back=false rounds=0 final=none proved=false passed=true autonomy set_before=false
    autonomy=$(cd "$dir" && "$VBW" config autonomy 2> /dev/null)
    # The settings write comes from the main session (not a subagent) and must be
    # earlier than the first 'Contract approved' decision and the first run lease
    # (a 'run start' command or a Workflow call). Timestamps are cut to the second.
    if transcripts | grep -v /subagents/ | xargs cat 2> /dev/null | autonomy_written_before_run "$dir/.vbw/record.json"; then set_before=true; fi
    hist=$(record_history)
    # Restoring is a fix that names the file (vbw fix restore), at some point in the record's history.
    printf '%s\n' "$hist" | jq -se --arg d "$deviation" 'any(.[]; any(.fixes[]?; .restore == $d))' > /dev/null 2>&1 && restore_fix=true
    [ -n "$deviation" ] && git -C "$dir" cat-file -e "HEAD:$deviation" 2> /dev/null && back=true
    asked=$([ "$restored" -eq 1 ] && echo true || echo false)
    # A fix round is one fix run (the kernel commits the record after each run).
    rounds=$(git -C "$dir" log --format=%s | grep -c '^chore(vbw): record after fix-' || true)
    final=$(jq -r '[.phases[] | .qa.result // "none"] | last // "none"' "$dir/.vbw/record.json" 2> /dev/null)
    jq -e 'all(.requirements[]; .status == "proven" or .status == "accepted")' "$dir/.vbw/record.json" > /dev/null 2>&1 && proved=true
    say "deviation: asked $asked, restore fix $restore_fix, back at HEAD $back, fix rounds $rounds, final QA $final"
    [ -n "$deviation" ] || { say "FAIL the deviation was never seeded"; failed=1; }
    expect "the user was asked before QA and chose Restore ($asked)" [ "$asked" = true ]
    expect "a restore fix named the file ($restore_fix)" [ "$restore_fix" = true ]
    expect "at least one fix round ran ($rounds)" [ "$rounds" -ge 1 ]
    expect "the file is back at HEAD ($back)" [ "$back" = true ]
    expect "QA's final verdict is pass ($final)" [ "$final" = pass ]
    expect "every requirement is proven or accepted" [ "$proved" = true ]
    expect "the autonomy stated in words was recorded: guided ($autonomy)" [ "$autonomy" = guided ]
    expect "autonomy_set_before_first_run: the setting was written before the first Contract approved and the first run ($set_before)" [ "$set_before" = true ]
    [ "$failed" -eq 0 ] && [ "$autonomy" = guided ] && [ "$set_before" = true ] && [ "$asked" = true ] && [ "$restore_fix" = true ] && [ "$rounds" -ge 1 ] && [ "$back" = true ] && [ "$final" = pass ] && [ "$proved" = true ] || { passed=false; failed=1; }
    result_write qafix "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg d "${deviation:-}" --argjson a "$asked" --argjson rf "$restore_fix" --argjson b "$back" --argjson r "$rounds" --arg fin "$final" --argjson p "$proved" --arg au "$autonomy" --argjson sb "$set_before" \
        '{deviation: $d, asked_before_qa: $a, restore_fix: $rf, restored_at_head: $b, fix_rounds: $r, final_qa_verdict: $fin, phase_proved: $p, autonomy: $au, autonomy_set_before_first_run: $sb}')" \
      '["a deviation other than one missing file","keeping a deviation (the user decision path)","a deviation the Dev introduces itself (the seed is played by the scenario)","the fix cap (three failed rounds) and its escalation","a project larger than the greet.sh fixture"]'
  }
}

# QA checks again only what changed (R48): a project of two independent phases is
# built and passes QA, then a commit by the "user" touches one phase's script (the
# way a fix would), and QA runs again. The kernel's own answer just before QA
# (vbw next --json, .qa) names the phase to check again, its reason and the phases
# whose pass stands; the record then shows which phases QA really checked again.
# plan_seed: a spec of two requirements and a plan of two independent phases
# (not yet approved), so the planner's phase split and tier never decide the run.
plan_seed() {
  printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!"; without a name it prints "Hello, world!"\n- R2 [auto] ./farewell.sh Ana prints "Goodbye, Ana!"; without a name it prints "Goodbye, world!"\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null || return 1
  printf '[ "$(sh greet.sh Ana)" = "Hello, Ana!" ] && [ "$(sh greet.sh)" = "Hello, world!" ]\n' > test_greet.sh
  printf '[ "$(sh farewell.sh Ana)" = "Goodbye, Ana!" ] && [ "$(sh farewell.sh)" = "Goodbye, world!" ]\n' > test_farewell.sh
  printf '%s' '{"phases": [{"id": "P1", "title": "Greet", "reqs": ["R1"]}, {"id": "P2", "title": "Farewell", "reqs": ["R2"]}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "greet.sh", "reqs": ["R1"], "files": ["greet.sh"], "after": [], "tasks": ["greet.sh prints Hello, NAME! or Hello, world! without a name"]},
              {"id": "P2.1", "phase": "P2", "title": "farewell.sh", "reqs": ["R2"], "files": ["farewell.sh"], "after": [], "tasks": ["farewell.sh prints Goodbye, NAME! or Goodbye, world! without a name"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "test_greet.sh"], "files": ["test_greet.sh"]},
               {"id": "C2", "req": "R2", "run": ["sh", "test_farewell.sh"], "files": ["test_farewell.sh"]}],
    "rules": [{"req": "R1", "text": "a name is greeted", "check": "C1"}, {"req": "R1", "text": "no name greets the world", "check": "C1"},
              {"req": "R2", "text": "a name gets a farewell", "check": "C2"}, {"req": "R2", "text": "no name says goodbye to the world", "check": "C2"}]}' \
    | "$VBW" apply > /dev/null || return 1
  git add -A && git commit -qm "chore: plan" || return 1
}
# recheck_seed: the plan above, approved.
recheck_seed() { plan_seed && "$VBW" approve > /dev/null; }

scenario_recheck() {
  new_project
  # The user agreed the spec and approved a plan of two independent phases,
  # at standard rigor (an express phase is never QA'd, M4): the planner's
  # phase split and tier, which vary run to run, never decide this scenario.
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor standard > /dev/null && recheck_seed) \
    || { say "setup failed: could not seed the approved two-phase plan"; return 1; }
  fixture="greet.sh and farewell.sh, one phase each, plan approved by the user before the session; rigor standard; after QA passes, one commit changes greet.sh and QA runs again"
  seeded="" next_json="{}" qa_before="{}"
  start="/vbw:vibe"
  phase_qa() { jq -c '. as $r | [$r.phases[] | select(.milestone == $r.milestone.id) | {key: .id, value: (.qa.at // "")}] | from_entries' "$dir/.vbw/record.json"; }
  seed_change() {
    [ -z "$seeded" ] || return 1
    jq -e '. as $r | [$r.phases[] | select(.milestone == $r.milestone.id)] | length >= 2 and all(.[]; .qa.result == "pass") and $r.milestone.status != "shipped"' "$dir/.vbw/record.json" > /dev/null 2>&1 || return 1
    local f
    f=$(jq -r '. as $r | ([$r.phases[] | select(.milestone == $r.milestone.id)][0].id) as $p
      | [$r.plans[] | select(.phase == $p) | .files[] | select(endswith(".sh"))] as $mine
      | [$r.plans[] | select(.phase != $p) | .files[]] as $others
      | [$r.checks[] | .files[]] as $tests
      | [$mine[] | select(. as $x | ($others + $tests) | index($x) | not)][0] // empty' "$dir/.vbw/record.json" 2> /dev/null)
    [ -n "$f" ] && [ -f "$dir/$f" ] || return 1
    qa_before=$(phase_qa)
    printf '# reviewed by the user\n' >> "$dir/$f"
    git -C "$dir" commit -qm "chore: note in $f" -- "$f" || return 1
    (cd "$dir" && "$VBW" prove > /dev/null 2>&1) || true
    # The kernel's answer before QA runs again: what it will check and what stands.
    next_json=$(cd "$dir" && "$VBW" next --json 2> /dev/null | jq -c '.qa // {}')
    seeded="$f"
    say "changed $f after QA passed; the kernel says: $next_json"
    return 0
  }
  on_question() { seed_change || true; return 1; }
  on_idle() { seed_change; }
  done_yet() {
    [ -n "$seeded" ] || return 1
    jq -e --argjson b "$qa_before" '[.phases[] | select(.id | IN($b | keys[])) | select(.qa.at != $b[.id])] | length > 0' "$dir/.vbw/record.json" > /dev/null 2>&1
  }
  checks() {
    local after rechecked kept reason predicted standing passed=true same=false named=false
    [ -n "$seeded" ] || { say "FAIL the change was never made (QA did not pass for two phases)"; failed=1; }
    after=$(phase_qa)
    rechecked=$(jq -nc --argjson a "$qa_before" --argjson z "$after" '[$z | keys[] | select($z[.] != $a[.])]')
    kept=$(jq -nc --argjson a "$qa_before" --argjson z "$after" '[$z | keys[] | select($z[.] == $a[.])]')
    predicted=$(printf '%s' "$next_json" | jq -c '(.recheck // {}) | keys')
    standing=$(printf '%s' "$next_json" | jq -c '.standing // []')
    reason=$(printf '%s' "$next_json" | jq -r '[(.recheck // {})[] | join("; ")] | join(" | ")')
    say "checked again: $rechecked, kept: $kept, reason: $reason"
    [ "$rechecked" = "$predicted" ] && [ "$kept" = "$standing" ] && same=true
    case "$reason" in *changed*) named=true ;; esac
    expect "exactly one phase was checked again" [ "$(printf '%s' "$rechecked" | jq 'length')" -eq 1 ]
    expect "at least one phase kept its pass" [ "$(printf '%s' "$kept" | jq 'length')" -ge 1 ]
    expect "the phases QA checked again are the ones the kernel named, and the kept ones the ones it said stand" [ "$same" = true ]
    expect "the reason names what changed" [ "$named" = true ]
    # The change is a commit outside any plan, so QA may rightly fail it as a
    # deviation: what matters here is that QA judged the phase again.
    expect "QA judged the re-checked phase again and recorded a verdict" jq -e --argjson r "$rechecked" 'all(.phases[] | select(.id | IN($r[])); .qa.result == "pass" or .qa.result == "fail")' .vbw/record.json
    [ "$failed" -eq 0 ] || passed=false
    result_write recheck "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg f "${seeded:-}" --argjson r "$rechecked" --argjson k "$kept" --arg why "$reason" --argjson p "$predicted" --argjson s "$standing" \
        --argjson v "$(jq -c --argjson r "$rechecked" '[.phases[] | select(.id | IN($r[])) | {(.id): .qa.result}] | add // {}' .vbw/record.json 2> /dev/null || echo '{}')" \
        '{changed_file: $f, rechecked: $r, kept: $k, reason: $why, kernel_named_recheck: $p, kernel_named_standing: $s, new_verdict: $v}')" \
      '["a fix round of the fix loop (the change is a commit played by the scenario)","a project of more than two phases or phases that build on each other","the wording of what VBW tells the user (read by a person)","a change to a phase'"'"'s tests or plan"]'
  }
}

# Approval as a choice (R61): the user agreed the spec and the plan, and starts
# /vbw:vibe. VBW shows the contract and asks "Approve contract <fingerprint>?"
# with the options Approve and Not yet; the user presses Enter on the first one
# and never types /vbw:approve. The record and git then show the contract
# approved by VBW's own hook, once, for the fingerprint the question named.
scenario_approval() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor standard > /dev/null && plan_seed) \
    || { say "setup failed: could not seed the agreed spec and plan"; return 1; }
  fixture="greet.sh and farewell.sh, one phase each; spec and plan agreed with the user before the session, contract not yet approved; rigor standard"
  asked_fp="" asked_all="" options_shown=false pressed=false
  start="/vbw:vibe"
  # The contract's fingerprint (12 characters), from vbw show contract.
  contract_fp() { (cd "$dir" && "$VBW" show contract 2> /dev/null | sed -n '1s/^contract \([0-9a-f]*\) .*$/\1/p' | cut -c1-12); }
  approved_now() { (cd "$dir" && "$VBW" show contract 2> /dev/null | sed -n '1p' | grep '(approved)' > /dev/null); }
  on_question() {
    local s fp
    s=$(screen)
    fp=$(printf '%s' "$s" | grep -oE 'Approve contract [0-9a-f]{12}' | head -1 | grep -oE '[0-9a-f]{12}$')
    [ -n "$fp" ] || return 1
    # A fix that edits a test asks again, for another fingerprint, before its proof.
    [ -n "$asked_fp" ] || asked_fp=$fp
    case " $asked_all " in *" $fp "*) ;; *) asked_all="${asked_all:+$asked_all }$fp" ;; esac
    if printf '%s' "$s" | grep 'Approve' > /dev/null && printf '%s' "$s" | grep 'Not yet' > /dev/null; then options_shown=true; fi
    # The user presses Enter on the first option, Approve.
    l3 keys "$scenario" Enter
    pressed=true
    return 0
  }
  # Never type /vbw:approve: when VBW waits for approval, ask VBW again.
  on_idle() {
    [ "$(next_action)" = approve ] || return 1
    l3 type "$scenario" "/vbw:vibe"
  }
  done_yet() { [ "$pressed" = true ] && approved_now; }
  checks() {
    local passed=true now n named
    now=$(contract_fp)
    n=$(jq '[.decisions[] | select(.text | startswith("Contract approved"))] | length' "$dir/.vbw/record.json" 2> /dev/null || echo 0)
    named=$(jq -r '[.decisions[] | select(.text | startswith("Contract approved")) | .text] | join(" ")' "$dir/.vbw/record.json" 2> /dev/null)
    expect "the approval question named a fingerprint (${asked_fp:-none})" [ -n "$asked_fp" ]
    expect "the question showed Approve and Not yet" [ "$options_shown" = true ]
    expect "the last question named the contract's fingerprint ($now)" [ "${asked_all##* }" = "$now" ]
    expect "the contract is approved" approved_now
    # One approval per question asked, each naming its own question's fingerprint, never twice.
    local fp each=true asked_n=0
    for fp in $asked_all; do
      asked_n=$((asked_n + 1))
      [ "$(printf '%s' "$named" | grep -o "($fp)" | wc -l | tr -d ' ')" -eq 1 ] || each=false
    done
    expect "one 'Contract approved' decision per question asked ($n for $asked_n: $asked_all)" [ "$n" -eq "$asked_n" ]
    case "$named" in *"($asked_fp)"*) named=true ;; *) named=false ;; esac
    expect "the first decision names the fingerprint the first question named" [ "$named" = true ]
    expect "each question's fingerprint is named by exactly one approval" [ "$each" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write approval "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg fp "${asked_fp:-}" --argjson shown "$options_shown" --argjson e "$pressed" --argjson ok "$named" --argjson each "$each" --argjson n "$n" --argjson asked "$asked_n" \
        '{fingerprint: $fp, choice_shown: $shown, approved_by_enter: ($e and $ok and $each and $n == $asked), decisions: $n}')" \
      '["the answer Not yet or the user'"'"'s own words","an approval after the contract changed under the question","typing /vbw:approve (covered by the kernel tests)","a project larger than the greet.sh and farewell.sh fixture"]'
  }
}

# R62: the interview asks once whether VBW may look for tools. The user answers
# yes in the real interface; the scenario stops the search at the proposed list
# (Not yet), so nothing is installed. Facts come from the record, git and the
# session logs, never screen text.
scenario_tools() {
  new_project
  fixture="greet.sh, one small milestone on an empty README project; the interview asks the tools offer; the user answers yes, then Not yet at the proposed list"
  start=$GREET
  offers=0 answered=false listed=false declined=false before_clean=""
  # Files an install would leave in the project, outside .vbw.
  install_traces() { (cd "$dir" && git status --porcelain -- . ":(exclude).vbw" | grep -v 'greet\|farewell' | grep -ciE 'skills|\.claude|\.agents|package|lock|requirements|eslint|prettier|shellcheck|\.pre-commit' || true); }
  # `npx skills add` commands Claude ran, from the session transcripts.
  install_commands() {
    local f n=0 c
    while IFS= read -r f; do
      c=$(jq -s '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
        | (.input.command // "") | select(test("skills add|npm (i|install)|pip install|brew install"))] | length' "$f" 2> /dev/null || echo 0)
      n=$((n + c))
    done < <(transcripts)
    echo "$n"
  }
  on_question() {
    local s n i
    s=$(screen)
    # Matched on its option, which the screen never wraps.
    if printf '%s' "$s" | grep -E '[0-9]+\. Yes, look' > /dev/null; then
      offers=$((offers + 1))
      # "No, skip it" is the first option: the user moves to "Yes, look" and presses Enter.
      n=$(printf '%s' "$s" | grep -E '[0-9]+\. Yes' | grep -oE '[0-9]+' | head -1)
      for ((i = 1; i < ${n:-2}; i++)); do l3 keys "$scenario" Down; done
      l3 keys "$scenario" Enter
      answered=true
      sleep 3
      return 0
    fi
    if [ "$answered" = true ] && printf '%s' "$s" | grep -E '[0-9]+\. Not yet' > /dev/null && ! printf '%s' "$s" | grep -E 'Approve contract|Ship' > /dev/null; then
      listed=true
      # Nothing may be installed while the list waits for the answer.
      before_clean=$([ "$(install_traces)" -eq 0 ] && [ "$(install_commands)" -eq 0 ] && echo true || echo false)
      n=$(printf '%s' "$s" | grep -E '[0-9]+\. Not yet' | grep -oE '[0-9]+' | head -1)
      for ((i = 1; i < n; i++)); do l3 keys "$scenario" Down; done
      l3 keys "$scenario" Enter
      declined=true
      return 0
    fi
    return 1
  }
  # The stored answer, as `vbw tools --json` reports it (project.tools in the record).
  stored() { (cd "$dir" && "$VBW" tools --json 2> /dev/null); }
  done_yet() { [ "$declined" = true ]; }
  checks() {
    local passed=true ans at again=false inst
    ans=$(stored | jq -r '.answer // "none"')
    at=$(stored | jq -r '.at // ""')
    [ "$offers" -le 1 ] || again=true
    inst=$(( $(install_traces) + $(install_commands) ))
    expect "the offer was shown (${offers})" [ "$offers" -ge 1 ]
    expect "the stored answer is yes ($ans, $at)" [ "$ans" = yes ]
    expect "it was not asked again (offers seen: $offers)" [ "$again" = false ]
    expect "the proposed list was shown" [ "$listed" = true ]
    expect "nothing was installed before the list was approved" [ "$before_clean" = true ]
    expect "nothing was installed after Not yet ($inst)" [ "$inst" -eq 0 ]
    [ "$failed" -eq 0 ] || passed=false
    result_write tools "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg a "$ans" --argjson again "$again" --argjson b "$([ "$before_clean" = true ] && echo false || echo true)" --argjson l "$listed" \
        '{answer: $a, asked_again: $again, installed_before_approval: $b, list_shown: $l}')" \
      '["the answer no","approving the list and the install itself","the question in a second session or worktree (covered by the store tests)","a project with a real stack: the fixture is one shell script"]'
  }
}

# The old VBW 1 folder (R65): the interview reviews it right after the level
# answer, recommends converting or starting fresh with the recommended option
# first, and asks once. `legacy`: the user picks the option that is NOT
# recommended (Start fresh); nothing is converted and the folder is untouched.
# `nolegacy`: a project without a folder is never asked. Facts come from the
# record, git and the session transcript, never screen text.

# Every question of the main session, in order, one JSON object per line:
# {question, options: [label...]}.
asked_questions() {
  local t
  t=$(transcripts | grep -v '/subagents/' | sort)
  [ -n "$t" ] || return 0
  printf '%s\n' "$t" | xargs cat 2> /dev/null | jq -c 'select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use" and .name == "AskUserQuestion") | .input.questions[]?
    | {question: .question, options: [.options[]?.label]}' 2> /dev/null
}

# The old-folder question: the one whose options offer Convert and Start fresh.
is_legacy_question='(.options | map(test("^Convert"; "i")) | any) and (.options | map(test("fresh"; "i")) | any)'

# Plays the interview as a user who accepts VBW's first option everywhere,
# except that the old-folder question gets Start fresh (the second option).
legacy_user() {
  purpose_done=0 followups=0 unmatched=0
  on_question() {
    local scr
    scr=$(current_question)
    if printf '%s' "$scr" | grep -iE '[0-9]+\. Start fresh' > /dev/null; then
      pick_label 'Start fresh'
    elif printf '%s' "$scr" | grep -iE 'proficiency|how should I explain|how involved|private on this machine|Ready to submit' > /dev/null; then
      return 1
    elif [ "$(interview_pending)" = none ]; then
      return 1
    elif [ "$purpose_done" -eq 0 ]; then
      purpose_done=1; answer_other "a little greeting tool for my grandmother, who is learning English."
    else
      followups=$((followups + 1)); answer_other "greet.sh with a name says Hello and the name, like Hello, Ana!; on its own it says Hello, world!. Nothing more."
    fi
  }
  on_idle() {
    [ "$(interview_pending)" = keep ] || return 1
    if [ "$purpose_done" -eq 0 ]; then
      last_reply | grep -iE 'building|for whom|who.*(for|use)' > /dev/null || return 1
      purpose_done=1
      l3 type "$scenario" "a little greeting tool for my grandmother, who is learning English."
    else
      last_reply | grep '?' > /dev/null || return 1
      followups=$((followups + 1))
      l3 type "$scenario" "greet.sh with a name says Hello and the name, like Hello, Ana!; on its own it says Hello, world!. Nothing more."
    fi
  }
  done_yet() { (cd "$dir" && "$VBW" interview --json 2> /dev/null | jq -e '.interviewed == true and .kept != null') > /dev/null 2>&1; }
}

scenario_legacy() {
  new_project
  fixture="greet.sh from scratch; a VBW 1 folder with one finished plan whose files exist; the user picks Start fresh, the option that is not recommended"
  start="/vbw:vibe I want to build a small greeting tool. One small milestone."
  mkdir -p "$dir/.vbw-planning/phases/01-greeting"
  printf '# Greeter\n\nA tiny command-line greeter.\n' > "$dir/.vbw-planning/PROJECT.md"
  printf '# State\n\nPhase 1 done.\n' > "$dir/.vbw-planning/STATE.md"
  printf -- '---\nphase: 1\nplan: 1\nfiles_modified:\n  - README.md\n---\n# Plan\n' > "$dir/.vbw-planning/phases/01-greeting/01-01-PLAN.md"
  printf '# Summary\n\nDone.\n' > "$dir/.vbw-planning/phases/01-greeting/01-01-SUMMARY.md"
  git -C "$dir" add -A && git -C "$dir" commit -qm "chore: VBW 1 plan"
  base=$(git -C "$dir" rev-parse HEAD)
  legacy_user
  checks() {
    local passed=true rec chosen conv=false first=false before=false completed=false same=false again=false n lq files new
    rec=$(cd "$dir" && "$VBW" legacy review 2> /dev/null | jq -r '.recommendation // "none"')
    chosen=$(jq -r '.project.legacy.choice // "none"' "$dir/.vbw/record.json" 2> /dev/null)
    jq -e 'has("converted")' "$dir/.vbw/record.json" > /dev/null 2>&1 && conv=true
    [ "$(transcripts | grep -v '/subagents/' | xargs cat 2> /dev/null | jq -s '[.[] | select(.type == "assistant") | .message.content[]?
      | select(.type == "tool_use" and ((.input | tostring) | test("vbw:convert|legacy done")))] | length')" -gt 0 ] && conv=true
    lq=$(asked_questions | jq -c "select($is_legacy_question)")
    n=$(printf '%s\n' "$lq" | grep -c . || true)
    [ "$n" -le 1 ] || again=true
    printf '%s\n' "$lq" | head -1 | jq -e '(.options[0] | test("^Convert"; "i") and test("Recommended"; "i")) and (.options[1] | test("fresh"; "i"))' > /dev/null 2>&1 && first=true
    # The old-folder question comes after the level question and before every other one.
    asked_questions | jq -s -e "(map(.question | test(\"proficiency\"; \"i\")) | index(true)) as \$l
      | (map($is_legacy_question) | index(true)) as \$g
      | (map(.question | test(\"explain things|how involved|building|private\"; \"i\")) | index(true)) as \$o
      | \$l != null and \$g != null and \$l < \$g and (\$o == null or \$g < \$o)" > /dev/null 2>&1 && before=true
    done_yet && completed=true
    (cd "$dir" && git diff --quiet "$base" -- .vbw-planning && [ -z "$(git status --porcelain -- .vbw-planning)" ]) && same=true
    expect "the review recommended converting ($rec)" [ "$rec" = convert ]
    expect "the question came after the level answer and before any other" [ "$before" = true ]
    expect "the recommended option (Convert) was first, Start fresh second" [ "$first" = true ]
    expect "the user's choice was recorded as fresh ($chosen)" [ "$chosen" = fresh ]
    expect "nothing was converted" [ "$conv" = false ]
    expect "the VBW 1 folder is unchanged" [ "$same" = true ]
    expect "it was asked once ($n)" [ "$again" = false ]
    expect "the interview was completed" [ "$completed" = true ]
    # A second session asks neither the old-folder question again nor changes the choice.
    files=$(transcripts | sort)
    l3 start "$scenario" "$dir" > /dev/null
    if screen | grep "Type \/reload-skills" > /dev/null; then l3 type "$scenario" "/reload-skills"; sleep 5; fi
    l3 type "$scenario" "/vbw:vibe Also let greet.sh take --shout, printing the greeting in capital letters."
    default_idle
    l3 keys "$scenario" Escape; sleep 2; default_idle
    l3 stop "$scenario"
    new=$(comm -13 <(printf '%s\n' "$files") <(transcripts | sort) | grep -v '/subagents/' || true)
    if [ -n "$new" ] && printf '%s\n' "$new" | xargs cat 2> /dev/null | jq -e 'select(.type == "assistant") | .message.content[]?
      | select(.type == "tool_use" and .name == "AskUserQuestion") | .input.questions[]?
      | select(.options | map(.label) | map(test("fresh"; "i")) | any)' > /dev/null 2>&1; then again=true; fi
    [ "$(jq -r '.project.legacy.choice // "none"' "$dir/.vbw/record.json" 2> /dev/null)" = fresh ] || again=true
    expect "a second session did not ask again" [ "$again" = false ]
    [ "$failed" -eq 0 ] || passed=false
    result_write legacy "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg r "$rec" --arg c "$chosen" --argjson b "$before" --argjson f "$first" --argjson cv "$conv" --argjson s "$same" --argjson a "$again" --argjson ic "$completed" \
        '{recommendation: $r, choice: $c, review_before_other_questions: $b, recommended_option_first: $f, converted: $cv, old_folder_unchanged: $s, asked_again: $a, interview_completed: $ic}')" \
      '["the choice Convert and the conversion itself","a folder the review recommends starting fresh for","a real VBW 1 project: the fixture has one phase and one plan","how the review reads at each level and depth (R41, human)"]'
  }
}

scenario_nolegacy() {
  new_project
  fixture="greet.sh from scratch; a project without a VBW 1 folder; the interview is answered with VBW's first options"
  start="/vbw:vibe I want to build a small greeting tool. One small milestone."
  legacy_user
  checks() {
    local passed=true asked=false completed=false none=false
    asked_questions | jq -e "select($is_legacy_question)" > /dev/null 2>&1 && asked=true
    [ "$(cd "$dir" && "$VBW" legacy review 2> /dev/null | jq -r '.legacy')" = false ] && none=true
    [ "$(jq -r '.project.legacy // "none"' "$dir/.vbw/record.json" 2> /dev/null)" = none ] || asked=true
    done_yet && completed=true
    expect "the project has no VBW 1 folder (review says legacy false)" [ "$none" = true ]
    expect "no old-folder question was asked" [ "$asked" = false ]
    expect "the interview was completed" [ "$completed" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write nolegacy "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson a "$asked" --argjson c "$completed" '{asked_legacy: $a, interview_completed: $c}')" \
      '["a project with a leftover folder that is not a VBW 1 plan","a second session","how the interview reads (R41, human)"]'
  }
}

# The VBW panel (R51, R53, R55, R58): the real app in a wide window (200 columns, the
# panel opens by itself from 144 up) on a project with two phases, one passed and one
# whose plan waits for the user's approval. The panel is read from the screen, as the
# user sees it: the milestone, the progress, what VBW is doing, what it needs from the
# user, the cost line, and an estimate or the plain "no basis yet" (a new clone has no
# finished steps). Then the user turns the sound off, closes the panel, and starts the
# app again: the panel stays closed and the sound stays off. The one place the screen is
# the evidence is the panel itself: what it shows is what the requirement asks for.
panel_seed() {
  printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!"; without a name it prints "Hello, world!"\n- R2 [auto] ./farewell.sh Ana prints "Goodbye, Ana!"; without a name it prints "Goodbye, world!"\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null || return 1
  printf '#!/bin/sh\necho "Hello, ${1:-world}!"\n' > greet.sh
  printf '[ "$(sh greet.sh Ana)" = "Hello, Ana!" ] && [ "$(sh greet.sh)" = "Hello, world!" ]\n' > test_greet.sh
  # Once farewell.sh exists its check takes 20 s, so the Dev who builds it works for minutes
  # and its Timeline lane reads a time in minutes (#696); red stays quick.
  printf '[ -f farewell.sh ] || exit 1\nsleep 20\n[ "$(sh farewell.sh Ana)" = "Goodbye, Ana!" ] && [ "$(sh farewell.sh)" = "Goodbye, world!" ]\n' > test_farewell.sh
  git add -A && git commit -qm "feat: greet.sh and its test" || return 1
  panel_apply "farewell.sh prints Goodbye, NAME! or Goodbye, world! without a name" || return 1
  git add -A && git commit -qm "chore: plan" || return 1
  # The user approved the plan and the first phase was built and checked earlier;
  # the second phase's plan was then reworded and waits for approval again.
  "$VBW" approve > /dev/null && { "$VBW" prove > /dev/null 2>&1 || true; } && "$VBW" qa record P1 pass standard > /dev/null || return 1
  panel_apply "farewell.sh says Goodbye, NAME! (or Goodbye, world! with no name) and exits 0" || return 1
  # Applying a plan starts the phases over: phase 1's verdict is recorded again.
  "$VBW" qa record P1 pass standard > /dev/null || return 1
  # A What's next recommendation with rows (T160): Mission Control once opened empty
  # in the real window when the Now tab drew rows, and nothing else caught it.
  printf '%s' '{"top": {"text": "Refunds for paid orders", "reason": "Customers ask for it most this month.", "size": "small"}, "runners": [{"text": "Gift cards", "size": "large"}, {"text": "Dark mode", "size": "medium"}]}' \
    | "$VBW" recommend > /dev/null || return 1
}

# panel_apply TASK: apply the two-phase plan, P2.1 with the task TASK.
panel_apply() {
  jq -n --arg t "$1" '{"phases": [{"id": "P1", "title": "Greet", "reqs": ["R1"]}, {"id": "P2", "title": "Farewell", "reqs": ["R2"]}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "greet.sh", "reqs": ["R1"], "files": ["greet.sh"], "after": [], "tasks": ["greet.sh prints Hello, NAME! or Hello, world! without a name"]},
              {"id": "P2.1", "phase": "P2", "title": "farewell.sh", "reqs": ["R2"], "files": ["farewell.sh"], "after": ["P1.1"], "tasks": [$t]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "test_greet.sh"], "files": ["test_greet.sh"]},
               {"id": "C2", "req": "R2", "run": ["sh", "test_farewell.sh"], "files": ["test_farewell.sh"]}],
    "rules": [{"req": "R1", "text": "a name is greeted", "check": "C1"}, {"req": "R1", "text": "no name greets the world", "check": "C1"},
              {"req": "R2", "text": "a name gets a farewell", "check": "C2"}, {"req": "R2", "text": "no name says goodbye to the world", "check": "C2"}]}' \
    | "$VBW" apply > /dev/null
}

scenario_panel() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor standard > /dev/null && panel_seed) \
    || { say "setup failed: could not seed the two-phase project"; return 1; }
  fixture="greet.sh and farewell.sh, two phases: the first passed QA and its requirement R1 is proven, the second plan was reworded after approval and waits for it again; no finished steps in the clone (so no estimate basis); window 200 columns wide, resized to 200x24 and to 60x40 with the needs-you line up and again while the build's helpers work; the user then approves and the build runs; after it the user clicks the Timeline tab and its lanes are read at 200x60 and at 60x40 (#696); the farewell check waits 20 s once farewell.sh exists, so the Dev's lane runs to minutes"
  start="/vbw:panel"
  facts="{}"
  panel_text() { screen | sed 's/[[:space:]][[:space:]]*/ /g'; }
  # The panel's text once it shows every phrase given (it redraws within seconds);
  # whatever is there after 40 s otherwise.
  panel_wait() {
    local i s p all
    for ((i = 0; i < 40; i++)); do
      s=$(panel_text) all=1
      for p in "$@"; do case "$s" in *"$p"*) ;; *) all=0 ;; esac; done
      [ "$all" -eq 1 ] && break
      sleep 1
    done
    printf '%s' "$s"
  }
  has() { case "$1" in *"$2"*) echo true ;; *) echo false ;; esac; }
  # The panel's close button is the last column of the first row.
  close_panel() { l3 click "$scenario" "$(($(tmux display -p -t "vbw-l3-$scenario" '#{window_width}') - 1))" 1; }
  observe() {
    local s mid snd by_itself
    # The panel opens by itself in a wide window (opened_by_itself says whether it did); if
    # not, the user opens it with /vbw-panel so the rest of the run can go on.
    if [ "$(has "$(panel_wait "Working on")" "Working on")" = false ]; then
      by_itself=false
      l3 type "$scenario" "/vbw-panel"
    else by_itself=true; fi
    mid=$(jq -r '.milestone.id' "$dir/.vbw/record.json")
    # The plan was approved, then reworded: Mission Control says it changed (detail.changed).
    s=$(panel_wait "Working on $mid:" "1 of 2 requirements done" "Your plan changed since you approved it" "Refunds for paid orders")
    printf '%s\n' "$s" > "$dir.panel.screen.txt"
    facts=$(jq -n --arg m "$(has "$s" "Working on $mid:")" --arg p "$(has "$s" "1 of 2 requirements done")" \
      --arg d "$(has "$s" "Waiting since")" --arg n "$(has "$s" "Your plan changed since you approved it")" \
      --arg t "$(has "$s" "Now")$(has "$s" "Plan")$(has "$s" "Proof")$(has "$s" "Timeline")" --arg r "$(has "$s" "Refunds for paid orders")" \
      --arg c "$(case "$s" in *"has cost \$"*|*"cost so far is not available"*) echo true ;; *) echo false ;; esac)" \
      --arg e "$(case "$s" in *"No estimate yet"*) echo "no basis yet" ;; *"min left"*) echo "approximate time" ;; *) echo "" ;; esac)" \
      --arg o "$by_itself" '{opened_by_itself: ($o == "true"), milestone_shown: ($m == "true"), progress_shown: ($p == "true"), doing_shown: ($d == "true"), need_shown: ($n == "true"),
        tabs_shown: ($t == "truetruetruetrue"), next_row_shown: ($r == "true"),
        need_text: (if $n == "true" then "Your plan changed since you approved it: please review the changes and approve it again." else "" end), cost_shown: ($c == "true"), estimate_shown: $e}')
    # The sound switch, as the user types it; the panel's own line follows within seconds.
    l3 type "$scenario" "/vbw-sound off"
    snd=$(panel_wait "Sound is off.")
    facts=$(jq -c --arg s "$(has "$snd" "Sound is off.")" '. + {sound_shown_off: ($s == "true")}' <<< "$facts")
    comms
    timeline
  }
  # #696: the Timeline tab after the build, in the wide window and in the narrow one.
  # Each lane is one screen line: a name led by its role (cut in a narrow pane), its bar
  # and its time. A lane wrapped onto two lines leaves a line under it with a bar or a
  # time and no name. Echoes true or false, then the lane lines, as the screen at $1
  # columns by $2 rows shows them (the user clicks the Timeline tab until they show).
  LANE='^ *(arch|lead|dev|qa|scou|debu|docs|agen)[^█]* (█)+ [0-9]+ (min [0-9]+ s|min|s) *$'
  timeline_lanes() {
    local sess="vbw-l3-$scenario" s rows row pre i
    tmux resize-window -t "$sess" -x "$1" -y "$2" 2> /dev/null
    sleep 8
    for ((i = 0; i < 30; i++)); do
      s=$(screen)
      # The panel's own text: what is between its borders.
      rows=$(printf '%s\n' "$s" | sed -n 's/^[^│]*│//p' | sed 's/│.*$//')
      printf '%s\n' "$rows" | grep -E "$LANE" > /dev/null && break
      row=$(printf '%s\n' "$s" | grep -n '\[ Timeline \]\|\[ Time \]' | head -1 | cut -d: -f1)
      pre=$(printf '%s\n' "$s" | grep '\[ Timeline \]\|\[ Time \]' | head -1 | sed 's/\[ Time.*//')
      [ -n "$row" ] && l3 click "$scenario" "$(($(printf '%s' "$pre" | LC_ALL=en_US.UTF-8 wc -m) + 4))" "$row"
      sleep 2
    done
    printf '%s\n' "$s" > "$dir.panel.timeline.$1x$2.screen.txt"
    # From the first lane to the first blank line (the runs list and the sparkline come
    # after one): every line is a lane, or the step's own line that ends the lanes.
    printf '%s\n' "$rows" | LC_ALL=en_US.UTF-8 awk -v lane="$LANE" '
      !on && $0 ~ lane { on = 1 }
      on && !done {
        if ($0 ~ lane) { n++; out = out "\n" $0; next }
        if ($0 ~ /^ *$/) { done = 1; next }
        if ($0 ~ /█/ || $0 ~ /^ *[0-9]* *(min|s)?( [0-9]+ s)? *$/) bad = 1
        done = 1
      }
      END { print ((n > 0 && !bad) ? "true" : "false") out }'
  }
  timeline() {
    local wide narrow
    wide=$(timeline_lanes 200 60)
    narrow=$(timeline_lanes "$NARROW_COLUMNS" 40)
    tmux resize-window -t "vbw-l3-$scenario" -x 200 -y 60 2> /dev/null
    [ "$(printf '%s\n' "$wide" | head -1)" = true ] || say "Timeline, wide window: a lane is not one line" >&2
    [ "$(printf '%s\n' "$narrow" | head -1)" = true ] || say "Timeline, narrow window: a lane is not one line" >&2
    facts=$(jq -c --arg w "$wide" --arg n "$narrow" '
      def lanes: split("\n") | .[1:] | map(sub(" +$"; ""));
      . + {timeline_one_line_wide: (($w | split("\n") | .[0]) == "true"), timeline_one_line_narrow: (($n | split("\n") | .[0]) == "true"),
           timeline_lanes_wide: ($w | lanes), timeline_lanes_narrow: ($n | lanes),
           timeline_time_in_minutes: ([$w, $n | lanes[] | test(" [0-9]+ min")] | any)}' <<< "$facts")
  }
  # R189: Comms in the real window. Resize the window, wait for the redraw, and
  # read what is drawn: the prompt box must still be whole (two borders of the full
  # width and its text line on screen) and Comms must still be there, once.
  # Echoes "ok" or what was wrong. $1 columns, $2 rows, $3 the text Comms must show
  # exactly once (none: Mission Control fills the window and the pane's bottom edge must show).
  fits_window() {
    local sess="vbw-l3-$scenario" s border line
    tmux resize-window -t "$sess" -x "$1" -y "$2" 2> /dev/null || { echo "could not resize"; return; }
    sleep 8
    s=$(tmux capture-pane -t "$sess" -p)
    printf '%s\n' "$s" > "$dir.panel.$1x$2.last.txt"
    line=$(printf '─%.0s' $(seq 1 "$1"))
    border=$(printf '%s\n' "$s" | grep -cxF "$line")
    [ "$border" -ge 2 ] || { echo "the prompt box is not whole at $1x$2 ($border full-width borders)"; return; }
    printf '%s\n' "$s" | grep '❯' > /dev/null || { echo "no prompt line at $1x$2"; return; }
    if [ -n "$3" ]; then
      [ "$(printf '%s\n' "$s" | grep -cF "$3")" -eq 1 ] || { echo "'$3' is not drawn exactly once at $1x$2"; return; }
    else
      printf '%s\n' "$s" | grep '^╰.*╯$' > /dev/null || { echo "Mission Control's bottom edge is not on screen at $1x$2"; return; }
    fi
    printf '%s\n' "$s" > "$dir.panel.$1x$2.screen.txt"
    echo ok
  }
  # R199: true when every one of the six tabs is drawn whole as '[ Name ]' (the full
  # name or its short form) in the screen captured at $1 columns by $2 rows.
  tabs_whole() {
    local t
    t=$(sed 's/[[:space:]][[:space:]]*/ /g' "$dir.panel.$1x$2.last.txt" 2> /dev/null)
    case "$t" in *"[ Now ]"*) ;; *) echo false; return ;; esac
    case "$t" in *"[ Plan ]"*) ;; *) echo false; return ;; esac
    case "$t" in *"[ Proof ]"*) ;; *) echo false; return ;; esac
    case "$t" in *"[ Timeline ]"* | *"[ Time ]"*) ;; *) echo false; return ;; esac
    case "$t" in *"[ Sessions ]"* | *"[ Sess ]"*) ;; *) echo false; return ;; esac
    case "$t" in *"[ Settings ]"* | *"[ Set ]"*) ;; *) echo false; return ;; esac
    echo true
  }
  # Both windows in turn, then the first size back. Echoes "short narrow tabs_short
  # tabs_narrow" as true/false.
  spill_checks() {
    local a b ta tb
    a=$(fits_window 200 "$SHORT_ROWS" "$1")
    ta=$(tabs_whole 200 "$SHORT_ROWS")
    b=$(fits_window "$NARROW_COLUMNS" 40 "")
    tb=$(tabs_whole "$NARROW_COLUMNS" 40)
    tmux resize-window -t "vbw-l3-$scenario" -x 200 -y 60 2> /dev/null; sleep 6
    [ "$a" = ok ] || say "short window: $a" >&2
    [ "$b" = ok ] || say "narrow window: $b" >&2
    echo "$([ "$a" = ok ] && echo true || echo false) $([ "$b" = ok ] && echo true || echo false) $ta $tb"
  }
  SHORT_ROWS=24 NARROW_COLUMNS=60
  # The helper rows of Comms (the left 120 columns, under the "VBW ▸" line): "role label" per row.
  crew_rows() {
    screen | cut -c1-120 | awk '/VBW ▸/ { on = 1; next } on && /^─/ { on = 0 } on' \
      | grep -oE '(^|[[:space:]])(architect|lead|dev|qa|scout|debugger|docs) {2,}[^ ]+' | sed 's/^[[:space:]]*//; s/  */ /g'
  }
  comms() {
    local shown cleared=false pair sh nr i s
    # 1. The needs-you line stands while the plan waits for approval.
    s=$(panel_wait "⚑ VBW needs you")
    shown=$(has "$s" "⚑ VBW needs you")
    pair=$(spill_checks "⚑ VBW needs you")
    read -r sh nr _ <<< "$pair"
    # 2. The user approves; the line must go once the gate is answered.
    l3 type "$scenario" "/vbw:approve"
    for ((i = 0; i < 40; i++)); do
      sleep 3
      if screen | grep 'Enter to select\|Ready to submit' > /dev/null; then answer_recommended; continue; fi
      if ! screen | grep "VBW needs you" > /dev/null && [ "$(next_action)" != approve ]; then cleared=true; break; fi
    done
    # 3. The build: helpers come and go on Comms. A row seen once, then gone while the
    # top line counts "N done", is a finished helper that left. The window is also
    # resized once while helpers are at work.
    local seen_rows="" cur r started=false done_gone=false how="" crew_sh=true crew_nr=true crew_ts=false crew_tn=false crew_checked=false act
    local waiting=0
    for ((i = 0; i < 400; i++)); do
      sleep 3
      if screen | grep 'Enter to select\|Ready to submit' > /dev/null; then answer_recommended; continue; fi
      act=$(next_action)
      # Claude Code goes on to the build by itself after an approval; if it has not within 45 s, the user asks.
      if [ "$started" = false ] && [ "$act" = build ] && ! screen | grep 'esc to interrupt' > /dev/null; then
        waiting=$((waiting + 1))
        if [ "$waiting" -ge 15 ]; then l3 type "$scenario" "/vbw:vibe"; waiting=0; fi
      fi
      cur=$(crew_rows)
      screen > "$dir.panel.build.last.txt"
      if [ -n "$cur" ]; then
        started=true
        while IFS= read -r r; do case "$seen_rows" in *"|$r|"*) ;; *) seen_rows="$seen_rows|$r|" ;; esac; done <<< "$cur"
        if [ "$crew_checked" = false ]; then
          crew_checked=true
          pair=$(spill_checks "VBW ▸")
          read -r crew_sh crew_nr crew_ts crew_tn <<< "$pair"
          continue
        fi
      fi
      if [ -n "$seen_rows" ] && [ "$done_gone" = false ] && screen | cut -c1-120 | grep -E 'VBW ▸.* [1-9][0-9]* done' > /dev/null; then
        while IFS= read -r r; do
          [ -n "$r" ] || continue
          case "$cur" in *"$r"*) ;; *) done_gone=true how="a helper's row left while the top line counted it done" ;; esac
        done <<< "$(printf '%s' "$seen_rows" | sed 's/^|//; s/|$//; s/||/\
/g')"
      fi
      if [ "$started" = true ] && [ "$act" != build ] && [ "$act" != run ]; then
        if [ "$done_gone" = false ] && ! screen | cut -c1-120 | grep 'VBW ▸' > /dev/null; then done_gone=true how="the run ended and the crew left Comms"; fi
        break
      fi
    done
    facts=$(jq -c --arg sh "$shown" --argjson cl "$cleared" --argjson dg "$done_gone" --arg how "$how" --argjson st "$started" \
      --argjson s1 "$sh" --argjson n1 "$nr" --argjson s2 "$crew_sh" --argjson n2 "$crew_nr" --argjson ts "$crew_ts" --argjson tn "$crew_tn" \
      --argjson sr "$SHORT_ROWS" --argjson nc "$NARROW_COLUMNS" \
      '. + {need_line_shown: ($sh == "true"), need_line_cleared: $cl, helper_seen_working: $st, helper_done_cleared: $dg, helper_done_how: $how,
            no_spill_short: ($s1 and $s2), no_spill_narrow: ($n1 and $n2), helper_line_short: $s2, tabs_whole_short: $ts, tabs_whole_narrow: $tn, short_rows: $sr, narrow_columns: $nc}' <<< "$facts")
  }
  done_yet() { observe; return 0; }
  checks() {
    local snd_back before
    # The first session's panel: close it as a person does, then start the app again.
    l3 start "$scenario" "$dir" > /dev/null
    if screen | grep "Type \/reload-skills" > /dev/null; then l3 type "$scenario" "/reload-skills"; sleep 5; fi
    panel_wait "Working on" > /dev/null
    close_panel
    sleep 5
    before=$(has "$(panel_text)" "Working on")
    l3 stop "$scenario"
    l3 start "$scenario" "$dir" > /dev/null
    if screen | grep "Type \/reload-skills" > /dev/null; then l3 type "$scenario" "/reload-skills"; sleep 5; fi
    sleep 10
    # Closed by the user: still closed after the restart. The sound was turned off: the switch says it is back on.
    l3 type "$scenario" "/vbw-sound"; sleep 4
    snd_back=$(panel_text)
    facts=$(jq -c --arg b "$before" --arg c "$(has "$snd_back" "Working on")" --arg o "$(has "$snd_back" "sound is on")" \
      '. + {closed_by_click: ($b == "false"), closed_stays_closed: ($b == "false" and $c == "false"), sound_toggle_persisted: ($o == "true")}' <<< "$facts")
    sleep 2
    l3 stop "$scenario"
    local k passed
    for k in opened_by_itself milestone_shown progress_shown doing_shown need_shown tabs_shown next_row_shown cost_shown sound_shown_off closed_by_click closed_stays_closed sound_toggle_persisted need_line_shown need_line_cleared helper_seen_working helper_done_cleared no_spill_short no_spill_narrow helper_line_short tabs_whole_short tabs_whole_narrow timeline_one_line_wide timeline_one_line_narrow timeline_time_in_minutes; do
      expect "the panel: $k" jq -e --arg k "$k" '.[$k] == true' <<< "$facts"
    done
    expect "the panel shows an estimate or the plain 'no basis yet'" jq -e '.estimate_shown | length > 0' <<< "$facts"
    passed=$(jq -r '[.opened_by_itself, .milestone_shown, .progress_shown, .doing_shown, .need_shown, .tabs_shown, .next_row_shown, .cost_shown, .sound_shown_off, .closed_by_click, .closed_stays_closed, .sound_toggle_persisted, .need_line_shown, .need_line_cleared, .helper_seen_working, .helper_done_cleared, .no_spill_short, .no_spill_narrow, .helper_line_short, .tabs_whole_short, .tabs_whole_narrow, .timeline_one_line_wide, .timeline_one_line_narrow, .timeline_time_in_minutes, (.estimate_shown | length > 0)] | all' <<< "$facts")
    [ "$passed" = true ] || failed=1
    result_write panel "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      '["the sound itself (nothing was heard: the run only checks the switch)","what a person reads at a glance: wording and layout are judged on the screen text, not by a reader","no spill is read from the visible tmux screen after a resize (prompt box whole, Comms drawn once), not from a real terminal'"'"'s scrollback","one short window (200 columns, 24 rows) and one narrow window (60 columns, 40 rows), with the needs-you line and with helpers at work; no other size","Comms in the 60-column window: Mission Control fills that window and Comms'"'"' own line is not on screen there (seen in the run, not judged), so the narrow check holds the prompt box and the pane'"'"'s bottom edge only","the tab names read as whole [ Name ] buttons in the visible screen text, not their look or other sizes","Mission Control'"'"'s own rows and tabs at those sizes (held by tests/panel/r189/containment.test.mjs, L1)","figure counts and the motion levels (full, calm, off)","a failed helper, a celebration and a ship in the real window","a milestone shipped before the recommendation (the seed stores the recommendation on an active milestone)","a time estimate with a number","Timeline lanes only from this run'"'"'s real helpers and their real times: no seeded run, no other size than 200x60 and 60x40, and lane times of an hour or more"]'
  }
}

# steptime (R190, phase P148): the step's end time in the real window. A project
# with two plans and six slow real checks, no step history at first. Phase 1: the
# scenario starts a build run by hand (the kernel's own `vbw run start build`), so
# a project with no history shows the step with no end time in the status line and
# Comms, and `vbw next` says so; it ends the run. Phase 2: it seeds a history of
# three finished builds (and proofs) in the clone, the user types /vbw:vibe, and the
# build runs through the real window. Sampled every 2 s from the screen: VBW's
# message in the chat ("until around HH:MM"), the status line under the prompt
# box ("until HH:MM") and Comms (the "VBW ▸" strip: "until around HH:MM") must read
# the same time; the status line's "proving N of M checks" must count up.
steptime_seed() {
  local i
  printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!"; without a name it prints "Hello, world!"\n- R2 [auto] ./farewell.sh Ana prints "Goodbye, Ana!"; without a name it prints "Goodbye, world!"\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null || return 1
  # Three checks per requirement, each waits 5 s first: a proof takes long enough to watch.
  for i in 1 2 3; do
    case $i in 1) a=Ana b="Hello, Ana!" c="Goodbye, Ana!" ;; 2) a="" b="Hello, world!" c="Goodbye, world!" ;; 3) a=Bo b="Hello, Bo!" c="Goodbye, Bo!" ;; esac
    printf 'sleep 5\n[ "$(sh greet.sh %s)" = "%s" ]\n' "$a" "$b" > "test_greet_$i.sh"
    printf 'sleep 5\n[ "$(sh farewell.sh %s)" = "%s" ]\n' "$a" "$c" > "test_farewell_$i.sh"
  done
  git add -A && git commit -qm "test: the greeting checks" || return 1
  jq -n '{"phases": [{"id": "P1", "title": "Greet", "reqs": ["R1"]}, {"id": "P2", "title": "Farewell", "reqs": ["R2"]}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "greet.sh", "reqs": ["R1"], "files": ["greet.sh"], "after": [], "tasks": ["greet.sh prints Hello, NAME! or Hello, world! without a name"]},
              {"id": "P2.1", "phase": "P2", "title": "farewell.sh", "reqs": ["R2"], "files": ["farewell.sh"], "after": ["P1.1"], "tasks": ["farewell.sh prints Goodbye, NAME! or Goodbye, world! without a name"]}],
    "checks": [(range(1; 4) as $i | {"id": "C\($i)", "req": "R1", "run": ["sh", "test_greet_\($i).sh"], "files": ["test_greet_\($i).sh"]}),
               (range(1; 4) as $i | {"id": "C\($i + 3)", "req": "R2", "run": ["sh", "test_farewell_\($i).sh"], "files": ["test_farewell_\($i).sh"]})],
    "rules": [(range(1; 4) as $i | {"req": "R1", "text": "greeting case \($i)", "check": "C\($i)"}),
              (range(1; 4) as $i | {"req": "R2", "text": "farewell case \($i)", "check": "C\($i + 3)"})]}' \
    | "$VBW" apply > /dev/null || return 1
  git add -A && git commit -qm "chore: plan" || return 1
  "$VBW" approve > /dev/null || return 1
  # Two checks at a time, so the count steps 0, 2, 4, 6 and can be seen.
  "$VBW" config set check_jobs 2 > /dev/null
}

# The history the clone would have after three earlier builds (2 plans, 10 min) and three proofs (6 checks, 1 min).
steptime_history() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir) || return 1
  mkdir -p "$common/vbw"
  jq -n '{steps: [(range(0; 3) as $i | {kind: "build", run: "build-seed-\($i)", started_at: "2026-10-15T09:00:00Z", ended_at: "2026-10-15T09:10:00Z", seconds: 600, parts: 2}),
                  (range(0; 3) as $i | {kind: "proof", run: "proof-seed-\($i)", started_at: "2026-10-15T09:10:00Z", ended_at: "2026-10-15T09:11:00Z", seconds: 60, parts: 6})]}' \
    > "$common/vbw/steps.json"
}

scenario_steptime() {
  new_project
  export L3_STATUSLINE=1
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor standard > /dev/null && steptime_seed) \
    || { say "setup failed: could not seed the two-plan project"; return 1; }
  fixture="greet.sh and farewell.sh (two plans, the second after the first), six real checks that wait 5 s each (check_jobs 2), approved; the working tree's status line on, the panel in a wide window; no step history first (a build run started by the scenario with vbw run start build, then ended), then a seeded history of three builds of 2 plans in 10 min and three proofs of 6 checks in 1 min, and the user types /vbw:vibe for the real build"
  start="/vbw:status"
  st_phase=A st_nohist_status=false st_nohist_text=false st_nohist_next=false
  st_samples="$dir.steptime.samples" st_stop="$dir.steptime.stop"
  rm -f "$st_samples" "$st_stop"
  # What the three places say now: sets sw_* variables.
  st_read() {
    local s
    s=$(screen) || return 1
    sw_status=$(printf '%s\n' "$s" | awk '/^─/ { n = NR } { l[NR] = $0 } END { for (i = n + 1; i <= NR; i++) print l[i] }')
    sw_comms=$(printf '%s\n' "$s" | sed 's/│.*//' | awk '/VBW ▸/ { on = 1 } on && /^─/ { on = 0 } on')
    sw_chat=$(printf '%s\n' "$s" | sed 's/│.*//' | awk '/^─/ { exit } /VBW ▸/ { exit } { print }')
    sw_screen=$s
  }
  st_time() { grep -oE "$1 (tomorrow )?[0-9]{2}:[0-9]{2}" | head -1 | grep -oE '[0-9]{2}:[0-9]{2}$' || true; }
  # One sample, a tab-separated line: chat time, status line time, Comms time, the status line's
  # proof count (done, total) and the note's first end in local time.
  st_sample() {
    local chat sl cm n m note
    st_read || return 1
    chat=$(printf '%s\n' "$sw_chat" | grep -iE 'building|fixing|proving|checking' | st_time 'until around')
    sl=$(printf '%s\n' "$sw_status" | st_time 'until')
    cm=$(printf '%s\n' "$sw_comms" | st_time 'until around')
    n="" m=""
    if printf '%s\n' "$sw_status" | grep -E 'proving [0-9]+ of [0-9]+ checks' > /dev/null; then
      n=$(printf '%s\n' "$sw_status" | grep -oE 'proving [0-9]+ of [0-9]+ checks' | head -1 | grep -oE '[0-9]+' | sed -n 1p)
      m=$(printf '%s\n' "$sw_status" | grep -oE 'proving [0-9]+ of [0-9]+ checks' | head -1 | grep -oE '[0-9]+' | sed -n 2p)
    fi
    note=$(jq -r '(.first_end // empty) | fromdateiso8601 | localtime | strftime("%H:%M")' "$dir/.vbw/runtime/step.json" 2> /dev/null || true)
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$chat" "$sl" "$cm" "$n" "$m" "$note" >> "$st_samples"
  }
  # Every 2 s until the session is gone or the stop file is there; the waits of the
  # driver (a background build keeps it idle for minutes) do not thin it out.
  st_sampler() { while [ ! -f "$st_stop" ]; do st_sample || break; sleep 2; done; }
  # Phase A: no history. The scenario starts the build run; the window shows it with no end time.
  st_no_history() {
    local i sayt
    sayt=$(cd "$dir" && "$VBW" next --json 2> /dev/null | jq -r '.step.say // ""')
    case "$sayt" in *"no end time yet"*) st_nohist_next=true ;; esac
    (cd "$dir" && "$VBW" run start build P1.1 > /dev/null 2>&1) || { say "could not start the run by hand"; return; }
    for ((i = 0; i < 20; i++)); do
      sleep 2
      st_read
      if printf '%s\n' "$sw_status" | grep '● working: building' > /dev/null && ! printf '%s\n' "$sw_status" | grep 'until' > /dev/null; then st_nohist_status=true; fi
      case "$sw_screen" in *"No end time yet"*) st_nohist_text=true ;; esac
      [ "$st_nohist_status" = true ] && [ "$st_nohist_text" = true ] && break
    done
    printf '%s\n' "$sw_screen" > "$dir.steptime.nohistory.screen.txt"
    (cd "$dir" && "$VBW" run end > /dev/null 2>&1) || say "could not end the run started by hand"
  }
  plans_done() { jq -e '[.plans[]? | .status] | length > 0 and all(. == "done")' "$dir/.vbw/record.json" > /dev/null 2>&1; }
  done_yet() {
    if [ "$st_phase" = A ]; then
      st_no_history
      (cd "$dir" && steptime_history) || { say "could not seed the history"; return 0; }
      say "seeded the clone's steps.json: 3 builds of 2 plans in 10 min, 3 proofs of 6 checks in 1 min"
      st_phase=B
      st_sampler &
      l3 type "$scenario" "/vbw:vibe"
      return 1
    fi
    shipped && return 0
    plans_done || return 1
    # Both plans are built: go on until the proof after them has run and been seen counting.
    case "$(next_action)" in build | run | prove) return 1 ;; esac
    awk -F'\t' '$4 != "" { found = 1 } END { exit !found }' "$st_samples" 2> /dev/null
  }
  checks() {
    : > "$st_stop"
    wait
    local counts same up passed chat sl cm note total
    chat=$(awk -F'\t' '$1 != "" { print $1; exit }' "$st_samples")
    sl=$(awk -F'\t' '$2 != "" { print $2; exit }' "$st_samples")
    cm=$(awk -F'\t' '$3 != "" { print $3; exit }' "$st_samples")
    note=$(awk -F'\t' '$6 != "" { print $6; exit }' "$st_samples")
    total=$(awk -F'\t' '$5 != "" { print $5; exit }' "$st_samples")
    # The longest run of counts that never went down, from the status line over time.
    counts=$(awk -F'\t' '$4 != "" { n = $4 + 0
        if (len > 0 && n < last) { if (len > blen) { best = seq; blen = len } seq = ""; len = 0 }
        if (len == 0 || n != last) { seq = seq (len ? " " : "") n; len++ }
        last = n }
      END { if (len > blen) best = seq; print best }' "$st_samples" | tr ' ' '\n' | jq -R 'select(length > 0) | tonumber' | jq -s .)
    same=$([ -n "$chat" ] && [ "$chat" = "$sl" ] && [ "$chat" = "$cm" ] && echo true || echo false)
    up=$(jq -n --argjson c "$counts" '($c | length) >= 2 and ($c[-1] > $c[0]) and ([range(1; $c | length) as $i | $c[$i] >= $c[$i - 1]] | all)')
    facts=$(jq -n --arg chat "$chat" --arg sl "$sl" --arg cm "$cm" --arg note "$note" --argjson same "$same" \
      --argjson counts "$counts" --argjson up "$up" --argjson total "${total:-0}" \
      --argjson nhs "$st_nohist_status" --argjson nht "$st_nohist_text" --argjson nhn "$st_nohist_next" \
      --argjson samples "$(wc -l < "$st_samples" | tr -d ' ')" \
      '{chat_end: $chat, statusline_end: $sl, comms_end: $cm, note_first_end: $note, same_end: $same,
        proof_counts: $counts, proof_total: $total, proof_counted_up: $up,
        no_history_no_end_time: ($nhs and $nht and $nhn), no_history_status_line_without_time: $nhs, no_history_screen_says_no_end_time: $nht, no_history_next_says_no_end_time: $nhn,
        screen_samples: $samples}')
    expect "chat, status line and Comms each gave an end time" jq -e '.chat_end != "" and .statusline_end != "" and .comms_end != ""' <<< "$facts"
    expect "the three end times are the same" jq -e '.same_end == true' <<< "$facts"
    expect "the three end times are the note's first end" jq -e '.note_first_end == .chat_end' <<< "$facts"
    expect "the background proof counted up" jq -e '.proof_counted_up == true' <<< "$facts"
    expect "with no history the window shows no end time" jq -e '.no_history_no_end_time == true' <<< "$facts"
    passed=$(jq -r '.chat_end != "" and .same_end and (.note_first_end == .chat_end) and .proof_counted_up and .no_history_no_end_time' <<< "$facts")
    [ "$passed" = true ] || failed=1
    result_write steptime "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      '["a build that ran late: the end moving to this run'"'"'s pace was not seen in the window (held by tests/step-note.bats, L1)","an end time on another day","a fix, QA, planning or mapping step in the window","the three times are read from the visible screen text at 2 s steps, by the first time each place showed one, not by a reader","the project with no history had a build started by the scenario with vbw run start, not by the router, so the router saying no end time yet in chat was not seen (vbw next --json gave it)","the status line, Comms and the chat message were read in one 200-column window only","the proof counted was the one the build flow ran with check_jobs 2; its pace on a machine with more lanes","the time left shrinking, a user watching, and the clock time being right to the minute against real elapsed time"]'
  }
}

# road (R191, phase P151): the end of the milestone, the road, in the real window.
# The steptime project (two plans in two phases of one milestone, six slow real
# checks), with a history of the kind R191 reads: plan units with tiers and tasks,
# proofs with their units (and the runs store), QA phases with tiers, fix rounds
# with tiers, and the outcomes of three finished phases in an earlier, shipped
# milestone. Phase A has no history: vbw next --json says no end time yet for the
# step and for the road, a run started by hand writes the same into the note, and
# the screen shows it. Phase B seeds the history and the outcomes (the way a project
# that shipped before has them) and the user types /vbw:vibe; the build runs through
# the real window. Sampled every 2 s from the screen: VBW's message in the chat (the
# step's sentence, then "Milestone end: ... until around HH:MM"), Mission Control's
# milestone row, the status line under the prompt box (it shows the step's time
# only), and from the step note the road's end. The two milestone times must agree
# within a minute.
scenario_road() {
  new_project
  export L3_STATUSLINE=1
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor standard > /dev/null && steptime_seed) \
    || { say "setup failed: could not seed the two-plan project"; return 1; }
  fixture="greet.sh and farewell.sh (two plans in two standard phases of one milestone, the second after the first), six real checks that wait 5 s each (check_jobs 2), approved; the working tree's status line on, the panel in a wide window; no history first (a build run started by the scenario with vbw run start build, then ended), then a seeded history (three builds of one plan of one task at 5 min, three proofs of the six checks, three QA checks of one phase at 2 min, three fix rounds at 200 s, the runs store with the six checks at 5 s) and three finished phases of a shipped milestone with 1, 1 and 2 fix rounds, and the user types /vbw:vibe for the real build"
  start="/vbw:status"
  road_history() {
    local common
    common=$(git rev-parse --path-format=absolute --git-common-dir) || return 1
    mkdir -p "$common/vbw"
    # Three earlier builds of one plan of one task (5 min), three proofs of the six
    # checks (5 s each, 20 s of wall time), three QA checks of one phase (2 min) and
    # three fix rounds (200 s), all at the standard tier; the runs store knows the six checks.
    jq -n '[range(1; 7) | "check:C\(.)"] as $names
      | {steps: [
        (range(0; 3) as $i | {kind: "build", run: "build-seed-\($i)", started_at: "2026-10-15T09:00:00Z", ended_at: "2026-10-15T09:05:00Z", seconds: 300, parts: 1,
           units: [{id: "P9.\($i)", tier: "standard", tasks: 1, seconds: 300}]}),
        (range(0; 3) as $i | {kind: "proof", run: "proof-seed-\($i)", started_at: "2026-10-15T09:10:00Z", ended_at: "2026-10-15T09:10:20Z", seconds: 20, parts: 6,
           units: [$names[] | {name: ., seconds: 5}]}),
        (range(0; 3) as $i | {kind: "qa", run: "qa-seed-\($i)", started_at: "2026-10-15T09:11:00Z", ended_at: "2026-10-15T09:13:00Z", seconds: 120,
           phases: [{id: "P9\($i)", tier: "standard"}]}),
        (range(0; 3) as $i | {kind: "fix", run: "fix-seed-\($i)", started_at: "2026-10-15T09:14:00Z", ended_at: "2026-10-15T09:17:20Z", seconds: 200, parts: 1,
           fixes: ["F\($i)"], tier: "standard"})]}' > "$common/vbw/steps.json"
    jq -n '[range(1; 7) | "check:C\(.)"] as $names
      | {runs: ($names | map({key: ., value: {fp: "seed", tree: "seed", status: "pass", at: "2026-10-15T09:10:00Z", seconds: 5, tail: "", reads: null, dirs: [], git: false}}) | from_entries)}' \
      > "$common/vbw/runs.json"
  }

  # Three finished phases of an earlier milestone, shipped, each at the standard tier
  # with its fix rounds (1, 1 and 2: the usual is 1), as a project that shipped before has them.
  road_outcomes() {
    local r=.vbw/record.json
    jq '.shipped = [{id: "M0", title: "Before", at: "2026-10-01T00:00:00Z"}]
      | .phases += [([1, 1, 2] | to_entries[]) as $e | {id: "P9\($e.key)", title: "Earlier phase \($e.key)", reqs: ["R1"], milestone: "M0", tier: "standard",
          qa: {result: "pass", tier: "standard", tree: "old", at: "2026-10-01T00:00:00Z"},
          outcome: {tier: "standard", predicted: "standard", held: true, fix_rounds: $e.value, qa_findings: 0, escalations: 0}}]' "$r" > "$r.tmp" \
      && mv "$r.tmp" "$r" && git add .vbw/record.json && git commit -qm "chore(vbw): earlier phases" || return 1
  }
  rd_phase=A rd_nohist_next=false rd_nohist_note=false rd_nohist_screen=false
  rd_samples="$dir.road.samples" rd_stop="$dir.road.stop"
  rm -f "$rd_samples" "$rd_stop"
  # What the places say now: sets rd_* variables (text without the panel, the panel's text, the status line).
  rd_read() {
    local s
    s=$(screen) || return 1
    # Claude Code's own "Teach auto mode about your environment?" dialog can open after
    # a turn and takes the next typed text: the user would press Esc, so the scenario does.
    case "$s" in *"Teach auto mode about your environment"*) l3 keys "$scenario" Escape; sleep 1; s=$(screen) || return 1 ;; esac
    # The seeded ship opens Mission Control on VBW Wrapped, which hides its rows until a tab
    # is chosen: the user would click Now, so the scenario does.
    case "$s" in *"VBW Wrapped"*)
      row=$(printf '%s\n' "$s" | grep -n '\[ Now \]' | head -1 | cut -d: -f1)
      pre=$(printf '%s\n' "$s" | grep '\[ Now \]' | head -1 | sed 's/\[ Now \].*//')
      if [ -n "$row" ]; then
        l3 click "$scenario" "$(($(printf '%s' "$pre" | LC_ALL=en_US.UTF-8 wc -m) + 4))" "$row"
        sleep 1; s=$(screen) || return 1
      fi ;;
    esac
    rd_status=$(printf '%s\n' "$s" | awk '/^─/ { n = NR } { l[NR] = $0 } END { for (i = n + 1; i <= NR; i++) print l[i] }')
    rd_chat=$(printf '%s\n' "$s" | sed 's/│.*//' | awk '/^─/ { exit } /VBW ▸/ { exit } { print }' | tr '\n' ' ' | tr -s ' ')
    rd_panel=$(printf '%s\n' "$s" | sed -n 's/^[^│]*│//p' | sed 's/│//g' | tr '\n' ' ' | tr -s ' ')
    rd_screen=$s
  }
  # The first "Milestone end: ... until around HH:MM" in a text, the HH:MM.
  rd_road_time() { grep -oE 'Milestone end:[^.]*until around [0-9]{2}:[0-9]{2}' | head -1 | grep -oE '[0-9]{2}:[0-9]{2}$' || true; }
  # The chat's step time: the first "until around HH:MM" that comes before the first "Milestone end:".
  rd_step_time() {
    grep -oE 'Milestone end:|until around [0-9]{2}:[0-9]{2}' \
      | awk '/^Milestone end:/ { exit } { print; exit }' | grep -oE '[0-9]{2}:[0-9]{2}$' || true
  }
  # One sample, a tab-separated line: the chat's step time, the chat's road time, Mission Control's
  # road time, whether the status line mentions the milestone, the status line's time and the note's road end.
  rd_sample() {
    local cs cr pr sh sl nr
    rd_read || return 1
    cs=$(printf '%s\n' "$rd_chat" | rd_step_time)
    cr=$(printf '%s\n' "$rd_chat" | rd_road_time)
    pr=$(printf '%s\n' "$rd_panel" | rd_road_time)
    sh=0
    printf '%s\n' "$rd_status" | grep -iE 'milestone end|no milestone end' > /dev/null && sh=1
    sl=$(printf '%s\n' "$rd_status" | grep -oE 'until (tomorrow )?[0-9]{2}:[0-9]{2}' | head -1 | grep -oE '[0-9]{2}:[0-9]{2}$' || true)
    nr=$(jq -r '(.road.end // empty) | fromdateiso8601 | localtime | strftime("%H:%M")' "$dir/.vbw/runtime/step.json" 2> /dev/null || true)
    # The screen while the build runs and the chat has the milestone's time (kept for the reader).
    case "$rd_panel" in *"Current step: building"*) printf '%s\n' "$rd_screen" > "$dir.road.building.screen.txt" ;; esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$cs" "$cr" "$pr" "$sh" "$sl" "$nr" >> "$rd_samples"
  }
  rd_sampler() { while [ ! -f "$rd_stop" ]; do rd_sample || break; sleep 2; done; }
  # Phase A: no history. The scenario starts the build run; the window shows no end time.
  rd_no_history() {
    local i
    case "$(cd "$dir" && "$VBW" next --json 2> /dev/null | jq -r '(.step.say // "") + " | " + (.road.say // "")')" in
      *"no end time yet"*"no milestone end time yet"*) rd_nohist_next=true ;;
    esac
    (cd "$dir" && "$VBW" run start build P1.1 > /dev/null 2>&1) || { say "could not start the run by hand"; return; }
    for ((i = 0; i < 20; i++)); do
      sleep 2
      rd_read
      # Mission Control opens by itself in a wide window; if not, the user opens it with /vbw-panel.
      if [ "$i" -eq 5 ]; then case "$rd_screen" in *"[ Now ]"*) ;; *) l3 type "$scenario" "/vbw-panel" ;; esac; fi
      case "$rd_screen" in *"No estimate yet"*) rd_nohist_screen=true ;; esac
      jq -e '.road != null and .road.end == null and (.road.say | test("no milestone end time yet"))' "$dir/.vbw/runtime/step.json" > /dev/null 2>&1 && rd_nohist_note=true
      [ "$rd_nohist_screen" = true ] && [ "$rd_nohist_note" = true ] && break
    done
    printf '%s\n' "$rd_screen" > "$dir.road.nohistory.screen.txt"
    (cd "$dir" && "$VBW" run end > /dev/null 2>&1) || say "could not end the run started by hand"
  }
  plans_done() { jq -e '[.plans[]? | .status] | length > 0 and all(. == "done")' "$dir/.vbw/record.json" > /dev/null 2>&1; }
  done_yet() {
    if [ "$rd_phase" = A ]; then
      rd_no_history
      (cd "$dir" && road_history && road_outcomes) || { say "could not seed the history"; return 0; }
      say "seeded the clone's history (builds, proofs, QA, fix rounds, runs) and three finished phases of a shipped milestone"
      rd_phase=B
      rd_sampler &
      l3 type "$scenario" "/vbw:vibe"
      return 1
    fi
    shipped && return 0
    plans_done || return 1
    case "$(next_action)" in build | run | prove) return 1 ;; esac
    awk -F'\t' '$2 != "" { a = 1 } $3 != "" { b = 1 } END { exit !(a && b) }' "$rd_samples" 2> /dev/null
  }
  checks() {
    : > "$rd_stop"
    wait
    local cs cr pr sh sl nr same
    first() { awk -F'\t' -v c="$1" '$c != "" { print $c; exit }' "$rd_samples"; }
    cs=$(first 1) cr=$(first 2) pr=$(first 3) sl=$(first 5) nr=$(first 6)
    sh=$(awk -F'\t' '$4 == 1 { f = 1 } END { print f ? "true" : "false" }' "$rd_samples")
    # Within a minute of each other (the clock wraps at midnight).
    within() { awk -v a="$1" -v b="$2" 'function m(t) { split(t, p, ":"); return p[1] * 60 + p[2] }
      BEGIN { d = m(a) - m(b); if (d < 0) d = -d; if (1440 - d < d) d = 1440 - d; exit !(d <= 1) }'; }
    same=false
    if [ -n "$cr" ] && [ -n "$pr" ] && [ -n "$nr" ] && within "$cr" "$pr" && within "$cr" "$nr" && within "$pr" "$nr"; then same=true; fi
    facts=$(jq -n --arg cs "$cs" --arg cr "$cr" --arg pr "$pr" --arg nr "$nr" --arg sl "$sl" --argjson same "$same" --argjson sh "$sh" \
      --argjson nhn "$rd_nohist_next" --argjson nht "$rd_nohist_note" --argjson nhs "$rd_nohist_screen" \
      --argjson samples "$(wc -l < "$rd_samples" | tr -d ' ')" \
      '{chat_step_end: $cs, chat_road_end: $cr, panel_road_end: $pr, note_road_end: $nr, same_road_end: $same,
        statusline_end: $sl, statusline_has_road: $sh,
        no_history_no_end_time: ($nhn and $nht and $nhs), no_history_next_says_no_end_time: $nhn, no_history_note_says_no_end_time: $nht, no_history_screen_says_no_end_time: $nhs,
        screen_samples: $samples}')
    expect "the chat gave the step's time and the milestone's" jq -e '.chat_step_end != "" and .chat_road_end != ""' <<< "$facts"
    expect "Mission Control gave the milestone's time" jq -e '.panel_road_end != ""' <<< "$facts"
    expect "chat, Mission Control and the note give the same milestone time" jq -e '.same_road_end == true' <<< "$facts"
    expect "the status line showed a time and no milestone" jq -e '.statusline_end != "" and .statusline_has_road == false' <<< "$facts"
    expect "with no history the window and vbw next show no end time" jq -e '.no_history_no_end_time == true' <<< "$facts"
    passed=$(jq -r '.chat_step_end != "" and .chat_road_end != "" and .panel_road_end != "" and .same_road_end and .statusline_end != "" and (.statusline_has_road | not) and .no_history_no_end_time' <<< "$facts")
    [ "$passed" = true ] || failed=1
    result_write road "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      '["a build that ran late: the milestone end moving with each late plan was not seen in the window (held by tests/road-note.bats, L1)","fix rounds, QA, planning and mapping steps in the window: the road was read at the build'"'"'s start and during the proof","a milestone end on another day, and a duration over an hour","the times are read from the visible screen text at 2 s steps, by the first time each place showed one, not by a reader","the project with no history had a build run started by the scenario with vbw run start, not by the router, so the router saying both sentences in chat without history was not seen (vbw next --json and the note gave them)","the earlier phases, the history and the runs store are seeded by the scenario in the clone and the record, not made by earlier real runs","the chat, Mission Control and the status line were read in one 200-column window only","the milestone time being right to the minute against real elapsed time","Claude Code'"'"'s own Teach auto mode dialog and the VBW Wrapped card the seeded ship opens were dismissed by the scenario (Esc, a click on Now), as a user would"]'
  }
}

# pluginoff (R184): a VBW project whose own .claude/settings.json turns the VBW
# plugin off. VBW runs as the user's installed marketplace plugin (L3_MODE=installed:
# --plugin-dir may not honour enabledPlugins "vbw@vbw-marketplace"), with the
# working tree's status line on, in a window wide enough for the panel. The
# facts: Claude Code itself reports VBW off (debug log), whether it still
# loaded the panel module, and whether anything of VBW is on the screen.
scenario_pluginoff() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null \
    && printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!"\n' > .vbw/spec.md \
    && "$VBW" spec sync > /dev/null \
    && mkdir -p .claude \
    && jq -n '{enabledPlugins: {"vbw@vbw-marketplace": false}}' > .claude/settings.json \
    && git add -A && git commit -qm "chore: VBW project that turns the VBW plugin off") \
    || { say "setup failed: could not seed the project"; return 1; }
  export L3_STATUSLINE=1 L3_MODE=installed
  fixture="a small VBW project (vbw init, one-requirement spec) whose .claude/settings.json sets enabledPlugins vbw@vbw-marketplace to false; VBW is the installed marketplace plugin, the session shows the working tree's status line; window 200 columns wide"
  start="Reply with the single word ok."
  seen=""
  done_yet() {
    sleep 20
    seen=$(screen | sed 's/[[:space:]][[:space:]]*/ /g')
    printf '%s\n' "$seen" > "$dir.pluginoff.screen.txt"
    return 0
  }
  checks() {
    local log off=false module=false panel=false line=false passed
    log=$(l3 debuglog "$dir")
    [ -f "$log" ] || log=/dev/null
    grep -qiE 'vbw[^ ]*.{0,80}(disabled|not enabled|is off)|(disabled|skipping).{0,80}vbw' "$log" && off=true
    grep -q 'hooks/panel\.js' "$log" && module=true
    printf '%s' "$seen" | grep -E 'Working on|VBW is idle|VBW next:|VBW needs you|VBW building|No VBW project is open' > /dev/null && panel=true
    printf '%s' "$seen" | grep -F '[VBW]' > /dev/null && line=true
    expect "Claude Code reports VBW turned off in the project" [ "$off" = true ]
    expect "no panel on screen" [ "$panel" = false ]
    expect "no VBW status line on screen" [ "$line" = false ]
    passed=true
    [ "$off" = true ] && [ "$panel" = false ] && [ "$line" = false ] || passed=false
    [ "$passed" = true ] || failed=1
    result_write pluginoff "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson o "$off" --argjson m "$module" --argjson p "$panel" --argjson l "$line" \
        '{plugin_disabled_confirmed: $o, panel_module_loaded: $m, panel_shown: $p, vbw_statusline_shown: $l}')" \
      '["the hand-back to an earlier status line through the installed setting (this session shows the working tree script directly)","the installed plugin version, which is not the working tree'"'"'s","user-level settings that turn VBW off (the project'"'"'s own file only)","a narrow window","a project that turns VBW off while a VBW run is live"]'
  }
}

# plugindir (R185): VBW is installed from the marketplace AND the working tree is
# loaded with claude --plugin-dir, in a session whose inherited PATH already
# holds the installed release's bin/ (a session started from inside another
# one). The session and one VBW agent it starts each run 'command -v vbw' and
# 'vbw version'. The facts come from the session transcripts and the debug log:
# which copies load, which hooks ran, the vbw each resolved, the plugin data
# folder name and CLAUDE_ENV_FILE the loaded copy's SessionStart hook gets (a
# probe hook in a throwaway copy of the tree in .vbw/runtime/scratch/, whose
# plugin.json version is suffixed when it equals the installed one, so the two
# copies tell apart). The result name comes from the caller: L3_PLUGINDIR_RESULT
# (plugindir-probe before the fix, plugindir after it; default plugindir).
# L3_PLUGINDIR_INHERIT=0 starts without the installed bin/ on PATH.
scenario_plugindir() {
  new_project
  # The caller names the result: plugindir-probe before the fix, plugindir after it.
  pd_name=${L3_PLUGINDIR_RESULT:-plugindir}
  pd_tree="$ROOT/.vbw/runtime/scratch/plugindir-tree"
  local inst_root inst_ver tree_ver
  inst_root=$(jq -r '.plugins["vbw@vbw-marketplace"][0].installPath // empty' "$(claude_dir)/plugins/installed_plugins.json" 2> /dev/null)
  [ -n "$inst_root" ] && [ -x "$inst_root/bin/vbw" ] || { say "setup failed: no installed VBW release (vbw@vbw-marketplace) in $(claude_dir)"; return 1; }
  inst_ver=$(jq -r .version "$inst_root/.claude-plugin/plugin.json")
  rm -rf "$pd_tree" && mkdir -p "$ROOT/.vbw/runtime/scratch" && cp -R "$ROOT/plugin" "$pd_tree" || { say "setup failed: could not copy the tree"; return 1; }
  find "$pd_tree" -name .DS_Store -delete
  tree_ver=$(jq -r .version "$pd_tree/.claude-plugin/plugin.json")
  if [ "$tree_ver" = "$inst_ver" ]; then
    tree_ver="$tree_ver+tree"
    jq --arg v "$tree_ver" '.version = $v' "$pd_tree/.claude-plugin/plugin.json" > "$pd_tree/.claude-plugin/plugin.json.new" \
      && mv "$pd_tree/.claude-plugin/plugin.json.new" "$pd_tree/.claude-plugin/plugin.json"
  fi
  # The probe: what the loaded copy's SessionStart hook is given, and a variable
  # exported through CLAUDE_ENV_FILE to see whether the Bash tools read that file.
  cat > "$pd_tree/hooks/probe.sh" << 'PROBE'
#!/usr/bin/env bash
{ echo "ROOT=$CLAUDE_PLUGIN_ROOT"; echo "DATA=${CLAUDE_PLUGIN_DATA:-}"; echo "ENVFILE=${CLAUDE_ENV_FILE:-}"; } > "$0.out"
[ -z "${CLAUDE_ENV_FILE:-}" ] || echo 'export VBWPROBE_ENV=applied' >> "$CLAUDE_ENV_FILE"
PROBE
  jq '.hooks.SessionStart += [{hooks: [{type: "command", command: "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/probe.sh\""}]}]' \
    "$pd_tree/hooks/hooks.json" > "$pd_tree/hooks/hooks.json.new" && mv "$pd_tree/hooks/hooks.json.new" "$pd_tree/hooks/hooks.json" \
    || { say "setup failed: could not add the probe hook"; return 1; }
  rm -f "$pd_tree/hooks/probe.sh.out"
  (cd "$dir" && "$VBW" init > /dev/null \
    && printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!"\n' > .vbw/spec.md \
    && "$VBW" spec sync > /dev/null \
    && git add -A && git commit -qm "chore: small VBW project") || { say "setup failed: could not seed the project"; return 1; }
  pd_inst_ver=$inst_ver pd_tree_ver=$tree_ver
  export L3_STATUSLINE=1 L3_MODE=both L3_TREE="$pd_tree"
  pd_inherit=true
  if [ "${L3_PLUGINDIR_INHERIT:-1}" = 0 ]; then pd_inherit=false; else export L3_INSTALLED_BIN="$inst_root/bin"; fi
  fixture="a small VBW project (vbw init, one-requirement spec); VBW $inst_ver installed from the marketplace and left on; a throwaway copy of this tree ($tree_ver, with a probe SessionStart hook) loaded with --plugin-dir; status line from that copy; launch PATH has the installed bin/ first: $pd_inherit"
  start='Do two things, then reply only with the word done. 1) With your Bash tool run exactly this: echo VBWPROBE; command -v vbw; vbw version; echo "$PATH"; echo "env=${VBWPROBE_ENV:-unset}"  2) Start one vbw:scout agent whose whole task is to run exactly that same command with its Bash tool and report the output. Change nothing.'
  pd_seen=""
  done_yet() {
    sleep 10
    pd_seen=$(screen | sed 's/[[:space:]][[:space:]]*/ /g')
    return 0
  }
  checks() {
    local log main agent out_s out_a facts passed copies hooks bins data envfile sl names
    log=$(l3 debuglog "$dir")
    [ -f "$log" ] || log=/dev/null
    main=$(main_transcript)
    agent=$(transcripts | grep '/subagents/' | head -1)
    out_s=$([ -z "$main" ] || pd_probe_out "$main")
    out_a=$([ -z "$agent" ] || pd_probe_out "$agent")
    copies=$(sed -nE 's/.*Read hooks\.json for plugin vbw \(enabled=true\): (.*)\/hooks\/hooks\.json$/\1/p' "$log" | sort -u | jq -R . | jq -sc .)
    hooks=$(sed -nE 's/.*Hooks: SessionStart.*\(plugin ([^)]*)\) finished.*/\1/p' "$log" | sort -u | jq -R . | jq -sc .)
    bins=$(printf '%s\n' "$out_s" | sed -n 4p | tr ':' '\n' | while IFS= read -r p; do [ -z "$p" ] || [ ! -x "$p/vbw" ] || printf '%s\n' "$p"; done | jq -R . | jq -sc .)
    data=$(sed -n 's/^DATA=//p' "$pd_tree/hooks/probe.sh.out" 2> /dev/null | head -1)
    envfile=$(sed -n 's/^ENVFILE=//p' "$pd_tree/hooks/probe.sh.out" 2> /dev/null | head -1)
    sl=$(printf '%s' "$pd_seen" | grep -oE 'VBW [0-9][^ ]*' | tail -1 | sed 's/^VBW //')
    names=false
    [ -z "$main" ] || jq -se --arg k "$pd_tree/bin/vbw" 'any(.[]; (tostring | contains("SessionStart")) and (tostring | contains($k)))' "$main" > /dev/null 2>&1 && names=true
    facts=$(jq -n --arg cv "$(claude --version 2> /dev/null | awk '{print $1}')" --arg tv "$pd_tree_ver" --arg iv "$pd_inst_ver" \
      --arg tr "$pd_tree" --argjson copies "${copies:-[]}" --argjson bins "${bins:-[]}" --argjson hooks "${hooks:-[]}" \
      --arg sp "$(printf '%s\n' "$out_s" | sed -n 2p)" --arg sv "$(printf '%s\n' "$out_s" | sed -n 3p)" \
      --arg se "$(printf '%s\n' "$out_s" | sed -n 5p)" \
      --arg ap "$(printf '%s\n' "$out_a" | sed -n 2p)" --arg av "$(printf '%s\n' "$out_a" | sed -n 3p)" \
      --arg ae "$(printf '%s\n' "$out_a" | sed -n 5p)" \
      --arg data "$(basename "${data:-}")" --arg envf "$envfile" --argjson inh "$pd_inherit" \
      --arg sl "$sl" --argjson names "$names" \
      --argjson ovr "$(grep -q 'from --plugin-dir overrides installed version' "$log" && echo true || echo false)" \
      '{claude_version: $cv, tree_root: $tr, tree_version: $tv, installed_version: $iv,
        loaded_copies: $copies, tree_overrides_installed: $ovr, plugin_bins_on_path: $bins,
        session_vbw_path: $sp, session_vbw_version: $sv, session_env_applied: ($se == "env=applied"),
        agent_vbw_path: $ap, agent_vbw_version: $av, agent_env_applied: ($ae == "env=applied"),
        hooks_from: $hooks, installed_hooks_ran: ($hooks | any(. != "vbw@inline")),
        plugin_data_id: $data, env_file_given: ($envf != ""), launch_path_had_installed: $inh,
        statusline_version_shown: $sl, session_start_names_kernel: $names}')
    passed=$(jq -r '.session_vbw_path == (.tree_root + "/bin/vbw") and .agent_vbw_path == (.tree_root + "/bin/vbw")
      and .session_vbw_version == .tree_version and .statusline_version_shown == .tree_version
      and .session_start_names_kernel and (.installed_hooks_ran | not)' <<< "$facts")
    expect "the session ran the working tree's vbw" jq -e '.session_vbw_path == (.tree_root + "/bin/vbw")' <<< "$facts"
    expect "the agent ran the working tree's vbw" jq -e '.agent_vbw_path == (.tree_root + "/bin/vbw")' <<< "$facts"
    expect "the status line showed the working tree's version" jq -e '.statusline_version_shown == .tree_version' <<< "$facts"
    expect "the installed copy's hooks did not run" jq -e '.installed_hooks_ran | not' <<< "$facts"
    [ "$passed" = true ] || failed=1
    result_write "$pd_name" "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      '["a marketplace release other than the one installed here","Claude Code versions other than the one that ran","a session started by a person from a shell with a different PATH","the user'"'"'s own status line setting (the session shows the throwaway copy'"'"'s script)","the tree'"'"'s own version number (the copy carries a +tree suffix when it equals the installed release)","a project that turns VBW off"]'
  }
}

# The first tool result starting with VBWPROBE in a transcript (the probe command's output).
pd_probe_out() {
  jq -rs '[.[] | select(.type == "user") | .message.content[]? | select(.type == "tool_result")
    | (.content | if type == "array" then map(.text? // "") | join("") else (. // "") end)
    | select(startswith("VBWPROBE"))] | first // empty' "$1" 2> /dev/null
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
    # The promise: VBW never undoes the user's decision. Since 2.0.44 a hand-deleted
    # delivered file is a deviation the session sees, so it may honour the decision in
    # either of two ways, each with its own checks: keep the requirement under the
    # decision (QA reads the decisions and passes first time), or withdraw the
    # requirement that asked for NOTES.md, with the contract approved again after the
    # decision. Both: NOTES.md stays deleted and no fix is opened after the decision.
    local restored=false withdrawn reapproved
    git -C "$dir" cat-file -e HEAD:NOTES.md 2> /dev/null && restored=true
    expect "NOTES.md stayed deleted: VBW did not undo the user's decision" [ "$restored" = false ]
    expect "no fix was opened after the decision ($after)" [ "${after##* }" = 0 ]
    withdrawn=$(jq -r '[.requirements[] | select(.text | test("NOTES"; "i"))] | length == 0' "$dir/.vbw/record.json" 2> /dev/null)
    if [ "$withdrawn" = true ]; then
      say "the session withdrew the NOTES.md requirement instead of keeping it under the decision"
      reapproved=$(jq -r '([.decisions[] | select(.text | test("NOTES"; "i")) | .at] | first) as $d
        | $d != null and any(.decisions[]; (.text | startswith("Contract approved")) and .at > $d)' "$dir/.vbw/record.json" 2> /dev/null)
      expect "the contract was approved again after the decision" [ "$reapproved" = true ]
    else
      expect "QA loaded the recorded decisions" [ "$qa_read" = true ]
      expect "after the decision, QA passed the phase first time and opened no fix ($after)" [ "$after" = "pass 0" ]
    fi
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
    [ "$said_yes" -eq 0 ] && workflow_started investigating && last_reply | grep -i 'fix' > /dev/null || return 0
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
  done_yet() { workflow_started researching && last_reply | grep '2\.23' > /dev/null; }
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
# copy, with nothing reused: leftover_proof) is unchanged and passes. lint.sh
# records where it ran and whether the file was there.
scenario_leftover() {
  new_project
  fixture="greet.sh from scratch plus a committed lint.sh that fails when todos.txt exists; project command lint: sh lint.sh"
  printf '#!/bin/sh\n[ -z "${LEFTOVER_PROBE:-}" ] || { pwd -P; [ -e todos.txt ] && echo yes || echo no; } > "$LEFTOVER_PROBE"\n[ ! -e todos.txt ]\n' > "$dir/lint.sh"
  git -C "$dir" add -A && git -C "$dir" commit -qm "chore: lint.sh"
  start="$GREET Also make the project command lint (sh lint.sh) part of the project's commands; it is already in the repository."
  checks() {
    common_checks
    local probe facts passed=true
    jq -e '.commands.lint' "$dir/.vbw/record.json" > /dev/null 2>&1 || { say "FAIL no lint command in the record"; failed=1; }
    probe=$(mktemp "${TMPDIR:-/tmp}/vbw-l3-probe.XXXXXX")
    facts=$(leftover_proof "$dir" todos.txt "$probe")
    rm -f "$probe"
    expect "the check flips in the working folder with the leftover file" jq -e '.check_flips_in_working_folder == true' <<< "$facts"
    expect "the proof is unchanged by the leftover file" jq -e '.proof_unchanged == true' <<< "$facts"
    expect "the proof passed" jq -e '.proof_passed == true' <<< "$facts"
    expect "the project command ran in a proof copy" jq -e '.ran_in_proof_copy == true' <<< "$facts"
    expect "the file was not in the proof copy" jq -e '.file_in_proof_copy == false' <<< "$facts"
    expect "the proof copy is gone" jq -e '.copy_removed == true' <<< "$facts"
    [ "$failed" -eq 0 ] || passed=false
    result_write leftover "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      '["a leftover modified tracked file","a git-ignored leftover (copied into the proof copy by design)","a project command other than a shell script","a project larger than the greet.sh fixture"]'
  }
}

# leftover_proof DIR FILE PROBE: the proof half of the leftover scenario, on the
# project in DIR whose approved lint command fails while FILE exists and, under
# LEFTOVER_PROBE, writes to PROBE the folder it ran in and whether FILE was
# there. Leaves FILE untracked in DIR, runs lint there (the file must flip it),
# then proves with nothing reused (vbw prove --full): the session leaves a
# passing proof, and a plain vbw prove reuses lint's pass by its read list
# (R166: FILE is not committed code), so lint would not run in a proof copy at
# all. Removes FILE and prints the facts as one JSON object (null: not known,
# because lint did not run in a proof copy). tests/l3-leftover.bats runs it.
leftover_proof() {
  local d=$1 f=$2 probe=$3 ev before after a where real argv=() flips=false same=false pp=false ran=false inc=null gone=null
  ev='.evidence | {passed, checks: (.checks | map_values(.status)), commands: (.commands | map_values(.status))}'
  before=$(jq -c "$ev" "$d/.vbw/record.json" 2> /dev/null)
  printf 'buy milk\n' > "$d/$f"
  while IFS= read -r -d '' a; do argv+=("$a"); done < <(jq -j '.commands.lint[] + "\u0000"' "$d/.vbw/record.json" 2> /dev/null)
  (cd "$d" && [ "${#argv[@]}" -gt 0 ] && ! "${argv[@]}" > /dev/null 2>&1) && flips=true
  : > "$probe"
  (cd "$d" && LEFTOVER_PROBE="$probe" "$VBW" prove --full > /dev/null 2>&1) || true
  after=$(jq -c "$ev" "$d/.vbw/record.json" 2> /dev/null)
  [ -n "$before" ] && [ "$before" = "$after" ] && same=true
  jq -e '.evidence.passed == true' "$d/.vbw/record.json" > /dev/null 2>&1 && pp=true
  where=$(sed -n 1p "$probe")
  real=$(cd "$d" && pwd -P)
  if [ -n "$where" ] && [ "$where" != "$real" ]; then
    ran=true
    case "$(sed -n 2p "$probe")" in yes) inc=true ;; no) inc=false ;; esac
    # No copy is left: not its folder, not its git worktree entry, no proof.* folder (grep -c reads everything, safe under pipefail).
    gone=false
    [ ! -e "$where" ] && [ "$(git -C "$d" worktree list --porcelain | grep -cF -- "$where")" = 0 ] \
      && [ -z "$(find "$d/.vbw/runtime" -maxdepth 1 -name 'proof.*' 2> /dev/null)" ] && gone=true
  fi
  rm -f "$d/$f"
  jq -nc --arg f "$f" --argjson fl "$flips" --argjson s "$same" --argjson p "$pp" --argjson r "$ran" --argjson i "$inc" --argjson g "$gone" \
    '{leftover_file: $f, check_flips_in_working_folder: $fl, proof_unchanged: $s, proof_passed: $p, ran_in_proof_copy: $r, file_in_proof_copy: $i, copy_removed: $g}'
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
# Options may still be rendering: it looks for up to 5 s. Not found, it counts
# in $unmatched, so a scenario cannot pass on the drive loop's default answer.
pick_label() {
  local n="" i
  for ((i = 0; i < 10; i++)); do
    n=$(current_question | grep -iE "^[^0-9]*[0-9]+\. $1" | head -1 | grep -oE '[0-9]+' | head -1)
    [ -n "$n" ] && break
    sleep 0.5
  done
  [ -n "$n" ] || { say "no option matching '$1' on screen"; unmatched=$((${unmatched:-0} + 1)); return 1; }
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
                | select(startswith("Your questions have been answered") or startswith("The user answered")) | "**User answers:** " + . + "\n")
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
    {"What is your level of proficiency": ["never", "small scripts or no-code", "professionally", "senior engineer"],
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

# scenario_interview LEVEL DEPTH INVOLVEMENT KEEP_REGEX PURPOSE KEYWORD DETAIL:
# sets up a project whose user answers the interview as given (drive handlers)
# and defines checks() to read the outcome. PURPOSE leaves out what the tool
# does, so the interview has something to follow up on. Every follow-up gets
# DETAIL, a reply that answers both kinds VBW asks (what it does, and in what
# form or language), in the user's own words. The caller's checks() writes the result.
scenario_interview() {
  a_level=$1 a_depth=$2 a_inv=$3 a_keep=$4 a_purpose=$5 a_word=$6 a_detail=$7
  new_project
  start="/vbw:vibe I want to build a small greeting tool. One small milestone."
  purpose_done=0 followups=0 unmatched=0
  # The question on screen decides the answer (the model may put several
  # questions in one form, so the recorded state is not a guide).
  on_question() {
    local p scr
    p=$(interview_pending)
    scr=$(current_question)
    # The keep question names the other answers ("how involved you are"), so it
    # is told apart first, by its options; the others by their opening words.
    if printf '%s' "$scr" | grep -i 'private on this machine' > /dev/null; then pick_label "$a_keep"
    elif printf '%s' "$scr" | grep -i 'what is your level of proficiency' > /dev/null; then pick_label "$a_level"
    elif printf '%s' "$scr" | grep -i 'how should I explain things' > /dev/null; then pick_label "$a_depth"
    elif printf '%s' "$scr" | grep -i 'how involved do you want to be' > /dev/null; then pick_label "$a_inv"
    elif [ "$p" = none ] || printf '%s' "$scr" | grep 'Ready to submit' > /dev/null; then return 1
    elif [ "$purpose_done" -eq 0 ]; then
      purpose_done=1; answer_other "$a_purpose"
    else
      followups=$((followups + 1))
      answer_other "$a_detail"
    fi
  }
  # "What and for whom" and the follow-ups may arrive as plain messages, not menus.
  on_idle() {
    [ "$(interview_pending)" = keep ] || return 1
    if [ "$purpose_done" -eq 0 ]; then
      last_reply | grep -iE 'building|for whom|who.*(for|use)' > /dev/null || return 1
      purpose_done=1
      l3 type "$scenario" "$a_purpose"
    else
      last_reply | grep '?' > /dev/null || return 1
      followups=$((followups + 1))
      l3 type "$scenario" "$a_detail"
    fi
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
  printf '%s' "$goals" | grep -i "$a_word" > /dev/null && in_goals=true
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
  if screen | grep "Type \/reload-skills" > /dev/null; then l3 type "$scenario" "/reload-skills"; sleep 5; fi
  l3 type "$scenario" "/vbw:vibe Also let greet.sh take --shout, printing the greeting in capital letters."
  default_idle
  l3 keys "$scenario" Escape; sleep 2; default_idle
  l3 stop "$scenario"
  after=$(cd "$dir" && "$VBW" interview --json 2> /dev/null || echo '{}')
  new=$(comm -13 <(printf '%s\n' "$files") <(transcripts | sort) | grep -v '/subagents/' || true)
  if [ -n "$new" ] && printf '%s\n' "$new" | xargs cat 2> /dev/null | jq -e 'select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use" and (((.input | tostring) | test("interview (set|keep)|level of proficiency")) or (.name == "Skill" and ((.input | tostring) | test("interview")))))' > /dev/null 2>&1; then asked=true; fi
  [ "$(cd "$dir" && "$VBW" next --json 2> /dev/null | jq -r '.profile.ask')" = false ] && ask_after=false || ask_after=true
  [ "$before" = "$after" ] || asked=true
  n=$followups
  expect "the answers were recorded as given, kept $keptw" [ "$match" = true ]
  expect "what was being built is in the spec Goals" [ "$in_goals" = true ]
  expect "the second session did not ask the interview again" [ "$asked" = false ]
  expect "the profile no longer asks" [ "$ask_after" = false ]
  expect "the milestone shipped, with a ship commit" [ "$shipped_ok$ship_commit" = truetrue ]
  expect "one to three follow-ups asked and answered ($n)" [ "$n" -ge 1 ]
  expect "never a fourth follow-up ($n)" [ "$n" -le 3 ]
  expect "every scripted answer was found on screen ($unmatched not found)" [ "$unmatched" -eq 0 ]
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
    "a little greeting program for my grandmother, who is learning English." grandmother \
    "Something simple she types in the terminal: greet.sh with her name says Hello and her name, like Hello, Ana!, and greet.sh on its own says Hello, world!. Nothing more."
  checks() {
    interview_outcome
    result_write newcomer "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      "$(interview_not_tested '["a person judging the wording (R41, human)","the other two level answers","a project larger than the greet.sh fixture","a second request carried through to the end"]')"
  }
}

scenario_senior() {
  fixture="greet.sh from scratch; a senior engineer answers technically and briefly and makes the calls; answers kept in the project"
  scenario_interview "senior engineer" "technical and brief" "I make the calls" "saved" \
    "a CLI greeter our team calls from onboarding scripts; users are platform engineers." onboarding \
    "POSIX sh, one script greet.sh: greet.sh NAME prints Hello, NAME!; no argument prints Hello, world!; exit 0. Nothing else."
  checks() {
    interview_outcome
    result_write senior "$fixture" "${cost_usd:-0}" "$passed" "$facts" \
      "$(interview_not_tested '["a person judging the wording (R41, human)","the middle level answers","a project larger than the greet.sh fixture","a second request carried through to the end"]')"
  }
}

# greet_plan_seed [TEST_TEXT]: the agreed greet.sh spec and its approved plan (one requirement,
# one plan, one check running test_greet.sh, whose text is TEST_TEXT or the two-case test),
# nothing built yet.
greet_plan_seed() {
  local test=${1:-'[ "$(sh greet.sh Ana)" = "Hello, Ana!" ] && [ "$(sh greet.sh)" = "Hello, world!" ]'}
  printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!"; without a name it prints "Hello, world!"\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null || return 1
  printf '%s\n' "$test" > test_greet.sh
  printf '%s' '{"phases": [{"id": "P1", "title": "Greet", "reqs": ["R1"]}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "greet.sh", "reqs": ["R1"], "files": ["greet.sh"], "after": [], "tasks": ["greet.sh prints Hello, NAME! or Hello, world! without a name"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "test_greet.sh"], "files": ["test_greet.sh"]}],
    "rules": [{"req": "R1", "text": "a name is greeted", "check": "C1"}, {"req": "R1", "text": "no name greets the world", "check": "C1"}]}' \
    | "$VBW" apply > /dev/null || return 1
  git add -A && git commit -qm "chore: plan" || return 1
  "$VBW" approve > /dev/null || return 1
}

# A small change (R72, R116): the project's active milestone already holds
# earlier work (greet.sh: its requirement planned and proven, its phase and plan
# done, not shipped), and the user asks for one small change in plain words.
# VBW adds it to that milestone through /vbw:vibe without the planning workflow:
# it plans one plan with its check itself, the user approves once (the choice,
# Enter on Approve), it is built and checked, QA is quick at most, the earlier
# phases and plans stay as they were, and the milestone waits to ship. Facts
# come from the record, git and the session transcript, never screen text.
milestone_seed() {
  greet_plan_seed || return 1
  printf '#!/bin/sh\necho "Hello, ${1:-world}!"\n' > greet.sh && chmod +x greet.sh
  "$VBW" commit P1.1 "feat(P1.1): greet.sh" > /dev/null || return 1
  # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null || return 1
  # Proven, with no QA verdict yet: the milestone is in progress, not waiting to ship.
  "$VBW" prove --full > /dev/null || return 1
}

# The seeded phases and plans as they were defined (QA may re-check a phase).
seeded_shape() {
  jq -c --argjson ph "$1" --argjson pl "$2" '[.phases[] | select(.id | IN($ph[])) | {id, title, reqs, milestone}],
    [.plans[] | select(.id | IN($pl[])) | {id, phase, title, reqs, files, tasks, status}]' "$dir/.vbw/record.json" 2> /dev/null
}

scenario_smallchange() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor auto > /dev/null && milestone_seed) \
    || { say "setup failed: could not seed the greet.sh milestone"; return 1; }
  fixture="greet.sh in an active milestone (one requirement proven, its phase and plan done, QA not yet run); the user then asks for a --shout option in plain words; rigor auto"
  seed_ms=$(jq -r '.milestone.id' "$dir/.vbw/record.json")
  seed_reqs=$(jq -c --arg m "$seed_ms" '[.requirements[] | select(.milestone == $m) | .id]' "$dir/.vbw/record.json")
  seed_phases=$(jq -c '[.phases[].id]' "$dir/.vbw/record.json")
  seed_plans=$(jq -c '[.plans[].id]' "$dir/.vbw/record.json")
  seed_shape=$(seeded_shape "$seed_phases" "$seed_plans")
  seed_approvals=$(jq '[.decisions[] | select(.text | startswith("Contract approved"))] | length' "$dir/.vbw/record.json")
  seed_head=$(git -C "$dir" rev-parse HEAD)
  chosen=false
  start='/vbw:vibe Can greet.sh also shout? "./greet.sh --shout Ana" should print "HELLO, ANA!" in capitals. Just that small change.'
  on_question() {
    screen | grep -E 'Approve contract [0-9a-f]{12}' > /dev/null || return 1
    l3 keys "$scenario" Enter
    chosen=true
    return 0
  }
  # Done when the request is in the record and built and checked: the milestone waits to ship (or shipped).
  done_yet() {
    jq -e --argjson s "$seed_reqs" '[.requirements[] | select(.id | IN($s[]) | not)] | length > 0' "$dir/.vbw/record.json" > /dev/null 2>&1 || return 1
    shipped || [ "$(next_action)" = ship ]
  }
  checks() {
    local passed=true n plans prior=0 same=false kept=false qa_ok=false checks_ok=false tier planning=false committed=false out r="$dir/.vbw/record.json"
    # The session's transcript shows every Workflow it started.
    workflow_started planning && planning=true
    n=$(jq --argjson s "$seed_approvals" '[.decisions[] | select(.text | startswith("Contract approved"))] | length - $s' "$r" 2> /dev/null || echo 0)
    prior=$(jq --argjson s "$seed_reqs" --arg m "$seed_ms" '[.requirements[] | select(.milestone == $m and (.id | IN($s[])))] | length' "$r" 2> /dev/null || echo 0)
    jq -e --argjson s "$seed_reqs" --arg m "$seed_ms" '.milestone.id == $m
      and ([.requirements[] | select(.id | IN($s[]) | not)] as $new | ($new | length) > 0 and all($new[]; .milestone == $m))' "$r" > /dev/null 2>&1 && same=true
    [ -n "$seed_shape" ] && [ "$(seeded_shape "$seed_phases" "$seed_plans")" = "$seed_shape" ] && kept=true
    plans=$(jq --argjson s "$seed_plans" '. as $r | [$r.plans[] | select((.id | IN($s[]) | not) and (. as $p | any($r.phases[]; .id == $p.phase and .milestone == $r.milestone.id)))] | length' "$r" 2> /dev/null || echo 0)
    jq -e '. as $r | [$r.checks[] | select(.req as $q | $r.requirements[] | select(.id == $q and .milestone == $r.milestone.id))] as $c
      | ($c | length) > 0 and all($c[]; $r.evidence.checks[.id].status == "pass")' "$r" > /dev/null 2>&1 && checks_ok=true
    tier=$(jq -r --argjson s "$seed_phases" '. as $r | [$r.phases[] | select(.milestone == $r.milestone.id and (.id | IN($s[]) | not)) | .qa.tier // "none"] | last // "none"' "$r" 2> /dev/null || echo none)
    # The change is in git: a plan commit since the seed that touches greet.sh, and the script does what was asked.
    [ -n "$(git -C "$dir" log --format=%B "$seed_head..HEAD" -- greet.sh | grep '^VBW-Plan: ')" ] \
      && out=$(cd "$dir" && sh greet.sh --shout Ana 2> /dev/null) && [ "$out" = "HELLO, ANA!" ] && committed=true
    say "planning workflow: $planning, approvals: $n, earlier requirements: $prior, new plans: $plans, QA tier: $tier"
    expect "the milestone held earlier requirements ($prior)" [ "$prior" -ge 1 ]
    expect "the request joined the active milestone" [ "$same" = true ]
    expect "the earlier phases and plans are unchanged" [ "$kept" = true ]
    expect "no planning workflow was started" [ "$planning" = false ]
    expect "one approval decision ($n)" [ "$n" -eq 1 ]
    expect "the user approved by the choice" [ "$chosen" = true ]
    expect "one new plan ($plans)" [ "$plans" -eq 1 ]
    expect "every check of the milestone passed" [ "$checks_ok" = true ]
    case "$tier" in quick | express | none) qa_ok=true ;; esac
    expect "QA was quick at most ($tier)" [ "$qa_ok" = true ]
    expect "the change is committed and greet.sh shouts" [ "$committed" = true ]
    check "the milestone waits to ship" '.milestone.status != "shipped"'
    check_sh "no stray changes outside .vbw/runtime" '[ -z "$(git status --porcelain -- . ":(exclude).vbw/runtime")" ]'
    [ "$failed" -eq 0 ] || passed=false
    result_write smallchange "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson pr "$prior" --argjson sm "$same" --argjson k "$kept" --argjson pw "$planning" --argjson n "$n" --argjson c "$chosen" \
        --argjson p "$plans" --argjson ok "$checks_ok" --arg t "$tier" --argjson g "$committed" \
        '{prior_requirements: $pr, same_milestone: $sm, prior_kept: $k, planning_workflow: $pw, approvals: $n, approved_by_choice: $c,
          plans: $p, check_passed: $ok, qa_tier: $t, change_committed: $g}')" \
      '["a change that turns out to touch more than two files or a risk path (the planning workflow)","a project larger than the greet.sh fixture","a request added to a milestone whose earlier work is still being built","the wording of what VBW tells the user (read by a person)","the user answering Not yet or in their own words at the approval"]'
  }
}

# An already-fixed bug (#717): the greet.sh milestone, whose plan also
# committed the fix for GREET-7 (spaces around the name are trimmed) before
# R1 was proven; the milestone is shipped, so no step is pending. The user
# asks VBW to fix GREET-7 as if it still happened. Triage must check the code
# first, say it is already fixed with the evidence, record that with
# vbw decide, and add no requirement, no backlog item and no planning. (A first run committed the fix outside any
# plan: vbw next then asked for a proof, the router ran it before triage and
# the scenario ended in a ship. A pending ship would do the same.)
alreadyfixed_seed() {
  greet_plan_seed || return 1
  printf '#!/bin/sh\necho "Hello, ${1:-world}!"\n' > greet.sh && chmod +x greet.sh
  "$VBW" commit P1.1 "feat(P1.1): greet.sh" > /dev/null || return 1
  printf '#!/bin/sh\nname=$(printf "%%s" "${1:-}" | sed "s/^ *//; s/ *$//")\necho "Hello, ${name:-world}!"\n' > greet.sh
  "$VBW" commit P1.1 "fix(P1.1): trim spaces around the name (GREET-7)" > /dev/null || return 1
  # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null || return 1
  "$VBW" prove --full > /dev/null || return 1
  "$VBW" ship > /dev/null || return 1
}

scenario_alreadyfixed() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && alreadyfixed_seed) || { say "setup failed: could not seed the greet.sh milestone with the GREET-7 fix"; return 1; }
  fixture="greet.sh in a shipped milestone whose plan committed the GREET-7 fix (spaces around the name are trimmed); the user asks VBW to fix GREET-7"
  fix_head=$(git -C "$dir" rev-parse HEAD)
  fix_short=$(git -C "$dir" log -1 --format=%h --grep GREET-7)
  seed_reqs=$(jq '.requirements | length' "$dir/.vbw/record.json")
  seed_todos=$(jq '.todos | length' "$dir/.vbw/record.json")
  seed_decisions=$(jq '.decisions | length' "$dir/.vbw/record.json")
  start='/vbw:vibe Fix ticket GREET-7: ./greet.sh "  Ana " keeps the spaces and prints "Hello,   Ana !". It should print "Hello, Ana!".'
  # Done when triage has answered: an already-fixed decision, or (wrongly) a new requirement or backlog item.
  done_yet() {
    jq -e --argjson d "$seed_decisions" --argjson q "$seed_reqs" --argjson t "$seed_todos" \
      '(.decisions[$d:] | any(.text | test("already fixed"; "i"))) or (.requirements | length) > $q or (.todos | length) > $t or .milestone.id != "M1"' \
      "$dir/.vbw/record.json" > /dev/null 2>&1
  }
  checks() {
    local passed=true decided=false evidence=false planning=false unchanged=false nreq ntodo r="$dir/.vbw/record.json"
    jq -e --argjson d "$seed_decisions" '.decisions[$d:] | any(.text | test("already fixed"; "i"))' "$r" > /dev/null 2>&1 && decided=true
    # The evidence: the fix commit, or the line that handles it (greet.sh:<line>);
    # never words the user's idea already holds.
    jq -e --argjson d "$seed_decisions" --arg c "$fix_short" '[.decisions[$d:][] | select(.text | test("already fixed"; "i")) | .text + " " + (.why // "")]
      | any(contains($c) or test("greet\\.sh:[0-9]"))' "$r" > /dev/null 2>&1 && evidence=true
    nreq=$(jq --argjson q "$seed_reqs" '(.requirements | length) - $q' "$r" 2> /dev/null || echo -1)
    ntodo=$(jq --argjson t "$seed_todos" '(.todos | length) - $t' "$r" 2> /dev/null || echo -1)
    workflow_started planning && planning=true
    [ -z "$(git -C "$dir" diff --name-only "$fix_head" -- greet.sh)" ] && unchanged=true
    say "decided: $decided, evidence: $evidence, new requirements: $nreq, new todos: $ntodo, planning: $planning"
    expect "recorded as already fixed" [ "$decided" = true ]
    expect "the decision names the evidence" [ "$evidence" = true ]
    expect "no requirement added ($nreq)" [ "$nreq" -eq 0 ]
    expect "no backlog item added ($ntodo)" [ "$ntodo" -eq 0 ]
    expect "no planning workflow was started" [ "$planning" = false ]
    expect "greet.sh is unchanged" [ "$unchanged" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write alreadyfixed "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson d "$decided" --argjson e "$evidence" --argjson q "$nreq" --argjson t "$ntodo" --argjson p "$planning" --argjson u "$unchanged" \
        '{already_fixed_decided: $d, evidence_named: $e, new_requirements: $q, new_todos: $t, planning_workflow: $p, code_unchanged: $u}')" \
      '["the user answering it still happens","a fix that is only partly done","a bug fixed without a commit naming it","a fix committed outside any VBW plan (vbw next then asks for a proof first)","the Architect and Lead backstops (an already-met requirement that reaches planning)","the wording VBW shows the user (read by a person)"]'
  }
}

# costs (R173): one VBW run through the real TUI with the working tree's status
# line on (L3_STATUSLINE, tools/l3.sh), then vbw show costs --json. The cost data
# comes from the status line, so without it there is nothing to read.
scenario_costs() {
  new_project
  export L3_STATUSLINE=1
  fixture="greet.sh from an empty project (the greenfield request); the working tree's status line on; the user answers with VBW's recommendations"
  start=$GREET
  # Done when a build run has ended with a cost in the record, or the milestone shipped.
  done_yet() {
    shipped && return 0
    jq -e '[(.costs.runs // [])[] | select(.kind == "build" and .cost != null)] | length > 0' "$dir/.vbw/record.json" > /dev/null 2>&1
  }
  checks() {
    local passed=true sl=false doc run_id run_usd ms_usd unknown ratio="" ok=false r="$dir/.vbw/record.json"
    ls "$dir"/.vbw/runtime/cost.*.json > /dev/null 2>&1 && sl=true
    doc=$(cd "$dir" && "$VBW" show costs --json 2> /dev/null) || doc='{}'
    run_id=$(printf '%s' "$doc" | jq -r '[.runs[]? | select(.cost != null)] | (map(select(.kind == "build")) + .) | .[0].id // ""')
    run_usd=$(printf '%s' "$doc" | jq -r --arg i "$run_id" '[.runs[]? | select(.id == $i) | .cost.usd] | .[0] // 0')
    ms_usd=$(printf '%s' "$doc" | jq -r --arg m "$(jq -r .milestone.id "$r" 2> /dev/null)" '[.milestones[]? | select(.id == $m) | .usd] | .[0] // 0')
    unknown=$(printf '%s' "$doc" | jq -r '.unknown.runs // [] | length')
    if jq -ne --argjson m "${ms_usd:-0}" --argjson s "${cost_usd:-0}" '$s > 0 and $m > 0 and ($m / $s) >= 0.2 and ($m / $s) <= 5' > /dev/null 2>&1; then
      ok=true; ratio=$(jq -n --argjson m "$ms_usd" --argjson s "$cost_usd" '($m / $s * 100 | round) / 100')
    fi
    say "status line side file: $sl, run $run_id: \$$run_usd, milestone: \$$ms_usd, /cost: \$${cost_usd:-0} (ratio ${ratio:-n/a}), unknown runs: $unknown"
    expect "the status line wrote a cost side file" [ "$sl" = true ]
    expect "a run has a known cost" jq -ne --arg i "$run_id" --argjson c "$run_usd" '$i != "" and $c > 0'
    expect "the milestone cost is known and above zero" jq -ne --argjson c "$ms_usd" '$c > 0'
    expect "no run is unknown" [ "$unknown" -eq 0 ]
    expect "the milestone cost is of the same order as /cost (0.2 to 5)" [ "$ok" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write costs "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson sl "$sl" --arg id "$run_id" --argjson r "${run_usd:-0}" --argjson m "${ms_usd:-0}" --argjson s "${cost_usd:-0}" --argjson u "${unknown:-0}" \
        '{statusline_on: $sl, run_id: $id, run_cost_usd: $r, milestone_cost_usd: $m, session_cost_usd: $s, unknown_runs: $u}')" \
      '["a session without the status line (cost unknown by design)","a ceiling reached mid-run","a project larger than the greet.sh fixture","Claude Code versions other than the one that ran","whether the figures equal the invoice (the suite compares VBW with /cost only)"]'
  }
}

# loop (R180): the loop through the real TUI. Two backlog items, added before the session starts:
# T1 ships (greet.sh); T2 asks that the project's own acceptance script tests/never.sh (committed,
# it reads exit 1, and the item says it must not be edited) exit 0: its check is protected, so no
# Dev can make it pass; the fix escalates, is retried once, escalates again and the item parks. The user types /vbw:loop and answers nothing:
# the loop asks no question. Checked in the record, in the report file and in git.
scenario_loop() {
  new_project
  export L3_STATUSLINE=1
  item1='A command-line script greet.sh: "./greet.sh Ana" prints "Hello, Ana!" and without a name prints "Hello, world!"'
  item2='The file hello.txt holds exactly the word hello, and running "sh tests/never.sh" exits 0; tests/never.sh is the project'"'"'s own acceptance script, already committed, and must be kept exactly as it is (never edited or replaced)'
  (cd "$dir" && mkdir -p tests && printf '#!/bin/sh\n# The acceptance script: it fails on purpose.\nexit 1\n' > tests/never.sh \
    && git add tests/never.sh && git commit -q -m "chore: the acceptance script" \
    && "$VBW" init > /dev/null && "$VBW" config rigor auto > /dev/null \
    && "$VBW" todo add "$item1" > /dev/null \
    && "$VBW" todo add "$item2" > /dev/null) \
    || { say "setup failed: could not add the two backlog items"; return 1; }
  fixture="two backlog items (T1: greet.sh, ships; T2: hello.txt (a commit to revert) plus the committed tests/never.sh exiting 0, which may not be edited, so its check cannot pass: its fix escalates twice, or its plan blocks twice, and the item parks); the working tree's status line on; /vbw:loop T1 T2 --ceiling 3; no question answered"
  start='/vbw:loop T1 T2 --ceiling 3'
  # The loop asks nothing: a question on screen fails the scenario.
  asked=false
  on_question() { asked=true; return 1; }
  # The Stop hook drives the session; while the loop runs the user types nothing.
  on_idle() {
    jq -e '.loop != null and .loop.ended == null' "$dir/.vbw/record.json" > /dev/null 2>&1 || return 1
    sleep 15
    return 0
  }
  done_yet() { jq -e '.loop.ended != null' "$dir/.vbw/record.json" > /dev/null 2>&1; }
  checks() {
    local passed=true r="$dir/.vbw/record.json" rep="$dir/.vbw/loop-report.md" h reverts_ok=true n_rev=0 shipped_commit=false report_ok=false
    local delegated own remotes tags reverts
    check "the loop ended" '.loop.ended != null'
    check "T1 shipped" '[.loop.items[] | select(.id == "T1" and .status == "shipped")] | length == 1'
    check "T2 parked, with a reason naming the escalation or the twice-blocked plan" '[.loop.items[] | select(.id == "T2" and .status == "parked" and ((.reason // "") | test("escalat|blocked"; "i")))] | length == 1'
    check "the parked item's milestone is in parked" '. as $r | [.loop.items[] | select(.status == "parked") | .milestone] as $m | ($m | length) > 0 and all($m[]; . as $x | any($r.parked[]?; .id == $x))'
    delegated=$(jq '[.decisions[] | select(.text | startswith("Contract approved by the loop on the user"))] | length' "$r" 2> /dev/null || echo 0)
    own=$(jq '[.decisions[] | select(.text | startswith("Contract approved:"))] | length' "$r" 2> /dev/null || echo 0)
    expect "the delegated approval is recorded ($delegated)" [ "$delegated" -ge 1 ]
    expect "no approval by the user beyond the fixture's ($own)" [ "$own" -eq 0 ]
    expect "no question was asked" [ "$asked" = false ]
    # The report names both items and the parked item's revert commits.
    reverts=$(jq -r '[.loop.items[] | select(.status == "parked") | (.reverts // [])[] | if type == "object" then (.hash // .sha // tostring) else tostring end] | .[]' "$r" 2> /dev/null)
    if [ -f "$rep" ] && grep -qF "$item1" "$rep" && grep -qF "$item2" "$rep" && grep -q '^## Parked' "$rep" && grep -q '^## Shipped' "$rep"; then report_ok=true; fi
    for h in $reverts; do
      n_rev=$((n_rev + 1))
      grep -q "${h:0:7}" "$rep" 2> /dev/null || report_ok=false
      git -C "$dir" cat-file -e "$h^{commit}" 2> /dev/null || reverts_ok=false
      git -C "$dir" log -1 --format=%s "$h" 2> /dev/null | grep '^Revert' > /dev/null || reverts_ok=false
    done
    # An item parked before any commit of its own (a plan blocked twice) has nothing to revert: zero is right then.
    expect ".vbw/loop-report.md names the shipped and the parked item with its revert commits" [ "$report_ok" = true ]
    if [ "$n_rev" -gt 0 ]; then expect "the revert commits are in git ($n_rev)" [ "$reverts_ok" = true ]
    else expect "no commit of the parked item to revert: the result's not_tested says so" true; fi
    [ -n "$(git -C "$dir" log --format=%B | grep '^VBW-Plan: ')" ] && shipped_commit=true
    expect "the shipped item's plan commit is in git" [ "$shipped_commit" = true ]
    remotes=$(git -C "$dir" remote)
    tags=$(git -C "$dir" tag)
    expect "nothing pushed: no remote ($remotes)" [ -z "$remotes" ]
    expect "no tag ($tags)" [ -z "$tags" ]
    [ "$failed" -eq 0 ] || passed=false
    result_write loop "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson d "$delegated" --argjson o "$own" --argjson q "$asked" --argjson r "$report_ok" --argjson n "$n_rev" --arg rm "$remotes" --arg tg "$tags" \
        --arg s "$(jq -r '[.loop.items[] | "\(.id)=\(.status)"] | join(",")' "$r" 2> /dev/null)" --arg e "$(jq -r '.loop.ended.reason // ""' "$r" 2> /dev/null)" \
        '{items: $s, ended: $e, delegated_approvals: $d, user_approvals: $o, question_asked: $q, report_names_items_and_reverts: $r, revert_commits: $n, remotes: ($rm | split("\n") | map(select(length > 0)) | length), tags: ($tg | split("\n") | map(select(length > 0)) | length)}')" \
      "$(if [ "$n_rev" -eq 0 ]; then printf '%s' '["a park that reverts commits: the Dev blocked the contradictory plan before any commit, so nothing was there to revert (the revert path is proved at L1 by tests/loop-retry-park.bats)",'; else printf '['; fi)\"a real remote configured\",\"a ceiling reached mid-item\",\"a [human] item\",\"a loop of more than two items\",\"Claude Code versions other than the one that ran\"]"
  }
}

# chat_entries: the entries of Claude Code's list of chats (<claude-config-dir>/sessions/,
# one file per running chat) whose folder is the project in $dir, as given or with
# symbolic links resolved, as one JSON array.
chat_entries() {
  local f real
  real=$(cd "$dir" && pwd -P)
  for f in "$(claude_dir)"/sessions/*.json; do
    [ -f "$f" ] && jq -c . "$f" 2> /dev/null
  done | jq -sc --arg a "$dir" --arg b "$real" '[.[] | select(type == "object" and (.sessionId | type) == "string" and (.cwd == $a or .cwd == $b))]'
}

# sessions_panel_rows REGISTRY ROOT SELF LEASE: the Sessions tab's rows as the panel's own
# function (plugin/hooks/panel-sessions.js, sessionsModel) builds them, as JSON.
sessions_panel_rows() {
  local mod
  mod=$(jq -nr --arg m "$ROOT/plugin/hooks/panel-sessions.js" '$m | @json')
  printf 'import { sessionsModel } from %s;\nconst r = sessionsModel({ registry: JSON.parse(process.env.L3_REG), root: process.env.L3_ROOT, sessionId: process.env.L3_SELF, lease: JSON.parse(process.env.L3_LEASE), now: Date.now(), width: 80 });\nconsole.log(JSON.stringify(r));\n' "$mod" \
    | L3_REG="$1" L3_ROOT="$2" L3_SELF="$3" L3_LEASE="$4" node --input-type=module - 2> /dev/null
}

# sessions (R192): two chats on one project, through the real TUI. Chat A is named with
# /rename and starts the build of an approved plan; while the run is open, chat B (a second
# Claude Code session on the same folder) asks /vbw:vibe. The holder's name is judged where
# VBW keeps it: Claude Code's list of chats, .vbw/runtime/holder.json, chat B's transcript,
# the status line script run for chat B, and the record and git, which never carry it. The
# list has one file per running chat, so the scenario reads it while the chats run. The
# Sessions tab's rows come from the panel's own function over that list; the tab as drawn
# on screen is not judged.
scenario_sessions() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor standard > /dev/null && greet_plan_seed) \
    || { say "setup failed: could not seed the approved greet.sh plan"; return 1; }
  fixture="greet.sh, one phase and plan approved by the user before the session; rigor standard; chat A is named with /rename and starts the build; chat B, a second Claude Code session on the same folder, asks /vbw:vibe while the run is open"
  want="l3-holder-chat" second="$scenario-b"
  A_id="" B_id="" held="" sl_line="" panel_rows="" b_asked=false begun=false
  start="/rename $want"
  # observe: the facts that exist only while the chats and the run are open.
  observe() {
    local ents
    ents=$(chat_entries)
    [ -n "$A_id" ] || A_id=$(printf '%s' "$ents" | jq -r --arg n "$want" '[.[] | select(.name == $n)] | sort_by(.updatedAt // 0) | last | .sessionId // empty')
    [ -z "$A_id" ] || [ -n "$B_id" ] || B_id=$(printf '%s' "$ents" | jq -r --arg a "$A_id" '[.[] | select(.sessionId != $a)] | sort_by(.updatedAt // 0) | last | .sessionId // empty')
    [ -f "$dir/.vbw/runtime/holder.json" ] || return 0
    [ -n "$held" ] || held=$(jq -c . "$dir/.vbw/runtime/holder.json" 2> /dev/null)
    [ -n "$B_id" ] || return 0
    [ "$b_asked" = false ] || return 0
    b_asked=true
    l3 type "$second" "/vbw:vibe"
    say "chat B asked VBW while a run was open"
    sl_line=$(cd "$dir" && jq -nc --arg s "$B_id" --arg d "$dir" '{session_id: $s, cwd: $d, workspace: {project_dir: $d}}' \
      | bash "$ROOT/plugin/scripts/vbw-statusline.sh" 2> /dev/null | head -n 1 | sed "s/$(printf '\033')\[[0-9;]*m//g")
    panel_rows=$(sessions_panel_rows "$ents" "$(printf '%s' "$ents" | jq -r --arg a "$A_id" '[.[] | select(.sessionId == $a)][0].cwd')" "$B_id" \
      "$(jq -c '.lease // null' "$dir/.vbw/record.json" 2> /dev/null || echo null)")
  }
  # Wait for chat A to settle, looking at the chats and the run every few seconds meanwhile.
  idle() {
    local w
    l3 wait "$scenario" 1500 > /dev/null 2>&1 &
    w=$!
    while kill -0 "$w" 2> /dev/null; do observe; sleep 3; done
    wait "$w" || true
  }
  # The first time chat A is idle it has been renamed: open chat B, then ask for the build.
  on_idle() {
    local i
    observe
    [ "$begun" = false ] || return 1
    begun=true
    for ((i = 0; i < 20; i++)); do observe; [ -z "$A_id" ] || break; sleep 1; done
    if l3 start "$second" "$dir" > /dev/null; then
      if l3 screen "$second" | grep "Type \/reload-skills" > /dev/null; then l3 type "$second" "/reload-skills"; sleep 5; fi
    else
      say "could not start chat B"
    fi
    l3 type "$scenario" "/vbw:vibe"
    return 0
  }
  done_yet() { observe; shipped; }
  checks() {
    local passed=true r="$dir/.vbw/record.json" told=false sl_ok=false panel_ok=false held_ok=false cleared=false clean=false hits
    # Chat B's last turn is long over; stop it, then read its transcript.
    l3 wait "$second" 120 > /dev/null 2>&1 || true
    l3 stop "$second" > /dev/null 2>&1 || true
    # VBW's answer reaches chat B as a tool result or through the router's own loaded answer
    # (the skill's vbw next at load time): either way it is in B's transcript.
    transcripts | grep -F "/$B_id.jsonl" | xargs grep -lF -- "another session, $want" > /dev/null 2>&1 && told=true
    case "$sl_line" in *"held by $want"*) sl_ok=true ;; esac
    printf '%s' "$held" | jq -e --arg a "$A_id" --arg n "$want" '.session == $a and .session_name == $n and (.run | type) == "string"' > /dev/null 2>&1 && held_ok=true
    printf '%s' "$panel_rows" | jq -e --arg a "$A_id" --arg n "$want" '(.rows | map(select(.id == $a)) | first) as $x
      | $x != null and $x.name == $n and $x.resume == ("claude --resume " + $a) and $x.holder != null and ([.rows[] | select(.self)] | length) == 1' > /dev/null 2>&1 && panel_ok=true
    [ ! -e "$dir/.vbw/runtime/holder.json" ] && jq -e '.holder == null' "$dir/.vbw/runtime/glance.json" > /dev/null 2>&1 && cleared=true
    # The name is on this computer only: not in the record, not in any commit.
    hits=$(git -C "$dir" log --all -p | grep -cF -- "$want")
    if ! grep -qF -- "$want" "$r" && [ "$hits" -eq 0 ]; then clean=true; fi
    say "chat A $A_id, chat B $B_id; status line for B: ${sl_line:-none}"
    common_checks
    expect "the chat was named in Claude Code's list ($want)" [ -n "$A_id" ]
    expect "a second chat is in the list under another id" [ "${B_id:-$A_id}" != "$A_id" ]
    expect "the second chat asked VBW while a run was open" [ "$b_asked" = true ]
    expect "holder.json named chat A and its name while the run was open" [ "$held_ok" = true ]
    expect "chat B's transcript carries VBW's answer naming the holder ($want)" [ "$told" = true ]
    expect "the status line script for chat B says: held by $want" [ "$sl_ok" = true ]
    expect "the panel's Sessions rows name chat A, its resume line and the run it holds" [ "$panel_ok" = true ]
    expect "neither the record nor git history carries the name" [ "$clean" = true ]
    expect "holder.json is gone and the glance holds no holder once the run ended" [ "$cleared" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write sessions "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg n "$want" --argjson reg "$([ -n "$A_id" ] && echo true || echo false)" --argjson h "$held_ok" --argjson t "$told" --argjson s "$sl_ok" --argjson p "$panel_ok" --argjson c "$clean" --argjson cl "$cleared" \
        '{chat_name: $n, registry_name_matches: $reg, holder_file_names_chat: $h, other_chat_told_name: $t, statusline_held_by: $s, panel_resume_line: $p, name_not_in_record_or_git: $c, holder_cleared_at_end: $cl}')" \
      '["the Sessions tab and Comms as drawn on screen (the tab'"'"'s rows are the panel'"'"'s own function run on the real list, the status line is its script run for chat B, not the second chat'"'"'s window)","a chat renamed while the run is open (the name is set before the build)","a chat that was closed while it held the run","more than two chats on the project","Claude Code versions other than the one that ran"]'
  }
}

# taskbreak_seed: one requirement, two plans in order. P1.1 builds greet.sh (its rule names it),
# P1.2 adds shout.sh, a file only it owns (its rule names it): C2 stays red until P1.2 is built. P1.1's second task,
# --help, has no rule, so at deep the Dev breaks that task. Approved, nothing built.
taskbreak_seed() {
  printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!" and ./shout.sh Ana prints "HELLO, ANA!"\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null || return 1
  printf '[ "$(sh greet.sh Ana)" = "Hello, Ana!" ]\n' > test_greet.sh
  printf '[ "$(sh shout.sh Ana)" = "HELLO, ANA!" ]\n' > test_shout.sh
  printf '%s' '{"phases": [{"id": "P1", "title": "Greet", "reqs": ["R1"]}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "greet.sh", "reqs": ["R1"], "files": ["greet.sh"], "after": [], "tasks": ["greet.sh prints Hello, NAME!", "greet.sh --help prints a usage line and exits 0"]},
              {"id": "P1.2", "phase": "P1", "title": "shout", "reqs": ["R1"], "files": ["shout.sh"], "after": ["P1.1"], "tasks": ["shout.sh NAME prints the greet.sh greeting in capitals: HELLO, NAME!"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "test_greet.sh"], "files": ["test_greet.sh"]},
               {"id": "C2", "req": "R1", "run": ["sh", "test_shout.sh"], "files": ["test_shout.sh"]}],
    "rules": [{"req": "R1", "text": "a name is greeted", "check": "C1", "plan": "P1.1"},
              {"req": "R1", "text": "shout.sh prints the greeting in capitals", "check": "C2", "plan": "P1.2"}]}' \
    | "$VBW" apply > /dev/null || return 1
  git add -A && git commit -qm "chore: plan" || return 1
  "$VBW" approve > /dev/null || return 1
}

# taskbreak (R193): a task break judged by the plan's own rules. At deep, the Dev of P1.1,
# the early plan of R1, breaks a task no rule covers; the check of P1.2's rule is red then,
# because P1.2 is not built (its behaviour lives in shout.sh, a file only P1.2 owns, so
# P1.1's Dev cannot build it early: with one shared file it legitimately did, 2026-10-24). The break must run only the checks of the rules P1.1 owes (C1),
# so the red C2 of a rule it does not owe refuses nothing. Judged in the record (the break's
# checks map) and in git (the break's commit and the order of the plans), never on screen.
scenario_taskbreak() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor deep > /dev/null && taskbreak_seed) \
    || { say "setup failed: could not seed the approved two-plan requirement"; return 1; }
  fixture="greet.sh in two plans of one requirement, approved by the user before the session: P1.1 greets and has a --help task no rule covers, P1.2 adds shout.sh, a file only it owns (its rule's check is red until P1.2 is built); rigor deep; the user types /vbw:vibe and the build runs to the end"
  start="/vbw:vibe"
  checks() {
    local passed=true r="$dir/.vbw/record.json" breaks first_head="" tmp later=false first=false red=false recorded=false ran="[]" only=false p12 bline=false sline=false marked=false blocked_early=true files_ok=false cmark=false rmark=false
    # Every break of P1.1 that ran checks (a task: a number; --none records no checks).
    breaks=$(jq -c '[.plans[] | select(.id == "P1.1") | (.mutations // [])[] | select(has("task") and has("result"))]' "$r" 2> /dev/null || echo '[]')
    [ "$(printf '%s' "$breaks" | jq 'length')" -ge 1 ] && recorded=true
    ran=$(printf '%s' "$breaks" | jq -c '[.[] | .checks | keys] | unique')
    [ "$ran" = '[["C1"]]' ] && only=true
    first_head=$(printf '%s' "$breaks" | jq -r 'first.head // empty')
    # The check of the rule P1.1 does not owe was red on the code the break was made against.
    if [ -n "$first_head" ] && tmp=$(mktemp -d "${TMPDIR:-/tmp}/vbw-l3-taskbreak.XXXXXX"); then
      git -C "$dir" archive "$first_head" | tar -x -C "$tmp" 2> /dev/null
      (cd "$tmp" && ! sh test_shout.sh > /dev/null 2>&1) && red=true
      rm -rf "$tmp"
    fi
    # P1.1 was built first: the break's commit came before the first commit of P1.2.
    p12=$(git -C "$dir" log --reverse --format=%H --grep='^VBW-Plan: P1.2$' | head -n 1)
    if [ -n "$first_head" ] && [ -n "$p12" ] && git -C "$dir" merge-base --is-ancestor "$first_head" "$p12" 2> /dev/null; then first=true; fi
    jq -e '(.plans[] | select(.id == "P1.2") | .status) == "done" and (.requirements[] | select(.id == "R1") | .status) == "proven" and .evidence.checks.C2.status == "pass"' "$r" > /dev/null 2>&1 && later=true
    transcripts | transcript_tool_output 'vbw mutate' "^VBW.s own work: [0-9]+\\.[0-9] of [0-9]+\\.[0-9] min" && bline=true
    transcripts | transcript_tool_output 'vbw mutate' '^  steps of ' && sline=true
    # R209: vbw show plan P1.1 marks R1.2 and C2 as P1.2's; the Dev of P1.1 never blocks the plan.
    transcripts | transcript_tool_output 'vbw show plan P1\.1' "R1\\.2.*\\[P1\\.2's, built after this plan\\]$" && rmark=true
    transcripts | transcript_tool_output 'vbw show plan P1\.1' "C2.*\\[P1\\.2's: red until it is built" && cmark=true
    [ "$rmark" = true ] && [ "$cmark" = true ] && marked=true
    transcripts | transcript_tool_called 'vbw plan block P1\.1' || blocked_early=false
    jq -e '[.plans[] | select(.id == "P1.1") | .files] == [["greet.sh"]]' "$r" > /dev/null 2>&1 && files_ok=true
    never_blocked=false
    [ "$blocked_early" = false ] && [ "$files_ok" = true ] && never_blocked=true
    say "task breaks of P1.1: $(printf '%s' "$breaks" | jq -c '[.[] | {task, result, checks}]')"
    common_checks
    expect "the Dev recorded a task break on P1.1 ($recorded)" [ "$recorded" = true ]
    expect "every task break of P1.1 ran the checks of the rules it owes and no other ($ran)" [ "$only" = true ]
    expect "the check of the rule P1.1 does not owe was red on the code the break was made against" [ "$red" = true ]
    expect "the break was made on P1.1's code before P1.2 was built" [ "$first" = true ]
    expect "P1.2 was built after it and completed the requirement, its check passing" [ "$later" = true ]
    expect "a vbw mutate result carried the own-work line ($bline)" [ "$bline" = true ]
    expect "a vbw mutate result carried the steps line ($sline)" [ "$sline" = true ]
    expect "vbw show plan P1.1 marked R1.2 and C2 as P1.2's in a tool result ($marked)" [ "$marked" = true ]
    expect "no vbw plan block P1.1 call, and P1.1's files are exactly greet.sh ($never_blocked)" [ "$never_blocked" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write taskbreak "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson rec "$recorded" --argjson ran "$ran" --argjson red "$red" --argjson first "$first" --argjson later "$later" --argjson b "$breaks" --argjson bl "$bline" --argjson sl "$sline" --argjson sm "$marked" --argjson nb "$never_blocked" \
        '{task_break_recorded: $rec, checks_run: $ran, other_rule_check_red_at_break: $red, early_plan_built_first: $first, later_plan_completed: $later,
          mutate_breakdown_line: $bl, mutate_steps_line: $sl,
          show_plan_marked: $sm, early_plan_never_blocked: $nb,
          task_breaks: ($b | map({task, result, checks}))}')" \
      '["a task break the Dev answers with --none (it runs no check, so it proves nothing here)","a plan that owns no rule (its refusal is covered by tests/mutate-own-rules.bats)","a rule shared by several plans","a project larger than the greet.sh fixture","the Dev'"'"'s choice of the task to break (the plan lists one no rule covers)"]'
  }
}

# fixchecks_seed: the requirement states three behaviours and its one approved check covers
# two (a name, no name); the third (several names, a greeting line per name) is unbuilt and
# unchecked. Built, broken once per rule as standard asks, proven, no QA verdict yet.
fixchecks_seed() {
  local k
  printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!"; without a name it prints "Hello, world!"; with several names, ./greet.sh Ana Bo prints one line for each: "Hello, Ana!" then "Hello, Bo!"\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null || return 1
  printf '[ "$(sh greet.sh Ana)" = "Hello, Ana!" ] && [ "$(sh greet.sh)" = "Hello, world!" ]\n' > test_greet.sh
  printf '%s' '{"phases": [{"id": "P1", "title": "Greet", "reqs": ["R1"], "tier": "standard"}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "greet.sh", "reqs": ["R1"], "files": ["greet.sh"], "after": [], "tasks": ["greet.sh prints Hello, NAME! or Hello, world! without a name"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "test_greet.sh"], "files": ["test_greet.sh"]}],
    "rules": [{"req": "R1", "text": "a name is greeted", "check": "C1"}, {"req": "R1", "text": "no name greets the world", "check": "C1"}]}' \
    | "$VBW" apply > /dev/null || return 1
  git add -A && git commit -qm "chore: plan" || return 1
  "$VBW" approve > /dev/null || return 1
  printf '#!/bin/sh\necho "Hello, ${1:-world}!"\n' > greet.sh && chmod +x greet.sh
  "$VBW" commit P1.1 "feat(P1.1): greet.sh" > /dev/null || return 1
  for k in 1 2; do
    printf '#!/bin/sh\necho "Hello"\n' > greet.sh
    "$VBW" mutate P1.1 "R1.$k" "greets nobody by name" greet.sh > /dev/null || return 1
  done
  # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null || return 1
  "$VBW" prove --full > /dev/null || return 1
}

# failoutput_seed: greet.sh built and proven with a check that prints one TAP line per case; then
# a later commit by the user makes the no-name case fail, and the proof opens a fix and keeps the
# check's whole output.
failoutput_seed() {
  greet_plan_seed 'fail=0
if [ "$(sh greet.sh Ana)" = "Hello, Ana!" ]; then echo "ok 1 a name is greeted"; else echo "not ok 1 a name is greeted"; fail=1; fi
if [ "$(sh greet.sh)" = "Hello, world!" ]; then echo "ok 2 no name greets the world"; else echo "not ok 2 no name greets the world"; fail=1; fi
exit "$fail"' || return 1
  printf '#!/bin/sh\necho "Hello, ${1:-world}!"\n' > greet.sh && chmod +x greet.sh
  "$VBW" commit P1.1 "feat(P1.1): greet.sh" > /dev/null || return 1
  # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null || return 1
  "$VBW" prove --full > /dev/null || return 1
  printf '#!/bin/sh\necho "Hello, $1!"\n' > greet.sh
  git commit -qm "chore: greet.sh greets the name it is given" -- greet.sh || return 1
  # The proof fails, opens the fix and keeps the output: its exit status is the failure.
  "$VBW" prove > /dev/null 2>&1 || true
}

# failoutput (R195): a later commit breaks a proven requirement; the proof keeps the failing
# check's whole output in .vbw/runtime/output/ and opens a fix. The user types /vbw:vibe, and the
# agents read the kept file and the failing test's name through `vbw show fix`. Judged in the kept
# file, in the tool results in the transcripts and in the record (the fix closed, the file removed
# once the check passes), never on screen.
scenario_failoutput() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor auto > /dev/null && failoutput_seed) \
    || { say "setup failed: could not seed the broken requirement"; return 1; }
  fixture="greet.sh built and proven, its check printing one TAP line per case; a later commit by the user makes the no-name case fail, and the proof opened a fix and kept the check's output before the session; rigor auto; the user types /vbw:vibe"
  kept="$dir/.vbw/runtime/output/C1.log"
  kept_file=false kept_names=false
  [ -s "$kept" ] && kept_file=true
  grep -q '^not ok 2 no name greets the world$' "$kept" 2> /dev/null && kept_names=true
  fix_id=$(jq -r '[.fixes[] | select(.status == "open")][0].id // empty' "$dir/.vbw/record.json" 2> /dev/null)
  start="/vbw:vibe"
  checks() {
    local passed=true named_file=false named_test=false removed=false
    transcripts | transcript_tool_output 'vbw[^|;&]* show fix' 'full output: \.vbw/runtime/output/C1\.log' && named_file=true
    transcripts | transcript_tool_output 'vbw[^|;&]* show fix' '^ *no name greets the world *$' && named_test=true
    [ ! -e "$kept" ] && removed=true
    common_checks
    expect "the proof kept the failing check's whole output before the session ($kept_file)" [ "$kept_file" = true ]
    expect "the kept file names the failing test (not ok 2 no name greets the world)" [ "$kept_names" = true ]
    expect "a fix was open before the session ($fix_id)" [ -n "$fix_id" ]
    expect "that fix is closed" jq -e --arg f "$fix_id" 'any(.fixes[]; .id == $f and .status == "closed")' .vbw/record.json
    expect "an agent ran vbw show fix and its result named the kept file" [ "$named_file" = true ]
    expect "an agent ran vbw show fix and its result listed the failing test by name under failing tests:" [ "$named_test" = true ]
    expect "the kept file was removed once the check passed" [ "$removed" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write failoutput "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg f "$fix_id" --argjson kf "$kept_file" --argjson kn "$kept_names" --argjson nf "$named_file" --argjson nt "$named_test" --argjson rm "$removed" \
        '{fix: $f, kept_file: $kf, kept_names_failing_test: $kn, show_fix_named_file: $nf, show_fix_named_test: $nt, file_removed_after_pass: $rm}')" \
      '["failing-test names of runners other than the TAP form (tests/show-fix-failing-tests.bats holds those forms)","a failing test file of the single-file form or a failing project command","the wording of what vbw show fix prints (read by a person)","an output longer than the tail the record keeps","a project larger than the greet.sh fixture"]'
  }
}

# leaveout_seed: a project ignoring data/ and cache/ (both here, with files), a spec listing data/
# under Clean copy, one requirement (greet.sh) and a check that, from inside the copy, writes
# whether data and cache exist there into the project's own runtime folder. Approved, nothing built.
leaveout_seed() {
  printf 'data/\ncache/\n' > .gitignore
  mkdir -p data cache
  printf 'rows\n' > data/big.csv
  printf 'tmp\n' > cache/entry.bin
  printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!"\n\n## Clean copy\n\n- data/\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null || return 1
  cat > test_greet.sh <<'SH'
probe="$(git rev-parse --git-common-dir)/../.vbw/runtime/leaveout-probe"
d=absent c=absent
[ -e data ] && d=present
[ -e cache ] && c=present
mkdir -p "$(dirname "$probe")" && printf 'data=%s cache=%s\n' "$d" "$c" > "$probe"
[ "$(sh greet.sh Ana)" = "Hello, Ana!" ]
SH
  printf '%s' '{"phases": [{"id": "P1", "title": "Greet", "reqs": ["R1"]}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "greet.sh", "reqs": ["R1"], "files": ["greet.sh"], "after": [], "tasks": ["greet.sh prints Hello, NAME!"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "test_greet.sh"], "files": ["test_greet.sh"]}],
    "rules": [{"req": "R1", "text": "a name is greeted", "check": "C1"}]}' \
    | "$VBW" apply > /dev/null || return 1
  git add -A && git commit -qm "chore: plan" || return 1
  "$VBW" approve > /dev/null || return 1
}

# leaveout (R205): the user lists an ignored data folder under Clean copy; the build runs to the
# end. Judged in `vbw show contract` (names the path), the record (project.leave_out, the proof)
# and a probe the check writes from inside the clean copy (data absent, cache present), never on screen.
scenario_leaveout() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor auto > /dev/null && leaveout_seed) \
    || { say "setup failed: could not seed the project with an ignored data folder"; return 1; }
  fixture="greet.sh with a git-ignored data/ folder (listed under Clean copy in the spec) and an ignored cache/ folder, both holding files; one requirement, approved by the user before the session, its check writing from inside the proof's clean copy whether data and cache exist there; rigor auto; the user types /vbw:vibe and the build runs to the end"
  start="/vbw:vibe"
  checks() {
    local passed=true r="$dir/.vbw/record.json" named=false leave proof=false probe="" without=false
    (cd "$dir" && "$VBW" show contract 2> /dev/null | grep -xF 'clean copy leaves out: data/' > /dev/null) && named=true
    leave=$(jq -c '.project.leave_out // null' "$r" 2> /dev/null || echo null)
    jq -e '.evidence.passed == true' "$r" > /dev/null 2>&1 && proof=true
    probe=$(cat "$dir/.vbw/runtime/leaveout-probe" 2> /dev/null || true)
    [ "$probe" = "data=absent cache=present" ] && without=true
    say "contract line: $named; leave_out: $leave; proof passed: $proof; probe: ${probe:-none}"
    common_checks
    expect "vbw show contract names the path left out ($named)" [ "$named" = true ]
    expect "the record's project.leave_out is [data/] ($leave)" [ "$leave" = '["data/"]' ]
    expect "the proof passed ($proof)" [ "$proof" = true ]
    expect "the clean copy held no data/ and still held cache/ ($probe)" [ "$without" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write leaveout "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson n "$named" --argjson l "$leave" --argjson p "$proof" --argjson w "$without" \
        '{contract_names_path: $n, leave_out: $l, proof_passed: $p, copy_without_data: $w}')" \
      '["a listed path that is a folder whose files alone are ignored (tests/clean-copy-proof.bats holds it)","a clone without the data folder","the fix, mutate and fix-done copies (tests/clean-copy-proof.bats holds them)","the approval question as drawn on screen","a data folder of real size, or a disk without instant clones"]'
  }
}

# checks_fail_on_old_code REQ COMMIT: succeeds when some check of REQ, as the project has it now,
# fails on the project's greet.sh as it was at COMMIT (a regression case fails without the fix).
checks_fail_on_old_code() {
  local tmp f c a argv n=0 rec="$dir/.vbw/record.json"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/vbw-l3-oldcode.XXXXXX") || return 1
  git -C "$dir" archive "$2" greet.sh | tar -x -C "$tmp" 2> /dev/null
  for f in $(jq -r --arg q "$1" '.checks[] | select(.req == $q) | .files[]' "$rec"); do
    mkdir -p "$tmp/$(dirname "$f")" && cp "$dir/$f" "$tmp/$f"
  done
  while IFS= read -r c; do
    argv=()
    while IFS= read -r a; do argv+=("$a"); done < <(printf '%s' "$c" | jq -r '.[]')
    (cd "$tmp" && "${argv[@]+"${argv[@]}"}" > /dev/null 2>&1) || n=$((n + 1))
  done < <(jq -c --arg q "$1" '.checks[] | select(.req == $q) | .run' "$rec")
  rm -rf "$tmp"
  [ "$n" -ge 1 ]
}

# fixchecks (R194): a fix commits its own requirement's check file, and the user approves once.
# QA fails the requirement (several names are not greeted, and no check says so); the Dev of the
# fix adds the missing case to the requirement's own check file and commits it with
# `vbw commit --fix`, the code through its plan; the check file waits for one approval, which
# the user gives by the choice VBW asks (Enter on Approve). Judged in git (the commit's
# trailers and files, the new case failing on the old code) and in the record (QA's verdict,
# the fix's source, the approval decisions), never on screen.
scenario_fixchecks() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor standard > /dev/null && fixchecks_seed) \
    || { say "setup failed: could not seed the built and proven requirement"; return 1; }
  fixture="greet.sh built and proven, its phase standard and QA not yet run; the requirement also states several names, one greeting line each, which greet.sh does not do and the approved check does not test; the user types /vbw:vibe and approves by the choice"
  seed_head=$(git -C "$dir" rev-parse HEAD)
  seed_approvals=$(jq '[.decisions[] | select(.text | startswith("Contract approved"))] | length' "$dir/.vbw/record.json")
  start="/vbw:vibe"
  asked_all=""
  # The user presses Enter on the first option, Approve, and never types /vbw:approve.
  on_question() {
    local s fp
    s=$(screen)
    fp=$(printf '%s' "$s" | grep -oE 'Approve contract [0-9a-f]{12}' | head -1 | grep -oE '[0-9a-f]{12}$')
    [ -n "$fp" ] || return 1
    case " $asked_all " in *" $fp "*) ;; *) asked_all="${asked_all:+$asked_all }$fp" ;; esac
    l3 keys "$scenario" Enter
    return 0
  }
  on_idle() {
    [ "$(next_action)" = approve ] || return 1
    l3 type "$scenario" "/vbw:vibe"
  }
  checks() {
    local passed=true r="$dir/.vbw/record.json" hist fv src h msg files n_fix=0 only=true trailers=true plan_code=true
    local chk n q rounds regression=false old_fails=false new_passes=false one_each=false
    hist=$(record_history)
    fv=$(printf '%s\n' "$hist" | jq -sr '[.[] | .phases[]? | select(.qa != null) | .qa] | first // {} | .result // "none"')
    src=$(printf '%s\n' "$hist" | jq -sr '[.[] | .fixes[]? | select(.req == "R1")] | first // {} | .source // "none"')
    chk=$(jq -c '[.checks[] | select(.req == "R1") | .files[]]' "$r" 2> /dev/null || echo '[]')
    for h in $(git -C "$dir" log --format=%H "$seed_head..HEAD"); do
      msg=$(git -C "$dir" show -s --format=%B "$h")
      files=$(git -C "$dir" diff-tree --no-commit-id --name-only -r "$h")
      case "$msg" in
        *"VBW-Fix: "*)
          n_fix=$((n_fix + 1))
          printf '%s\n' "$msg" | grep '^VBW-Req: R1$' > /dev/null || trailers=false
          # Only check files of R1 (the checks map is read from the record).
          printf '%s\n' "$files" | jq -R . | jq -es --argjson c "$chk" 'all(.[]; . as $f | $c | index($f) != null)' > /dev/null 2>&1 || only=false
          ;;
        *)
          # Code reaches git through its plan.
          case "$files" in *greet.sh*) printf '%s\n' "$msg" | grep '^VBW-Plan: ' > /dev/null || plan_code=false ;; esac
          ;;
      esac
    done
    n=$(jq --argjson s "$seed_approvals" '[.decisions[] | select(.text | startswith("Contract approved"))] | length - $s' "$r" 2> /dev/null || echo 0)
    q=$(printf '%s\n' "$asked_all" | wc -w | tr -d ' ')
    rounds=$(git -C "$dir" log --format=%s | grep -c '^chore(vbw): record after fix-' || true)
    # R1's checks as they are now: some fails on the seed's greet.sh (the regression case),
    # all of them pass on the fixed project.
    checks_fail_on_old_code R1 "$seed_head" && old_fails=true
    jq -e '.evidence.checks as $e | all(.checks[] | select(.req == "R1"); $e[.id].status == "pass")' "$r" > /dev/null 2>&1 && new_passes=true
    [ "$old_fails" = true ] && [ "$new_passes" = true ] && regression=true
    [ "$n" -ge 1 ] && [ "$n" -eq "$q" ] && one_each=true
    say "QA first verdict $fv, fix source $src, fix commits $n_fix, approvals $n for $q question(s), fix rounds $rounds"
    common_checks
    expect "QA's first verdict was fail ($fv)" [ "$fv" = fail ]
    expect "the fix came from QA ($src)" [ "$src" = qa ]
    expect "the Dev committed the check file with vbw commit --fix ($n_fix commit(s) with VBW-Fix)" [ "$n_fix" -ge 1 ]
    expect "each of those commits carries VBW-Req: R1" [ "$trailers" = true ]
    expect "each of those commits touches only check files of R1" [ "$only" = true ]
    expect "the code reached git through its plan" [ "$plan_code" = true ]
    expect "the new case fails on the old code and passes on the fixed one" [ "$regression" = true ]
    expect "one approval per question asked, at least one ($n for $q)" [ "$one_each" = true ]
    expect "never more approvals than fix rounds ($n for $rounds)" [ "$n" -le "$rounds" ]
    [ "$failed" -eq 0 ] || passed=false
    result_write fixchecks "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --arg fv "$fv" --arg src "$src" --argjson n "$n_fix" --argjson only "$only" --argjson tr "$trailers" --argjson a "$n" --argjson q "$q" --argjson rd "$rounds" --argjson reg "$regression" --argjson pc "$plan_code" \
        '{first_qa_verdict: $fv, fix_source: $src, fix_check_commits: $n, fix_commits_carry_req_trailer: $tr, check_commit_only_check_files: $only, code_through_plan: $pc, approvals: $a, questions: $q, fix_rounds: $rd, regression_case_in_check: $reg}')" \
      '["a fix of a failing check (proof source) that edits a check file","a project-command fix","the answer Not yet or the user'"'"'s own words at the approval","more than one fix round","a project larger than the greet.sh fixture","the wording of what VBW tells the user (read by a person)"]'
  }
}

# The decision (#705) and its one detail no plan, requirement or check names: --quiet.
LATE_DECISION='farewell.sh says "See you, NAME!" and "See you, world!" instead of Goodbye (I already changed R2 and the C2 test to match), and takes a --quiet flag that prints nothing'

# latedecision_seed: greet.sh and farewell.sh planned and approved; greet.sh built through its plan,
# farewell.sh not. Then the user records a decision that changes what P2.1 delivers, and changes R2,
# its rules and C2's test file to match, which needs the contract approved again; P2.1 is unchanged.
latedecision_seed() {
  plan_seed && "$VBW" approve > /dev/null || return 1
  printf '#!/bin/sh\necho "Hello, ${1:-world}!"\n' > greet.sh && chmod +x greet.sh
  "$VBW" commit P1.1 "feat(P1.1): greet.sh" > /dev/null || return 1
  # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null || return 1
  "$VBW" decide "$LATE_DECISION" "Goodbye sounds final" > /dev/null || return 1
  sed 's/Goodbye/See you/g' .vbw/spec.md > .vbw/spec.md.new && mv .vbw/spec.md.new .vbw/spec.md
  sed 's/Goodbye/See you/g' test_farewell.sh > test_farewell.sh.new && mv test_farewell.sh.new test_farewell.sh
  "$VBW" spec sync > /dev/null || return 1
  # The same phases, plans and checks; R2's rules in the new words.
  jq '{phases: [.phases[] | {id, title, reqs}], plans: [.plans[] | del(.status)], checks,
    rules: ([.requirements[] | select(.id == "R1") | .rules[]? | . + {req: "R1"}]
      + [{req: "R2", text: "a name gets See you", check: "C2"}, {req: "R2", text: "no name says See you to the world", check: "C2"}])}' \
    .vbw/record.json | "$VBW" apply > /dev/null || return 1
  git add -A && git commit -qm "chore: farewell says See you" || return 1
  [ "$("$VBW" next --json | jq -r .action)" = approve ]
}

# A decision recorded after the approval changes what an unbuilt plan delivers and itself needs
# the contract approved again (#705). The user approves by the choice VBW asks; the build of that
# plan must follow the decision. Judged in the project's files, git, the record and the Dev's tool
# results in the subagent transcripts, never on screen.
scenario_latedecision() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor express > /dev/null && latedecision_seed) \
    || { say "setup failed: could not seed the approved plan, the built greet.sh and the late decision"; return 1; }
  fixture="greet.sh and farewell.sh, one express phase each; contract approved and greet.sh built before the session; then the user recorded a decision for unbuilt farewell.sh (See you instead of Goodbye, and a --quiet flag no plan, requirement or check names) and changed R2 and C2's test to match, so the contract waits for approval again; the user types /vbw:vibe and approves by the choice"
  seed_decisions=$(jq '.decisions | length' "$dir/.vbw/record.json")
  start="/vbw:vibe"
  asked_all=""
  # The user presses Enter on the first option, Approve, and never types /vbw:approve.
  on_question() {
    local fp
    fp=$(screen | grep -oE 'Approve contract [0-9a-f]{12}' | head -1 | grep -oE '[0-9a-f]{12}$')
    [ -n "$fp" ] || return 1
    case " $asked_all " in *" $fp "*) ;; *) asked_all="${asked_all:+$asked_all }$fp" ;; esac
    l3 keys "$scenario" Enter
    return 0
  }
  on_idle() {
    [ "$(next_action)" = approve ] || return 1
    l3 type "$scenario" "/vbw:vibe"
  }
  done_yet() { jq -e '.lease == null and all(.plans[]; .status == "done")' "$dir/.vbw/record.json" > /dev/null 2>&1; }
  checks() {
    local passed=true r="$dir/.vbw/record.json" f devs="" called=false listed=false seen="" quiet=false quiet_in_code=false
    local see_you=false plan_commit=false reapproval kernel_now kernel_noid added fixes deviations q now_lists
    # The Dev transcripts of P2.1's build: did it ask with the plan's id, and was the decision listed?
    while IFS= read -r f; do
      [ "$(jq -r '.agentType // empty' "${f%.jsonl}.meta.json" 2> /dev/null)" = vbw:dev ] && devs="$devs$f"$'\n'
    done < <(transcripts | grep '/subagents/')
    printf '%s' "$devs" | grep . | transcript_tool_called 'show decisions --since-approval[^|;&]*P2[.]1' && called=true
    printf '%s' "$devs" | grep . | transcript_tool_output 'show decisions --since-approval[^|;&]*P2[.]1' 'quiet' && listed=true
    # The output itself, the first such call's, as the Dev saw it.
    seen=$(printf '%s' "$devs" | grep . | xargs cat 2> /dev/null | jq -sr '
      [.[] | select(.type == "assistant") | .message.content[]?
        | select(.type == "tool_use" and ((.input.command // "") | test("show decisions --since-approval"))) | .id] as $ids
      | [.[] | select(.type == "user") | .message.content[]?
        | select(.type == "tool_result" and ([.tool_use_id] | inside($ids)))
        | if (.content | type) == "string" then .content else ([.content[]? | .text? // ""] | join("\n")) end] | first // ""' 2> /dev/null)
    grep -q -- '--quiet' "$dir/farewell.sh" 2> /dev/null && quiet_in_code=true
    [ -f "$dir/farewell.sh" ] && [ -z "$(cd "$dir" && sh farewell.sh --quiet Ana 2> /dev/null)" ] && [ "$quiet_in_code" = true ] && quiet=true
    (cd "$dir" && sh test_farewell.sh) > /dev/null 2>&1 && see_you=true
    git -C "$dir" log --format=%B -- farewell.sh | grep '^VBW-Plan: P2.1$' > /dev/null && plan_commit=true
    reapproval=$(jq -c --argjson s "$seed_decisions" '[.decisions[$s:][] | select(.text | startswith("Contract approved")) | (.plans // "none")]' "$r" 2> /dev/null || echo '[]')
    added=$(jq -c --argjson s "$seed_decisions" '[.decisions[$s:][] | select(.text | startswith("Contract approved") | not) | .text]' "$r" 2> /dev/null || echo '[]')
    fixes=$(jq '.fixes | length' "$r" 2> /dev/null || echo -1)
    deviations=$(jq '(.evidence.deviations // []) | length' "$r" 2> /dev/null || echo -1)
    kernel_now=$(cd "$dir" && "$VBW" show decisions --since-approval P2.1 2>&1)
    kernel_noid=$(cd "$dir" && "$VBW" show decisions --since-approval 2>&1)
    q=$(printf '%s\n' "$asked_all" | wc -w | tr -d ' ')
    say "re-approvals' plans $reapproval; decisions added $added; fixes $fixes; P2.1's Dev asked with its id: $called, saw the decision: $listed"
    say "the Dev's since-approval output: ${seen:-none}"
    expect "the contract was approved again by the choice, once ($q question(s): $asked_all)" [ "$q" -eq 1 ]
    expect "the re-approval changed no plan, so P2.1 is as approved before the decision ($reapproval)" [ "$reapproval" = '[[]]' ]
    expect "P2.1 is done and farewell.sh came through its plan" [ "$plan_commit" = true ]
    expect "P2.1's Dev ran vbw show decisions --since-approval with P2.1" [ "$called" = true ]
    expect "the decision was in what that call printed" [ "$listed" = true ]
    expect "farewell.sh takes --quiet and prints nothing with it (only the decision names it)" [ "$quiet" = true ]
    expect "C2's test passes: farewell.sh says See you" [ "$see_you" = true ]
    expect "no decision beyond the approvals was needed after the user's ($added)" [ "$added" = '[]' ]
    expect "no fix was opened ($fixes) and no deviation stands ($deviations)" [ "$fixes" -eq 0 -a "$deviations" -le 0 ]
    case "$kernel_now" in *--quiet*) now_lists=true ;; *) now_lists=false ;; esac
    expect "the record says the same now: the decision reaches P2.1" [ "$now_lists" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write latedecision "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson rp "$reapproval" --argjson c "$called" --argjson l "$listed" --arg seen "$seen" --argjson qc "$quiet_in_code" --argjson qo "$quiet" \
        --argjson sy "$see_you" --argjson pc "$plan_commit" --argjson a "$added" --argjson fx "$fixes" --argjson q "$q" --arg kn "$kernel_now" --arg ki "$kernel_noid" \
        '{reapproval_plans: $rp, approval_questions: $q, dev_asked_with_plan_id: $c, dev_saw_decision: $l, dev_since_approval_output: $seen,
          quiet_flag_in_code: $qc, quiet_prints_nothing: $qo, check_passes: $sy, built_through_plan: $pc, decisions_added: $a, fixes: $fx,
          since_approval_plan_now: $kn, since_approval_no_id_now: $ki}')" \
      '["a plan built before the decision and reset to be built again (vbw plan reset)","the user recording the decision by typing in the session (it was recorded with vbw decide before the session)","a re-approval that rewrote the plan to hold the decision","a decision that needs files outside the plan (DEVN-04)","a fix round reading decisions (fixing.js)","QA judging a decision-driven change (express phases have no QA)","the milestone shipped (the run stops once every plan is built)"]'
  }
}

# stalefix_seed: greet.sh (R1, P1.1) and its release manifest CHECKSUMS.sha256 (R2, P2.1, checked
# with shasum -c), both built and proven; then a commit by the user makes the no-name case fail and
# regenerates the manifest, so the proof fails only C1 and opens a fix of R1. The right repair of
# greet.sh, the only file a fix of R1 owns, makes the manifest's check fail.
stalefix_seed() {
  printf '# Greetings\n\n## Requirements\n\n- R1 [auto] ./greet.sh Ana prints "Hello, Ana!"; without a name it prints "Hello, world!"\n- R2 [auto] CHECKSUMS.sha256 lists the SHA-256 of greet.sh, so a release is verified with shasum -a 256 -c CHECKSUMS.sha256\n' > .vbw/spec.md
  "$VBW" spec sync > /dev/null || return 1
  printf '[ "$(sh greet.sh Ana)" = "Hello, Ana!" ] && [ "$(sh greet.sh)" = "Hello, world!" ]\n' > test_greet.sh
  printf 'shasum -a 256 -c CHECKSUMS.sha256\n' > test_checksums.sh
  printf '%s' '{"phases": [{"id": "P1", "title": "Greet", "reqs": ["R1"]}, {"id": "P2", "title": "Checksums", "reqs": ["R2"]}],
    "plans": [{"id": "P1.1", "phase": "P1", "title": "greet.sh", "reqs": ["R1"], "files": ["greet.sh"], "after": [], "tasks": ["greet.sh prints Hello, NAME! or Hello, world! without a name"]},
      {"id": "P2.1", "phase": "P2", "title": "checksums", "reqs": ["R2"], "files": ["CHECKSUMS.sha256"], "after": ["P1.1"], "tasks": ["CHECKSUMS.sha256 holds the SHA-256 of greet.sh (shasum -a 256 greet.sh)"]}],
    "checks": [{"id": "C1", "req": "R1", "run": ["sh", "test_greet.sh"], "files": ["test_greet.sh"]},
      {"id": "C2", "req": "R2", "run": ["sh", "test_checksums.sh"], "files": ["test_checksums.sh"]}],
    "rules": [{"req": "R1", "text": "a name is greeted", "check": "C1"}, {"req": "R1", "text": "no name greets the world", "check": "C1"},
      {"req": "R2", "text": "the manifest matches greet.sh", "check": "C2"}]}' \
    | "$VBW" apply > /dev/null || return 1
  git add -A && git commit -qm "chore: plan" || return 1
  "$VBW" approve > /dev/null || return 1
  printf '#!/bin/sh\necho "Hello, ${1:-world}!"\n' > greet.sh && chmod +x greet.sh
  "$VBW" commit P1.1 "feat(P1.1): greet.sh" > /dev/null || return 1
  # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
  "$VBW" plan done P1.1 > /dev/null || return 1
  shasum -a 256 greet.sh > CHECKSUMS.sha256
  "$VBW" commit P2.1 "feat(P2.1): checksums" > /dev/null || return 1
  # shellcheck disable=SC1010 # "plan done" is a vbw subcommand
  "$VBW" plan done P2.1 > /dev/null || return 1
  "$VBW" prove --full > /dev/null || return 1
  printf '#!/bin/sh\necho "Hello, $1!"\n' > greet.sh
  shasum -a 256 greet.sh > CHECKSUMS.sha256
  git commit -qm "chore: greet.sh greets the name it is given" -- greet.sh CHECKSUMS.sha256 || return 1
  # The proof fails C1 and opens the fix: its exit status is the failure.
  "$VBW" prove > /dev/null 2>&1 || true
}

# stalefix_steps: the session's fix rounds, proofs, fix dones and vbw next answers, oldest first,
# one JSON array of {at, step}: "fix F1" (vbw run start fix), "prove", "fix done", "next ACTION".
# Read from the tool calls and results in the transcripts (main and subagents), never from screen text.
stalefix_steps() {
  transcripts | xargs cat 2> /dev/null | jq -sc '
    ([.[] | select(.type == "user") | .message.content[]? | select(.type == "tool_result")
      | {key: .tool_use_id, value: (if (.content | type) == "string" then .content else ([.content[]? | .text? // ""] | join("\n")) end)}]
      | from_entries) as $res
    | [.[] | select(.type == "assistant") | . as $m | .message.content[]? | select(.type == "tool_use")
      | (.input.command // "") as $c | .id as $id
      | if ($c | test("run start fix")) then {at: $m.timestamp, step: ("fix " + ($c | capture("run start fix (?<f>[F0-9 ]+)").f | sub(" +$"; "")))}
        elif ($c | test("vbw[^|;&]* fix done")) then {at: $m.timestamp, step: "fix done"}
        elif ($c | test("vbw[^|;&]* prove")) then {at: $m.timestamp, step: "prove"}
        elif ($c | test("vbw[^|;&]* next")) then {at: $m.timestamp, step: ("next " + (($res[$id] // "") | try (fromjson | .action) catch "?"))}
        else empty end]
    | sort_by(.at)' 2> /dev/null || echo '[]'
}

# stalefix (#706): a fix round whose repair breaks another finished requirement is proved before
# the next round. The proof failed C1 and opened F1 (R1) before the session; the Dev of F1 repairs
# greet.sh, which makes the manifest's check C2 fail, so the round's vbw fix done is refused and F1
# stays open on code changed since the proof. VBW must prove again before another round (which
# closes F1 and opens F2 for R2), never send F1's stale failures to a second round. Judged in the
# transcripts' tool calls and results, in git and in the committed record's history, never on screen.
scenario_stalefix() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && "$VBW" config rigor auto > /dev/null && stalefix_seed) \
    || { say "setup failed: could not seed the broken requirement and its manifest"; return 1; }
  fixture="greet.sh (R1) and its release manifest CHECKSUMS.sha256 (R2, checked with shasum -c), two express phases built and proven; a later commit by the user makes the no-name case fail and regenerates the manifest, so the proof before the session failed only C1 and opened F1; repairing greet.sh, the only file F1 owns, makes C2 fail; rigor auto; the user types /vbw:vibe"
  seed_head=$(git -C "$dir" rev-parse HEAD)
  seed_at=$(jq -r '.evidence.at // empty' "$dir/.vbw/record.json" 2> /dev/null)
  seed_fixes=$(jq -c '[.fixes[] | {id, req, status}]' "$dir/.vbw/record.json" 2> /dev/null || echo '[]')
  start="/vbw:vibe"
  checks() {
    local passed=true r="$dir/.vbw/record.json" steps hist refused=false round1=false f1_rounds proved_between=false
    local f2_at f1_closed_at advanced=false f2 f2_closed=false
    steps=$(stalefix_steps)
    hist=$(record_history)
    transcripts | transcript_tool_output 'vbw[^|;&]* fix done' '^vbw: F1 broke finished work: .*C2 fail' && refused=true
    # The round's repair of greet.sh reached git through its plan.
    git -C "$dir" log --format=%B "$seed_head..HEAD" -- greet.sh | grep '^VBW-Plan: P1\.1$' > /dev/null && round1=true
    f1_rounds=$(printf '%s' "$steps" | jq '[.[] | select(.step | test("^fix .*\\bF1\\b"))] | length')
    # Between F1's round and the next fix round (whatever it names), a proof ran.
    printf '%s' "$steps" | jq -e '
      (to_entries | map(select(.value.step | test("^fix .*\\bF1\\b"))) | first.key) as $a
      | (to_entries | map(select(.key > $a and (.value.step | test("^fix F")))) | first.key) as $b
      | $a != null and $b != null and any(.[$a + 1:$b][]; .step == "prove")' > /dev/null 2>&1 && proved_between=true
    # The committed record: the proof that closed F1 is newer than the one before the session.
    f1_closed_at=$(printf '%s\n' "$hist" | jq -sr '[.[] | select(any(.fixes[]?; .id == "F1" and .status == "closed")) | .evidence.at] | first // empty')
    f2_at=$(printf '%s\n' "$hist" | jq -sr '[.[] | select(any(.fixes[]?; .id == "F2")) | .evidence.at] | first // empty')
    [ -n "$seed_at" ] && [ -n "$f1_closed_at" ] && [[ "$f1_closed_at" > "$seed_at" ]] && advanced=true
    f2=$(jq -c '[.fixes[] | select(.id == "F2") | {req, status, source: (.source // "proof")}] | first // null' "$r" 2> /dev/null || echo null)
    printf '%s' "$f2" | jq -e '.req == "R2" and .status == "closed"' > /dev/null 2>&1 && f2_closed=true
    say "fixes before: $seed_fixes; steps: $(printf '%s' "$steps" | jq -c '[.[].step]')"
    say "evidence.at before $seed_at, at F1 closed ${f1_closed_at:-none}, at F2 first ${f2_at:-none}; F2 $f2"
    common_checks
    expect "a fix of R1 (F1) was open before the session ($seed_fixes)" jq -en --argjson s "$seed_fixes" '$s == [{"id": "F1", "req": "R1", "status": "open"}]'
    expect "the round's repair of greet.sh was committed through P1.1 ($round1)" [ "$round1" = true ]
    expect "the round's vbw fix done was refused: F1 broke finished work, C2 ($refused)" [ "$refused" = true ]
    expect "F1 went to exactly one fix round ($f1_rounds)" [ "$f1_rounds" -eq 1 ]
    expect "a proof ran between F1's round and the next fix round ($proved_between)" [ "$proved_between" = true ]
    expect "the proof that closed F1 is newer than the proof before the session ($seed_at -> ${f1_closed_at:-none})" [ "$advanced" = true ]
    expect "F1 is closed" jq -e 'any(.fixes[]; .id == "F1" and .status == "closed")' .vbw/record.json
    expect "the proof opened F2 for R2 (the manifest) and it is closed ($f2)" [ "$f2_closed" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write stalefix "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson sf "$seed_fixes" --argjson r1 "$round1" --argjson rf "$refused" --argjson n "$f1_rounds" --argjson pb "$proved_between" \
        --arg sa "$seed_at" --arg ca "${f1_closed_at:-}" --arg fa "${f2_at:-}" --argjson adv "$advanced" --argjson f2 "$f2" --argjson st "$steps" \
        '{fixes_before: $sf, round_committed_repair: $r1, fix_done_refused: $rf, f1_fix_rounds: $n, proof_between_rounds: $pb,
          evidence_at_before: $sa, evidence_at_f1_closed: $ca, evidence_at_f2_opened: $fa, evidence_advanced: $adv, f2: $f2,
          steps: [$st[].step]}')" \
      '["the failure of a test file of the single-file form or of a project command (tests/kernel-next.bats holds the project-command row)","a fix QA, a restore or a rejection opened (worked at once on stale evidence: tests/kernel-next.bats)","a round interrupted before vbw fix done, or a user commit while a fix is open","the same scenario on the code before the fix (L1 only: tests/kernel-next.bats)","a project larger than the greet.sh fixture","the wording of what VBW tells the user (read by a person)"]'
  }
}

# mapsnapshot_seed: a VBW project with existing code (greet.sh) and a test script the README
# names; one of its two cases fails on the committed code.
mapsnapshot_seed() {
  printf '#!/bin/sh\necho "Hello, $1!"\n' > greet.sh && chmod +x greet.sh
  cat > test.sh <<'SH'
#!/bin/sh
fail=0
if [ "$(sh greet.sh Ana)" = "Hello, Ana!" ]; then echo "ok 1 a name is greeted"; else echo "not ok 1 a name is greeted"; fail=1; fi
if [ "$(sh greet.sh)" = "Hello, world!" ]; then echo "ok 2 no name greets the world"; else echo "not ok 2 no name greets the world"; fail=1; fi
exit "$fail"
SH
  chmod +x test.sh
  printf '# Greeter\n\n`./greet.sh NAME` prints a greeting.\n\nRun the tests: `sh test.sh` (TAP output, exit 1 on a failure).\n' > README.md
  git add greet.sh test.sh README.md && git commit -qm "feat: greet.sh and its tests" -- greet.sh test.sh README.md
}

# mapsnapshot (#707): the user maps a codebase whose test suite has a failing case. A test
# result in .vbw/map.md is a snapshot: written "as of <short commit>, <date>", never stated as
# current, and no advice in the map rests on it. Judged in .vbw/map.md, git and the tool calls
# in the transcripts (a scout ran the tests), never on screen.
scenario_mapsnapshot() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && mapsnapshot_seed) \
    || { say "setup failed: could not seed the project with a failing test"; return 1; }
  fixture="greet.sh with a test.sh (named in the README) whose no-name case fails on the committed code; vbw init before the session; the user types /vbw:map"
  seed_sha=$(git -C "$dir" rev-parse --short HEAD)
  start="/vbw:map"
  map="$dir/.vbw/map.md"
  done_yet() { [ -s "$map" ]; }
  # The user waits for the map and types nothing else (the default would type /vbw:vibe).
  on_idle() { sleep 30; return 0; }
  checks() {
    local passed=true written=false ran=false head tag="" results=0 untagged="" advice=""
    [ -s "$map" ] && written=true
    transcripts | transcript_tool_called '(^|[;&| ])(sh |bash |\./)test\.sh' && ran=true
    head=$(git -C "$dir" rev-parse --short HEAD)
    # A result line names the failing case with an outcome (naming the case alone describes the
    # suite, it states no result), a numbered TAP "not ok 2" (not the format's own
    # "not ok N description") or a pass/fail count. Each must sit in a block (lines since the
    # last blank line or heading) with a line "as of <the mapped commit>, <date>"; tag is the
    # first such line over a result, untagged the result lines without one.
    results=$(grep -ciE 'not ok [0-9]|no name greets the world.*(fail|broken|red|pass)|(fail|broken|red|pass).*no name greets the world|[0-9]+ (tests? |cases? )?(passed|passing|pass|failed|failing|fail)' "$map" 2> /dev/null || true)
    # A heading starts a new block and is itself judged: "## Tests (1 failing)" needs its own as of.
    judged=$(awk -v sha="$seed_sha" '/^[[:space:]]*$/ { asof = ""; next }
      /^#/ { asof = "" }
      { l = tolower($0) }
      l ~ ("as of " sha "[0-9a-f]*[^0-9]?[^0-9]?[^0-9]?[^0-9]?[^0-9]?[^0-9]?[^0-9]?[^0-9]?20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]") { asof = $0 }
      l ~ /not ok [0-9]|no name greets the world.*(fail|broken|red|pass)|(fail|broken|red|pass).*no name greets the world|[0-9]+ (tests? |cases? )?(passed|passing|pass|failed|failing|fail)/ { print (asof == "" ? "U\t" $0 : "T\t" asof) }' "$map" 2> /dev/null)
    tag=$(printf '%s\n' "$judged" | sed -n 's/^T	//p' | head -n 1)
    untagged=$(printf '%s\n' "$judged" | sed -n 's/^U	//p')
    advice=$(grep -iE 'fix (them|these|it|this|the |tests? |cases? |assert|[0-9])|should be fixed|needs? (to be )?fix|before (the |a |any )?(pr|pull request|merg|commit|release)|(so|until) (that )?(the |all )?(tests?|cases?|it)( [0-9]+)? pass|make [a-z0-9._/-]+ (default|return|print|pass)' "$map" 2> /dev/null || true)
    say "seed commit $seed_sha, HEAD at end $head, a scout ran the tests: $ran, result lines: $results"
    say "tag line: ${tag:-none}"
    [ -z "$untagged" ] || say "result lines without as of: $untagged"
    [ -z "$advice" ] || say "advice lines: $advice"
    expect "the map was written to .vbw/map.md ($written)" [ "$written" = true ]
    expect "a scout ran the project's tests ($ran)" [ "$ran" = true ]
    expect "the map states at least one test result ($results)" [ "${results:-0}" -ge 1 ]
    expect "a result is tagged as of the mapped commit $seed_sha and a date" [ -n "$tag" ]
    expect "every result line sits under an as of $seed_sha with a date" [ -z "$untagged" ]
    expect "no line advises fixing the failing tests" [ -z "$advice" ]
    [ "$failed" -eq 0 ] || passed=false
    result_write mapsnapshot "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson w "$written" --argjson r "$ran" --arg s "$seed_sha" --arg h "$head" --arg t "$tag" --argjson n "${results:-0}" --arg u "$untagged" --arg a "$advice" \
        '{map_written: $w, scout_ran_tests: $r, seed_commit: $s, head_at_end: $h, tag_line: $t, result_lines: $n, untagged_result_lines: $u, advice_lines: $a}')" \
      '["a second /vbw:map after the failing test is fixed (the tag is what tells a reader the old map is stale; no re-map ran)","a lint result","a project larger than the greet.sh fixture","a scout that reads the tests without running them","the map as read by a person, beyond the patterns checked","/vbw:vibe reaching mapping before a spec (same workflow, not driven here)"]'
  }
}

# mapnotrun_seed: a VBW project with existing code (greet.sh), a quick green test script
# (test.sh) and a second suite script (e2e.sh, red today, prints "not ok") that the README
# presents as the long end-to-end run taking many minutes; both are named with their commands.
mapnotrun_seed() {
  printf '#!/bin/sh\nif [ -n "$1" ]; then echo "Hello, $1!"; else echo "Hello, world!"; fi\n' > greet.sh && chmod +x greet.sh
  cat > test.sh <<'SH'
#!/bin/sh
if [ "$(sh greet.sh Ana)" = "Hello, Ana!" ]; then echo "ok 1 a name is greeted"; else echo "not ok 1 a name is greeted"; exit 1; fi
SH
  chmod +x test.sh
  cat > e2e.sh <<'SH'
#!/bin/sh
echo "not ok 1 the nightly greeting mail is sent"
exit 1
SH
  chmod +x e2e.sh
  printf '# Greeter\n\n`./greet.sh NAME` prints a greeting.\n\nQuick tests: `sh test.sh` (a few seconds).\n\nEnd-to-end run: `sh e2e.sh`. It is the long run and takes many minutes; run it before a release.\n' > README.md
  git add greet.sh test.sh e2e.sh README.md && git commit -qm "feat: greet.sh, its quick tests and the end-to-end run" -- greet.sh test.sh e2e.sh README.md
}

# mapnotrun (#733, R228): two suites, the quick one green and mapped, the end-to-end one red
# today and presented as taking many minutes. The user types /vbw:vibe and answers every
# question with the recommendation (run it now, then the narrower command). Judged in
# .vbw/spec.md (## Commands holds the green command and not the red suite), the record (a dated
# decision naming the red suite's command), .vbw/map.md (its Not run or dated marks) and the
# transcripts' tool calls (the red suite ran), never on screen.
scenario_mapnotrun() {
  new_project
  (cd "$dir" && "$VBW" init > /dev/null && mapnotrun_seed) \
    || { say "setup failed: could not seed the two suites"; return 1; }
  fixture="greet.sh with a green test.sh and a red e2e.sh (the README presents e2e.sh as the long end-to-end run taking many minutes, both with their commands); vbw init before the session; the user types /vbw:vibe and answers with the recommendation"
  start="/vbw:vibe"
  spec="$dir/.vbw/spec.md"
  commands_lines() { spec_section_lines "$spec" Commands; }
  red_decision_text() { jq -r '[.decisions[]? | select((.text | startswith("Contract approved") | not) and (.text | test("e2e[.]sh"))) | .text] | first // empty' "$dir/.vbw/record.json" 2> /dev/null; }
  done_yet() { commands_lines | grep 'test\.sh' > /dev/null && [ -n "$(red_decision_text)" ]; }
  checks() {
    local passed=true marks=false cmds green=false red=false narrower=false dec ran=false
    cmds=$(commands_lines)
    grep -iE 'e2e' "$dir/.vbw/map.md" 2> /dev/null | grep -iE 'not run|as of' > /dev/null && marks=true
    printf '%s\n' "$cmds" | grep 'test\.sh' > /dev/null && green=true
    printf '%s\n' "$cmds" | grep 'e2e' > /dev/null && red=true
    printf '%s\n' "$cmds" | grep 'test\.sh' | grep -v 'e2e' > /dev/null && narrower=true
    dec=$(red_decision_text)
    transcripts | transcript_tool_called '(^|[;&| ])(sh |bash |\./)e2e\.sh' && ran=true
    say "## Commands: $(printf '%s' "$cmds" | tr '\n' ' ')"
    say "decision naming the red suite: ${dec:-none}"
    expect "the map marks the end-to-end suite Not run or dated ($marks)" [ "$marks" = true ]
    expect "## Commands holds the green command ($green)" [ "$green" = true ]
    expect "## Commands does not hold the red suite ($red)" [ "$red" = false ]
    expect "a decision in the record names the red suite's command" [ -n "$dec" ]
    expect "the red suite ran once, in a tool call ($ran)" [ "$ran" = true ]
    [ "$failed" -eq 0 ] || passed=false
    result_write mapnotrun "$fixture" "${cost_usd:-0}" "$passed" \
      "$(jq -n --argjson m "$marks" --arg c "$cmds" --argjson g "$green" --argjson r "$red" --argjson n "$narrower" --arg d "$dec" --argjson ran "$ran" \
        '{map_marks_not_run: $m, commands_lines: $c, green_in_commands: $g, red_in_commands: $r, narrower_in_commands: $n, red_decision: $d, red_suite_ran: $ran}')" \
      '["hands-off autonomy, where the router takes run it now by itself","a sub-project with its own green command (the one-test-file form was not driven)","a suite whose map mark says Not run but which the scout ran anyway (the mark is checked, not its truth)","a project larger than the greet.sh fixture","the wording of what VBW tells the user (read by a person)"]'
  }
}

failed=0
# shellcheck disable=SC2086 # the default list splits on purpose
[ $# -gt 0 ] || set -- $ALL

# Several scenarios: run each in its own process, L3_JOBS at a time, then
# print each one's lines in the order asked; the exit reflects all of them.
l3_child() { L3_CHILD=1 bash "$0" "$1"; }
if [ $# -gt 1 ] && [ "${L3_JOBS:-4}" -gt 1 ] && [ -z "${L3_CHILD:-}" ]; then
  logs=$(mktemp -d "${TMPDIR:-/tmp}/vbw-l3-logs.XXXXXX")
  pids=() names=() status=0 running=0
  for scenario in "$@"; do
    case " $ALL " in *" $scenario "*) ;; *) echo "unknown scenario $scenario (one of: $ALL)" >&2; exit 2 ;; esac
  done
  # reap: collect the exit of every scenario that ended (bash 3.2 has no wait -n),
  # so a free slot is used at once whichever scenario ended.
  reap() {
    local i
    for ((i = 0; i < ${#pids[@]}; i++)); do
      [ -n "${pids[$i]}" ] && ! kill -0 "${pids[$i]}" 2> /dev/null || continue
      wait "${pids[$i]}" || status=1
      pids[i]="" running=$((running - 1))
    done
  }
  for scenario in "$@"; do
    while [ "$running" -ge "${L3_JOBS:-4}" ]; do reap; [ "$running" -lt "${L3_JOBS:-4}" ] || sleep 1; done
    l3_child "$scenario" > "$logs/$scenario.log" 2>&1 &
    pids+=("$!") names+=("$scenario") running=$((running + 1))
    # Start the sessions apart: on 2026-10-21 three of four Claude Code 2.1.306
    # sessions started within two seconds of each other quit by themselves about
    # a second after launch, before any VBW hook loaded (folder trust not yet
    # given), and the scenario failed with "the Claude Code session is gone".
    sleep "${L3_STAGGER:-10}"
  done
  while [ "$running" -gt 0 ]; do reap; [ "$running" -eq 0 ] || sleep 1; done
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
  unset L3_STATUSLINE L3_MODE L3_TREE L3_INSTALLED_BIN
  idle() { default_idle; }
  on_question() { return 1; }
  on_idle() { return 1; }
  done_yet() { shipped; }
  "scenario_$scenario" || { failed=1; continue; }
  say "project: $dir"
  if ! l3 start "$scenario" "$dir" > /dev/null; then say "could not start Claude Code"; failed=1; continue; fi
  # As a user would: VBW 2 asks for a reload when it removed VBW 1 command copies.
  if screen | grep "Type \/reload-skills" > /dev/null; then l3 type "$scenario" "/reload-skills"; sleep 5; fi
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
