#!/usr/bin/env bats
# R121 (decisions D206, D161; L1): every new idea brought to /vbw:vibe is sorted
# on one line as now, next or later, with a reason and a size, before any
# planning, inside one AskUserQuestion menu whose first option is VBW's sort.
# The instructions live in the triage skill (plugin/skills/triage/SKILL.md),
# outside the router, which only points to it. What the main conversation does
# is the skill's text (L1); the kernel's part is tests/triage-kernel.bats.

load helper

SKILL="$PLUGIN_ROOT/skills/triage/SKILL.md"
ROUTER="$PLUGIN_ROOT/skills/vibe/SKILL.md"
DOC="$REPO_ROOT/docs/triage.md"
README="$REPO_ROOT/README.md"

# flat FILE: the file on one line, lower case, so a sentence wrapped over lines still matches.
flat() { tr '\n' ' ' < "$1" | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
has() { flat "$1" | grep -qE -- "$2" || { echo "$(basename "$(dirname "$1")")/$(basename "$1") lacks: $2"; return 1; }; }

@test "R121: the triage skill exists, loads the kernel's summary in one call and starts no agent or workflow" {
  [ -f "$SKILL" ]
  grep -qx 'name: triage' "$SKILL"
  grep -qE '^description: .{20,}$' "$SKILL"
  grep -qF '"${CLAUDE_PLUGIN_ROOT}/bin/vbw" triage' "$SKILL"
  ! grep -qE '^allowed-tools:.*(Workflow|Agent|Task)' "$SKILL" || { echo "the triage may not start an agent or a workflow"; false; }
}

@test "R121: the router sends every new request to the triage before any requirement, planning or file change" {
  grep -qF 'vbw:triage' "$ROUTER"
  has "$ROUTER" 'new (request|idea).{0,160}vbw:triage|vbw:triage.{0,160}new (request|idea)'
  has "$SKILL" 'before (any|a) (requirement|planning|plan|file)'
}

@test "R121: one line per idea: the sort (now joins the active milestone; next or later go into the backlog), a one-sentence reason and the size" {
  has "$SKILL" 'one line'
  has "$SKILL" '\bnow\b.{0,120}(active milestone|this milestone)'
  has "$SKILL" '\bnext\b.{0,40}\blater\b.{0,120}backlog|backlog.{0,120}\bnext\b.{0,40}\blater\b'
  has "$SKILL" 'reason'
  has "$SKILL" 'one sentence'
  has "$SKILL" 'small.{0,20}medium.{0,20}large'
}

@test "R121: the line is inside one AskUserQuestion menu, VBW's sort first and marked (Recommended), the two other sorts as the other options, no typed command" {
  grep -qF 'AskUserQuestion' "$SKILL"
  grep -qF '(Recommended)' "$SKILL"
  has "$SKILL" 'first option'
  has "$SKILL" 'line is inside'
  has "$SKILL" 'question text.{0,80}(sort|line)'
  has "$SKILL" '(print|show|write) no line before'
  has "$SKILL" '(two other|other two) sorts'
  has "$SKILL" 'never (ask|have) the user (to )?type|no typed command'
}

@test "R121: a message that is not a new idea gets no triage; a match of an existing requirement or backlog item is named, with an offer to move a backlog item to now" {
  has "$SKILL" 'not a new idea|no triage'
  has "$SKILL" 'answer.{0,80}question'
  has "$SKILL" 'continue'
  has "$SKILL" 'go on'
  has "$SKILL" 'approv'
  has "$SKILL" 'already (matches|match|is) .{0,80}(requirement|backlog)'
  has "$SKILL" 'name'
  has "$SKILL" 'move.{0,60}(to|into) now|now.{0,60}move'
}

@test "R121: several ideas get one line each in the same menu, up to four; more than four are sorted four at a time" {
  has "$SKILL" 'one (triage )?line (per|for each) idea|one line each'
  has "$SKILL" 'four'
  has "$SKILL" 'four at a time'
}

@test "R121: 'now' adds the idea with vbw spec add and the normal flow continues; with no active milestone it starts the next one" {
  grep -qF 'vbw spec add' "$SKILL"
  grep -qF 'vbw milestone start' "$SKILL"
  has "$SKILL" 'no active milestone'
  has "$SKILL" 'plan(ning)? again|approval menu|normal flow'
}

@test "R121: 'next' and 'later' add the idea with vbw todo add, its sort and its size" {
  grep -qE 'vbw todo add --sort (next|later|<|\$|\{)' "$SKILL"
  grep -qF -- '--size' "$SKILL"
}

@test "R121: the triage never interrupts a run: a request during a run is sorted, and a 'now' idea waits for the run to end" {
  has "$SKILL" '(during|while) a run|run is open'
  has "$SKILL" 'wait'
  has "$SKILL" 'interrupt'
}

@test "R121: the triage happens at every autonomy setting: guided, balanced and hands-off" {
  has "$SKILL" 'guided'
  has "$SKILL" 'balanced'
  has "$SKILL" 'hands-off'
  has "$SKILL" 'every autonomy|all autonomy|any autonomy|whatever the autonomy'
}

@test "R121: the router stays within 1,400 words and all prompts within 22,800 words" {
  [ "$(wc -w < "$ROUTER")" -le 1400 ]
  local f total=0 w
  for f in "$PLUGIN_ROOT"/skills/*/SKILL.md "$PLUGIN_ROOT"/agents/*.md; do
    w=$(wc -w < "$f")
    total=$((total + w))
    [ "$w" -le 2000 ] || [ "$f" = "$ROUTER" ] || { echo "$f has $w words"; false; }
  done
  [ "$total" -le 22800 ] || { echo "all prompts: $total words"; false; }
}

@test "R121: the user documentation explains the three sorts, the sizes and how to overrule" {
  [ -f "$DOC" ]
  has "$DOC" '\bnow\b'
  has "$DOC" '\bnext\b'
  has "$DOC" '\blater\b'
  has "$DOC" 'small.{0,20}medium.{0,20}large'
  has "$DOC" 'overrul'
  has "$DOC" 'reason'
  has "$DOC" 'vbw todo list'
  grep -qF 'docs/triage.md' "$README"
  has "$README" 'now.{0,20}next.{0,20}later'
}

@test "F90: docs/triage.md shows the real vbw todo list format" {
  grep -qF 'T3 [next, small] Refunds' "$DOC"
  grep -qF 'T2 [later, large] Gift cards' "$DOC"
}
